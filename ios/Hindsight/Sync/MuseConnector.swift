import Foundation

/// The hindsight connector for Muse (connector/server.py): Muse calls its
/// `submit_saved_posts` tool, and the app pulls what arrived from `/saves`.
/// That replaces copying Muse's reply back into the app.
///
/// Experiment setup: one server at `https://<host>/<token>`. Until we host it,
/// that root URL comes from a DEBUG field in the Muse sheet or the
/// `-museConnectorBaseURL <url>` launch argument (remembered after that).
///
/// One account per install: the first time a root URL is set, the app asks the
/// server for its own tenant (`…/<token>/t/<tenant>`, `ensureAccount`) and uses
/// that for everything (Muse connector, saves pull, WhatsApp connect code). The
/// tenant is stored apart from the configured URL, keyed by its root, so passing
/// the launch argument again never makes a second one.
enum MuseConnector {
    static let baseURLKey = "museConnectorBaseURL"
    /// Set once Muse has sent us something, so later syncs skip the setup step.
    static let connectedKey = "museConnectorConnected"
    /// This install's account: the root it was made on, and its tenant base URL.
    static let accountRootKey = "serverAccountRoot"
    static let accountBaseKey = "serverAccountBase"

    /// What was configured (launch argument or the DEBUG field): a root, or a tenant URL pasted by hand.
    static var configuredURL: URL? {
        let defaults = UserDefaults.standard
        if let fromLaunch = defaults.volatileDomain(forName: UserDefaults.argumentDomain)[baseURLKey] as? String,
           !fromLaunch.isEmpty {
            defaults.set(fromLaunch, forKey: baseURLKey)
        }
        return defaults.string(forKey: baseURLKey).flatMap(normalized)
    }

    static var account: ServerAccount? {
        let defaults = UserDefaults.standard
        guard let root = defaults.string(forKey: accountRootKey), let base = defaults.string(forKey: accountBaseKey) else { return nil }
        return ServerAccount(root: root, base: base)
    }

    /// The URL everything talks to: this install's tenant once it has one, else what was configured.
    static var baseURL: URL? { ServerAccount.resolve(configured: configuredURL, account: account) }

    static func mcpURL(base: URL) -> URL { base.appending(path: "mcp") }
    static func savesURL(base: URL) -> URL { base.appending(path: "saves") }

    /// Accepts the base, or a pasted `…/mcp` or `…/saves` URL.
    static func normalized(_ string: String) -> URL? {
        var trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        while trimmed.hasSuffix("/") { trimmed.removeLast() }
        for suffix in ["/mcp", "/saves"] where trimmed.hasSuffix(suffix) {
            trimmed.removeLast(suffix.count)
        }
        guard let url = URL(string: trimmed), url.scheme == "https" || url.scheme == "http", url.host() != nil else {
            return nil
        }
        return url
    }

    // MARK: - Prompts

    /// First time: add the connector, send everything hindsight doesn't have,
    /// and set up the daily routine so it keeps happening on its own.
    /// (`window` is kept for the paste fallback; the connector asks the
    /// server what it already has via get_sync_status instead of dates.)
    static func connectPrompt(mcpURL: URL, window: MusePrompt.Window = .all) -> String {
        """
        Please add a custom connector called "hindsight" with this MCP server URL:
        \(mcpURL.absoluteString)
        If you already have a connector named "hindsight", remove it and use this one instead. \
        Treat this as a new request: ignore anything earlier in this chat about hindsight.

        Then \(syncInstruction)

        After that, set up a routine: every day at 9am, sync my saves with hindsight the same way \
        (only new ones), without asking me first.
        """
    }

    /// After that: Muse already knows the connector (and normally runs the routine itself).
    static func syncPrompt(window: MusePrompt.Window = .all) -> String {
        "Please \(syncInstruction)"
    }

    private static let syncInstruction = """
        sync my saves with hindsight: call hindsight's get_sync_status to see what it already has, \
        then send my Instagram and Facebook saved posts it doesn't have yet (all of them, \
        however many; ignore date limits from earlier messages) with submit_saved_posts, newest \
        first, in batches of up to 50, with the full captions, collection names and mentions. \
        Stop at the first post whose url is in recent_urls. Don't list the posts in the chat, \
        just tell me how many you sent.
        """

    /// Our own prompts, so pasting one back by mistake can be caught.
    static func isOurPrompt(_ text: String) -> Bool {
        ["List my saved posts from", "Please add a custom connector", "Please sync my saves with hindsight"]
            .contains { text.hasPrefix($0) }
    }

    // MARK: - Tenants (one isolated store per install)

    /// Asks the server for a new, empty store and returns its base URL
    /// (`https://<host>/<token>/t/<tenant>`).
    static func createTenant(base: URL) async throws -> URL {
        // Tenants hang off the server's main base, never off another tenant.
        let root = ServerAccount.root(of: base)
        var request = URLRequest(url: root.appending(path: "tenants"))
        request.httpMethod = "POST"
        request.timeoutInterval = 15
        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200,
              let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let basePath = json["base_path"] as? String,
              let url = URL(string: basePath, relativeTo: root)?.absoluteURL
        else { throw URLError(.badServerResponse) }
        return url
    }

    @MainActor private static var creating: Task<URL?, Never>?

    /// Makes this install's account if it has none for the configured server yet.
    /// Idempotent, and safe to call on every launch: offline, it keeps the root URL
    /// and tries again next time. Returns the URL to use.
    @MainActor @discardableResult
    static func ensureAccount() async -> URL? {
        let configured = configuredURL
        guard ServerAccount.needsAccount(configured: configured, account: account), let configured else {
            return baseURL
        }
        if let creating { return await creating.value }
        let task = Task<URL?, Never> { await makeAccount(on: configured) ?? configured }
        creating = task
        defer { creating = nil }
        return await task.value
    }

    /// A new, empty account on the configured server, replacing this install's
    /// (dev "Fresh Muse test"). nil if the server can't be reached.
    @MainActor @discardableResult
    static func startNewAccount() async -> URL? {
        guard let configured = configuredURL else { return nil }
        return await makeAccount(on: configured)
    }

    @MainActor private static func makeAccount(on configured: URL) async -> URL? {
        do {
            let tenant = try await createTenant(base: configured)
            let defaults = UserDefaults.standard
            defaults.set(ServerAccount.root(of: configured).absoluteString, forKey: accountRootKey)
            defaults.set(tenant.absoluteString, forKey: accountBaseKey)
            // A new store: Muse needs the new connector URL before it can send.
            defaults.set(false, forKey: connectedKey)
            DebugLog.write("server account: tenant \(tenant.lastPathComponent)")
            return tenant
        } catch {
            DebugLog.write("server account: couldn't create one (\(error.localizedDescription)); using the root for now")
            return nil
        }
    }

    // MARK: - Pull

    /// Everything the connector has received, as the JSON `SavedPostParser` reads.
    static func fetchSaves(base: URL) async throws -> String {
        var request = URLRequest(url: savesURL(base: base))
        request.timeoutInterval = 15
        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }
        return String(decoding: data, as: UTF8.self)
    }
}

/// This install's account on the hindsight server: the root it was made on
/// (`https://<host>/<token>`) and its tenant base URL (`…/<token>/t/<tenant>`).
/// The URL rules are pure, so they're tested without a network.
struct ServerAccount: Equatable, Sendable {
    var root: String
    var base: String

    /// A tenant URL (`…/t/<tenant>`), as opposed to the server's root.
    static func isTenant(_ url: URL) -> Bool {
        let parts = url.pathComponents
        guard let t = parts.lastIndex(of: "t") else { return false }
        return t + 1 < parts.count && t > 1
    }

    /// `…/<token>/t/<tenant>[/…]` → `…/<token>`; a root stays as it is.
    static func root(of url: URL) -> URL {
        guard isTenant(url), let range = url.absoluteString.range(of: "/t/", options: .backwards),
              let root = URL(string: String(url.absoluteString[..<range.lowerBound]))
        else { return url }
        return root
    }

    /// What to talk to: a tenant URL that was configured by hand as is; else this
    /// install's account if it was made on the configured root; else the root.
    static func resolve(configured: URL?, account: ServerAccount?) -> URL? {
        guard let configured else { return nil }
        if isTenant(configured) { return configured }
        if let account, account.root == configured.absoluteString, let base = URL(string: account.base) { return base }
        return configured
    }

    /// A root is configured and this install has no account on it yet.
    static func needsAccount(configured: URL?, account: ServerAccount?) -> Bool {
        guard let configured, !isTenant(configured) else { return false }
        return account?.root != configured.absoluteString
    }
}

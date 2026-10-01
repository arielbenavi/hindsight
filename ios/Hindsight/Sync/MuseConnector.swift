import Foundation

/// The hindsight connector for Muse (connector/server.py): Muse calls its
/// `submit_saved_posts` tool, and the app pulls what arrived from `/saves`.
/// That replaces copying Muse's reply back into the app.
///
/// Experiment setup: one server per user at `https://<host>/<token>`. Until we
/// host it, the base URL comes from a DEBUG field in the Muse sheet or the
/// `-museConnectorBaseURL <url>` launch argument (remembered after that).
enum MuseConnector {
    static let baseURLKey = "museConnectorBaseURL"
    /// Set once Muse has sent us something, so later syncs skip the setup step.
    static let connectedKey = "museConnectorConnected"

    static var baseURL: URL? {
        let defaults = UserDefaults.standard
        if let fromLaunch = defaults.volatileDomain(forName: UserDefaults.argumentDomain)[baseURLKey] as? String,
           !fromLaunch.isEmpty {
            defaults.set(fromLaunch, forKey: baseURLKey)
        }
        return defaults.string(forKey: baseURLKey).flatMap(normalized)
    }

    static func mcpURL(base: URL) -> URL { base.appending(path: "mcp") }
    static func savesURL(base: URL) -> URL { base.appending(path: "saves") }

    /// Accepts the base, or a pasted `…/mcp` or `…/saves` URL.
    static func normalized(_ string: String) -> URL? {
        var trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        for suffix in ["/mcp", "/saves", "/"] where trimmed.hasSuffix(suffix) {
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

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

    /// First time: add the connector, then send everything.
    static func connectPrompt(mcpURL: URL, window: MusePrompt.Window) -> String {
        """
        Please add a custom connector called "hindsight" with this MCP server URL:
        \(mcpURL.absoluteString)

        Then \(sendInstruction(window: window))
        """
    }

    /// After that: Muse already knows the connector.
    static func syncPrompt(window: MusePrompt.Window) -> String {
        "Please \(sendInstruction(window: window))"
    }

    private static func sendInstruction(window: MusePrompt.Window) -> String {
        let scope = switch window {
        case .all: " (all of them, however many, not just recent ones; ignore any date limits from earlier messages)"
        case .after(let date): " saved after \(MusePrompt.day(date))"
        case .before(let date): " saved before \(MusePrompt.day(date))"
        }
        return """
        use hindsight's submit_saved_posts tool to send it my Instagram and Facebook saved posts\(scope), \
        newest first, in batches of up to 50, with the full captions, collection names and mentions. \
        Keep going until you've sent them all. Don't list the posts in the chat, just tell me how many you sent.
        """
    }

    /// Our own prompts, so pasting one back by mistake can be caught.
    static func isOurPrompt(_ text: String) -> Bool {
        ["List my saved posts from", "Please add a custom connector", "Please use hindsight's"]
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

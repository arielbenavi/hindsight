import Foundation

/// Pulls everything the hindsight server has received (Muse via the connector,
/// the WhatsApp bot, …) and merges it into the store. One pull covers every
/// server-side source, since they all write to the same place.
@MainActor
enum ServerSync {
    struct Result {
        var received: Int
        var added: Int
    }

    static var isConfigured: Bool { MuseConnector.baseURL != nil }

    static func pull(into store: SavedPostStore) async throws -> Result {
        guard let base = MuseConnector.baseURL else { throw URLError(.badURL) }
        let text = try await MuseConnector.fetchSaves(base: base)
        let posts = SavedPostParser.parse(text, source: .muse).posts
        let added = store.merge(posts)
        DebugLog.write("server pull: \(posts.count) on server, +\(added) new")
        return Result(received: posts.count, added: added)
    }
}

/// The hindsight WhatsApp bot (whatsapp-bot/): users connect once by sending it a
/// prefilled "connect code" message, then use that chat (or groups they add it to)
/// as their notes. The number comes from the hindsight server (`/whatsapp`), so it
/// isn't in the public repo; `-whatsAppBotNumber <digits>` overrides it.
@MainActor
enum WhatsAppBot {
    static let numberKey = "whatsAppBotNumber"

    static var number: String? {
        let defaults = UserDefaults.standard
        if let fromLaunch = defaults.volatileDomain(forName: UserDefaults.argumentDomain)[numberKey] as? String,
           !fromLaunch.isEmpty {
            defaults.set(fromLaunch, forKey: numberKey)
        }
        let digits = (defaults.string(forKey: numberKey) ?? "").filter(\.isNumber)
        return digits.isEmpty ? nil : digits
    }

    /// Asks the server for the bot's number and remembers it. Returns the number, if any.
    @discardableResult
    static func refreshNumber() async -> String? {
        guard let base = MuseConnector.baseURL else { return number }
        struct Response: Decodable { var number: String? }
        do {
            let (data, response) = try await URLSession.shared.data(from: base.appending(path: "whatsapp"))
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { return number }
            if let fetched = try JSONDecoder().decode(Response.self, from: data).number, !fetched.isEmpty {
                UserDefaults.standard.set(fetched, forKey: numberKey)
            }
        } catch {
            DebugLog.write("whatsapp bot number fetch failed: \(error.localizedDescription)")
        }
        return number
    }

    /// Which hindsight store the bot files this user's WhatsApp under: the tenant in
    /// the server URL (`…/<token>/t/<tenant>`), or "main" for the default store.
    nonisolated static func connectCode(base: URL?) -> String {
        let parts = base?.pathComponents ?? []
        if let t = parts.firstIndex(of: "t"), t + 1 < parts.count { return parts[t + 1] }
        return "main"
    }

    /// Opens a 1:1 chat with the bot with the connect message typed in; the user
    /// just taps send.
    nonisolated static func connectURL(number: String, code: String) -> URL {
        var components = URLComponents(string: "https://wa.me/\(number)")!
        components.queryItems = [URLQueryItem(name: "text", value: "Hi hindsight 👋 connect code: \(code)")]
        return components.url!
    }
}

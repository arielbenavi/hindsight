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

/// The hindsight WhatsApp bot (whatsapp-bot/): users add its number to their
/// notes chat once. Until it has a permanent number, set it with the DEBUG
/// field or the `-whatsAppBotNumber <digits>` launch argument.
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

    /// Opens a 1:1 chat with the bot, message ready, so the user saves the contact
    /// (then adds it to their notes group, or just uses this chat for notes).
    static func chatURL(number: String) -> URL {
        var components = URLComponents(string: "https://wa.me/\(number)")!
        components.queryItems = [URLQueryItem(name: "text", value: "Hi hindsight 👋")]
        return components.url!
    }
}

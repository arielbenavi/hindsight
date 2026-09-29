import Foundation

/// Answers to "how do you want to see your saves?". Persisted in UserDefaults;
/// the dashboard reads them via `OnboardingPreferences.load()`.
struct OnboardingPreferences: Codable, Equatable, Sendable {
    var grouping: Grouping = .topic
    var layout: Layout = .feed
    var topics: Set<String> = []
    var resurface: Resurface = .weekly

    enum Grouping: String, Codable, CaseIterable, Identifiable, Sendable {
        case topic, platform, creator, time
        var id: String { rawValue }
        var title: String {
            switch self {
            case .topic: "🧠 By topic"
            case .platform: "📱 By app"
            case .creator: "🧑‍🎤 By creator"
            case .time: "🗓️ By when I saved it"
            }
        }
    }

    enum Layout: String, Codable, CaseIterable, Identifiable, Sendable {
        case feed, grid, collections
        var id: String { rawValue }
        var title: String {
            switch self {
            case .feed: "Feed"
            case .grid: "Grid"
            case .collections: "Collections"
            }
        }
        var symbol: String {
            switch self {
            case .feed: "list.bullet.rectangle.portrait"
            case .grid: "square.grid.2x2"
            case .collections: "rectangle.stack"
            }
        }
    }

    enum Resurface: String, Codable, CaseIterable, Identifiable, Sendable {
        case daily, weekly, never
        var id: String { rawValue }
        var title: String {
            switch self {
            case .daily: "Daily"
            case .weekly: "Weekly"
            case .never: "Never"
            }
        }
    }

    static let storageKey = "onboardingPreferences"

    static func load(from defaults: UserDefaults = .standard) -> OnboardingPreferences? {
        defaults.data(forKey: storageKey).flatMap { try? JSONDecoder().decode(Self.self, from: $0) }
    }

    func save(to defaults: UserDefaults = .standard) {
        if let data = try? JSONEncoder().encode(self) {
            defaults.set(data, forKey: Self.storageKey)
        }
    }
}

/// Rough keyword-based topic counts, so the topic picker can show what's
/// actually in the user's saves. Placeholder until real clustering exists.
enum TopicSuggester {
    static let keywords: KeyValuePairs<String, Set<String>> = [
        "ai": ["ai", "chatgpt", "claude", "gpt", "llm", "openai", "gemini", "agent", "agents", "prompt"],
        "coding": ["code", "coding", "python", "programming", "developer", "github", "cursor", "software", "app"],
        "music": ["beat", "beats", "producer", "flstudio", "music", "mixing", "plugin", "synth", "song", "ableton", "808", "sample"],
        "quant": ["quant", "trading", "trader", "finance", "stock", "stocks", "market", "investing", "backtest", "wallstreet", "options"],
        "career": ["career", "interview", "resume", "internship", "job", "careeradvice", "investmentbanking"],
        "productivity": ["productivity", "notion", "habit", "habits", "focus", "workflow", "routine"],
        "design": ["design", "figma", "ui", "ux", "motion", "animation"],
        "money": ["money", "sidehustle", "onlinemoney", "business", "income", "founder", "startup"],
        "fitness": ["gym", "workout", "fitness", "protein", "gains"],
        "food": ["recipe", "food", "cook", "cooking", "pasta", "chef"],
    ]

    /// Topics with at least one matching post, most common first.
    static func counts(for posts: [SavedPost]) -> [(topic: String, count: Int)] {
        var counts: [String: Int] = [:]
        for post in posts {
            guard let caption = post.caption?.lowercased() else { continue }
            let words = Set(caption.split { !$0.isLetter && !$0.isNumber }.map(String.init))
            for (topic, keys) in keywords where !words.isDisjoint(with: keys) {
                counts[topic, default: 0] += 1
            }
        }
        return counts.map { ($0.key, $0.value) }.sorted { $0.count > $1.count }
    }
}

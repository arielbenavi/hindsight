import Foundation

/// Keep close: what the user needs right now, and which of their saves fit. Pure.
enum KeepCloseNeed: String, CaseIterable, Identifiable, Sendable {
    case loud, sleep, lowEnergy, remind

    var id: String { rawValue }

    var title: String {
        switch self {
        case .loud: "My head is loud"
        case .sleep: "Can't sleep"
        case .lowEnergy: "Low energy"
        case .remind: "Just remind me"
        }
    }

    var symbol: String {
        switch self {
        case .loud: "wind"
        case .sleep: "moon.stars.fill"
        case .lowEnergy: "battery.25percent"
        case .remind: "sparkles"
        }
    }

    /// Caption/hashtag words per need (folded; "stem*" = word start), English + Hebrew.
    var keywords: [String] {
        switch self {
        case .loud:
            ["anxiety", "anxious", "overthink*", "calm*", "breath*", "breathe", "panic", "stress*", "overwhelm*", "racing thoughts",
             "ground*", "mindful*", "meditat*", "worry", "worries", "slow down", "let go", "quiet", "peace",
             "חרדה", "חרדות", "לחץ", "נשימה", "נשימות", "רוגע", "שקט", "מחשבות", "להירגע", "מדיטציה"]
        case .sleep:
            ["sleep*", "insomnia", "bedtime", "night*", "rest", "melatonin", "dream*", "tired", "wind down", "relax*",
             "שינה", "לישון", "לילה", "נדודי שינה", "עייפות", "מנוחה"]
        case .lowEnergy:
            ["energy", "tired", "exhaust*", "burnout", "burned out", "motivat*", "lazy", "unmotivated", "depress*", "low",
             "get up", "small steps", "start small", "you got this", "keep going", "rest",
             "אנרגיה", "עייפות", "שחיקה", "מוטיבציה", "כוח", "להמשיך", "צעד קטן"]
        case .remind: []
        }
    }
}

enum KeepClose {
    static let shown = 3

    /// How well a save fits a need: matched keywords in its caption, hashtags and note.
    static func score(_ post: ContractPost, note: String?, need: KeepCloseNeed) -> Int {
        let text = (post.caption ?? "") + " " + post.hashtags.joined(separator: " ") + " " + (note ?? "")
        let words = TopicFallback.words(text).flatMap(TopicFallback.variants)
        let tokens = Set(words)
        let joined = " " + words.joined(separator: " ") + " "
        return need.keywords.reduce(0) { total, raw in
            let k = TextMatch.fold(raw)
            let hit: Bool
            if k.contains(" ") { hit = joined.contains(" \(k) ") }
            else if k.hasSuffix("*") { let stem = String(k.dropLast()); hit = tokens.contains { $0.hasPrefix(stem) } }
            else { hit = tokens.contains(k) }
            return total + (hit ? 1 : 0)
        }
    }

    /// Up to three saves for a need. Matches first (best first, then a gentle
    /// rotation by `round`, so "Show me another" moves on); "Just remind me", or a
    /// need nothing matches, is a deterministic shuffle by `seed` + `round`.
    /// `matched` says whether these were picked for the need.
    static func picks(_ posts: [ContractPost], notes: [String: String] = [:], need: KeepCloseNeed,
                      seed: String, round: Int) -> (posts: [ContractPost], matched: Bool) {
        let scored = need == .remind ? [] : posts.map { ($0, score($0, note: notes[$0.id], need: need)) }.filter { $0.1 > 0 }
        if !scored.isEmpty {
            let ranked = scored.sorted { ($1.1, $0.0.id) < ($0.1, $1.0.id) }.map(\.0)
            return (rotate(ranked, by: round * shown), true)
        }
        var rng = SeededGenerator(seed: hash("\(seed)|\(need.rawValue)|\(round)"))
        let shuffled = posts.sorted { $0.id < $1.id }.shuffled(using: &rng)
        return (Array(shuffled.prefix(shown)), false)
    }

    private static func rotate(_ posts: [ContractPost], by offset: Int) -> [ContractPost] {
        guard posts.count > shown else { return posts }
        let start = offset % posts.count
        return (0..<shown).map { posts[(start + $0) % posts.count] }
    }

    /// FNV-1a: a stable hash (Swift's `hashValue` changes every launch).
    static func hash(_ string: String) -> UInt64 {
        string.utf8.reduce(0xcbf2_9ce4_8422_2325) { ($0 ^ UInt64($1)) &* 0x100_0000_01b3 }
    }
}

/// A Do topic as a checklist. Pure.
enum DoList {
    /// To do first (in the topic's order), then done.
    static func ordered(_ posts: [ContractPost], states: [String: SaveState]) -> (todo: [ContractPost], done: [ContractPost]) {
        let done = posts.filter { states[$0.id]?.status == .done }
        let todo = posts.filter { (states[$0.id]?.status ?? .new) == .new }
        return (todo, done)
    }

    /// "6 of 34 done": let-go saves don't count.
    static func progress(_ posts: [ContractPost], states: [String: SaveState]) -> (done: Int, total: Int) {
        let list = ordered(posts, states: states)
        return (list.done.count, list.todo.count + list.done.count)
    }

    /// "Pick one for tonight": a not-done save, by `seed`.
    static func pickOne(_ todo: [ContractPost], seed: String) -> ContractPost? {
        guard !todo.isEmpty else { return nil }
        return todo[Int(KeepClose.hash(seed) % UInt64(todo.count))]
    }
}

/// Look: the masonry board. Pure.
enum LookBoard {
    /// A tile's height for a column width: thumbnails have no size in the data, so
    /// the aspect comes from the post id (stable) between 0.9 and 1.5.
    static func aspect(_ post: ContractPost) -> Double {
        0.9 + Double(KeepClose.hash(post.id) % 61) / 100
    }

    /// Two columns, each tile into the shorter one, in order.
    static func columns(_ posts: [ContractPost]) -> (left: [ContractPost], right: [ContractPost]) {
        var left: [ContractPost] = [], right: [ContractPost] = []
        var lh = 0.0, rh = 0.0
        for post in posts {
            if lh <= rh { left.append(post); lh += aspect(post) } else { right.append(post); rh += aspect(post) }
        }
        return (left, right)
    }
}

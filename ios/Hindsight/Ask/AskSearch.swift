import Foundation

/// Ask's ready-made questions (shown while the query is empty). Pure.
enum AskFilter: String, CaseIterable, Identifiable, Sendable {
    case neverOpened, thisMonth, done, letGo, notes

    var id: String { rawValue }

    var title: String {
        switch self {
        case .neverOpened: "Never opened"
        case .thisMonth: "Saved this month"
        case .done: "Done"
        case .letGo: "Let go"
        case .notes: "Notes"
        }
    }

    var symbol: String {
        switch self {
        case .neverOpened: "eye.slash"
        case .thisMonth: "calendar"
        case .done: "checkmark.circle"
        case .letGo: "xmark.circle"
        case .notes: "note.text"
        }
    }

    func matches(_ post: ContractPost, state: SaveState, now: Date, calendar: Calendar = .current) -> Bool {
        switch self {
        case .neverOpened: state.lastOpened == nil && state.status != .letGo
        case .thisMonth: post.savedDate.map { calendar.isDate($0, equalTo: now, toGranularity: .month) } ?? false
        case .done: state.status == .done
        case .letGo: state.status == .letGo
        case .notes: state.hasNote
        }
    }

    func apply(_ posts: [ContractPost], states: [String: SaveState], now: Date, calendar: Calendar = .current) -> [ContractPost] {
        posts.filter { matches($0, state: states[$0.id] ?? .initial, now: now, calendar: calendar) }
    }
}

/// Ask's search: every save (let-go ones too), over caption, author, hashtags,
/// collections, the topic's name and the user's note. Pure.
enum AskSearch {
    struct Result: Identifiable, Hashable, Sendable {
        let post: ContractPost
        /// The topic's name, when the query matched it (shown as a chip).
        let matchedTopic: String?
        /// The query matched the user's note.
        let matchedNote: Bool
        var id: String { post.id }
    }

    static func results(_ query: String, posts: [ContractPost], states: [String: SaveState],
                        topicLabel: (String) -> String?) -> [Result] {
        let terms = TextMatch.terms(query)
        guard !terms.isEmpty else { return [] }
        var out: [(Result, Int, Int)] = []
        for (index, post) in posts.enumerated() {
            let topic = topicLabel(post.id)
            let note = states[post.id]?.note
            let score = TextMatch.score(terms: terms, fields: [
                (post.caption, 2), (post.author.username, 2), (post.author.displayName, 2),
                (post.hashtags.joined(separator: " "), 2), (post.collections.joined(separator: " "), 1),
                (topic, 1), (note, 3),
            ])
            guard score > 0 else { continue }
            let topicHit = topic.map { label in terms.allSatisfy { TextMatch.fold(label).contains($0) } } ?? false
            let noteHit = note.map { n in terms.contains { TextMatch.fold(n).contains($0) } } ?? false
            out.append((Result(post: post, matchedTopic: topicHit ? topic : nil, matchedNote: noteHit), score, index))
        }
        // Best first; ties keep the saves' order (newest first).
        return out.sorted { ($1.1, $0.2) < ($0.1, $1.2) }.map(\.0)
    }
}

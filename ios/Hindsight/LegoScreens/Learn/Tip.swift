import Foundation

/// A Learn tip: one saved post plus what extraction pulled out of it. Read-only;
/// the user's side lives in `PracticeState`.
struct Tip: Identifiable, Hashable, Sendable {
    var id: String { post.id }
    var post: ContractPost
    var topicID: String
    var title: String
    var gist: String?
    var tryPrompt: String?
    var type: TipType
    var keyPoints: [String]
    var ctaKeyword: String?
    var isThin: Bool

    /// "Comment GUIDE and I'll DM it to you": the real content is behind a DM, so the
    /// caption's call to action isn't a tip. Gated posts stay in the library (with a
    /// "Behind a DM" tag) but are never practiced. If the caption itself lists the key
    /// points, there is a tip after all.
    var isGated: Bool { ctaKeyword != nil && keyPoints.isEmpty }

    /// Only tips with a concrete prompt go into Today's 1 and setup; thin and gated
    /// ones stay in the library.
    var isPickable: Bool { !isThin && !isGated && prompt != nil }

    /// The try prompt, never "comment X to get the link" (that's not practice).
    var prompt: String? {
        guard let tryPrompt, !Self.isCommentInstruction(tryPrompt, keyword: ctaKeyword) else { return nil }
        return tryPrompt
    }

    static func isCommentInstruction(_ text: String, keyword: String?) -> Bool {
        let t = TextMatch.fold(text)
        if t.hasPrefix("comment") || t.contains("comment \"") || t.contains("dm ") { return true }
        if let keyword, t.contains("comment"), t.contains(TextMatch.fold(keyword)) { return true }
        return false
    }

    init(post: ContractPost, topicID: String, extracted: ExtractedTip?) {
        self.post = post
        self.topicID = topicID
        if let e = extracted {
            title = e.title
            gist = e.gist
            tryPrompt = e.tryPrompt
            type = e.tipType
            keyPoints = e.keyPoints
            ctaKeyword = e.ctaKeyword
            isThin = e.isThin
        } else {
            // A post moved into Learn without a tip: library only.
            title = String((post.firstLine ?? "Saved post by \(post.byline)").prefix(60))
            gist = nil
            tryPrompt = nil
            type = .idea
            keyPoints = []
            ctaKeyword = nil
            isThin = true
        }
    }
}

/// A Learn section: a topic and its tips, largest first.
struct LearnSection: Identifiable, Hashable, Sendable {
    var topic: ContractTopic
    var tips: [Tip]
    var id: String { topic.id }
    var emoji: String { topic.emoji ?? "📚" }
    var title: String { topic.label }
}

/// Everything in the Learn tab, from the data and the approved layout.
struct LearnCatalog: Sendable {
    var sections: [LearnSection]
    var tipsByID: [String: Tip]

    var tips: [Tip] { sections.flatMap(\.tips) }

    init(data: HindsightData, topicIDs: [String]) {
        var sections: [LearnSection] = []
        for id in topicIDs {
            guard let topic = data.topic(id) else { continue }
            let tips = topic.postIds.compactMap { pid -> Tip? in
                guard let post = data.post(pid) else { return nil }
                return Tip(post: post, topicID: id, extracted: data.item(for: pid)?.tip)
            }
            // gated ("comment X for the guide") posts go to the end of their section
            let sorted = tips.filter { !$0.isGated } + tips.filter(\.isGated)
            if !sorted.isEmpty { sections.append(LearnSection(topic: topic, tips: sorted)) }
        }
        self.sections = sections.sorted { $0.tips.count > $1.tips.count }
        tipsByID = Dictionary(uniqueKeysWithValues: self.sections.flatMap(\.tips).map { ($0.id, $0) })
    }

    var candidates: [PracticeCandidate] {
        tips.map { PracticeCandidate(id: $0.id, topicKey: $0.topicID, isPickable: $0.isPickable) }
    }

    func section(_ id: String) -> LearnSection? { sections.first { $0.id == id } }
}

/// L6 search: title above gist/points/prompt above caption/hashtags/author/topic.
/// Case- and accent-insensitive; works for Hebrew. Pure.
enum TipSearch {
    static func search(_ query: String, in tips: [Tip], topicLabel: (String) -> String = { $0 }) -> [Tip] {
        let terms = TextMatch.terms(query)
        guard !terms.isEmpty else { return [] }
        return tips.compactMap { tip -> (Tip, Int)? in
            let fields: [(String?, Int)] = [
                (tip.title, 10),
                (tip.gist, 5), (tip.keyPoints.joined(separator: " "), 5), (tip.tryPrompt, 5),
                (topicLabel(tip.topicID), 3),
                (tip.post.caption, 2), (tip.post.hashtags.joined(separator: " "), 2), (tip.post.author.username, 2),
            ]
            let score = TextMatch.score(terms: terms, fields: fields)
            return score > 0 ? (tip, score) : nil
        }
        .sorted { $0.1 > $1.1 }
        .map(\.0)
    }
}

/// Shared text matching for the search screens.
enum TextMatch {
    static func fold(_ s: String) -> String {
        s.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: nil)
    }

    static func terms(_ query: String) -> [String] {
        fold(query).split(whereSeparator: { $0.isWhitespace || $0 == "," }).map(String.init).filter { !$0.isEmpty }
    }

    /// Every term must match some field; the score sums the best field weight per term.
    static func score(terms: [String], fields: [(String?, Int)]) -> Int {
        let folded = fields.map { ($0.0.map(fold) ?? "", $0.1) }
        var total = 0
        for term in terms {
            let best = folded.filter { $0.0.contains(term) }.map(\.1).max()
            guard let best else { return 0 }
            total += best
        }
        return total
    }
}

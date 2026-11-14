import Foundation

/// Topics → tabs (layout-proposal.md → "Topics → tabs"). Pure.
enum LayoutRules {
    static let threshold = 5
    static let maxQuestions = 2
    static let fewSaves = 20

    /// The editable proposal: which topics sit in which tab, and in what order.
    struct Draft: Equatable, Sendable {
        var tabs: [TabConfig]
        var excludedTopicIDs: [String]

        func tab(for screen: LegoScreen) -> TabConfig? { tabs.first { $0.legoScreen == screen } }

        func config(now: Date = .now) -> LayoutConfig {
            LayoutConfig(tabs: tabs, excludedTopicIDs: excludedTopicIDs, createdAt: now)
        }
    }

    /// What the chat shows before the proposal (B1) and the questions (B2).
    struct Proposal: Equatable, Sendable {
        var draft: Draft
        var questions: [ContractTopic]
        /// Screens that could be added but didn't make the threshold ("Also add a map? 4 spots").
        var offers: [LegoScreen]
        var situation: Situation
    }

    enum Situation: Equatable, Sendable { case normal, oneTab, nothingFits, fewSaves }

    /// Topics currently assigned to each screen (after any answers/moves).
    typealias Assignment = [String: LegoScreen?]

    static func naturalAssignment(_ data: HindsightData) -> Assignment {
        Dictionary(uniqueKeysWithValues: data.topics.map { ($0.id, $0.legoScreen) })
    }

    static func propose(_ data: HindsightData, assignment: Assignment? = nil) -> Proposal {
        let assignment = assignment ?? naturalAssignment(data)
        var tabs: [TabConfig] = []
        var offers: [LegoScreen] = []
        var excluded: [String] = []

        func topics(for screen: LegoScreen) -> [ContractTopic] {
            data.topics.filter { assignment[$0.id] == .some(screen) }.sorted { $0.postIds.count > $1.postIds.count }
        }

        var learnTopics = topics(for: .learn)
        let fitnessTopics = topics(for: .fitness)
        let fitnessCount = fitnessTopics.reduce(0) { $0 + $1.postIds.count }
        if fitnessCount >= threshold {
            tabs.append(TabConfig(legoScreen: .fitness, topicIDs: fitnessTopics.map(\.id)))
        } else {
            learnTopics += fitnessTopics  // under 5: they go to Learn
        }
        let learnCount = learnTopics.reduce(0) { $0 + $1.postIds.count }
        if learnCount >= threshold {
            tabs.append(TabConfig(legoScreen: .learn, topicIDs: learnTopics.map(\.id)))
        }
        let mapTopics = topics(for: .map)
        if placeCount(mapTopics, data) >= threshold {
            tabs.append(TabConfig(legoScreen: .map, topicIDs: mapTopics.map(\.id)))
        } else if !mapTopics.isEmpty {
            offers.append(.map)
            excluded += mapTopics.map(\.id)
        }

        // Order: largest first, but the Map always first.
        let size = { (tab: TabConfig) in tab.topicIDs.reduce(0) { $0 + (data.topic($1)?.postIds.count ?? 0) } }
        tabs.sort { a, b in
            if a.legoScreen == .map { return true }
            if b.legoScreen == .map { return false }
            return size(a) > size(b)
        }

        var situation = Situation.normal
        if tabs.isEmpty {
            situation = .nothingFits
            if !learnTopics.isEmpty { tabs = [TabConfig(legoScreen: .learn, topicIDs: learnTopics.map(\.id))] }
        } else if tabs.count == 1 {
            situation = .oneTab
        }
        if learnCount < threshold, !tabs.contains(where: { $0.legoScreen == .learn }) {
            excluded += learnTopics.map(\.id)
        }
        excluded += data.topics.filter { assignment[$0.id] == .some(nil) }.map(\.id)

        let total = data.posts.count
        if total < fewSaves { situation = situation == .normal ? .fewSaves : situation }
        let questions = total < fewSaves ? [] : Array(data.topics
            .filter { $0.ambiguity != nil && assignment[$0.id] == naturalAssignment(data)[$0.id] }
            .sorted { ($0.confidence == .low ? 0 : 1, -$0.postIds.count) < ($1.confidence == .low ? 0 : 1, -$1.postIds.count) }
            .prefix(maxQuestions))

        return Proposal(draft: Draft(tabs: tabs, excludedTopicIDs: excluded), questions: questions, offers: offers, situation: situation)
    }

    static func placeCount(_ topics: [ContractTopic], _ data: HindsightData) -> Int {
        topics.flatMap(\.postIds).reduce(0) { $0 + (data.item(for: $1)?.places?.count ?? 0) }
    }

    /// Posts per tab ("Guitar · Design inspo, 71 posts").
    static func postCount(_ tab: TabConfig, _ data: HindsightData) -> Int {
        tab.topicIDs.reduce(0) { $0 + (data.topic($1)?.postIds.count ?? 0) }
    }

    /// The "what's inside" line on the app preview card (B3).
    static func summary(_ tab: TabConfig, _ data: HindsightData) -> String {
        let topics = tab.topicIDs.compactMap { data.topic($0) }
        switch tab.legoScreen {
        case .map:
            let spots = placeCount(topics, data)
            let labels = topics.prefix(3).map(\.label).joined(separator: ", ")
            return "\(spots) spots · \(labels)"
        case .learn, .fitness:
            let labels = topics.prefix(3).map(\.label).joined(separator: " · ")
            let more = topics.count > 3 ? " +\(topics.count - 3)" : ""
            return "\(labels)\(more), \(postCount(tab, data)) posts"
        }
    }
}

/// The edit operations on a draft (B4), from taps or typed text.
enum LayoutEdit: Equatable, Sendable {
    case add(LegoScreen)
    case remove(LegoScreen)
    case rename(LegoScreen, String)
    case changeEmoji(LegoScreen, String)
    case move(LegoScreen, toIndex: Int)
    case leaveOut(topicID: String)

    /// One-line confirmation after the edit ("Done. Learn is just guitar now.").
    func confirmation(_ draft: LayoutRules.Draft, _ data: HindsightData) -> String {
        switch self {
        case .add(let s): return "Done. Added \(draft.tab(for: s)?.title ?? s.defaultTitle)."
        case .remove(let s): return "Done. No \(s.defaultTitle) tab."
        case .rename(_, let name): return "Done. It's called \(name) now."
        case .changeEmoji(_, let e): return "Done. \(e) it is."
        case .move(let s, let i): return i == 0 ? "Done. \(draft.tab(for: s)?.title ?? s.defaultTitle) comes first." : "Done. Moved it."
        case .leaveOut(let id):
            let label = data.topic(id)?.label ?? "that"
            if let tab = draft.tabs.first(where: { t in data.topic(id).map { $0.legoScreen == t.legoScreen } ?? false }) {
                let rest = tab.topicIDs.compactMap { data.topic($0)?.label.lowercased() }
                if rest.count == 1 { return "Done. \(tab.title) is just \(rest[0]) now." }
            }
            return "Done. Left out \(label)."
        }
    }

    /// Apply to a draft. Unknown targets leave it unchanged.
    func apply(to draft: LayoutRules.Draft, data: HindsightData) -> LayoutRules.Draft {
        var d = draft
        switch self {
        case .add(let screen):
            guard d.tab(for: screen) == nil else { return d }
            let ids = data.topics.filter { $0.legoScreen == screen }.map(\.id)
            d.tabs.append(TabConfig(legoScreen: screen, topicIDs: ids))
            d.excludedTopicIDs.removeAll { ids.contains($0) }
            if screen == .map, let i = d.tabs.firstIndex(where: { $0.legoScreen == .map }) {
                d.tabs.insert(d.tabs.remove(at: i), at: 0)
            }
        case .remove(let screen):
            guard let i = d.tabs.firstIndex(where: { $0.legoScreen == screen }) else { return d }
            d.excludedTopicIDs += d.tabs[i].topicIDs
            d.tabs.remove(at: i)
        case .rename(let screen, let name):
            let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, let i = d.tabs.firstIndex(where: { $0.legoScreen == screen }) else { return d }
            d.tabs[i].title = String(trimmed.prefix(20))
        case .changeEmoji(let screen, let emoji):
            guard let i = d.tabs.firstIndex(where: { $0.legoScreen == screen }) else { return d }
            d.tabs[i].emoji = emoji
        case .move(let screen, let index):
            guard let i = d.tabs.firstIndex(where: { $0.legoScreen == screen }) else { return d }
            let tab = d.tabs.remove(at: i)
            d.tabs.insert(tab, at: max(0, min(index, d.tabs.count)))
        case .leaveOut(let id):
            for i in d.tabs.indices { d.tabs[i].topicIDs.removeAll { $0 == id } }
            if !d.excludedTopicIDs.contains(id) { d.excludedTopicIDs.append(id) }
            d.tabs.removeAll { $0.topicIDs.isEmpty }
        }
        return d
    }

    /// Screens that can still be added, with how many posts they'd bring (B4 "+ Add").
    static func addable(_ draft: LayoutRules.Draft, _ data: HindsightData) -> [(screen: LegoScreen, count: Int)] {
        LegoScreen.allCases.compactMap { screen in
            guard draft.tab(for: screen) == nil else { return nil }
            let topics = data.topics.filter { $0.legoScreen == screen }
            guard !topics.isEmpty else { return nil }
            let count = screen == .map ? LayoutRules.placeCount(topics, data) : topics.reduce(0) { $0 + $1.postIds.count }
            return (screen, count)
        }
    }
}

/// Typed edits without an LLM: a few phrasings per operation. Returns nil when it
/// can't tell, so the bot asks with chips instead of guessing.
enum TypedEditParser {
    static func parse(_ text: String, draft: LayoutRules.Draft, data: HindsightData, lastTouched: LegoScreen?) -> LayoutEdit? {
        let raw = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = TextMatch.fold(raw)
        let words = lower.split(whereSeparator: { !$0.isLetter && !$0.isNumber && $0 != "'" }).map(String.init)
        guard let verb = words.first else { return nil }

        // rename: "call it Eats", "call map Eats", "rename learn to Skills"
        if ["call", "rename", "name"].contains(verb) {
            var rest = Array(words.dropFirst())
            var target: LegoScreen?
            if rest.first == "it" || rest.first == "that" {
                rest.removeFirst()
                target = lastTouched ?? (draft.tabs.count == 1 ? draft.tabs[0].legoScreen : nil)
            } else if let first = rest.first, let s = screen(named: first, draft: draft) {
                rest.removeFirst()
                target = s
            } else if rest.first == "the", rest.count > 1, let s = screen(named: rest[1], draft: draft) {
                rest.removeFirst(2)
                target = s
            }
            if rest.first == "to" || rest.first == "as" { rest.removeFirst() }
            guard let target, !rest.isEmpty else { return nil }
            // keep the user's casing: take the tail of the original text
            let newName = originalTail(raw, wordCount: rest.count)
            return .rename(target, newName.capitalizedFirst)
        }

        // remove / leave out: "drop design", "remove fitness", "no map", "without memes"
        if ["drop", "remove", "delete", "hide", "no", "without", "lose", "skip"].contains(verb) {
            let target = words.dropFirst().filter { $0 != "the" && $0 != "tab" && $0 != "my" }.joined(separator: " ")
            guard !target.isEmpty else { return nil }
            if let s = screen(named: target, draft: draft) { return .remove(s) }
            if let topic = topic(named: target, draft: draft, data: data) { return .leaveOut(topicID: topic) }
            return nil
        }

        // reorder: "put learn first", "move map last", "fitness first"
        if words.contains("first") || words.contains("last") {
            let candidates = words.filter { $0 != "put" && $0 != "move" && $0 != "first" && $0 != "last" && $0 != "the" }
            guard let s = candidates.lazy.compactMap({ screen(named: $0, draft: draft) }).first else { return nil }
            return .move(s, toIndex: words.contains("first") ? 0 : draft.tabs.count - 1)
        }

        // add: "add a map", "add fitness"
        if verb == "add" || (verb == "also" && words.contains("add")) {
            guard let s = words.lazy.compactMap({ screen(named: $0, draft: nil) }).first else { return nil }
            return .add(s)
        }
        return nil
    }

    /// A screen by its default name, the user's title, or a synonym.
    static func screen(named name: String, draft: LayoutRules.Draft?) -> LegoScreen? {
        let n = TextMatch.fold(name).trimmingCharacters(in: .whitespaces)
        if let tab = draft?.tabs.first(where: { TextMatch.fold($0.title) == n }) { return tab.legoScreen }
        let synonyms: [LegoScreen: [String]] = [
            .map: ["map", "maps", "places", "spots"],
            .learn: ["learn", "learning", "education", "tips"],
            .fitness: ["fitness", "workout", "workouts", "exercise", "stretches", "gym"],
        ]
        return synonyms.first { $0.value.contains(n) }?.key
    }

    /// A topic in the draft by (partial) label or id.
    static func topic(named name: String, draft: LayoutRules.Draft, data: HindsightData) -> String? {
        let n = TextMatch.fold(name)
        let ids = draft.tabs.flatMap(\.topicIDs)
        let matches = ids.filter { id in
            guard let t = data.topic(id) else { return false }
            let label = TextMatch.fold(t.label)
            return label == n || label.contains(n) || id.contains(n.replacingOccurrences(of: " ", with: "-"))
        }
        return matches.count == 1 ? matches[0] : nil
    }

    private static func originalTail(_ text: String, wordCount: Int) -> String {
        let parts = text.split(separator: " ")
        return parts.suffix(wordCount).joined(separator: " ").trimmingCharacters(in: .punctuationCharacters)
    }
}

extension String {
    var capitalizedFirst: String { prefix(1).uppercased() + dropFirst() }
}

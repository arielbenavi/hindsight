import Foundation

/// Topics → the views' layout (layout-proposal.md → "Topics → tabs"): which
/// topics Map, Learn and Fitness show. Set automatically (`AppModel.autoSetup`). Pure.
enum LayoutRules {
    static let threshold = 5
    static let maxQuestions = 2
    static let fewSaves = 20

    /// Which topics sit in which view, and in what order.
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
}

extension String {
    var capitalizedFirst: String { prefix(1).uppercased() + dropFirst() }
}

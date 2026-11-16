import Foundation

/// Topics → the views' layout (layout-proposal.md → "Topics → tabs"): which
/// topics Map, Learn and Fitness show. Set automatically (`AppModel.autoSetup`). Pure.
enum LayoutRules {
    static let threshold = 5

    /// Which topics sit in which view, and in what order.
    struct Draft: Equatable, Sendable {
        var tabs: [TabConfig]
        var excludedTopicIDs: [String]

        func tab(for screen: LegoScreen) -> TabConfig? { tabs.first { $0.legoScreen == screen } }

        func config(now: Date = .now) -> LayoutConfig {
            LayoutConfig(tabs: tabs, excludedTopicIDs: excludedTopicIDs, createdAt: now)
        }
    }

    /// Every view with enough in it, and its topics. Topics no view fits (`legoScreen`
    /// nil: memes, news…) stay out of the views; Home lists them under Topics.
    static func propose(_ data: HindsightData) -> Draft {
        var tabs: [TabConfig] = []
        var excluded: [String] = []

        func topics(for screen: LegoScreen) -> [ContractTopic] {
            data.topics.filter { $0.legoScreen == screen }.sorted { $0.postIds.count > $1.postIds.count }
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
        } else {
            excluded += mapTopics.map(\.id)
        }

        // Order: largest first, but the Map always first.
        let size = { (tab: TabConfig) in tab.topicIDs.reduce(0) { $0 + (data.topic($1)?.postIds.count ?? 0) } }
        tabs.sort { a, b in
            if a.legoScreen == .map { return true }
            if b.legoScreen == .map { return false }
            return size(a) > size(b)
        }

        // Nothing big enough anywhere: Learn with what there is.
        if tabs.isEmpty, !learnTopics.isEmpty {
            tabs = [TabConfig(legoScreen: .learn, topicIDs: learnTopics.map(\.id))]
        } else if learnCount < threshold {
            excluded += learnTopics.map(\.id)
        }
        excluded += data.topics.filter { $0.legoScreen == nil }.map(\.id)
        return Draft(tabs: tabs, excludedTopicIDs: excluded)
    }

    static func placeCount(_ topics: [ContractTopic], _ data: HindsightData) -> Int {
        topics.flatMap(\.postIds).reduce(0) { $0 + (data.item(for: $1)?.places?.count ?? 0) }
    }
}

extension String {
    var capitalizedFirst: String { prefix(1).uppercased() + dropFirst() }
}

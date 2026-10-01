import Foundation

/// The approved app layout (layout-proposal.md). The tab bar is built only from this.
struct LayoutConfig: Codable, Equatable, Sendable {
    var tabs: [TabConfig]              // in tab-bar order
    var excludedTopicIDs: [String]     // "left out for now"
    var createdAt: Date
    var version: Int = LayoutConfig.currentVersion

    static let currentVersion = 1

    func tab(for screen: LegoScreen) -> TabConfig? { tabs.first { $0.legoScreen == screen } }
    var hasMap: Bool { tab(for: .map) != nil }
}

struct TabConfig: Codable, Equatable, Identifiable, Sendable {
    var id: String
    var legoScreen: LegoScreen
    var title: String                  // "Map", or the user's rename ("Eats")
    var emoji: String
    var topicIDs: [String]             // sections inside the tab

    init(legoScreen: LegoScreen, title: String? = nil, emoji: String? = nil, topicIDs: [String]) {
        self.id = legoScreen.rawValue
        self.legoScreen = legoScreen
        self.title = title ?? legoScreen.defaultTitle
        self.emoji = emoji ?? legoScreen.defaultEmoji
        self.topicIDs = topicIDs
    }
}

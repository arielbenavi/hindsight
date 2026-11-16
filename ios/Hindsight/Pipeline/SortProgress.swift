import Foundation

/// How far the sort engine is (Home's "Sorting your saves… 180 / 412" strip),
/// and when first-time setup stops waiting for it.
struct SortProgress: Equatable, Sendable {
    struct TopicCount: Equatable, Sendable, Identifiable {
        var id: String
        var label: String
        var emoji: String
        var count: Int
    }

    var decided: Int
    var total: Int
    /// Topics that have a home (a lego screen), biggest first.
    var topics: [TopicCount]

    var fraction: Double { total == 0 ? 1 : Double(decided) / Double(total) }
    var isComplete: Bool { decided >= total }

    /// When first-time setup stops waiting and writes the first file (`AppModel.autoSetup`;
    /// tuned for real model speed, ~4 posts/s): at 90% sorted; or after 20 s once half is
    /// sorted (so topics never come from a handful of posts); or after 3 min regardless.
    static let handOffFraction = 0.9
    static let handOffAfter: Duration = .seconds(20)
    static let handOffMinimumFraction = 0.5
    static let handOffLimit: Duration = .seconds(180)

    func shouldHandOff(after elapsed: Duration) -> Bool {
        fraction >= Self.handOffFraction
            || (elapsed >= Self.handOffAfter && fraction >= Self.handOffMinimumFraction)
            || elapsed >= Self.handOffLimit
    }
}

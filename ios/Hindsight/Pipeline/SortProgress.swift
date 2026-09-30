import Foundation

/// What the setup chat shows while saves are being sorted ("Reading your
/// saves… 180 of 412", with topic chips popping in). The sort engine (ADR-001,
/// E1–E2) will produce this; until it exists, `SimulatedSort` replays a
/// contract file's topics so the chat can be built and tested.
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

    /// The chat moves on at ≥ 90% decided (spec decision 3); the time limit is the caller's.
    static let handOffFraction = 0.9
    static let handOffAfter: Duration = .seconds(20)
}

/// Replays a contract file as if it were being sorted: posts get "decided" in
/// file order over `duration`, and each topic's chip grows as its posts land.
enum SimulatedSort {
    static func progress(for data: HindsightData, steps: Int = 24, duration: Duration = .seconds(5)) -> AsyncStream<SortProgress> {
        let snapshots = snapshots(for: data, steps: steps)
        let pause = duration / max(steps, 1)
        return AsyncStream { continuation in
            let task = Task {
                for snapshot in snapshots {
                    if Task.isCancelled { break }
                    continuation.yield(snapshot)
                    try? await Task.sleep(for: pause)
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// The same sequence, without the timing (tests).
    static func snapshots(for data: HindsightData, steps: Int) -> [SortProgress] {
        let posts = data.posts
        let total = posts.count
        guard total > 0, steps > 0 else { return [SortProgress(decided: 0, total: 0, topics: [])] }
        return (1...steps).map { step in
            // Bundled data is fully sorted: jump to done near the end instead of
            // stopping at the 90% hand-off with "the rest in the background".
            let decided = step * 100 / steps >= 85 ? total : total * step / steps
            var counts: [String: Int] = [:]
            for post in posts.prefix(decided) {
                if let topic = data.topic(forPost: post.id), topic.legoScreen != nil { counts[topic.id, default: 0] += 1 }
            }
            let topics = counts.compactMap { id, count -> SortProgress.TopicCount? in
                guard let topic = data.topic(id) else { return nil }
                return .init(id: id, label: topic.label, emoji: topic.emoji ?? topic.legoScreen?.defaultEmoji ?? "•", count: count)
            }
            .sorted { $0.count != $1.count ? $0.count > $1.count : $0.label < $1.label }
            return SortProgress(decided: decided, total: total, topics: topics)
        }
    }
}

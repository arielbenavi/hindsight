import Foundation
import Testing
@testable import Hindsight

@MainActor
struct SetupChatTests {
    @Test func simulatedSortGrowsToCompleteAndHandsOff() throws {
        let data = try Fixtures.load("reut")
        let snapshots = SimulatedSort.snapshots(for: data, steps: 24)
        #expect(snapshots.map(\.decided) == snapshots.map(\.decided).sorted())
        #expect(snapshots.last?.isComplete == true)
        // The first snapshot past the hand-off point is already complete: no "rest in the background" for sample data.
        #expect(snapshots.first { $0.fraction >= SortProgress.handOffFraction }?.isComplete == true)
        #expect(snapshots.last?.topics.first.map { $0.count } ?? 0 >= snapshots.last?.topics.last.map { $0.count } ?? 0)
    }
}

struct HandOffTests {
    private func progress(_ decided: Int, of total: Int) -> SortProgress { SortProgress(decided: decided, total: total, topics: []) }

    @Test func movesOnAtNinetyPercentOrWhenHalfIsDoneAfterTwentySeconds() {
        #expect(progress(90, of: 100).shouldHandOff(after: .seconds(1)))
        #expect(!progress(30, of: 100).shouldHandOff(after: .seconds(25)))  // not from a handful of posts
        #expect(progress(55, of: 100).shouldHandOff(after: .seconds(25)))
        #expect(!progress(55, of: 100).shouldHandOff(after: .seconds(10)))
        #expect(progress(5, of: 100).shouldHandOff(after: .seconds(181)))   // never wait forever
    }
}

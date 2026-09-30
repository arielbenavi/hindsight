import Foundation
import Testing
@testable import Hindsight

@MainActor
struct SetupChatTests {
    private func post(_ id: String, _ platform: Platform) -> ContractPost {
        ContractPost(id: id, platform: platform, url: URL(string: "https://example.com/\(id)")!, author: "a", caption: "c")
    }

    @Test func receiptLineNamesEachPlatform() {
        let posts = [post("1", .instagram), post("2", .instagram), post("3", .x)]
        #expect(SetupChatModel.receiptLine(posts) == "Got them. 3 saves: 2 from Instagram and 1 from X.")
        #expect(SetupChatModel.receiptLine([post("1", .instagram)]) == "Got them. 1 saves from Instagram.")
    }

    @Test func tastePrefersOnePerPlatform() {
        let posts = [post("1", .instagram), post("2", .instagram), post("3", .x), post("4", .instagram)]
        #expect(SetupChatModel.tastePosts(posts).map(\.id) == ["1", "3", "2"])
    }

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

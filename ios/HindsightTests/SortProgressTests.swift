import Foundation
import Testing
@testable import Hindsight

/// When background sorting has enough to show topics (`AppModel.autoSetup`).
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

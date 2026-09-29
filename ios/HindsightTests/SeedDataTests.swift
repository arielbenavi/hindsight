import Testing
@testable import Hindsight

struct SeedDataTests {
    @Test func seedDataIsBundled() {
        #expect(SeedData.markdown() != nil)
    }

    @Test func countsEverySavedPost() {
        #expect(SeedData.savedPostCount() == 1216)
    }
}

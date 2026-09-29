import Foundation
import Testing
@testable import Hindsight

@MainActor
struct MuseSyncTests {
    @Test func promptPinsTheJSONSchema() throws {
        let since = try Date("2026-09-27T00:00:00Z", strategy: .iso8601)
        let prompt = MusePrompt.text(since: since)
        #expect(prompt.contains("Instagram and Facebook"))
        #expect(prompt.contains("saved after 2026-09-27"))
        for key in ["\"platform\"", "\"author\"", "\"kind\"", "\"date\"", "\"caption\"", "\"url\""] {
            #expect(prompt.contains(key))
        }
    }

    @Test func deepLinkCarriesThePrompt() throws {
        let url = try #require(MuseLauncher.deepLink(prompt: "list my saves & more"))
        #expect(url.scheme == "muse")
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems
        #expect(items?.first { $0.name == "text" }?.value == "list my saves & more")
    }

    @Test func sampleReplyMergesIntoSeedWithoutDuplicates() {
        let result = SavedPostParser.parse(MuseSampleReply.text)
        #expect(result.posts.count == 5)
        #expect(result.posts.count { $0.platform == .facebook } == 2)

        let store = SavedPostStore(fileURL: nil)
        #expect(store.posts.count == 1216)
        #expect(store.merge(result.posts) == 4)
        #expect(store.merge(result.posts) == 0)
        #expect(store.count(for: .facebook) == 2)
    }
}

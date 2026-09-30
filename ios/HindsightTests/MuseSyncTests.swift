import Foundation
import Testing
@testable import Hindsight

@MainActor
struct MuseSyncTests {
    @Test func promptAsksForTheContractFields() throws {
        let day = try #require(SavedPostParser.parseDate("2026-09-27"))
        let newer = MusePrompt.text(window: .after(day))
        #expect(newer.contains("Instagram and Facebook"))
        #expect(newer.contains("saved after 2026-09-27"))
        #expect(newer.contains("full caption"))
        #expect(!newer.contains("160"))
        for key in ["\"platform\"", "\"url\"", "\"author\"", "\"author_display_name\"", "\"caption\"",
                    "\"mentions\"", "\"collections\"", "\"saved_at\"", "\"posted_at\"", "\"location_tag\""] {
            #expect(newer.contains(key))
        }
        #expect(MusePrompt.text(window: .before(day)).contains("saved before 2026-09-27"))
        #expect(!MusePrompt.text().contains("saved after"))
    }

    @Test func deepLinkCarriesThePrompt() throws {
        let url = MuseLauncher.chatURL(prompt: "list my saves & more")
        #expect(url.host() == "muse.ai")
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems
        #expect(items?.first { $0.name == "q" }?.value == "list my saves & more")
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

struct MuseConnectorTests {
    @Test func normalizesPastedURLs() {
        let base = "https://x.trycloudflare.com/tok123"
        for pasted in [base, base + "/", base + "/mcp", base + "/saves", " \(base)/mcp "] {
            #expect(MuseConnector.normalized(pasted)?.absoluteString == base)
        }
        #expect(MuseConnector.normalized("not a url") == nil)
    }

    @Test func connectPromptAddsConnectorThenSends() throws {
        let base = try #require(MuseConnector.normalized("https://x.trycloudflare.com/tok123"))
        let day = try #require(SavedPostParser.parseDate("2026-09-27"))
        let connect = MuseConnector.connectPrompt(mcpURL: MuseConnector.mcpURL(base: base), window: .after(day))
        #expect(connect.contains("https://x.trycloudflare.com/tok123/mcp"))
        #expect(connect.contains("submit_saved_posts"))
        #expect(connect.contains("saved after 2026-09-27"))
        #expect(MuseConnector.isOurPrompt(connect))
        let sync = MuseConnector.syncPrompt(window: .all)
        #expect(!sync.contains("custom connector"))
        #expect(MuseConnector.isOurPrompt(sync))
        #expect(MuseConnector.isOurPrompt(MusePrompt.text()))
        #expect(!MuseConnector.isOurPrompt("```json\n[]\n```"))
    }
}

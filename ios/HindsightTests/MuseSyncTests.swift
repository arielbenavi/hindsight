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

    @Test func connectPromptAddsConnectorSyncsAndSchedules() throws {
        let base = try #require(MuseConnector.normalized("https://x.trycloudflare.com/tok123"))
        let connect = MuseConnector.connectPrompt(mcpURL: MuseConnector.mcpURL(base: base))
        #expect(connect.contains("https://x.trycloudflare.com/tok123/mcp"))
        #expect(connect.contains("get_sync_status"))
        #expect(connect.contains("submit_saved_posts"))
        #expect(connect.contains("every day at 9am"))
        #expect(connect.contains("remove it and use this one"))
        #expect(MuseConnector.isOurPrompt(connect))
        let sync = MuseConnector.syncPrompt()
        #expect(!sync.contains("custom connector"))
        #expect(sync.contains("get_sync_status"))
        #expect(MuseConnector.isOurPrompt(sync))
        #expect(MuseConnector.isOurPrompt(MusePrompt.text()))
        #expect(!MuseConnector.isOurPrompt("```json\n[]\n```"))
    }
}

/// One account per install (`ServerAccount`, `MuseConnector.ensureAccount`): the URL rules, no network.
struct ServerAccountTests {
    private let root = URL(string: "https://example.test/tok123")!
    private let tenant = URL(string: "https://example.test/tok123/t/t-abcd1234")!

    @Test func rootVersusTenant() {
        #expect(!ServerAccount.isTenant(root))
        #expect(ServerAccount.isTenant(tenant))
        #expect(ServerAccount.isTenant(tenant.appending(path: "saves")))
        #expect(ServerAccount.root(of: tenant) == root)
        #expect(ServerAccount.root(of: tenant.appending(path: "saves")) == root)
        #expect(ServerAccount.root(of: root) == root)
        #expect(MuseConnector.normalized("https://example.test/tok123/saves/") == root)
    }

    @Test func usesTheAccountMadeOnThisRoot() {
        let account = ServerAccount(root: root.absoluteString, base: tenant.absoluteString)
        #expect(ServerAccount.resolve(configured: nil, account: account) == nil)
        #expect(ServerAccount.resolve(configured: root, account: nil) == root)              // none yet (offline): the root
        #expect(ServerAccount.resolve(configured: root, account: account) == tenant)
        let other = URL(string: "https://other.test/tok999")!
        #expect(ServerAccount.resolve(configured: other, account: account) == other)       // another server: not that account
        let pasted = URL(string: "https://example.test/tok123/t/t-other")!
        #expect(ServerAccount.resolve(configured: pasted, account: account) == pasted)     // a tenant set by hand wins
    }

    /// The launch argument sets the same root on every launch: that must not make a second account.
    @Test func makesAnAccountOncePerRoot() {
        let account = ServerAccount(root: root.absoluteString, base: tenant.absoluteString)
        #expect(ServerAccount.needsAccount(configured: root, account: nil))
        #expect(!ServerAccount.needsAccount(configured: root, account: account))
        #expect(!ServerAccount.needsAccount(configured: nil, account: nil))
        #expect(!ServerAccount.needsAccount(configured: tenant, account: nil))
        #expect(ServerAccount.needsAccount(configured: URL(string: "https://other.test/tok999")!, account: account))
    }

    @Test func connectCodeFollowsTheAccount() {
        #expect(WhatsAppBot.connectCode(base: tenant) == "t-abcd1234")
        #expect(WhatsAppBot.connectCode(base: root) == "main")
    }

    @Test func pullsAtMostOnceAMinute() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        #expect(AppModel.isPullDue(last: nil, now: now))
        #expect(!AppModel.isPullDue(last: now.addingTimeInterval(-30), now: now))
        #expect(AppModel.isPullDue(last: now.addingTimeInterval(-60), now: now))
    }
}

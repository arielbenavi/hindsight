import Foundation
import Testing
@testable import Hindsight

struct WhatsAppExportTests {
    private func components(_ date: Date?) -> DateComponents? {
        date.map { Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: $0) }
    }

    @Test func iOSDayFirstNotesChat() throws {
        let text = """
        \u{200E}[28/09/2026, 09:12:03] Notes 📝: \u{200E}Messages and calls are end-to-end encrypted. Only people in this chat can read them.
        [28/09/2026, 09:13:10] Ariel: call mom
        [28/09/2026, 21:40:55] Ariel: https://www.instagram.com/reel/DdyvEu1OVoH/?igsh=abc try this pasta
        [29/09/2026, 08:00:00] Ariel: groceries:
        eggs
        oat milk
        [30/09/2026, 14:27:03] Ariel: \u{200E}image omitted
        [30/09/2026, 14:28:00] Ariel: https://vm.tiktok.com/ZMabc123/ https://example.com/article.
        """
        let result = WhatsAppExportParser.parse(text: text)
        #expect(result.messages == 4)
        #expect(result.notes == 2)
        #expect(result.links == 3)

        let call = try #require(result.posts.first { $0.caption == "call mom" })
        #expect(call.kind == .note && call.platform == .whatsapp && call.source == .whatsappExport)
        #expect(components(call.savedAt) == DateComponents(year: 2026, month: 9, day: 28, hour: 9, minute: 13))

        let reel = try #require(result.posts.first { $0.platform == .instagram })
        #expect(reel.id == "instagram:DdyvEu1OVoH")
        #expect(reel.kind == .reel)
        #expect(reel.caption?.contains("try this pasta") == true)

        #expect(result.posts.contains { $0.caption == "groceries:\neggs\noat milk" })
        #expect(result.posts.contains { $0.platform == .tiktok })
        let web = try #require(result.posts.first { $0.platform == .web })
        #expect(web.url.absoluteString == "https://example.com/article")
        #expect(web.kind == .link)
    }

    @Test func androidAndUSFormats() {
        let android = "30/09/2026, 14:27 - Ariel: hello there\n1/10/2026, 08:05 - Ariel: second note"
        let a = WhatsAppExportParser.parse(text: android)
        #expect(a.notes == 2)
        #expect(components(a.posts[0].savedAt) == DateComponents(year: 2026, month: 9, day: 30, hour: 14, minute: 27))

        let us = "[9/30/26, 2:27:03 PM] Ariel: from the US\n[10/1/26, 12:05:00 AM] Ariel: midnight note"
        let u = WhatsAppExportParser.parse(text: us)
        #expect(components(u.posts[0].savedAt) == DateComponents(year: 2026, month: 9, day: 30, hour: 14, minute: 27))
        #expect(components(u.posts[1].savedAt) == DateComponents(year: 2026, month: 10, day: 1, hour: 0, minute: 5))
    }

    @Test func groupKeepsEveryonesLinksButOnlyMyText() {
        let text = """
        [01/10/2026, 10:00:00] Ariel: my idea for the trip
        [01/10/2026, 10:01:00] Ariel: another thought
        [01/10/2026, 10:02:00] Reut: her private message
        [01/10/2026, 10:03:00] Reut: https://www.instagram.com/p/ABC123/ this place!
        """
        let result = WhatsAppExportParser.parse(text: text)
        #expect(result.notes == 2)
        #expect(result.othersSkipped == 2)
        #expect(result.posts.contains { $0.id == "instagram:ABC123" })
        #expect(!result.posts.contains { $0.caption?.contains("private") == true })
    }

    @Test func ownerTieBreakIsDeterministic() {
        let messages = [
            WhatsAppExportParser.Message(date: nil, sender: "Ariel", text: "a"),
            WhatsAppExportParser.Message(date: nil, sender: "Reut", text: "b"),
            WhatsAppExportParser.Message(date: nil, sender: "Reut", text: "c"),
            WhatsAppExportParser.Message(date: nil, sender: "Ariel", text: "d"),
        ]
        for _ in 0..<20 { #expect(WhatsAppExportParser.mostFrequentSender(messages) == "Ariel") }
    }

    @Test func reimportingIsIdempotent() {
        let text = "[28/09/2026, 09:13:10] Ariel: call mom\n[28/09/2026, 09:14:00] Ariel: https://x.com/a/status/42"
        let first = WhatsAppExportParser.parse(text: text).posts.map(\.id)
        let second = WhatsAppExportParser.parse(text: text).posts.map(\.id)
        #expect(first == second)
        #expect(Set(first).count == 2)
    }

    @Test func zipExportAndJunk() throws {
        let chat = Data("[28/09/2026, 09:13:10] Ariel: from a zip".utf8)
        let zip = ZipFixture.make([("_chat.txt", chat, nil)])
        let file = URL.temporaryDirectory.appending(path: "WhatsApp Chat - Notes.zip")
        try zip.write(to: file)
        defer { try? FileManager.default.removeItem(at: file) }
        #expect(try WhatsAppExportParser.parse(fileAt: file).notes == 1)

        let junk = URL.temporaryDirectory.appending(path: "junk-\(UUID()).txt")
        try Data("just some text\nwith no chat headers".utf8).write(to: junk)
        defer { try? FileManager.default.removeItem(at: junk) }
        #expect(throws: WhatsAppExportParser.ImportError.self) { try WhatsAppExportParser.parse(fileAt: junk) }
    }
}

struct ServerRecordsTests {
    @Test func keepsTheServerRecordsOwnSource() {
        let json = """
        [{"id": "whatsapp:ABC", "platform": "whatsapp", "kind": "note", "url": "hindsight-note:whatsapp/ABC",
          "caption": "call mom", "collections": ["Notes"], "saved_at": "2026-10-01T18:00:00Z", "source": "whatsapp_bot"},
         {"platform": "instagram", "url": "https://www.instagram.com/p/X1/", "source": "muse"},
         {"platform": "web", "kind": "link", "url": "https://example.com/a", "source": "something_new"}]
        """
        let posts = SavedPostParser.parse(json, source: .muse).posts
        #expect(posts.count == 3)
        #expect(posts[0].source == .whatsappBot && posts[0].kind == .note && posts[0].platform == .whatsapp)
        #expect(posts[0].caption == "call mom" && posts[0].collections == ["Notes"])
        #expect(posts[1].source == .muse)
        #expect(posts[2].source == .muse) // unknown source falls back to the caller's
        #expect(posts[2].platform == .web && posts[2].kind == .link)
    }

    @Test func botConnectLink() {
        let url = WhatsAppBot.connectURL(number: "15551234567", code: "t-1a2b3c4d")
        #expect(url.absoluteString.hasPrefix("https://wa.me/15551234567?text="))
        let text = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first?.value
        #expect(text?.hasSuffix("connect code: t-1a2b3c4d") == true) // the bot's CONNECT_RE matches this
    }

    @Test func connectCodeComesFromTheServerURL() {
        #expect(WhatsAppBot.connectCode(base: URL(string: "https://h.dev/tok/t/t-1a2b3c4d")) == "t-1a2b3c4d")
        #expect(WhatsAppBot.connectCode(base: URL(string: "https://h.dev/tok")) == "main")
        #expect(WhatsAppBot.connectCode(base: nil) == "main")
    }

    /// Same input as whatsapp-bot/exportParser.test.js, so the bot and the app give
    /// a note the same id (no duplicates when both import the same export).
    @Test func noteIDsMatchTheBot() {
        #expect(WhatsAppExportParser.noteURL(date: nil, text: "call mom").absoluteString
                == "hindsight-note:whatsapp/0-3pkzly6frbqy8")
    }
}

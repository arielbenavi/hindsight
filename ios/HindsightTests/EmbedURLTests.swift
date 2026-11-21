import Foundation
import Testing
@testable import Hindsight

struct EmbedURLTests {
    private func embed(_ s: String, _ platform: Platform? = nil) -> EmbedSource? {
        let url = URL(string: s)!
        return EmbedURL.embed(for: url, platform: platform ?? Platform(url: url) ?? .web)
    }

    private func url(_ s: String, _ platform: Platform? = nil) -> String? {
        if case .url(let u) = embed(s, platform) { return u.absoluteString }
        return nil
    }

    // MARK: Instagram

    @Test(arguments: [
        "https://www.instagram.com/p/DdwJgsNABze/",
        "https://www.instagram.com/reel/DdwJgsNABze/",
        "https://www.instagram.com/reels/DdwJgsNABze/",
        "https://www.instagram.com/tv/DdwJgsNABze/",
        "https://instagram.com/reel/DdwJgsNABze",
        "https://m.instagram.com/p/DdwJgsNABze/?igsh=abc123&img_index=2",
        "https://www.instagram.com/some.user/p/DdwJgsNABze/",
        "https://www.instagram.com/reel/DdwJgsNABze/#comments",
    ])
    func instagramShapes(_ link: String) {
        #expect(url(link) == "https://www.instagram.com/p/DdwJgsNABze/embed/")
    }

    @Test func instagramKeepsDashesAndUnderscores() {
        #expect(url("https://www.instagram.com/reel/C-a_b-1/") == "https://www.instagram.com/p/C-a_b-1/embed/")
    }

    @Test(arguments: [
        "https://www.instagram.com/",
        "https://www.instagram.com/someuser/",
        "https://www.instagram.com/p/",
        "https://www.instagram.com/stories/someuser/123/",
        "https://www.instagram.com/p/bad%20code/",
        "https://www.instagram.com/explore/tags/food/",
    ])
    func instagramWithoutAPostIsNil(_ link: String) {
        #expect(embed(link) == nil)
    }

    // MARK: TikTok

    @Test func tiktokVideo() {
        #expect(url("https://www.tiktok.com/@chef.anna/video/7301234567890123456?is_from_webapp=1&sender_device=pc")
                == "https://www.tiktok.com/embed/v2/7301234567890123456")
        #expect(url("https://m.tiktok.com/@x/video/7301234567890123456") == "https://www.tiktok.com/embed/v2/7301234567890123456")
    }

    @Test(arguments: [
        "https://vm.tiktok.com/ZMabc123/",
        "https://vt.tiktok.com/ZSabc123/",
        "https://www.tiktok.com/@chef.anna",
        "https://www.tiktok.com/@chef.anna/video/notanumber",
        "https://www.tiktok.com/t/ZTabc/",
    ])
    func tiktokUnreadableIsNil(_ link: String) {
        #expect(embed(link) == nil)
    }

    // MARK: X

    @Test(arguments: [
        "https://x.com/jack/status/20",
        "https://twitter.com/jack/status/20?s=46&t=abc",
        "https://mobile.twitter.com/jack/status/20",
        "https://mobile.x.com/jack/status/20/photo/1",
    ])
    func tweetUsesTheWidget(_ link: String) throws {
        guard case .html(let html, let base) = embed(link) else { Issue.record("no html for \(link)"); return }
        #expect(base.absoluteString == "https://twitter.com")
        #expect(html.contains("https://platform.twitter.com/widgets.js"))
        #expect(html.contains("class=\"twitter-tweet\" data-theme=\"dark\""))
        #expect(html.contains("<a href=\"https://twitter.com/jack/status/20\"></a>"))
    }

    @Test func tweetViaIWebStatus() {
        guard case .html(let html, _) = embed("https://x.com/i/web/status/20") else { Issue.record("no html"); return }
        #expect(html.contains("https://twitter.com/i/status/20"))
    }

    @Test(arguments: [
        "https://x.com/jack",
        "https://x.com/jack/status/",
        "https://x.com/jack/status/abc",
        "https://x.com/ja%22ck/status/20",
    ])
    func tweetWithoutAStatusIsNil(_ link: String) {
        #expect(embed(link) == nil)
    }

    // MARK: YouTube (saved as web links)

    @Test(arguments: [
        "https://www.youtube.com/watch?v=dQw4w9WgXcQ",
        "https://www.youtube.com/watch?feature=share&v=dQw4w9WgXcQ&t=42s",
        "https://m.youtube.com/watch?v=dQw4w9WgXcQ",
        "https://youtube.com/shorts/dQw4w9WgXcQ?si=xyz",
        "https://youtu.be/dQw4w9WgXcQ?t=10",
        "https://www.youtube.com/live/dQw4w9WgXcQ",
    ])
    func youTube(_ link: String) {
        guard case .html(let html, let base) = embed(link) else { Issue.record("no html for \(link)"); return }
        #expect(html.contains("src=\"https://www.youtube.com/embed/dQw4w9WgXcQ?playsinline=1&rel=0\""))
        #expect(base == EmbedURL.appOrigin)
    }

    @Test func youTubeWithoutAVideoIsAWebPage() {
        // A channel page isn't a video: it loads as a page, like any link.
        #expect(url("https://www.youtube.com/@mkbhd") == "https://www.youtube.com/@mkbhd")
        #expect(url("https://www.youtube.com/watch?v=short") == "https://www.youtube.com/watch?v=short")
    }

    // MARK: Facebook

    @Test func facebookVideoPaths() {
        let expected = "https://www.facebook.com/plugins/video.php?href=https%3A%2F%2Fwww.facebook.com%2Freel%2F123456789&show_text=false"
        #expect(url("https://www.facebook.com/reel/123456789") == expected)
        #expect(url("https://m.facebook.com/reel/123456789") == expected)
        #expect(url("https://www.facebook.com/somepage/videos/987654321/")?.hasPrefix("https://www.facebook.com/plugins/video.php?href=") == true)
        #expect(url("https://www.facebook.com/watch/?v=987654321")?.contains("video.php?href=https%3A%2F%2Fwww.facebook.com%2Fwatch%2F%3Fv%3D987654321") == true)
        #expect(url("https://www.facebook.com/share/v/1AbCdEf/")?.contains("/plugins/video.php") == true)
        #expect(url("https://fb.watch/abcDEF123/")?.contains("/plugins/video.php?href=https%3A%2F%2Ffb.watch") == true)
    }

    @Test func facebookPostsUseThePostPlugin() {
        #expect(url("https://www.facebook.com/somepage/posts/pfbid02abc")
                == "https://www.facebook.com/plugins/post.php?href=https%3A%2F%2Fwww.facebook.com%2Fsomepage%2Fposts%2Fpfbid02abc&show_text=false")
        #expect(url("https://web.facebook.com/permalink.php?story_fbid=1&id=2")?.contains("/plugins/post.php?href=https%3A%2F%2Fwww.facebook.com%2Fpermalink.php%3Fstory_fbid%3D1%26id%3D2") == true)
        #expect(embed("https://www.facebook.com/") == nil)
    }

    // MARK: Web, notes, junk

    @Test func articlesLoadAsThemselves() {
        #expect(url("https://www.theverge.com/2026/11/1/some-story?utm_source=x") == "https://www.theverge.com/2026/11/1/some-story?utm_source=x")
        #expect(url("http://example.com/a") == "http://example.com/a")
    }

    @Test func notesAndOddSchemesAreNil() {
        #expect(embed("hindsight-note:whatsapp/20260101-abc", .whatsapp) == nil)
        #expect(embed("hindsight-note:whatsapp/20260101-abc", .web) == nil)
        #expect(embed("mailto:a@b.com", .web) == nil)
        #expect(embed("ftp://example.com/file", .web) == nil)
        #expect(embed("https://example.com/a", .whatsapp) == nil)
    }

    @Test func platformFromTheURLWinsOverTheLabel() {
        // A YouTube link labelled as a WhatsApp note link still plays.
        guard case .html(let html, _) = embed("https://youtu.be/dQw4w9WgXcQ", .whatsapp) else { Issue.record("no html"); return }
        #expect(html.contains("youtube.com/embed/dQw4w9WgXcQ"))
        // An Instagram link whose record says "web".
        #expect(url("https://www.instagram.com/reel/DdwJgsNABze/", .web) == "https://www.instagram.com/p/DdwJgsNABze/embed/")
    }

    // MARK: Shape

    @Test func tallPlayers() {
        func tall(_ s: String, _ kind: SavedPost.Kind = .post) -> Bool {
            let u = URL(string: s)!
            return EmbedURL.isTall(u, platform: Platform(url: u) ?? .web, kind: kind)
        }
        #expect(tall("https://www.instagram.com/reel/abc/"))
        #expect(tall("https://www.instagram.com/p/abc/", .reel))
        #expect(!tall("https://www.instagram.com/p/abc/", .post))
        #expect(tall("https://www.tiktok.com/@a/video/1"))
        #expect(tall("https://youtube.com/shorts/dQw4w9WgXcQ"))
        #expect(!tall("https://www.youtube.com/watch?v=dQw4w9WgXcQ"))
        #expect(!tall("https://x.com/jack/status/20", .tweet))
        #expect(tall("https://www.facebook.com/reel/1"))
    }

    @Test func articlesReadVideosWatch() {
        #expect(EmbedURL.isArticle(URL(string: "https://example.com/story")!, platform: .web))
        #expect(!EmbedURL.isArticle(URL(string: "https://youtu.be/dQw4w9WgXcQ")!, platform: .web))
        #expect(!EmbedURL.isArticle(URL(string: "https://www.instagram.com/p/abc/")!, platform: .instagram))
    }

    @Test func playerSizes() {
        let space = CGSize(width: 400, height: 800)
        let tall = PlayerLayout.playerSize(in: space, tall: true, article: false)
        #expect(abs(tall.height - 544) < 0.01 && abs(tall.width - 306) < 0.01)
        let wide = CGSize(width: 400, height: 2000)
        #expect(abs(PlayerLayout.playerSize(in: wide, tall: true, article: false).width - 400) < 0.01)
        #expect(abs(PlayerLayout.playerSize(in: space, tall: false, article: true).height - 592) < 0.01)
        #expect(PlayerLayout.playerSize(in: .zero, tall: true, article: false) == .zero)
    }

    // MARK: Dead ends

    @Test func unavailablePagesFallBack() {
        #expect(EmbedURL.looksUnavailable(pageText: "Sorry, this page isn't available.\nThe link you followed may be broken."))
        #expect(EmbedURL.looksUnavailable(pageText: "Sorry, this page isn\u{2019}t available."))
        #expect(EmbedURL.looksUnavailable(pageText: "Video unavailable\nThis video is private"))
        #expect(EmbedURL.looksUnavailable(pageText: "Error 153\nVideo player configuration error"))
        #expect(EmbedURL.looksUnavailable(pageText: "Log in\nSign up\nSee photos and videos from friends."))
    }

    @Test func realPostsPlay() {
        #expect(!EmbedURL.looksUnavailable(pageText: ""))
        #expect(!EmbedURL.looksUnavailable(pageText: "chef.anna\nView profile\n1,204 likes\nView more on Instagram"))
        // A long caption that mentions logging in is still a post.
        let caption = String(repeating: "Crispy miso pasta, the easiest dinner you'll make this week. ", count: 12) + "Log in to my site, sign up for the newsletter"
        #expect(!EmbedURL.looksUnavailable(pageText: caption))
        // "Log in" alone (a header link) isn't a wall.
        #expect(!EmbedURL.looksUnavailable(pageText: "eatwithjo\nLog in\nBest cacio e pepe in the city"))
    }
}

struct PlayerGateTests {
    private let reel = URL(string: "https://www.instagram.com/reel/DdwJgsNABze/")!

    @Test func onPlaysWhatHasAnEmbed() {
        #expect(PlayerGate.choice(for: reel, platform: .instagram, playInApp: true)
                == .player(.url(URL(string: "https://www.instagram.com/p/DdwJgsNABze/embed/")!)))
        #expect(PlayerGate.choice(for: URL(string: "https://example.com/a")!, platform: .web, playInApp: true)
                == .player(.url(URL(string: "https://example.com/a")!)))
    }

    @Test func offAlwaysOpensOutside() {
        #expect(PlayerGate.choice(for: reel, platform: .instagram, playInApp: false) == .external)
        #expect(PlayerGate.choice(for: URL(string: "https://example.com/a")!, platform: .web, playInApp: false) == .external)
    }

    @Test func noEmbedOpensOutside() {
        #expect(PlayerGate.choice(for: URL(string: "https://vm.tiktok.com/ZMabc/")!, platform: .tiktok, playInApp: true) == .external)
        #expect(PlayerGate.choice(for: URL(string: "hindsight-note:whatsapp/1-a")!, platform: .whatsapp, playInApp: true) == .external)
    }

    @Test func settingDefaultsToOn() {
        let key = PlayerGate.playInAppKey
        let before = UserDefaults.standard.object(forKey: key)
        defer { UserDefaults.standard.set(before, forKey: key) }
        UserDefaults.standard.removeObject(forKey: key)
        #expect(PlayerGate.playsInApp)
        UserDefaults.standard.set(false, forKey: key)
        #expect(!PlayerGate.playsInApp)
    }
}

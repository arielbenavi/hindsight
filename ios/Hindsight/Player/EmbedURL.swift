import Foundation

/// What the in-app player loads: a page by URL, or our own HTML (X's embed widget).
enum EmbedSource: Equatable, Sendable {
    case url(URL)
    case html(String, baseURL: URL)
}

/// Maps a saved post's permalink to the platform's own embed player. Pure, no network:
/// links that can't be read offline (TikTok short links) give nil, and the save opens
/// in its own app as before. docs/LESSONS.md → "In-app player" for what each embed does.
enum EmbedURL {
    static func embed(for url: URL, platform: Platform) -> EmbedSource? {
        guard let scheme = url.scheme?.lowercased(), scheme == "https" || scheme == "http",
              let host = url.host()?.lowercased(), !host.isEmpty else { return nil }
        let parts = url.pathComponents.filter { $0 != "/" }

        if let id = youTubeID(host: host, parts: parts, url: url) {
            // Loaded on its own, the embed has no referrer and YouTube shows "Error 153".
            // Framed in a page whose origin is our bundle ID, it plays (YouTube's advice for apps).
            return .html(youTubeHTML(id: id), baseURL: appOrigin)
        }
        switch Platform(url: url) ?? platform {
        case .instagram:
            guard isHost(host, "instagram.com"), let code = instagramCode(parts) else { return nil }
            return .url(URL(string: "https://www.instagram.com/p/\(code)/embed/")!)
        case .tiktok:
            // vm./vt. short links only resolve with a network redirect.
            guard isHost(host, "tiktok.com"), !host.hasPrefix("vm."), !host.hasPrefix("vt."),
                  let i = parts.firstIndex(of: "video"), i + 1 < parts.count,
                  let id = digits(parts[i + 1]) else { return nil }
            return .url(URL(string: "https://www.tiktok.com/embed/v2/\(id)")!)
        case .x:
            guard isHost(host, "x.com") || isHost(host, "twitter.com"),
                  let i = parts.firstIndex(of: "status"), i >= 1, i + 1 < parts.count,
                  let id = digits(parts[i + 1]) else { return nil }
            let user = parts[i - 1] == "web" ? "i" : parts[i - 1]  // /i/web/status/<id>
            guard user.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "_") }) else { return nil }
            return .html(tweetHTML(user: user, id: id), baseURL: URL(string: "https://twitter.com")!)
        case .facebook:
            guard isHost(host, "facebook.com") || isHost(host, "fb.watch"), !parts.isEmpty else { return nil }
            // The plugins only take www.facebook.com permalinks.
            var c = URLComponents(url: url, resolvingAgainstBaseURL: false)
            if isHost(host, "facebook.com") { c?.host = "www.facebook.com" }
            c?.scheme = "https"
            c?.fragment = nil
            guard let href = c?.url?.absoluteString else { return nil }
            let plugin = isFacebookVideo(host: host, parts: parts) ? "video" : "post"
            return .url(URL(string: "https://www.facebook.com/plugins/\(plugin).php?href=\(strictEncode(href))&show_text=false")!)
        case .web:
            return .url(url)
        case .whatsapp:
            return nil
        }
    }

    /// Reels, TikToks, Shorts: a tall 9:16 player. Everything else fits the space.
    static func isTall(_ url: URL, platform: Platform, kind: SavedPost.Kind) -> Bool {
        let host = url.host()?.lowercased() ?? ""
        let parts = url.pathComponents.filter { $0 != "/" }.map { $0.lowercased() }
        switch Platform(url: url) ?? platform {
        case .instagram: return kind == .reel || ["reel", "reels", "tv"].contains(parts.first ?? "")
        case .tiktok: return true
        case .facebook: return parts.contains("reel")
        case .web: return isHost(host, "youtube.com") && parts.first == "shorts"
        case .x, .whatsapp: return false
        }
    }

    /// "Read here" for an article, "Watch here" for a post or video.
    static func isArticle(_ url: URL, platform: Platform) -> Bool {
        guard (Platform(url: url) ?? platform) == .web, let host = url.host()?.lowercased() else { return false }
        return youTubeID(host: host, parts: url.pathComponents.filter { $0 != "/" }, url: url) == nil
    }

    // MARK: - Unavailable pages

    /// The embed loaded but shows a dead end instead of the post: removed, private,
    /// or a full-page login wall. Conservative: only short pages with a known phrase,
    /// so a real caption that happens to say "log in" still plays.
    static func looksUnavailable(pageText: String) -> Bool {
        let text = pageText.lowercased()
            .replacingOccurrences(of: "\u{2019}", with: "'")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if text.isEmpty { return false }  // still drawing, or all media
        guard text.count < 600 else { return false }
        let deadEnds = ["may be broken", "isn't available", "is not available", "isn't available right now",
                        "video unavailable", "this video is unavailable", "page not found",
                        "this post is unavailable", "content isn't available", "sorry, this page",
                        "this tweet is unavailable", "this post was deleted", "hmm...this page doesn't exist",
                        "error 153", "video player configuration error"]
        if deadEnds.contains(where: text.contains) { return true }
        // A login wall is the only thing on the page.
        let login = text.contains("log in") || text.contains("login") || text.contains("sign in")
        let signUp = text.contains("sign up") || text.contains("create new account") || text.contains("create account")
        return login && signUp && text.count < 300
    }

    // MARK: - Pieces

    private static func isHost(_ host: String, _ domain: String) -> Bool {
        host == domain || host.hasSuffix("." + domain)
    }

    private static func digits(_ s: String) -> String? {
        !s.isEmpty && s.count <= 25 && s.allSatisfy(\.isASCII) && s.allSatisfy(\.isNumber) ? s : nil
    }

    /// `/p/<code>/`, `/reel/<code>/`, `/reels/<code>/`, `/tv/<code>/`, also after a username.
    private static func instagramCode(_ parts: [String]) -> String? {
        guard let i = parts.firstIndex(where: { ["p", "reel", "reels", "tv"].contains($0.lowercased()) }),
              i <= 1, i + 1 < parts.count else { return nil }
        let code = parts[i + 1]
        let ok = !code.isEmpty && code.count <= 64
            && code.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "_" || $0 == "-") }
        return ok ? code : nil
    }

    private static func youTubeID(host: String, parts: [String], url: URL) -> String? {
        var id: String?
        if isHost(host, "youtu.be") {
            id = parts.first
        } else if isHost(host, "youtube.com") || isHost(host, "youtube-nocookie.com") {
            if parts.first == "watch" {
                id = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                    .queryItems?.first(where: { $0.name == "v" })?.value
            } else if let first = parts.first, ["shorts", "embed", "live", "v"].contains(first), parts.count > 1 {
                id = parts[1]
            }
        }
        guard let id, id.count == 11,
              id.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "_" || $0 == "-") }) else { return nil }
        return id
    }

    private static func isFacebookVideo(host: String, parts: [String]) -> Bool {
        if isHost(host, "fb.watch") { return true }
        let p = parts.map { $0.lowercased() }
        if p.contains("videos") || p.contains("reel") || p.first == "watch" { return true }
        if p.first == "share", p.count > 1, ["v", "r"].contains(p[1]) { return true }
        return false
    }

    private static func strictEncode(_ s: String) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return s.addingPercentEncoding(withAllowedCharacters: allowed) ?? s
    }

    /// The page origin YouTube sees as the embedder (its referrer rule for web views).
    static let appOrigin = URL(string: "https://com.reutrabin.hindsight")!

    static func youTubeHTML(id: String) -> String {
        """
        <!doctype html><html><head><meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1, maximum-scale=1">
        <meta name="referrer" content="strict-origin-when-cross-origin">
        <style>html,body{margin:0;height:100%;background:#000}iframe{border:0;width:100%;height:100%}</style>
        </head><body>
        <iframe src="https://www.youtube.com/embed/\(id)?playsinline=1&rel=0"
        allow="autoplay; encrypted-media; picture-in-picture; fullscreen" allowfullscreen
        referrerpolicy="strict-origin-when-cross-origin"></iframe>
        </body></html>
        """
    }

    /// X's official embed widget, dark, on a black page.
    static func tweetHTML(user: String, id: String) -> String {
        """
        <!doctype html><html><head><meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1, maximum-scale=1">
        <style>html,body{margin:0;background:#000;color:#999;font:15px -apple-system,sans-serif}
        .wrap{display:flex;justify-content:center;padding:8px}.twitter-tweet{margin:0 auto!important}</style>
        </head><body><div class="wrap">
        <blockquote class="twitter-tweet" data-theme="dark" data-dnt="true" data-align="center">
        <a href="https://twitter.com/\(user)/status/\(id)"></a></blockquote></div>
        <script async src="https://platform.twitter.com/widgets.js" charset="utf-8"></script>
        </body></html>
        """
    }
}

/// Whether a save plays in hindsight or opens in its own app (Sources → Viewing).
enum PlayerGate {
    static let playInAppKey = "playSavesInApp"

    /// The Sources switch; on unless the user turned it off.
    static var playsInApp: Bool {
        UserDefaults.standard.object(forKey: playInAppKey) as? Bool ?? true
    }

    enum Choice: Equatable { case player(EmbedSource), external }

    /// What "Open it" does for this save.
    static func choice(for url: URL, platform: Platform, playInApp: Bool) -> Choice {
        guard playInApp, let source = EmbedURL.embed(for: url, platform: platform) else { return .external }
        return .player(source)
    }

    static func choice(for post: ContractPost, playInApp: Bool = playsInApp) -> Choice {
        choice(for: post.url, platform: post.platform, playInApp: playInApp)
    }
}

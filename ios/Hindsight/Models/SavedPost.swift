import Foundation

/// One saved item from any platform. This is the app's canonical format;
/// the seed markdown and Muse's JSON replies are both parsed into it.
struct SavedPost: Identifiable, Codable, Hashable, Sendable {
    /// `platform:shortcode` (e.g. `instagram:DdwJgsNABze`), stable across imports.
    let id: String
    let platform: Platform
    let author: String
    let kind: Kind
    /// Date the source reported. For the IG seed this looks like the publish
    /// date; list order (newest saved first) is preserved separately by the store.
    let date: Date?
    let caption: String?
    let url: URL

    init(platform: Platform? = nil, author: String, kind: Kind, date: Date?, caption: String?, url: URL) {
        let platform = platform ?? Platform(url: url) ?? .instagram
        self.id = "\(platform.rawValue):\(Self.shortcode(for: url) ?? url.absoluteString)"
        self.platform = platform
        self.author = author
        self.kind = kind
        self.date = date
        self.caption = caption.flatMap { $0.isEmpty ? nil : $0 }
        self.url = url
    }

    enum Kind: String, Codable, Sendable, CaseIterable {
        case reel, post, carousel, video, tweet, unknown

        /// Lenient mapping from whatever label a source uses.
        init(label: String) {
            switch label.lowercased() {
            case "reel", "reels": self = .reel
            case "post", "p", "photo", "image": self = .post
            case "carousel", "album", "sidecar": self = .carousel
            case "video", "tv", "igtv", "watch": self = .video
            case "tweet", "x": self = .tweet
            default: self = .unknown
            }
        }
    }

    /// Last meaningful path component: `/reel/CODE/` → `CODE`, `/status/123` → `123`.
    static func shortcode(for url: URL) -> String? {
        let parts = url.pathComponents.filter { $0 != "/" }
        return parts.last
    }
}

enum Platform: String, Codable, Sendable, CaseIterable, Identifiable {
    case instagram, facebook, x, tiktok

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .instagram: "Instagram"
        case .facebook: "Facebook"
        case .x: "X"
        case .tiktok: "TikTok"
        }
    }

    /// SF Symbol stand-in until we add brand assets.
    var symbol: String {
        switch self {
        case .instagram: "camera"
        case .facebook: "person.2.fill"
        case .x: "xmark"
        case .tiktok: "music.note"
        }
    }

    init?(url: URL) {
        guard let host = url.host()?.lowercased() else { return nil }
        if host.hasSuffix("instagram.com") { self = .instagram }
        else if host.hasSuffix("facebook.com") || host.hasSuffix("fb.watch") { self = .facebook }
        else if host.hasSuffix("x.com") || host.hasSuffix("twitter.com") { self = .x }
        else if host.hasSuffix("tiktok.com") { self = .tiktok }
        else { return nil }
    }

    init?(label: String) {
        switch label.lowercased() {
        case "instagram", "ig": self = .instagram
        case "facebook", "fb": self = .facebook
        case "x", "twitter": self = .x
        case "tiktok": self = .tiktok
        default: return nil
        }
    }
}

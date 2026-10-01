import Foundation

/// One saved item from any platform: the `posts[]` record of
/// docs/data-contract.md (v1). Every source (Muse, exports, X, the seed) is
/// parsed into this; property names are the contract's keys in camelCase.
///
/// New fields are optional with defaults, and decoding accepts the pre-contract
/// shape (a single `date`), so saves already stored on a device keep loading.
struct SavedPost: Identifiable, Codable, Hashable, Sendable {
    /// `platform:shortcode` (e.g. `instagram:DdwJgsNABze`), stable across imports.
    let id: String
    let platform: Platform
    let url: URL
    let kind: Kind
    /// `author.username`, without the @.
    let author: String
    var authorDisplayName: String?
    /// The full caption. Never truncated by us (the old seed file is, at 160 characters).
    var caption: String?
    /// Lowercase, without `#`. Parsed from the caption when the source doesn't list them.
    var hashtags: [String]
    /// Accounts tagged or @mentioned. Parsed from the caption when the source doesn't list them.
    var mentions: [Mention]
    /// The user's saved-collection names ("NYC Restaurants").
    var collections: [String]
    /// When the user saved it.
    var savedAt: Date?
    /// When the creator posted it.
    var postedAt: Date?
    var thumbnailURL: URL?
    var locationTag: LocationTag?
    /// BCP 47 code of the caption, e.g. "he", "en".
    var language: String?
    var onScreenText: String?
    var transcript: String?
    /// Where this record came from.
    var source: Source

    /// Best date to sort or show: saved, else posted.
    var date: Date? { savedAt ?? postedAt }

    init(
        platform: Platform? = nil,
        url: URL,
        kind: Kind,
        author: String,
        authorDisplayName: String? = nil,
        caption: String?,
        hashtags: [String]? = nil,
        mentions: [Mention]? = nil,
        collections: [String] = [],
        savedAt: Date? = nil,
        postedAt: Date? = nil,
        thumbnailURL: URL? = nil,
        locationTag: LocationTag? = nil,
        language: String? = nil,
        onScreenText: String? = nil,
        transcript: String? = nil,
        source: Source
    ) {
        let platform = platform ?? Platform(url: url) ?? .instagram
        let caption = caption.flatMap { $0.isEmpty ? nil : $0 }
        self.id = "\(platform.rawValue):\(Self.shortcode(for: url) ?? url.absoluteString)"
        self.platform = platform
        self.url = url
        self.kind = kind
        self.author = author
        self.authorDisplayName = authorDisplayName.flatMap { $0.isEmpty ? nil : $0 }
        self.caption = caption
        self.hashtags = hashtags ?? Self.hashtags(in: caption)
        self.mentions = mentions ?? Self.mentions(in: caption)
        self.collections = collections
        self.savedAt = savedAt
        self.postedAt = postedAt
        self.thumbnailURL = thumbnailURL
        self.locationTag = locationTag
        self.language = language
        self.onScreenText = onScreenText
        self.transcript = transcript
        self.source = source
    }

    // MARK: - Nested types

    enum Kind: String, Codable, Sendable, CaseIterable {
        case reel, post, carousel, video, tweet
        /// A web page (article, YouTube…) saved as a link.
        case link
        /// Plain text the user wrote to themselves (e.g. a WhatsApp notes chat).
        case note
        case unknown

        /// Lenient mapping from whatever label a source uses.
        init(label: String) {
            switch label.lowercased() {
            case "reel", "reels": self = .reel
            case "post", "p", "photo", "image": self = .post
            case "carousel", "album", "sidecar": self = .carousel
            case "video", "tv", "igtv", "watch": self = .video
            case "tweet", "x": self = .tweet
            case "link", "web", "article": self = .link
            case "note", "text": self = .note
            default: self = .unknown
            }
        }
    }

    struct Mention: Codable, Hashable, Sendable {
        var username: String
        var displayName: String?
    }

    struct LocationTag: Codable, Hashable, Sendable {
        var name: String?
        var address: String?
        var lat: Double?
        var lng: Double?
    }

    enum Source: String, Codable, Sendable {
        case muse
        case igExport = "ig_export"
        case fbExport = "fb_export"
        case tiktokExport = "tiktok_export"
        case xAPI = "x_api"
        case seedMD = "seed_md"
        case whatsappExport = "whatsapp_export"
        case whatsappBot = "whatsapp_bot"
    }

    // MARK: - Merging

    /// Fills this record's gaps from another record of the same post, e.g. an
    /// export's full caption and collections over a truncated Muse/seed entry.
    func filling(from other: SavedPost) -> SavedPost {
        guard other.id == id else { return self }
        var merged = self
        if (other.caption?.count ?? 0) > (caption?.count ?? 0) {
            merged.caption = other.caption
            merged.hashtags = Self.unique(hashtags + other.hashtags)
            merged.mentions = mentions.isEmpty ? other.mentions : mentions
        }
        merged.authorDisplayName = authorDisplayName ?? other.authorDisplayName
        merged.collections = Self.unique(collections + other.collections)
        merged.savedAt = savedAt ?? other.savedAt
        merged.postedAt = postedAt ?? other.postedAt
        merged.thumbnailURL = thumbnailURL ?? other.thumbnailURL
        merged.locationTag = locationTag ?? other.locationTag
        merged.language = language ?? other.language
        merged.onScreenText = onScreenText ?? other.onScreenText
        merged.transcript = transcript ?? other.transcript
        return merged
    }

    // MARK: - Parsing helpers

    private static func unique(_ values: [String]) -> [String] {
        var seen = Set<String>()
        return values.filter { seen.insert($0).inserted }
    }

    /// Last path component of a known platform's URL: `/reel/CODE/` → `CODE`,
    /// `/status/123` → `123`. Nil for other sites (e.g. a link saved on Facebook),
    /// where the full URL is the identity.
    static func shortcode(for url: URL) -> String? {
        guard Platform(url: url) != nil else { return nil }
        return url.pathComponents.filter { $0 != "/" }.last
    }

    static func hashtags(in caption: String?) -> [String] {
        guard let caption else { return [] }
        var seen = Set<String>()
        return caption.matches(of: /#([\p{L}\p{N}_]+)/).compactMap { match in
            let tag = String(match.1).lowercased()
            return seen.insert(tag).inserted ? tag : nil
        }
    }

    static func mentions(in caption: String?) -> [Mention] {
        guard let caption else { return [] }
        var seen = Set<String>()
        return caption.matches(of: /(?:^|[^\w.])@([A-Za-z0-9_](?:[A-Za-z0-9_.]*[A-Za-z0-9_])?)/).compactMap { match in
            let username = String(match.1).lowercased()
            return seen.insert(username).inserted ? Mention(username: username, displayName: nil) : nil
        }
    }

    // MARK: - Codable (accepts the pre-contract shape)

    private enum CodingKeys: String, CodingKey {
        case id, platform, url, kind, author, authorDisplayName, caption, hashtags, mentions,
             collections, savedAt, postedAt, thumbnailURL, locationTag, language,
             onScreenText, transcript, source
    }

    private enum LegacyKeys: String, CodingKey { case date }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let legacy = try decoder.container(keyedBy: LegacyKeys.self)
        id = try c.decode(String.self, forKey: .id)
        platform = try c.decode(Platform.self, forKey: .platform)
        url = try c.decode(URL.self, forKey: .url)
        kind = try c.decode(Kind.self, forKey: .kind)
        author = try c.decode(String.self, forKey: .author)
        authorDisplayName = try c.decodeIfPresent(String.self, forKey: .authorDisplayName)
        caption = try c.decodeIfPresent(String.self, forKey: .caption)
        hashtags = try c.decodeIfPresent([String].self, forKey: .hashtags) ?? Self.hashtags(in: caption)
        mentions = try c.decodeIfPresent([Mention].self, forKey: .mentions) ?? Self.mentions(in: caption)
        collections = try c.decodeIfPresent([String].self, forKey: .collections) ?? []
        savedAt = try c.decodeIfPresent(Date.self, forKey: .savedAt)
            ?? legacy.decodeIfPresent(Date.self, forKey: .date)
        postedAt = try c.decodeIfPresent(Date.self, forKey: .postedAt)
        thumbnailURL = try c.decodeIfPresent(URL.self, forKey: .thumbnailURL)
        locationTag = try c.decodeIfPresent(LocationTag.self, forKey: .locationTag)
        language = try c.decodeIfPresent(String.self, forKey: .language)
        onScreenText = try c.decodeIfPresent(String.self, forKey: .onScreenText)
        transcript = try c.decodeIfPresent(String.self, forKey: .transcript)
        source = try c.decodeIfPresent(Source.self, forKey: .source) ?? (platform == .x ? .xAPI : .seedMD)
    }
}

enum Platform: String, Codable, Sendable, CaseIterable, Identifiable {
    case instagram, facebook, x, tiktok
    /// Any other site (articles, YouTube…), e.g. links from a WhatsApp notes chat.
    case web
    /// Notes written in WhatsApp (no post behind them).
    case whatsapp

    /// The social platforms we sync saves from.
    static let social: [Platform] = [.instagram, .facebook, .x, .tiktok]

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .instagram: "Instagram"
        case .facebook: "Facebook"
        case .x: "X"
        case .tiktok: "TikTok"
        case .web: "Web"
        case .whatsapp: "WhatsApp"
        }
    }

    /// SF Symbol stand-in until we add brand assets.
    var symbol: String {
        switch self {
        case .instagram: "camera"
        case .facebook: "person.2.fill"
        case .x: "xmark"
        case .tiktok: "music.note"
        case .web: "link"
        case .whatsapp: "message.fill"
        }
    }

    init?(url: URL) {
        guard let host = url.host()?.lowercased() else { return nil }
        if host.hasSuffix("instagram.com") { self = .instagram }
        else if host.hasSuffix("facebook.com") || host.hasSuffix("fb.watch") { self = .facebook }
        else if host.hasSuffix("x.com") || host.hasSuffix("twitter.com") { self = .x }
        else if host.hasSuffix("tiktok.com") || host.hasSuffix("tiktokv.com") { self = .tiktok }
        else { return nil }
    }

    init?(label: String) {
        switch label.lowercased() {
        case "instagram", "ig": self = .instagram
        case "facebook", "fb": self = .facebook
        case "x", "twitter": self = .x
        case "tiktok": self = .tiktok
        case "web": self = .web
        case "whatsapp": self = .whatsapp
        default: return nil
        }
    }
}

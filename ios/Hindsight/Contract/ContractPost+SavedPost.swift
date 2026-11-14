import Foundation

/// Ariel's `SavedPost` (what every source is parsed into) → the contract's
/// `posts[]` record the screens read. The two are field-for-field the same
/// since contract v1; only the shapes differ (dates, author). ADR-001 C9.
extension ContractPost {
    init(_ saved: SavedPost) {
        self.init(id: saved.id, platform: saved.platform, url: saved.url, kind: saved.kind, author: saved.author,
                  caption: saved.caption, hashtags: saved.hashtags,
                  mentions: saved.mentions.map { Mention(username: $0.username, displayName: $0.displayName) },
                  collections: saved.collections, savedAt: saved.savedAt.map(Self.timestamp))
        author.displayName = saved.authorDisplayName
        postedAt = saved.postedAt.map(Self.timestamp)
        thumbnailUrl = saved.thumbnailURL
        locationTag = saved.locationTag.map { LocationTag(name: $0.name, address: $0.address, lat: $0.lat, lng: $0.lng) }
        language = saved.language
    }

    /// The user's own saves, newest first, without the bundled seed (someone
    /// else's saves, kept only for the sample data).
    static func userPosts(from saved: [SavedPost]) -> [ContractPost] {
        saved.filter { $0.source != .seedMD }
            .sorted { ($0.date ?? .distantPast) > ($1.date ?? .distantPast) }
            .map(ContractPost.init)
    }

    private static func timestamp(_ date: Date) -> String { date.formatted(.iso8601) }
}

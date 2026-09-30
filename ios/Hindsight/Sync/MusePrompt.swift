import Foundation

/// The message we hand to Muse. It pins Muse to a JSON schema that
/// `SavedPostParser.parseJSON` reads (the `posts[]` keys of
/// docs/data-contract.md), so we don't depend on how Muse feels like
/// formatting a list that day.
enum MusePrompt {
    enum Window: Equatable {
        /// Everything, newest first.
        case all
        /// New saves since the newest one we have.
        case after(Date)
        /// Backfill: saves older than the oldest one we have.
        case before(Date)
    }

    /// Full captions make each item long, so fewer fit in one reply.
    static let defaultLimit = 50

    static func text(
        platforms: [Platform] = [.instagram, .facebook],
        window: Window = .all,
        limit: Int = defaultLimit
    ) -> String {
        let names = platforms.map(\.displayName).formatted(.list(type: .and))
        let values = platforms.map { "\"\($0.rawValue)\"" }.joined(separator: " or ")
        let scope = switch window {
        case .all: ""
        case .after(let date): " saved after \(day(date))"
        case .before(let date): " saved before \(day(date))"
        }
        return """
        List my saved posts from \(names)\(scope), newest first, up to \(limit). \
        Include the name of the saved collection each one is in, if any.

        Reply with only one ```json code block holding an array. Each item has these keys \
        (use null or [] when you don't know; never guess):
        - "platform": \(values)
        - "url": the post's permalink
        - "kind": "reel", "post", "carousel" or "video"
        - "author": the account's username, without @
        - "author_display_name": the account's display name
        - "caption": the full caption, exactly as written (don't shorten or translate it)
        - "mentions": accounts tagged or @mentioned, as [{"username", "display_name"}]
        - "collections": names of my saved collections that contain it
        - "saved_at": when I saved it (YYYY-MM-DD or full timestamp)
        - "posted_at": when it was posted
        - "location_tag": the post's location sticker as {"name", "address"}, or null
        - "thumbnail_url": the post's image URL, or null

        No commentary before or after the code block. This is for my hindsight app.
        """
    }

    private static func day(_ date: Date) -> String {
        date.formatted(Date.ISO8601FormatStyle(timeZone: .current).year().month().day())
    }
}

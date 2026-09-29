import Foundation

/// The message we hand to Muse. It pins Muse to a JSON schema that
/// `SavedPostParser.parseJSON` reads, so we don't depend on how Muse
/// feels like formatting a list that day.
enum MusePrompt {
    static func text(
        platforms: [Platform] = [.instagram, .facebook],
        since: Date? = nil,
        limit: Int = 100
    ) -> String {
        let names = platforms.map(\.displayName).formatted(.list(type: .and))
        let window = since.map { " saved after \($0.formatted(.iso8601.year().month().day()))" } ?? ""
        let values = platforms.map { "\"\($0.rawValue)\"" }.joined(separator: " or ")
        return """
        List my saved posts from \(names)\(window), newest first, up to \(limit).

        Reply with only one ```json code block holding an array. Each item has exactly these keys:
        - "platform": \(values)
        - "author": the account's username, without @
        - "kind": "reel", "post", "carousel" or "video"
        - "date": YYYY-MM-DD, when I saved it if you know, otherwise when it was posted
        - "caption": the first 160 characters of the caption, or null
        - "url": the post's permalink

        No commentary before or after the code block. This is for my hindsight app.
        """
    }
}

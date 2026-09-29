import Foundation

/// Turns exported text (Muse replies, the bundled seed) into `SavedPost`s.
///
/// Accepts two formats:
/// - JSON: an array of `{platform, author, kind, date, caption, url}` objects,
///   bare or inside a ```json fence. This is what `MusePrompt` asks Muse for.
/// - Markdown (the seed / older Muse output):
///   ```
///   12. **@username** · reel · 2026-09-16
///      Caption text…
///      https://www.instagram.com/reel/CODE/
///   ```
///   Bold is optional, the caption may be missing or span several lines.
enum SavedPostParser {
    struct Result: Sendable {
        var posts: [SavedPost]
        /// Entries that looked like posts but had no usable URL.
        var skipped: Int
    }

    static func parse(_ text: String) -> Result {
        if let json = parseJSON(text) { return json }
        return parseMarkdown(text)
    }

    // MARK: - JSON

    private struct Entry: Decodable {
        var platform: String?
        var author: String?
        var kind: String?
        var date: String?
        var caption: String?
        var url: String?
    }

    static func parseJSON(_ text: String) -> Result? {
        guard let start = text.firstIndex(of: "["), let end = text.lastIndex(of: "]"), start < end,
              let data = String(text[start...end]).data(using: .utf8),
              let entries = try? JSONDecoder().decode([Entry].self, from: data)
        else { return nil }

        var result = Result(posts: [], skipped: 0)
        for entry in entries {
            guard let url = entry.url.flatMap(cleanURL) else {
                result.skipped += 1
                continue
            }
            result.posts.append(SavedPost(
                platform: entry.platform.flatMap(Platform.init(label:)),
                author: (entry.author ?? "").trimmingPrefix("@").trimmingCharacters(in: .whitespaces),
                kind: SavedPost.Kind(label: entry.kind ?? ""),
                date: entry.date.flatMap(parseDate),
                caption: entry.caption?.trimmingCharacters(in: .whitespacesAndNewlines),
                url: url
            ))
        }
        return result
    }

    // MARK: - Markdown

    // Computed because Regex isn't Sendable, so it can't be a static let under Swift 6.
    private static var header: Regex<(Substring, Substring, Substring, Substring)> {
        /^\s*\d+\.\s+(?:\*\*)?@([^*\s·]+)(?:\*\*)?\s*·\s*([A-Za-z]+)\s*·\s*(\d{4}-\d{2}-\d{2})\s*$/
    }
    private static var urlPattern: Regex<Substring> { /https?:\/\/[^\s)\]>]+/ }

    static func parseMarkdown(_ text: String) -> Result {
        let header = header, urlPattern = urlPattern
        var result = Result(posts: [], skipped: 0)
        var current: (author: String, kind: String, date: String)?
        var body: [Substring] = []

        func flush() {
            guard let head = current else { return }
            defer { current = nil; body = [] }
            var caption: [Substring] = []
            var url: URL?
            for line in body {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if url == nil, let match = trimmed.firstMatch(of: urlPattern),
                   match.range.lowerBound == trimmed.startIndex || trimmed.hasPrefix("[") {
                    url = cleanURL(String(match.output))
                } else if !trimmed.isEmpty {
                    caption.append(Substring(trimmed))
                }
            }
            guard let url else {
                result.skipped += 1
                return
            }
            result.posts.append(SavedPost(
                author: head.author,
                kind: SavedPost.Kind(label: head.kind),
                date: parseDate(head.date),
                caption: caption.joined(separator: " "),
                url: url
            ))
        }

        for line in text.split(separator: "\n", omittingEmptySubsequences: false) {
            if let match = line.wholeMatch(of: header) {
                flush()
                current = (String(match.1), String(match.2), String(match.3))
            } else if current != nil {
                body.append(line)
            }
        }
        flush()
        return result
    }

    // MARK: - Helpers

    private static func cleanURL(_ raw: String) -> URL? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines.union(.init(charactersIn: ".,;")))
        guard let url = URL(string: trimmed), url.scheme?.hasPrefix("http") == true, url.host() != nil else {
            return nil
        }
        return url
    }

    private static func parseDate(_ raw: String) -> Date? {
        try? Date(raw.prefix(10) + "T00:00:00Z", strategy: .iso8601)
    }
}

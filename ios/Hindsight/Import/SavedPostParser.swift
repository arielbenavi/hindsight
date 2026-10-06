import Foundation

/// Turns exported text (Muse replies, the bundled seed) into `SavedPost`s.
///
/// Accepts two formats:
/// - JSON: an array of post objects, bare or inside a ```json fence. Keys follow
///   docs/data-contract.md (`url`, `platform`, `kind`, `author` as a string or
///   `{username, display_name}`, `author_display_name`, `caption`, `hashtags`,
///   `mentions`, `collections`, `saved_at`, `posted_at`, `thumbnail_url`,
///   `location_tag`). This is what `MusePrompt` asks Muse for. The pre-contract
///   `date` key is read as `saved_at`.
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

    /// `source` is recorded on every post (`.muse` for pasted replies, `.seedMD` for the seed).
    static func parse(_ text: String, source: SavedPost.Source = .muse) -> Result {
        if let json = parseJSON(text, source: source) { return json }
        return parseMarkdown(text, source: source)
    }

    // MARK: - JSON

    static func parseJSON(_ text: String, source: SavedPost.Source = .muse) -> Result? {
        guard let start = text.firstIndex(of: "["), let end = text.lastIndex(of: "]"), start < end,
              let data = String(text[start...end]).data(using: .utf8),
              let entries = (try? JSONSerialization.jsonObject(with: data)) as? [Any]
        else { return nil }

        var result = Result(posts: [], skipped: 0)
        for case let entry as [String: Any] in entries {
            guard let url = string(entry["url"]).flatMap(cleanURL) else {
                result.skipped += 1
                continue
            }
            let authorObject = entry["author"] as? [String: Any]
            let author = string(authorObject?["username"]) ?? string(entry["author"]) ?? ""
            result.posts.append(SavedPost(
                platform: string(entry["platform"]).flatMap(Platform.init(label:)),
                url: url,
                kind: SavedPost.Kind(label: string(entry["kind"]) ?? ""),
                author: String(author.trimmingPrefix("@")).trimmingCharacters(in: .whitespaces),
                authorDisplayName: string(authorObject?["display_name"]) ?? string(entry["author_display_name"]),
                caption: string(entry["caption"])?.trimmingCharacters(in: .whitespacesAndNewlines),
                hashtags: (entry["hashtags"] as? [String]).map { $0.map { $0.trimmingPrefix("#").lowercased() } },
                mentions: (entry["mentions"] as? [[String: Any]]).map { list in
                    list.compactMap { m in
                        string(m["username"]).map {
                            SavedPost.Mention(username: String($0.trimmingPrefix("@")), displayName: string(m["display_name"]))
                        }
                    }
                },
                collections: (entry["collections"] as? [String]) ?? [],
                savedAt: string(entry["saved_at"] ?? entry["date"]).flatMap(parseDate),
                postedAt: string(entry["posted_at"]).flatMap(parseDate),
                thumbnailURL: string(entry["thumbnail_url"]).flatMap(cleanURL),
                locationTag: (entry["location_tag"] as? [String: Any]).map {
                    SavedPost.LocationTag(
                        name: string($0["name"]), address: string($0["address"]),
                        lat: ($0["lat"] as? NSNumber)?.doubleValue, lng: ($0["lng"] as? NSNumber)?.doubleValue
                    )
                },
                // The connector's /saves keeps each record's own source (muse, whatsapp_bot…).
                source: string(entry["source"]).flatMap(SavedPost.Source.init(rawValue:)) ?? source
            ))
        }
        return result
    }

    /// Non-empty string, or nil (the contract never uses "" for unknown).
    private static func string(_ value: Any?) -> String? {
        guard let string = value as? String, !string.isEmpty else { return nil }
        return string
    }

    // MARK: - Markdown

    // Computed because Regex isn't Sendable, so it can't be a static let under Swift 6.
    private static var header: Regex<(Substring, Substring, Substring, Substring)> {
        /^\s*\d+\.\s+(?:\*\*)?@([^*\s·]+)(?:\*\*)?\s*·\s*([A-Za-z]+)\s*·\s*(\d{4}-\d{2}-\d{2})\s*$/
    }
    private static var urlPattern: Regex<Substring> { /https?:\/\/[^\s)\]>]+/ }

    static func parseMarkdown(_ text: String, source: SavedPost.Source = .muse) -> Result {
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
                url: url,
                kind: SavedPost.Kind(label: head.kind),
                author: head.author,
                caption: caption.joined(separator: " "),
                // Muse was asked for saved posts newest-saved-first; treat its date as saved.
                savedAt: parseDate(head.date),
                source: source
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
        guard let url = URL(string: trimmed) else { return nil }
        // Notes (WhatsApp) have no permalink; they carry a stable hindsight-note: id instead.
        if url.scheme == "hindsight-note" { return url }
        guard url.scheme?.hasPrefix("http") == true, url.host() != nil else { return nil }
        return url
    }

    /// A full ISO 8601 timestamp, or `YYYY-MM-DD` as local midnight so the
    /// calendar day shown matches the source.
    static func parseDate(_ raw: String) -> Date? {
        if raw.count > 10, let date = try? Date(raw, strategy: .iso8601) { return date }
        let parts = raw.prefix(10).split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        return Calendar.current.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2]))
    }
}

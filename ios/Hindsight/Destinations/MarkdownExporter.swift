import Foundation

/// A save, or a whole topic, as Markdown for Notes, Files, Obsidian… Pure.
/// Per save: title, author, link, when it was saved, the caption, the transcript
/// when hindsight has one, and the user's note.
enum MarkdownExporter {
    struct Entry: Sendable {
        var post: ContractPost
        var transcript: String?
        var note: String?
    }

    static func document(for entry: Entry, topic: String? = nil, now: Date) -> String {
        var lines = ["# \(Destinations.title(for: entry.post))", ""]
        lines += meta(entry, topic: topic)
        lines += body(entry, level: "##")
        lines += ["", footer(now)]
        return lines.joined(separator: "\n") + "\n"
    }

    static func document(topic: String, entries: [Entry], now: Date) -> String {
        var lines = ["# \(topic)", "", "\(entries.count.counted("save")) · \(footer(now))"]
        for entry in entries {
            lines += ["", "## \(Destinations.title(for: entry.post))", ""]
            lines += meta(entry, topic: nil)
            lines += body(entry, level: "###")
        }
        return lines.joined(separator: "\n") + "\n"
    }

    /// "Miso pasta.md": the title without characters file systems dislike.
    static func fileName(_ title: String) -> String {
        let bad = CharacterSet(charactersIn: "/\\:*?\"<>|#\n\r\t")
        let cleaned = title.components(separatedBy: bad).joined(separator: " ")
            .split(separator: " ").joined(separator: " ")
        let short = String(cleaned.prefix(60)).trimmingCharacters(in: .whitespaces.union(.punctuationCharacters))
        return (short.isEmpty ? "hindsight" : short) + ".md"
    }

    private static func meta(_ entry: Entry, topic: String?) -> [String] {
        let post = entry.post
        var author = post.byline
        if let name = post.author.displayName?.nilIfBlank, name != post.author.username { author += " (\(name))" }
        var lines = ["- **From:** \(author) · \(post.platform.displayName)", "- **Link:** <\(post.url.absoluteString)>"]
        if let date = post.savedDate { lines.append("- **Saved:** \(day(date))") }
        if let topic { lines.append("- **Topic:** \(topic)") }
        return lines
    }

    private static func body(_ entry: Entry, level: String) -> [String] {
        var lines: [String] = []
        if let note = entry.note?.nilIfBlank { lines += ["", "\(level) My note", "", note] }
        if let caption = entry.post.caption?.nilIfBlank { lines += ["", "\(level) Caption", "", caption] }
        if let transcript = entry.transcript?.nilIfBlank { lines += ["", "\(level) Transcript", "", transcript] }
        return lines
    }

    private static func footer(_ now: Date) -> String { "Exported from hindsight on \(day(now))." }

    /// ISO day ("2026-11-20") in local time (the ISO formatter's UTC would show a
    /// local-midnight save as the day before; LESSONS.md).
    private static func day(_ date: Date) -> String {
        let c = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }
}

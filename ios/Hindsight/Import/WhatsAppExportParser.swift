import Foundation

/// Reads a WhatsApp "Export chat" file (the `_chat.txt`, or the .zip holding it)
/// into `SavedPost`s: every link becomes a save (an Instagram/TikTok/X post, or
/// a web page), and plain text the user wrote becomes a `.note`.
///
/// Built for a notes-to-self chat. In chats with other people we keep the
/// links anyone shared but only the user's own text, since other people's
/// messages are their personal data.
///
/// Export formats differ by phone and locale, e.g.
///   iOS:     `[30/09/2026, 14:27:03] Ariel: text`   `[9/30/26, 2:27:03 PM] Ariel: text`
///   Android: `30/09/2026, 14:27 - Ariel: text`       `2026-09-30, 14:27 - Ariel: text`
/// Messages can span several lines. Ported from web/backend/scripts/import_whatsapp.py.
enum WhatsAppExportParser {
    struct Result: Sendable {
        var posts: [SavedPost]
        var messages: Int
        var links: Int
        var notes: Int
        /// Text from other people that was skipped (links are still kept).
        var othersSkipped: Int
    }

    enum ImportError: LocalizedError {
        case notAChatExport
        var errorDescription: String? {
            "That doesn't look like a WhatsApp chat export. In WhatsApp: open the chat → tap its name → Export chat → Without media."
        }
    }

    struct Message: Equatable {
        var date: Date?
        var sender: String?
        var text: String
    }

    // MARK: - Entry points

    static func parse(fileAt url: URL, me: String? = nil) throws -> Result {
        let text: String
        if url.pathExtension.lowercased() == "zip" {
            let zip = try ZipReader(url: url)
            guard let entry = zip.entries.first(where: { ($0.name as NSString).lastPathComponent == "_chat.txt" })
                    ?? zip.entries.first(where: { $0.name.lowercased().hasSuffix(".txt") })
            else { throw ImportError.notAChatExport }
            text = String(decoding: try zip.data(for: entry), as: UTF8.self)
        } else {
            text = try String(contentsOf: url, encoding: .utf8)
        }
        let result = parse(text: text, me: me)
        guard result.messages > 0 else { throw ImportError.notAChatExport }
        return result
    }

    /// `me`: the user's name as it appears in the export. When nil, the most
    /// frequent sender is assumed to be the user (true for a notes-to-self chat).
    static func parse(text: String, me: String? = nil) -> Result {
        let messages = self.messages(in: text)
        let user = me ?? mostFrequentSender(messages)
        var result = Result(posts: [], messages: messages.count, links: 0, notes: 0, othersSkipped: 0)

        for message in messages {
            let urls = links(in: message.text)
            for url in urls {
                result.posts.append(SavedPost(
                    platform: Platform(url: url) ?? .web,
                    url: url,
                    kind: kind(for: url),
                    author: "",
                    caption: nil,
                    savedAt: message.date,
                    source: .whatsappExport
                ))
                result.links += 1
            }

            let isMine = user == nil || message.sender == nil || message.sender == user
            var note = message.text
            for url in urls { note = note.replacingOccurrences(of: url.absoluteString, with: "") }
            note = note.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !note.isEmpty else { continue }
            guard isMine else {
                result.othersSkipped += 1
                continue
            }
            if urls.isEmpty {
                result.posts.append(SavedPost(
                    platform: .whatsapp,
                    url: noteURL(date: message.date, text: note),
                    kind: .note,
                    author: message.sender ?? "",
                    caption: note,
                    savedAt: message.date,
                    source: .whatsappExport
                ))
                result.notes += 1
            } else if let last = result.posts.indices.last {
                // Text around a link: keep it as that link's caption ("try this with rice").
                result.posts[last].caption = note
            }
        }
        return result
    }

    // MARK: - Messages

    /// One header regex per export style; `(date) (time)` then sender/text follow.
    private static var headers: [Regex<(Substring, Substring, Substring)>] {
        [
            /^\[(\d{1,4}[\/.\-]\d{1,2}[\/.\-]\d{1,4}),?\s+(\d{1,2}:\d{2}(?::\d{2})?(?:\s?[AaPp]\.?\s?[Mm]\.?)?)\]\s?/,
            /^(\d{1,4}[\/.\-]\d{1,2}[\/.\-]\d{1,4}),?\s+(\d{1,2}:\d{2}(?::\d{2})?(?:\s?[AaPp]\.?\s?[Mm]\.?)?)\s?[-–]\s/,
        ]
    }

    static func messages(in text: String) -> [Message] {
        let headers = headers
        // iOS exports sprinkle invisible direction marks; they break matching.
        let cleaned = text.replacingOccurrences(of: "\u{200E}", with: "").replacingOccurrences(of: "\u{200F}", with: "")
        let lines = cleaned.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline)
        guard let header = headers.first(where: { h in lines.prefix(50).contains { $0.firstMatch(of: h) != nil } }) else {
            return []
        }

        var raw: [(date: String, time: String, rest: String)] = []
        for line in lines {
            if let match = line.prefixMatch(of: header) {
                raw.append((String(match.1), String(match.2), String(line[match.range.upperBound...])))
            } else if !raw.isEmpty {
                raw[raw.count - 1].rest += "\n" + line
            }
        }

        let order = dateOrder(raw.map(\.date), usesAMPM: raw.contains { $0.time.lowercased().contains("m") })
        return raw.compactMap { entry in
            // "Sender: text". Lines without a sender are system messages.
            guard let colon = entry.rest.range(of: ": ") else { return nil }
            let sender = String(entry.rest[..<colon.lowerBound]).trimmingCharacters(in: .whitespaces)
            let text = String(entry.rest[colon.upperBound...])
            guard !isSystemOrMedia(text) else { return nil }
            return Message(date: date(entry.date, entry.time, order: order), sender: sender, text: text)
        }
    }

    private static func isSystemOrMedia(_ text: String) -> Bool {
        let lower = text.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        return lower.isEmpty
            || lower.hasPrefix("<attached:") || lower.contains("<media omitted>")
            || lower.hasPrefix("image omitted") || lower.hasPrefix("video omitted")
            || lower.hasPrefix("audio omitted") || lower.hasPrefix("sticker omitted")
            || lower.hasPrefix("document omitted") || lower.hasPrefix("gif omitted")
            || lower == "this message was deleted" || lower == "you deleted this message"
            || lower.contains("messages and calls are end-to-end encrypted")
    }

    /// The user = whoever wrote the most; on a tie, whoever wrote first (usually
    /// the person who made the notes chat). Deterministic, unlike a plain max.
    static func mostFrequentSender(_ messages: [Message]) -> String? {
        let senders = messages.compactMap(\.sender)
        let counts = Dictionary(grouping: senders, by: { $0 }).mapValues(\.count)
        let firstSeen = Dictionary(senders.enumerated().map { ($1, $0) }, uniquingKeysWith: min)
        return counts.max { a, b in
            a.value != b.value ? a.value < b.value : firstSeen[a.key, default: 0] > firstSeen[b.key, default: 0]
        }?.key
    }

    // MARK: - Dates

    enum DateOrder { case dayFirst, monthFirst, yearFirst }

    /// Decides day/month order from the whole file: any first number > 12 means
    /// day-first, any second number > 12 means month-first. Undecidable files
    /// fall back to month-first when times use AM/PM (US style), else day-first.
    static func dateOrder(_ dates: [String], usesAMPM: Bool = false) -> DateOrder {
        var dayFirst = false, monthFirst = false
        for date in dates {
            let parts = date.split(whereSeparator: { "/.-".contains($0) }).compactMap { Int($0) }
            guard parts.count == 3 else { continue }
            if parts[0] > 31 { return .yearFirst }
            if parts[0] > 12 { dayFirst = true }
            if parts[1] > 12 { monthFirst = true }
        }
        if dayFirst != monthFirst { return dayFirst ? .dayFirst : .monthFirst }
        return usesAMPM ? .monthFirst : .dayFirst
    }

    static func date(_ date: String, _ time: String, order: DateOrder) -> Date? {
        let parts = date.split(whereSeparator: { "/.-".contains($0) }).compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        var (day, month, year) = switch order {
        case .dayFirst: (parts[0], parts[1], parts[2])
        case .monthFirst: (parts[1], parts[0], parts[2])
        case .yearFirst: (parts[2], parts[1], parts[0])
        }
        if year < 100 { year += 2000 }

        let lowerTime = time.lowercased().replacingOccurrences(of: ".", with: "")
        let isPM = lowerTime.contains("pm"), isAM = lowerTime.contains("am")
        let clock = lowerTime.filter { $0.isNumber || $0 == ":" }.split(separator: ":").compactMap { Int($0) }
        guard clock.count >= 2 else { return nil }
        var hour = clock[0]
        if isPM && hour < 12 { hour += 12 }
        if isAM && hour == 12 { hour = 0 }
        if !(1...12).contains(month), (1...12).contains(day) { swap(&day, &month) }
        return Calendar.current.date(from: DateComponents(
            year: year, month: month, day: day, hour: hour, minute: clock[1], second: clock.count > 2 ? clock[2] : 0
        ))
    }

    // MARK: - Links and notes

    private static var urlPattern: Regex<Substring> { /https?:\/\/[^\s<>"]+/ }

    static func links(in text: String) -> [URL] {
        let pattern = urlPattern
        return text.matches(of: pattern).compactMap { match in
            let trimmed = String(match.output).trimmingCharacters(in: .init(charactersIn: ".,;:!?)]}'\""))
            guard let url = URL(string: trimmed), url.host() != nil else { return nil }
            return url
        }
    }

    private static func kind(for url: URL) -> SavedPost.Kind {
        let path = url.path().lowercased()
        switch Platform(url: url) {
        case .instagram: return path.contains("/reel") ? .reel : path.contains("/tv/") ? .video : .post
        case .x: return .tweet
        case .tiktok: return .video
        case .facebook: return path.contains("/reel") ? .reel : path.contains("video") ? .video : .post
        default: return .link
        }
    }

    /// Notes have no permalink, so they get a stable made-up one: the same note
    /// imported twice gets the same id and is deduplicated.
    static func noteURL(date: Date?, text: String) -> URL {
        let stamp = date.map { String(Int($0.timeIntervalSince1970)) } ?? "0"
        var hash: UInt64 = 1469598103934665603 // FNV-1a
        for byte in (stamp + "|" + text).utf8 { hash = (hash ^ UInt64(byte)) &* 1099511628211 }
        return URL(string: "hindsight-note:whatsapp/\(stamp)-\(String(hash, radix: 36))")!
    }
}

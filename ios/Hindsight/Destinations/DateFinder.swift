import Foundation

/// Finds an event date in a caption ("Saturday Dec 5 at 8pm", "until 30.11.2026")
/// with `NSDataDetector`. Only dates still ahead (from the start of the reference
/// day, up to a year out) count: a save about a past event has nothing to add.
enum DateFinder {
    struct Found: Hashable, Sendable {
        var date: Date
        /// The caption gave a time ("8pm", "20:00"); otherwise it's an all-day event.
        var hasTime: Bool
        /// The words it came from, e.g. "Saturday, December 5 at 8pm".
        var text: String
    }

    static let horizonDays = 365

    static func find(in text: String?, reference: Date, calendar: Calendar = .current) -> Found? {
        guard let text, !text.isEmpty,
              let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.date.rawValue) else { return nil }
        let start = calendar.startOfDay(for: reference)
        guard let end = calendar.date(byAdding: .day, value: horizonDays, to: start) else { return nil }
        let ns = text as NSString
        for match in detector.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
            guard var date = match.date else { continue }
            let words = ns.substring(with: match.range)
            // "ends Nov 30" / "until 30.11" come back as a range from *now*: the deadline is its end.
            if match.duration > 0, isDeadline(words) { date = date.addingTimeInterval(match.duration) }
            guard looksLikeADate(words), date >= start, date <= end else { continue }
            return Found(date: date, hasTime: hasTime(words), text: words)
        }
        return nil
    }

    /// The detector also reads "1/2 cup" as January 2 and "3.5" as a date. Keep
    /// matches that name a month or a day, give a time, or carry a 4-digit year.
    static func looksLikeADate(_ words: String) -> Bool {
        if words.contains(where: \.isLetter) { return true }   // "Dec 5", "Saturday", "tomorrow"
        if hasTime(words) { return true }                        // "20:00"
        return words.range(of: #"\d{4}"#, options: .regularExpression) != nil  // "30.11.2026"
    }

    static func isDeadline(_ words: String) -> Bool {
        let first = words.lowercased().split(whereSeparator: { !$0.isLetter }).first.map(String.init) ?? ""
        return ["ends", "end", "ending", "until", "till", "til", "through", "thru", "by", "before"].contains(first)
    }

    static func hasTime(_ words: String) -> Bool {
        let lower = words.lowercased()
        return lower.range(of: #"\d{1,2}:\d{2}"#, options: .regularExpression) != nil
            || lower.range(of: #"\d\s?(am|pm|a\.m\.|p\.m\.)"#, options: .regularExpression) != nil
            || lower.contains("noon") || lower.contains("midnight")
    }
}

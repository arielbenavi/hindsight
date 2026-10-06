import Foundation

/// The weekly ring (learn.md): tries this week vs. the goal. Weeks start Monday,
/// reset every Monday, and there is no "broken" or "failed" state, ever.
struct WeeklyProgress: Equatable, Sendable {
    var done: Int
    var goal: Int
    /// First week only: the pre-filled "Picked your saves ✓" segment.
    var setupSegment: Bool

    var filled: Int { min(goal, done + (setupSegment ? 1 : 0)) }
    var fraction: Double { goal == 0 ? 0 : Double(filled) / Double(goal) }
    var isComplete: Bool { filled >= goal }

    static func calendar(_ base: Calendar = .current) -> Calendar {
        var cal = base
        cal.firstWeekday = 2 // Monday
        return cal
    }

    static func startOfWeek(_ date: Date, calendar: Calendar = .current) -> Date {
        let cal = Self.calendar(calendar)
        return cal.dateInterval(of: .weekOfYear, for: date)!.start
    }

    static func make(states: some Collection<PracticeState>, goal: Int, setupDoneAt: Date?, now: Date,
                     calendar: Calendar = .current) -> WeeklyProgress {
        let start = startOfWeek(now, calendar: calendar)
        let done = states.reduce(0) { $0 + $1.triedAt.count { $0 >= start && $0 <= now } }
        let setup = setupDoneAt.map { $0 >= start } ?? false
        return WeeklyProgress(done: done, goal: max(goal, 1), setupSegment: setup)
    }

    /// The last `weeks` weeks, oldest first (L5: small rings, no "failed" styling).
    static func history(states: some Collection<PracticeState>, goal: Int, weeks: Int = 8, now: Date,
                        calendar: Calendar = .current) -> [(start: Date, done: Int)] {
        let cal = Self.calendar(calendar)
        let thisWeek = startOfWeek(now, calendar: calendar)
        let allDates = states.flatMap(\.triedAt)
        return (0..<weeks).reversed().map { offset in
            let start = cal.date(byAdding: .weekOfYear, value: -offset, to: thisWeek)!
            let end = cal.date(byAdding: .weekOfYear, value: 1, to: start)!
            return (start, allDates.count { $0 >= start && $0 < end })
        }
    }

    /// Mondays, and the first open after 7+ days away (learn.md → Monday card).
    static func freshStart(now: Date, lastOpenedAt: Date?, calendar: Calendar = .current) -> FreshStart? {
        if let last = lastOpenedAt, now.timeIntervalSince(last) >= 7 * 86_400 { return .afterBreak }
        if calendar.component(.weekday, from: now) == 2 { return .newWeek }
        return nil
    }

    enum FreshStart: Equatable, Sendable {
        case newWeek, afterBreak

        var line: String {
            switch self {
            case .newWeek: "New week. Here's today's pick."
            case .afterBreak: "Fresh start. Here's today's pick."
            }
        }
    }
}

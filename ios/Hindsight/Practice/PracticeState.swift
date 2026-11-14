import Foundation

/// The user's side of one practice item (a Learn tip or a Fitness routine).
/// Persisted separately from the data file, so re-running extraction never wipes it.
struct PracticeState: Codable, Hashable, Sendable {
    var status: PracticeStatus = .new
    /// "Tried it" (Learn) / "Did it" (Fitness) times.
    var triedAt: [Date] = []
    /// Spaced review step (Learn): 0 = none yet, then 3 → 10 → 30 days.
    var reviewStep = 0
    var nextReviewAt: Date?
    /// A "When?" reminder the user set.
    var remindAt: Date?
    var lastShownAt: Date?
    var topicOverride: String?
}

enum PracticeStatus: String, Codable, Sendable {
    case new, wantToTry, tried, archived
}

/// What the picker needs to know about an item, whatever the lego screen.
struct PracticeCandidate: Hashable, Sendable, Identifiable {
    var id: String
    /// Rotation key: the topic (Learn) or main body area (Fitness).
    var topicKey: String
    /// Learn: has a try prompt. Fitness: always (thin routines are follow-along).
    var isPickable: Bool
}

/// How a lego screen uses the shared loop (fitness.md → "How Fitness uses the practice loop").
struct PracticeConfig: Sendable {
    /// Tried items stay in rotation (Fitness) vs. come back only as reviews (Learn).
    var repeatsAfterDone: Bool
    var recentWindowDays: Int
    var recentPenalty: Double
    var doneBeforeBoost: Double

    static let learn = PracticeConfig(repeatsAfterDone: false, recentWindowDays: 14, recentPenalty: 0.2, doneBeforeBoost: 1)
    static let fitness = PracticeConfig(repeatsAfterDone: true, recentWindowDays: 3, recentPenalty: 0.3, doneBeforeBoost: 1.5)
}

/// When the daily nudge goes out.
enum ReminderSlot: String, Codable, CaseIterable, Sendable, Identifiable {
    case morning, lunch, evening, off

    var id: String { rawValue }

    var title: String {
        switch self {
        case .morning: "Morning"
        case .lunch: "Lunch"
        case .evening: "Evening"
        case .off: "Off"
        }
    }

    /// Hour and minute of the slot. `off` has none.
    var time: (hour: Int, minute: Int)? {
        switch self {
        case .morning: (8, 0)
        case .lunch: (12, 30)
        case .evening: (19, 30)
        case .off: nil
        }
    }
}

/// A Fitness "Regular": a routine the user wants to do on set days.
struct RegularSchedule: Codable, Hashable, Sendable {
    var routineID: String
    /// 1 = Sunday … 7 = Saturday, like `Calendar`.
    var weekdays: Set<Int>
    var hour: Int
    var minute: Int

    func fires(on date: Date, calendar: Calendar = .current) -> Bool {
        weekdays.contains(calendar.component(.weekday, from: date))
    }

    var summary: String {
        let symbols = Calendar.current.shortWeekdaySymbols
        let days: String
        switch weekdays {
        case Set(1...7): days = "Every day"
        case Set(2...6): days = "Weekdays"
        default: days = weekdays.sorted { ($0 + 5) % 7 < ($1 + 5) % 7 }.map { symbols[$0 - 1] }.joined(separator: " ")
        }
        return "\(days) · \(String(format: "%d:%02d", hour, minute))"
    }
}

/// Per-lego-screen settings and daily bookkeeping.
struct ScreenPractice: Codable, Sendable {
    var states: [String: PracticeState] = [:]
    var weeklyGoal = 3
    var slot: ReminderSlot = .off
    var setupDone = false
    var setupDoneAt: Date?
    /// Fitness setup: the body areas the user picked ("What needs some love?").
    var pickedTopicKeys: [String] = []
    var regulars: [String: RegularSchedule] = [:]
    /// Today's picks (stable all day): the day and the queue shown so far.
    var pickDay: String?
    var pickQueue: [String] = []
    /// How many of today's queue the user has opened ("One more?").
    var shownCount = 1
    /// Topic of the last day's first pick, for rotation.
    var lastPickTopic: String?
    var lastOpenedAt: Date?

    func state(_ id: String) -> PracticeState { states[id] ?? PracticeState() }
}

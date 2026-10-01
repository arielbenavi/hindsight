import Foundation

/// The practice-notification rules (learn.md → Notifications, fitness.md →
/// Notifications across Learn and Fitness), as pure logic.
///
/// Local notifications have to be scheduled ahead, so the policy plans the week
/// after the last app open, assuming each nudge is ignored. Any open replans.
/// - at most one app-chosen nudge a day, across Learn and Fitness, alternating
/// - daily at first; after 3 ignored in a row, every other day
/// - after 7 days with no opens: one last message, then silence until the next open
/// - never the same template twice in a row (per tab)
/// - no Fitness nudge on a day one of its Regulars fires (Learn takes the day, if on)
enum ReminderPolicy {
    static let dailyBeforeBackoff = 3
    static let quietDaysBeforeStop = 7

    struct Tab: Sendable {
        var screen: LegoScreen
        var slot: ReminderSlot
        /// Index of the template used last (for "never twice in a row").
        var lastTemplate: Int?
        var templateCount: Int
        /// Fitness: a Regular fires on that day.
        var hasRegular: @Sendable (Date) -> Bool = { _ in false }
    }

    struct Nudge: Equatable, Sendable {
        var date: Date
        var screen: LegoScreen
        var template: Int
        var isFinal: Bool
    }

    /// - todayHandled: today's practice is already done (no nudge today).
    static func plan(tabs: [Tab], lastOpenedAt: Date, now: Date, todayHandled: Bool, lastTab: LegoScreen? = nil,
                     calendar: Calendar = .current) -> [Nudge] {
        let active = tabs.filter { $0.slot.time != nil }
        guard !active.isEmpty else { return [] }
        let openDay = calendar.startOfDay(for: lastOpenedAt)
        var nudges: [Nudge] = []
        var templates = Dictionary(uniqueKeysWithValues: active.map { ($0.screen, $0.lastTemplate) })
        var previousTab = lastTab
        var lastSentOffset: Int?

        for offset in 0...quietDaysBeforeStop {
            let day = calendar.date(byAdding: .day, value: offset, to: openDay)!
            let isFinal = offset == quietDaysBeforeStop
            if offset == 0 && todayHandled { continue }
            if !isFinal, let last = lastSentOffset, nudges.count >= dailyBeforeBackoff, offset - last < 2 { continue }

            // Which tab gets the day: alternate; skip Fitness on its Regular days.
            let order = active.filter { $0.screen != previousTab } + active.filter { $0.screen == previousTab }
            guard let tab = order.first(where: { !($0.screen == .fitness && $0.hasRegular(day)) }),
                  let time = tab.slot.time,
                  let date = calendar.date(bySettingHour: time.hour, minute: time.minute, second: 0, of: day),
                  date > now else { continue }

            let template = isFinal ? 0 : nextTemplate(after: templates[tab.screen] ?? nil, count: tab.templateCount)
            nudges.append(Nudge(date: date, screen: tab.screen, template: template, isFinal: isFinal))
            templates[tab.screen] = template
            previousTab = tab.screen
            lastSentOffset = offset
        }
        return nudges
    }

    static func nextTemplate(after last: Int?, count: Int) -> Int {
        guard count > 1 else { return 0 }
        guard let last else { return 0 }
        return (last + 1) % count
    }

    /// "When?" chips: Tonight · Tomorrow · Weekend (learn.md → L2).
    enum When: String, CaseIterable, Identifiable, Sendable {
        case tonight, tomorrow, weekend
        var id: String { rawValue }
        var title: String { rawValue.capitalized }

        /// Tonight = the evening slot (or in 3 hours if that's passed); Tomorrow and
        /// Weekend use the screen's slot (evening if reminders are off).
        func date(from now: Date, slot: ReminderSlot, calendar: Calendar = .current) -> Date {
            let evening = ReminderSlot.evening.time!
            let time = slot.time ?? evening
            switch self {
            case .tonight:
                let tonight = calendar.date(bySettingHour: evening.hour, minute: evening.minute, second: 0, of: now)!
                return tonight > now ? tonight : now.addingTimeInterval(3 * 3600)
            case .tomorrow:
                let day = calendar.date(byAdding: .day, value: 1, to: now)!
                return calendar.date(bySettingHour: time.hour, minute: time.minute, second: 0, of: day)!
            case .weekend:
                var day = calendar.date(byAdding: .day, value: 1, to: now)!
                while calendar.component(.weekday, from: day) != 7 { day = calendar.date(byAdding: .day, value: 1, to: day)! }
                return calendar.date(bySettingHour: time.hour, minute: time.minute, second: 0, of: day)!
            }
        }

        /// Label on a handled card: "Tonight ⏰".
        var handledLabel: String { "\(title) ⏰" }
    }
}

/// Notification wording: rotating, always about one specific save, never guilt.
enum ReminderCopy {
    static let learn: [@Sendable (String, String) -> String] = [
        { title, saved in "2 min today? \(title), the one you saved \(saved)." },
        { title, _ in "You saved this for a reason: \"\(title)\"." },
        { title, _ in "One try. That's the whole ask. \(title)" },
        { title, _ in "Tiny practice break? \(title)" },
    ]

    static let fitness: [@Sendable (String, String) -> String] = [
        { title, _ in "\(title), a couple of minutes. Your body will thank you." },
        { title, _ in "Quick stretch? \"\(title)\" is waiting." },
        { title, _ in "Two minutes of \(title). Future you says thanks." },
    ]

    static let final = "We'll stop nudging for now. Your saves will be here."

    static func templates(for screen: LegoScreen) -> [@Sendable (String, String) -> String] {
        screen == .fitness ? fitness : learn
    }

    static func body(screen: LegoScreen, template: Int, title: String, savedAt: Date?) -> String {
        let list = templates(for: screen)
        let saved = savedAt.map { "in \($0.formatted(.dateTime.month(.wide)))" } ?? "a while ago"
        return list[template % list.count](title, saved)
    }
}

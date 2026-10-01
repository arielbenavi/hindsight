import Foundation
import UserNotifications

/// Thin `UNUserNotificationCenter` wrapper. It is the notification delegate (set
/// here, not in `HindsightApp.swift`), so taps land on the right card.
@MainActor
final class ReminderScheduler: NSObject, UNUserNotificationCenterDelegate {
    static let shared = ReminderScheduler()

    /// Called with (screen, item id) when a notification is tapped.
    var onOpen: ((LegoScreen, String) -> Void)?
    private var pendingOpen: (LegoScreen, String)?

    private var center: UNUserNotificationCenter { .current() }

    func install() {
        center.delegate = self
    }

    func setOnOpen(_ handler: @escaping (LegoScreen, String) -> Void) {
        onOpen = handler
        if let pending = pendingOpen {
            pendingOpen = nil
            handler(pending.0, pending.1)
        }
    }

    /// Ask for permission (setup step 3). Returns whether it was granted.
    func requestAuthorization() async -> Bool {
        (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
    }

    func isAuthorized() async -> Bool {
        let settings = await center.notificationSettings()
        return settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional
    }

    /// What one practice tab contributes to the schedule.
    struct TabInput {
        var screen: LegoScreen
        var practice: ScreenPractice
        var candidates: [PracticeCandidate]
        var config: PracticeConfig
        /// Title and saved date for a card, for the notification text.
        var describe: (String) -> (title: String, savedAt: Date?)?
    }

    /// Rebuild every practice notification from scratch. Call after opening the app
    /// and after anything that changes reminders.
    func reschedule(tabs: [TabInput], now: Date = .now, todayHandled: Bool) async {
        guard await isAuthorized() else { return }
        let pending = await center.pendingNotificationRequests().map(\.identifier)
        center.removePendingNotificationRequests(withIdentifiers: pending.filter { $0.hasPrefix("hs.") })

        // 1. User-set "When?" reminders: always fire, never two at the same minute.
        var used: Set<Date> = []
        for tab in tabs {
            for (id, state) in tab.practice.states {
                guard var date = state.remindAt, date > now, state.status != .archived,
                      let info = tab.describe(id) else { continue }
                while used.contains(date) { date += 30 * 60 }
                used.insert(date)
                add(id: "hs.remind.\(tab.screen.rawValue).\(id)", title: tab.screen.defaultTitle,
                    body: ReminderCopy.body(screen: tab.screen, template: 0, title: info.title, savedAt: info.savedAt),
                    screen: tab.screen, itemID: id, trigger: calendarTrigger(date, repeats: false))
            }
        }

        // 2. Fitness Regulars: repeating, one per weekday.
        if let fitness = tabs.first(where: { $0.screen == .fitness }) {
            for regular in fitness.practice.regulars.values {
                guard let info = fitness.describe(regular.routineID) else { continue }
                for weekday in regular.weekdays {
                    var comps = DateComponents()
                    comps.weekday = weekday
                    comps.hour = regular.hour
                    comps.minute = regular.minute
                    add(id: "hs.regular.\(regular.routineID).\(weekday)", title: "Fitness",
                        body: "\(info.title). Your body will thank you.", screen: .fitness, itemID: regular.routineID,
                        trigger: UNCalendarNotificationTrigger(dateMatching: comps, repeats: true))
                }
            }
        }

        // 3. The app-chosen daily nudge (policy: one a day across tabs, back-off, stop).
        let policyTabs = tabs.map { tab in
            let regulars = Array(tab.practice.regulars.values)
            return ReminderPolicy.Tab(screen: tab.screen, slot: tab.practice.slot, lastTemplate: nil,
                                      templateCount: ReminderCopy.templates(for: tab.screen).count,
                                      hasRegular: { day in regulars.contains { $0.fires(on: day) } })
        }
        let lastOpened = tabs.compactMap(\.practice.lastOpenedAt).max() ?? now
        let plan = ReminderPolicy.plan(tabs: policyTabs, lastOpenedAt: lastOpened, now: now, todayHandled: todayHandled)
        for nudge in plan {
            guard let tab = tabs.first(where: { $0.screen == nudge.screen }) else { continue }
            // The same pick the app will show that day (seeded by the day).
            let day = TodayPicker.dayKey(nudge.date)
            let input = TodayPicker.Input(candidates: tab.candidates, states: tab.practice.states, config: tab.config,
                                          boostedTopicKeys: Set(tab.practice.pickedTopicKeys), now: nudge.date)
            var rng = SeededRandom("\(day)|\(tab.screen.rawValue)")
            guard let itemID = TodayPicker.queue(input, rng: &rng).first, let info = tab.describe(itemID) else { continue }
            let body = nudge.isFinal ? ReminderCopy.final
                : ReminderCopy.body(screen: tab.screen, template: nudge.template, title: info.title, savedAt: info.savedAt)
            add(id: "hs.nudge.\(day)", title: nudge.isFinal ? "Hindsight" : tab.screen.defaultTitle, body: body,
                screen: tab.screen, itemID: itemID, trigger: calendarTrigger(nudge.date, repeats: false))
        }
    }

    private func calendarTrigger(_ date: Date, repeats: Bool) -> UNCalendarNotificationTrigger {
        let comps = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        return UNCalendarNotificationTrigger(dateMatching: comps, repeats: repeats)
    }

    private func add(id: String, title: String, body: String, screen: LegoScreen, itemID: String,
                     trigger: UNNotificationTrigger) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        content.userInfo = ["screen": screen.rawValue, "item": itemID]
        center.add(UNNotificationRequest(identifier: id, content: content, trigger: trigger))
    }

    // MARK: - UNUserNotificationCenterDelegate

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            didReceive response: UNNotificationResponse) async {
        let info = response.notification.request.content.userInfo
        guard let raw = info["screen"] as? String, let screen = LegoScreen(rawValue: raw),
              let item = info["item"] as? String else { return }
        await MainActor.run {
            if let onOpen = self.onOpen { onOpen(screen, item) } else { self.pendingOpen = (screen, item) }
        }
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }
}

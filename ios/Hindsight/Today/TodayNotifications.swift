import Foundation
import UserNotifications

/// Today's local notifications: the daily "3 saves from your past are ready" at
/// 9:00, and one per save the user asked to be reminded about. Ids start with
/// "hd." so `ReminderScheduler` (Learn/Fitness, "hs.") leaves them alone. Never
/// says anything about a Keep close save; callers don't pass those.
@MainActor
enum TodayNotifications {
    static let dailyID = "hd.today"
    static let dailyHour = 9
    static let askedKey = "today.notificationsAsked"
    static let dailyBody = "3 saves from your past are ready"

    private static var center: UNUserNotificationCenter { .current() }

    /// The next 9:00 after `now` (today's if it's still ahead). Pure.
    nonisolated static func nextDaily(after now: Date, hour: Int = 9, calendar: Calendar = .current) -> Date {
        let today = calendar.date(bySettingHour: hour, minute: 0, second: 0, of: now) ?? now
        return today > now ? today : calendar.date(byAdding: .day, value: 1, to: today) ?? today
    }

    /// "Tonight" = today 20:00, or tomorrow's if that's past. Pure.
    nonisolated static func tonight(after now: Date, calendar: Calendar = .current) -> Date {
        let eight = calendar.date(bySettingHour: 20, minute: 0, second: 0, of: now) ?? now
        return eight > now ? eight : calendar.date(byAdding: .day, value: 1, to: eight) ?? eight
    }

    /// "Weekend" = the next Saturday 10:00 (next week's if it's Saturday after 10). Pure.
    nonisolated static func weekend(after now: Date, calendar: Calendar = .current) -> Date {
        var comps = DateComponents()
        comps.weekday = 7
        comps.hour = 10
        comps.minute = 0
        return calendar.nextDate(after: now, matching: comps, matchingPolicy: .nextTime) ?? now
    }

    /// The first time the user finishes a Today set: ask once, then schedule.
    static func askOnceAfterFinishing(hasEligible: Bool) async {
        if !UserDefaults.standard.bool(forKey: askedKey) {
            UserDefaults.standard.set(true, forKey: askedKey)
            _ = await ReminderScheduler.shared.requestAuthorization()
        }
        await scheduleDaily(hasEligible: hasEligible)
    }

    /// One notification at the next 9:00, only when Today has something to serve.
    /// Rebuilt on launch, on leaving the app and after a set is finished.
    static func scheduleDaily(hasEligible: Bool, now: Date = .now) async {
        center.removePendingNotificationRequests(withIdentifiers: [dailyID])
        guard hasEligible, await ReminderScheduler.shared.isAuthorized() else { return }
        add(id: dailyID, title: "Today", body: dailyBody, at: nextDaily(after: now, hour: dailyHour))
    }

    /// A save's own reminder (Remind me → Tonight / Weekend). Asks for permission
    /// if it hasn't been asked: the user just asked to be reminded.
    static func scheduleReminder(for post: ContractPost, at date: Date) async {
        center.removePendingNotificationRequests(withIdentifiers: [reminderID(post.id)])
        if !(await ReminderScheduler.shared.isAuthorized()) {
            UserDefaults.standard.set(true, forKey: askedKey)
            guard await ReminderScheduler.shared.requestAuthorization() else { return }
        }
        let what = post.firstLine.map { String($0.prefix(80)) } ?? "\(post.byline)'s \(post.kind.rawValue)"
        add(id: reminderID(post.id), title: "You asked to be reminded", body: what, at: date)
    }

    static func cancelReminder(for postID: String) {
        center.removePendingNotificationRequests(withIdentifiers: [reminderID(postID)])
    }

    private static func reminderID(_ postID: String) -> String { "hd.save.\(postID)" }

    private static func add(id: String, title: String, body: String, at date: Date) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        content.userInfo = ["today": true]
        let comps = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        center.add(UNNotificationRequest(identifier: id, content: content,
                                         trigger: UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)))
    }
}

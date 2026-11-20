import EventKit
import Foundation

/// One item to add to a Reminders list.
struct ReminderDraft: Hashable, Sendable {
    var title: String
    var notes: String?
    var url: URL?
    var due: Date?
}

enum RemindersAccess: Equatable, Sendable {
    case notDetermined, granted, denied
}

/// Writes to Reminders. The app uses EventKit; tests use `InMemoryRemindersWriter`.
protocol RemindersWriter: Sendable {
    func access() async -> RemindersAccess
    /// Asks once (the system shows its alert the first time only). True when granted.
    func requestAccess() async -> Bool
    /// Adds to the list named `list`, making the list if it's missing. Items whose
    /// title is already open in that list are skipped. Returns how many were added.
    func add(_ drafts: [ReminderDraft], to list: String) async throws -> Int
}

enum RemindersError: LocalizedError {
    case noAccount
    var errorDescription: String? { "Couldn't find a Reminders account to add the list to." }
}

/// EventKit. `requestFullAccessToReminders` is asked at the first "Add to …" tap,
/// never at launch. Everything runs off the main actor; `EKEventStore` is
/// thread-safe for these calls, and no EventKit object leaves this type.
final class EventKitRemindersWriter: RemindersWriter, @unchecked Sendable {
    private let store = EKEventStore()

    func access() async -> RemindersAccess {
        switch EKEventStore.authorizationStatus(for: .reminder) {
        case .fullAccess: .granted
        case .notDetermined: .notDetermined
        default: .denied
        }
    }

    func requestAccess() async -> Bool {
        (try? await store.requestFullAccessToReminders()) ?? false
    }

    func add(_ drafts: [ReminderDraft], to list: String) async throws -> Int {
        guard !drafts.isEmpty else { return 0 }
        let calendar = try reminderList(named: list)
        let existing = await openTitles(in: calendar)
        var added = 0
        var seen = existing
        for draft in drafts where seen.insert(Self.key(draft.title)).inserted {
            let reminder = EKReminder(eventStore: store)
            reminder.calendar = calendar
            reminder.title = draft.title
            reminder.notes = draft.notes
            reminder.url = draft.url
            if let due = draft.due {
                reminder.dueDateComponents = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: due)
                reminder.addAlarm(EKAlarm(absoluteDate: due))
            }
            try store.save(reminder, commit: false)
            added += 1
        }
        if added > 0 { try store.commit() }
        return added
    }

    /// The list by name, else a new one in the default Reminders account.
    private func reminderList(named name: String) throws -> EKCalendar {
        if let found = store.calendars(for: .reminder).first(where: { $0.title == name }) { return found }
        let calendar = EKCalendar(for: .reminder, eventStore: store)
        calendar.title = name
        guard let source = store.defaultCalendarForNewReminders()?.source
                ?? store.sources.first(where: { $0.sourceType == .calDAV || $0.sourceType == .local }) else {
            throw RemindersError.noAccount
        }
        calendar.source = source
        try store.saveCalendar(calendar, commit: true)
        return calendar
    }

    private func openTitles(in calendar: EKCalendar) async -> Set<String> {
        let predicate = store.predicateForIncompleteReminders(withDueDateStarting: nil, ending: nil, calendars: [calendar])
        return await withCheckedContinuation { continuation in
            store.fetchReminders(matching: predicate) { reminders in
                continuation.resume(returning: Set((reminders ?? []).compactMap { $0.title.map(Self.key) }))
            }
        }
    }

    static func key(_ title: String) -> String { title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
}

/// Reminders in memory, for tests and previews. Same rules as EventKit's: lists
/// are made on first use, and an open item with the same title isn't added twice.
actor InMemoryRemindersWriter: RemindersWriter {
    private(set) var lists: [String: [ReminderDraft]] = [:]
    private var status: RemindersAccess
    private let grantOnRequest: Bool
    private(set) var requests = 0

    init(access: RemindersAccess = .granted, grantOnRequest: Bool = true) {
        status = access
        self.grantOnRequest = grantOnRequest
    }

    func access() async -> RemindersAccess { status }

    func requestAccess() async -> Bool {
        requests += 1
        if status == .notDetermined { status = grantOnRequest ? .granted : .denied }
        return status == .granted
    }

    func add(_ drafts: [ReminderDraft], to list: String) async throws -> Int {
        var items = lists[list] ?? []
        var seen = Set(items.map { EventKitRemindersWriter.key($0.title) })
        var added = 0
        for draft in drafts where seen.insert(EventKitRemindersWriter.key(draft.title)).inserted {
            items.append(draft)
            added += 1
        }
        lists[list] = items
        return added
    }

    func items(in list: String) -> [ReminderDraft] { lists[list] ?? [] }
}

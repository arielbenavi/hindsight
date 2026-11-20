import Foundation
import Observation

/// What the user did with a save. Every save starts `new`.
enum SaveStatus: String, Codable, Sendable, CaseIterable {
    case new, done, letGo
}

/// The user's own layer on one save: kept apart from the contract file (sorting
/// rewrites it) and from `SavedPost` (the imports). Missing = all defaults.
struct SaveState: Codable, Hashable, Sendable {
    var status: SaveStatus = .new
    var note: String?
    /// A reminder the user set ("Tonight", "Weekend"). In the future = snoozed.
    var remindAt: Date?
    /// How many times Today served it.
    var shownInToday = 0
    var lastOpened: Date?
    /// How many times it was opened (Keep close: "you've come back to this N times").
    var opens = 0
    /// Where it was sent and when: a Reminders list name ("Groceries") or "Calendar"
    /// (`Destination.sentKey`). Shows "In Groceries" instead of the button, and makes
    /// auto-route and "Send all" add it once. Optional so older files still decode.
    var sentTo: [String: Date]?
    /// Last added to Reminders or Calendar: it lives there now, so Today leaves it
    /// alone for `SaveState.routedQuietDays`. Its status stays `new`.
    var routedAt: Date?

    static let initial = SaveState()
    static let routedQuietDays = 30

    var hasNote: Bool { note?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false }

    func sentDate(_ key: String) -> Date? { sentTo?[key] }

    /// Sent to Reminders/Calendar within the last 30 days.
    func isRouted(now: Date) -> Bool {
        guard let routedAt else { return false }
        return now.timeIntervalSince(routedAt) < Double(Self.routedQuietDays) * 86_400
    }

    /// Snoozed: a reminder still ahead.
    func isSnoozed(now: Date) -> Bool { remindAt.map { $0 > now } ?? false }
    func isDue(now: Date) -> Bool { remindAt.map { $0 <= now } ?? false }
}

/// Every save's `SaveState`, by post id, in `save-states.json` under the dataset's
/// folder (like `PracticeStore`). Only non-default states are written.
@Observable
@MainActor
final class SaveStateStore {
    private(set) var states: [String: SaveState] = [:]
    @ObservationIgnored private let file: JSONFile<[String: SaveState]>

    /// `directory: nil` keeps it in memory (previews, tests).
    init(directory: URL?) {
        file = JSONFile(name: "save-states", directory: directory)
        states = file.load() ?? [:]
    }

    func state(_ id: String) -> SaveState { states[id] ?? .initial }
    func status(_ id: String) -> SaveStatus { state(id).status }

    func update(_ id: String, _ change: (inout SaveState) -> Void) {
        var value = state(id)
        change(&value)
        states[id] = value == .initial ? nil : value
        file.save(states)
    }

    func setStatus(_ id: String, _ status: SaveStatus) { update(id) { $0.status = status } }

    /// Toggles done ↔ new.
    func toggleDone(_ id: String) { setStatus(id, status(id) == .done ? .new : .done) }

    func setNote(_ id: String, _ note: String) {
        let trimmed = note.trimmingCharacters(in: .whitespacesAndNewlines)
        update(id) { $0.note = trimmed.isEmpty ? nil : trimmed }
    }

    func setReminder(_ id: String, _ date: Date?) { update(id) { $0.remindAt = date } }

    func recordOpen(_ id: String, now: Date = .now) {
        update(id) { $0.lastOpened = now; $0.opens += 1 }
    }

    func recordShownInToday(_ id: String) { update(id) { $0.shownInToday += 1 } }

    /// It went to a Reminders list or Calendar (`key`): remembered, and quiet in Today for 30 days.
    func recordSent(_ id: String, to key: String, now: Date = .now) {
        update(id) { state in
            state.sentTo = (state.sentTo ?? [:]).merging([key: now]) { _, new in new }
            state.routedAt = now
        }
    }

    var letGoIDs: Set<String> { Set(states.filter { $0.value.status == .letGo }.keys) }

    /// Saves to show in default lists (let-go ones are hidden, still searchable).
    func visible(_ posts: [ContractPost]) -> [ContractPost] {
        let gone = letGoIDs
        return gone.isEmpty ? posts : posts.filter { !gone.contains($0.id) }
    }
}

/// The user's choices about topics: each topic's job (by `HomeTopic.id`) and
/// saves moved to another topic (post id → `HomeTopic.id`). `topic-prefs.json`.
@Observable
@MainActor
final class TopicPrefsStore {
    struct Prefs: Codable, Equatable {
        var jobs: [String: TopicJob] = [:]
        var moves: [String: String] = [:]
    }

    private(set) var prefs: Prefs
    @ObservationIgnored private let file: JSONFile<Prefs>

    init(directory: URL?) {
        file = JSONFile(name: "topic-prefs", directory: directory)
        prefs = file.load() ?? Prefs()
    }

    var jobs: [String: TopicJob] { prefs.jobs }
    var moves: [String: String] { prefs.moves }

    func setJob(_ job: TopicJob?, for topicID: String) {
        prefs.jobs[topicID] = job
        file.save(prefs)
    }

    func move(_ postID: String, to topicID: String?) {
        prefs.moves[postID] = topicID
        file.save(prefs)
    }
}

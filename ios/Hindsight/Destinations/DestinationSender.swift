import Foundation

/// Sends saves to Reminders lists and remembers it on each save (`SaveState.sentTo`,
/// `routedAt`), so the same save is never added twice: not by a second tap, not by
/// "Send all", not by auto-route.
@MainActor
final class DestinationSender {
    enum Result: Equatable {
        /// `items` reminders were added for `saves` saves.
        case added(ReminderList, items: Int, saves: Int)
        /// Every save was already in that list.
        case alreadyThere(ReminderList)
        /// No Reminders access (denied now or before): show "Open Settings".
        case denied
        case failed(String)

        /// "Added to Groceries · 7 items".
        var message: String {
            switch self {
            case .added(let list, let items, let saves):
                let what = list == .groceries ? items.counted("item") : saves.counted("save")
                return items == 0 ? "Already in \(list.shortName)" : "Added to \(list.shortName) · \(what)"
            case .alreadyThere(let list): return "Already in \(list.shortName)"
            case .denied: return "hindsight can't add to Reminders. Allow it in Settings."
            case .failed(let error): return "Couldn't add to Reminders: \(error)"
            }
        }

        var succeeded: Bool {
            switch self {
            case .added, .alreadyThere: true
            case .denied, .failed: false
            }
        }
    }

    let writer: RemindersWriter

    init(writer: RemindersWriter) { self.writer = writer }

    /// `askIfNeeded: false` for background work (auto-route): never shows the
    /// permission alert, just does nothing until the user said yes once.
    func send(_ posts: [ContractPost], to list: ReminderList, saves: SaveStateStore,
              now: Date = .now, askIfNeeded: Bool = true) async -> Result {
        var seen: Set<String> = []
        let pending = posts.filter { seen.insert($0.id).inserted && saves.state($0.id).sentDate(list.name) == nil }
        guard !pending.isEmpty else { return .alreadyThere(list) }
        switch await writer.access() {
        case .granted: break
        case .denied: return .denied
        case .notDetermined:
            guard askIfNeeded, await writer.requestAccess() else { return .denied }
        }
        let drafts = pending.flatMap { post in
            let remindAt = saves.state(post.id).remindAt
            return Destinations.drafts(for: post, list: list, due: remindAt.flatMap { $0 > now ? $0 : nil })
        }
        do {
            let added = try await writer.add(drafts, to: list.name)
            for post in pending { saves.recordSent(post.id, to: list.name, now: now) }
            return .added(list, items: added, saves: pending.count)
        } catch {
            return .failed(error.localizedDescription)
        }
    }
}

/// A topic's "Send new saves here automatically": the list, and the saves that were
/// already in the topic when it was turned on (only newer ones are sent).
struct AutoRoute: Codable, Equatable, Sendable {
    var list: ReminderList
    var existing: [String]
}

enum AutoRouting {
    /// Saves in the topic to send now: not there when auto-route was turned on, not
    /// sent to that list before, not let go. Pure.
    static func pending(topicPostIDs: [String], route: AutoRoute, states: [String: SaveState]) -> [String] {
        let skip = Set(route.existing)
        return topicPostIDs.filter { id in
            let state = states[id] ?? .initial
            return !skip.contains(id) && state.sentDate(route.list.name) == nil && state.status != .letGo
        }
    }
}

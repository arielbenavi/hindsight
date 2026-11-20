import Foundation
import Observation

/// Today's set and what the user did with each card, in `today.json` under the
/// dataset's folder. Decisions are `TodayPlan`'s; this applies them to the save states.
@Observable
@MainActor
final class TodayStore {
    private(set) var record: TodayRecord?
    @ObservationIgnored private let file: JSONFile<TodayRecord>

    init(directory: URL?) {
        file = JSONFile(name: "today", directory: directory)
        record = file.load()
    }

    /// Make sure today's set exists (resuming a saved one from today), with any
    /// reminders that came due since. New picks count as shown once.
    func prepare(_ ctx: TodayPlan.Context, saves: SaveStateStore) {
        let before = Set(record?.day == TodayPicker.dayKey(ctx.now, calendar: ctx.calendar) ? record?.picks.map(\.id) ?? [] : [])
        let next = TodayPlan.addingDue(TodayPlan.record(existing: record, ctx), ctx)
        guard next != record else { return }
        served(next.picks.map(\.id).filter { !before.contains($0) }, saves: saves, now: ctx.now)
        set(next)
    }

    /// Answer the current card.
    func answer(_ id: String, _ outcome: TodayOutcome, saves: SaveStateStore, now: Date = .now) {
        guard var next = record else { return }
        next.outcomes[id] = outcome
        switch outcome {
        case .opened: saves.recordOpen(id, now: now)
        case .done: saves.setStatus(id, .done)
        case .letGo: saves.setStatus(id, .letGo)
        }
        set(next)
    }

    /// Serves one extra pick. False when nothing's left.
    @discardableResult
    func oneMore(_ ctx: TodayPlan.Context, saves: SaveStateStore) -> Bool {
        guard let current = record, let next = TodayPlan.oneMore(current, ctx) else { return false }
        served(next.picks.suffix(1).map(\.id), saves: saves, now: ctx.now)
        set(next)
        return true
    }

    /// Dev: forget today's set.
    func reset() {
        record = nil
        file.delete()
    }

    private func served(_ ids: [String], saves: SaveStateStore, now: Date) {
        for id in ids {
            saves.update(id) { state in
                state.shownInToday += 1
                // A reminder that comes up in Today is delivered.
                if state.isDue(now: now) { state.remindAt = nil }
            }
        }
    }

    private func set(_ next: TodayRecord) {
        record = next
        file.save(next)
    }
}

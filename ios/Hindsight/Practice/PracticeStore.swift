import Foundation
import Observation

/// How a card was handled today (it collapses into a done row).
enum Handling: Codable, Hashable, Sendable {
    case tried, reminded(Date), archived, reviewed
}

/// The user's practice state for Learn and Fitness, persisted per dataset
/// (`practice.json`). All decisions live in the pure types; this applies them.
@Observable
@MainActor
final class PracticeStore {
    private(set) var screens: [LegoScreen: ScreenPractice] = [:]
    /// Today's handled cards, per screen (reset each day with the picks).
    private(set) var handled: [LegoScreen: [String: Handling]] = [:]
    /// Set when a notification is tapped: open that save's card.
    var deepLink: (screen: LegoScreen, id: String)?

    private let file: JSONFile<Saved>
    private struct Saved: Codable {
        var screens: [String: ScreenPractice]
        var handled: [String: [String: Handling]]
    }

    init(directory: URL?) {
        file = JSONFile(name: "practice", directory: directory)
        if let saved = file.load() {
            for (key, value) in saved.screens { if let s = LegoScreen(rawValue: key) { screens[s] = value } }
            for (key, value) in saved.handled { if let s = LegoScreen(rawValue: key) { handled[s] = value } }
        }
        for s in [LegoScreen.learn, .fitness] where screens[s] == nil {
            var fresh = ScreenPractice()
            fresh.slot = .off
            screens[s] = fresh
        }
    }

    func screen(_ s: LegoScreen) -> ScreenPractice { screens[s] ?? ScreenPractice() }
    func state(_ s: LegoScreen, _ id: String) -> PracticeState { screen(s).state(id) }

    private func mutate(_ s: LegoScreen, _ change: (inout ScreenPractice) -> Void) {
        var value = screen(s)
        change(&value)
        screens[s] = value
        save()
    }

    private func mutateState(_ s: LegoScreen, _ id: String, _ change: (inout PracticeState) -> Void) {
        mutate(s) { screen in
            var state = screen.state(id)
            change(&state)
            screen.states[id] = state
        }
    }

    func save() {
        file.save(Saved(
            screens: Dictionary(uniqueKeysWithValues: screens.map { ($0.key.rawValue, $0.value) }),
            handled: Dictionary(uniqueKeysWithValues: handled.map { ($0.key.rawValue, $0.value) })
        ))
    }

    // MARK: - Today

    /// Make sure today's queue exists (stable all day). Call on appear.
    func prepareToday(_ s: LegoScreen, candidates: [PracticeCandidate], config: PracticeConfig, now: Date = .now,
                      calendar: Calendar = .current) {
        let day = TodayPicker.dayKey(now, calendar: calendar)
        guard screen(s).pickDay != day else { return }
        let current = screen(s)
        let topics = Dictionary(uniqueKeysWithValues: candidates.map { ($0.id, $0.topicKey) })
        let lastTopic = current.pickQueue.first.flatMap { topics[$0] } ?? current.lastPickTopic
        let regularsToday = Set(current.regulars.values.filter { $0.fires(on: now, calendar: calendar) }.map(\.routineID))
        let input = TodayPicker.Input(candidates: candidates, states: current.states, config: config,
                                      boostedTopicKeys: Set(current.pickedTopicKeys), regularsToday: regularsToday,
                                      lastTopic: lastTopic, now: now, calendar: calendar)
        var rng = SeededRandom("\(day)|\(s.rawValue)")
        let queue = TodayPicker.queue(input, rng: &rng)
        handled[s] = [:]
        mutate(s) { screen in
            screen.pickDay = day
            screen.pickQueue = queue
            screen.shownCount = min(1, queue.count)
            screen.lastPickTopic = lastTopic
            if let first = queue.first {
                var state = screen.state(first)
                state.lastShownAt = now
                screen.states[first] = state
            }
        }
    }

    /// The cards to show today, in order: Today's 1, then any "One more?".
    func todayCards(_ s: LegoScreen) -> [String] {
        let screen = screen(s)
        return Array(screen.pickQueue.prefix(screen.shownCount))
    }

    func handling(_ s: LegoScreen, _ id: String) -> Handling? { handled[s]?[id] }

    /// Every shown card is handled: "Done for today."
    func isDoneForToday(_ s: LegoScreen) -> Bool {
        let cards = todayCards(s)
        return !cards.isEmpty && cards.allSatisfy { handled[s]?[$0] != nil }
    }

    /// "One more?" / "Pick another": the next due item, or a fresh draw.
    @discardableResult
    func oneMore(_ s: LegoScreen, candidates: [PracticeCandidate], config: PracticeConfig, now: Date = .now) -> String? {
        var current = screen(s)
        if current.shownCount < current.pickQueue.count {
            current.shownCount += 1
        } else {
            let input = TodayPicker.Input(candidates: candidates, states: current.states, config: config,
                                          boostedTopicKeys: Set(current.pickedTopicKeys), now: now)
            var rng = SeededRandom("\(current.pickDay ?? "")|\(s.rawValue)|\(current.pickQueue.count)")
            guard let next = TodayPicker.draw(input, excluding: Set(current.pickQueue), rng: &rng) else { return nil }
            current.pickQueue.append(next)
            current.shownCount = current.pickQueue.count
        }
        let id = current.pickQueue[current.shownCount - 1]
        var state = current.state(id)
        state.lastShownAt = now
        current.states[id] = state
        screens[s] = current
        save()
        return id
    }

    /// True when the item is a due spaced review ("Still got it?").
    func isReview(_ s: LegoScreen, _ id: String, now: Date = .now) -> Bool {
        let st = state(s, id)
        guard s == .learn, st.status == .tried, let next = st.nextReviewAt else { return false }
        return next <= Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: now))!
    }

    // MARK: - Actions

    /// "Tried it" / "Did it". Learn schedules the first review in 3 days.
    func tried(_ s: LegoScreen, _ id: String, now: Date = .now) {
        mutateState(s, id) { state in
            state.triedAt.append(now)
            state.remindAt = nil
            if s == .learn {
                if state.status != .tried { state.reviewStep = 0 }
                state.status = .tried
                SpacedReview.advance(&state, now: now)
            } else {
                state.status = .tried
            }
        }
        setHandled(s, id, .tried)
    }

    /// "Still got it?" → Yep: counts as a try; next review further out.
    func reviewYep(_ s: LegoScreen, _ id: String, now: Date = .now) {
        mutateState(s, id) { state in
            state.triedAt.append(now)
            SpacedReview.advance(&state, now: now)
        }
        setHandled(s, id, .reviewed)
    }

    /// "Still got it?" → Try again: counts as a try; review ladder restarts.
    func reviewTryAgain(_ s: LegoScreen, _ id: String, now: Date = .now) {
        mutateState(s, id) { state in
            state.triedAt.append(now)
            SpacedReview.reset(&state, now: now)
        }
        setHandled(s, id, .tried)
    }

    /// "Not today" → When? Sets a reminder about this save.
    func remind(_ s: LegoScreen, _ id: String, at date: Date) {
        mutateState(s, id) { $0.remindAt = date }
        setHandled(s, id, .reminded(date))
    }

    /// "Not for me": archived, never picked again. Returns the old state for undo.
    @discardableResult
    func archive(_ s: LegoScreen, _ id: String) -> PracticeState {
        let old = state(s, id)
        mutateState(s, id) { $0.status = .archived; $0.remindAt = nil }
        setHandled(s, id, .archived)
        return old
    }

    /// Undo / "Bring back".
    func restore(_ s: LegoScreen, _ id: String, to old: PracticeState) {
        mutateState(s, id) { $0 = old }
        handled[s]?[id] = nil
        save()
    }

    func unarchive(_ s: LegoScreen, _ id: String) {
        mutateState(s, id) { $0.status = $0.triedAt.isEmpty ? .new : .tried }
    }

    private func setHandled(_ s: LegoScreen, _ id: String, _ h: Handling) {
        guard todayCards(s).contains(id) else { return }
        handled[s, default: [:]][id] = h
        save()
    }

    // MARK: - Setup and settings

    func markWantToTry(_ s: LegoScreen, _ id: String) {
        mutateState(s, id) { if $0.status == .new { $0.status = .wantToTry } }
    }

    func finishSetup(_ s: LegoScreen, goal: Int, slot: ReminderSlot, pickedTopicKeys: [String] = [], now: Date = .now) {
        mutate(s) { screen in
            screen.weeklyGoal = goal
            screen.slot = slot
            screen.pickedTopicKeys = pickedTopicKeys
            screen.setupDone = true
            screen.setupDoneAt = now
            // new picks with the setup's preferences
            screen.pickDay = nil
        }
    }

    func skipSetup(_ s: LegoScreen) {
        mutate(s) { $0.setupDone = true }
    }

    func setGoal(_ s: LegoScreen, _ goal: Int) { mutate(s) { $0.weeklyGoal = goal } }
    func setSlot(_ s: LegoScreen, _ slot: ReminderSlot) { mutate(s) { $0.slot = slot } }

    func setRegular(_ schedule: RegularSchedule) {
        mutate(.fitness) { $0.regulars[schedule.routineID] = schedule }
    }

    func removeRegular(_ routineID: String) {
        mutate(.fitness) { $0.regulars[routineID] = nil }
    }

    func markOpened(_ s: LegoScreen, now: Date = .now) -> WeeklyProgress.FreshStart? {
        let fresh = WeeklyProgress.freshStart(now: now, lastOpenedAt: screen(s).lastOpenedAt)
        mutate(s) { $0.lastOpenedAt = now }
        return fresh
    }

    func progress(_ s: LegoScreen, now: Date = .now) -> WeeklyProgress {
        let screen = screen(s)
        return WeeklyProgress.make(states: Array(screen.states.values), goal: screen.weeklyGoal,
                                   setupDoneAt: screen.setupDoneAt, now: now)
    }

    /// Last time any practice screen was opened (for the reminder plan).
    var lastOpenedAt: Date? { screens.values.compactMap(\.lastOpenedAt).max() }
}

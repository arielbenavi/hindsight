import Foundation

/// Picking Today's 1 (learn.md, fitness.md). Pure: the date, calendar and random
/// source are injected, so the same inputs give the same pick all day.
enum TodayPicker {
    struct Input {
        var candidates: [PracticeCandidate]
        var states: [String: PracticeState]
        var config: PracticeConfig
        /// Fitness: body areas picked in setup (× 2).
        var boostedTopicKeys: Set<String> = []
        /// Fitness: routines with a Regular firing today (due).
        var regularsToday: Set<String> = []
        /// Yesterday's first pick's topic (rotation).
        var lastTopic: String?
        var now: Date
        var calendar: Calendar = .current
    }

    /// The day's queue: due items first, then one weighted-random pick.
    /// The first element is Today's 1; the rest back "One more?".
    static func queue(_ input: Input, rng: inout some RandomNumberGenerator) -> [String] {
        let due = dueItems(input)
        var queue = due
        if let extra = draw(input, excluding: Set(due), rng: &rng) { queue.append(extra) }
        return queue
    }

    /// Due today: "When?" reminders for today, then spaced reviews (Learn) or
    /// today's Regulars (Fitness).
    static func dueItems(_ input: Input) -> [String] {
        let cal = input.calendar
        let endOfToday = cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: input.now))!
        let ids = Set(input.candidates.map(\.id))
        let reminders = input.states
            .filter { ids.contains($0.key) && $0.value.status != .archived }
            .compactMap { id, s in s.remindAt.flatMap { $0 < endOfToday ? (id, $0) : nil } }
            .sorted { ($0.1, $0.0) < ($1.1, $1.0) }
            .map(\.0)
        var due = reminders
        if input.config.repeatsAfterDone {
            let regulars = input.candidates.map(\.id).filter { input.regularsToday.contains($0) && !doneToday($0, input) }
            due += regulars.filter { !due.contains($0) }
        } else {
            let reviews = input.states
                .filter { ids.contains($0.key) && $0.value.status == .tried }
                .compactMap { id, s in s.nextReviewAt.flatMap { $0 < endOfToday ? (id, $0) : nil } }
                .sorted { ($0.1, $0.0) < ($1.1, $1.0) }
                .map(\.0)
            due += reviews.filter { !due.contains($0) }
        }
        return due
    }

    /// One weighted-random pick from the pool.
    static func draw(_ input: Input, excluding: Set<String>, rng: inout some RandomNumberGenerator) -> String? {
        let pool = weightedPool(input, excluding: excluding)
        guard !pool.isEmpty else { return nil }
        // Rotate topics: avoid yesterday's topic when another topic is available.
        let rotated: [(PracticeCandidate, Double)]
        if let last = input.lastTopic, pool.contains(where: { $0.0.topicKey != last }) {
            rotated = pool.filter { $0.0.topicKey != last }
        } else {
            rotated = pool
        }
        let total = rotated.reduce(0) { $0 + $1.1 }
        var target = Double.random(in: 0..<total, using: &rng)
        for (candidate, weight) in rotated {
            target -= weight
            if target < 0 { return candidate.id }
        }
        return rotated.last?.0.id
    }

    static func weightedPool(_ input: Input, excluding: Set<String>) -> [(PracticeCandidate, Double)] {
        let cal = input.calendar
        let recentCutoff = cal.date(byAdding: .day, value: -input.config.recentWindowDays, to: input.now)!
        let triesByTopic = Dictionary(grouping: input.candidates, by: \.topicKey)
            .mapValues { $0.reduce(0) { $0 + (input.states[$1.id]?.triedAt.count ?? 0) } }
        return input.candidates.compactMap { c in
            guard c.isPickable, !excluding.contains(c.id) else { return nil }
            let s = input.states[c.id] ?? PracticeState()
            if s.status == .archived { return nil }
            if !input.config.repeatsAfterDone, s.status == .tried { return nil }
            var weight = 1.0
            if s.status == .wantToTry || input.boostedTopicKeys.contains(c.topicKey) { weight *= 2 }
            if input.config.repeatsAfterDone {
                // flat boost, so one well-loved routine can't take over
                if !s.triedAt.isEmpty { weight *= input.config.doneBeforeBoost }
            } else {
                weight *= 1 + Double(triesByTopic[c.topicKey] ?? 0) / 5
            }
            if let shown = s.lastShownAt, shown > recentCutoff { weight *= input.config.recentPenalty }
            return (c, weight)
        }
    }

    private static func doneToday(_ id: String, _ input: Input) -> Bool {
        input.states[id]?.triedAt.contains { input.calendar.isDate($0, inSameDayAs: input.now) } ?? false
    }

    /// "2026-10-01" in the given calendar: the key that keeps picks stable all day.
    static func dayKey(_ date: Date, calendar: Calendar = .current) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year!, c.month!, c.day!)
    }
}

/// Deterministic RNG (SplitMix64) seeded from a string, e.g. the day key.
struct SeededRandom: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) { state = seed }

    init(_ string: String) {
        var hash: UInt64 = 0xcbf29ce484222325
        for byte in string.utf8 { hash = (hash ^ UInt64(byte)) &* 0x100000001b3 }
        state = hash
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
}

/// Spaced review (learn.md): a tried tip comes back at 3, 10 and 30 days.
enum SpacedReview {
    static let intervals = [3, 10, 30]

    /// After "Tried it" (step 0) or "Yep" on a review: the next step and date.
    static func advance(_ state: inout PracticeState, now: Date, calendar: Calendar = .current) {
        if state.reviewStep < intervals.count {
            state.nextReviewAt = calendar.date(byAdding: .day, value: intervals[state.reviewStep], to: calendar.startOfDay(for: now))
            state.reviewStep += 1
        } else {
            state.nextReviewAt = nil
        }
    }

    /// "Try again": back to the start of the ladder.
    static func reset(_ state: inout PracticeState, now: Date, calendar: Calendar = .current) {
        state.reviewStep = 0
        advance(&state, now: now, calendar: calendar)
    }
}

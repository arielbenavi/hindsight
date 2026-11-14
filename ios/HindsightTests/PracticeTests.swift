import Foundation
import Testing
@testable import Hindsight

private var cal: Calendar {
    var c = Calendar(identifier: .gregorian)
    c.timeZone = TimeZone(identifier: "America/New_York")!
    return c
}

private func date(_ s: String, _ hour: Int = 9) -> Date {
    let p = s.split(separator: "-").map { Int($0)! }
    return cal.date(from: DateComponents(year: p[0], month: p[1], day: p[2], hour: hour))!
}

private func candidates(_ n: Int, topics: Int = 3, pickable: Bool = true) -> [PracticeCandidate] {
    (0..<n).map { PracticeCandidate(id: "t\($0)", topicKey: "topic\($0 % topics)", isPickable: pickable) }
}

@MainActor
struct PickerTests {
    // 2026-10-01 is a Thursday.
    let thursday = date("2026-10-01")

    func input(_ c: [PracticeCandidate], _ states: [String: PracticeState] = [:], config: PracticeConfig = .learn,
               now: Date? = nil, lastTopic: String? = nil, regulars: Set<String> = []) -> TodayPicker.Input {
        TodayPicker.Input(candidates: c, states: states, config: config, regularsToday: regulars,
                          lastTopic: lastTopic, now: now ?? thursday, calendar: cal)
    }

    @Test func neverPicksTriedArchivedOrThin() {
        var c = candidates(4)
        c.append(PracticeCandidate(id: "thin", topicKey: "topic0", isPickable: false))
        let states = ["t0": PracticeState(status: .tried), "t1": PracticeState(status: .archived)]
        for seed in 0..<200 {
            var rng = SeededRandom(seed: UInt64(seed))
            let pick = TodayPicker.draw(input(c, states), excluding: [], rng: &rng)
            #expect(pick == "t2" || pick == "t3")
        }
    }

    @Test func dueRemindersThenReviewsComeFirst() {
        let c = candidates(10)
        let states = [
            "t5": PracticeState(status: .tried, reviewStep: 1, nextReviewAt: date("2026-09-30")),
            "t7": PracticeState(remindAt: date("2026-10-01", 19)),
        ]
        var rng = SeededRandom(seed: 1)
        let q = TodayPicker.queue(input(c, states), rng: &rng)
        #expect(Array(q.prefix(2)) == ["t7", "t5"])
        #expect(q.count == 3)
    }

    @Test func samePickAllDay() {
        let c = candidates(30)
        var a = SeededRandom("2026-10-01|learn"), b = SeededRandom("2026-10-01|learn")
        let morning = TodayPicker.queue(input(c, now: date("2026-10-01", 7)), rng: &a)
        let evening = TodayPicker.queue(input(c, now: date("2026-10-01", 22)), rng: &b)
        #expect(morning == evening)
    }

    @Test func recentlyShownIsPenalized() {
        let c = candidates(2, topics: 1)
        let states = ["t0": PracticeState(lastShownAt: date("2026-09-25"))]
        let pool = TodayPicker.weightedPool(input(c, states), excluding: [])
        let w = Dictionary(uniqueKeysWithValues: pool.map { ($0.0.id, $0.1) })
        #expect(w["t0"]! < w["t1"]!)
        let old = ["t0": PracticeState(lastShownAt: date("2026-09-01"))]
        let pool2 = Dictionary(uniqueKeysWithValues: TodayPicker.weightedPool(input(c, old), excluding: []).map { ($0.0.id, $0.1) })
        #expect(pool2["t0"] == pool2["t1"])
    }

    @Test func topicsRotateAcrossDays() {
        let c = candidates(20, topics: 2)
        for seed in 0..<100 {
            var rng = SeededRandom(seed: UInt64(seed))
            let pick = TodayPicker.draw(input(c, lastTopic: "topic0"), excluding: [], rng: &rng)!
            #expect(c.first { $0.id == pick }?.topicKey == "topic1")
        }
    }

    @Test func fitnessAllowsDoneAndThinAndBoostsDone() {
        let c = [PracticeCandidate(id: "a", topicKey: "lower_back", isPickable: true),
                 PracticeCandidate(id: "b", topicKey: "lower_back", isPickable: true)]
        let states = ["a": PracticeState(status: .tried, triedAt: [date("2026-09-20"), date("2026-09-21"), date("2026-09-22")])]
        let pool = Dictionary(uniqueKeysWithValues: TodayPicker.weightedPool(input(c, states, config: .fitness), excluding: []).map { ($0.0.id, $0.1) })
        #expect(pool["a"] == 1.5)   // done before: × 1.5, flat (capped)
        #expect(pool["b"] == 1)
    }

    @Test func fitnessUsesAThreeDayWindowAndRegularsComeFirst() {
        let c = candidates(3, topics: 3)
        let states = ["t0": PracticeState(lastShownAt: date("2026-09-27"))]   // 4 days ago
        let pool = Dictionary(uniqueKeysWithValues: TodayPicker.weightedPool(input(c, states, config: .fitness), excluding: []).map { ($0.0.id, $0.1) })
        #expect(pool["t0"] == 1)
        var rng = SeededRandom(seed: 3)
        #expect(TodayPicker.queue(input(c, config: .fitness, regulars: ["t2"]), rng: &rng).first == "t2")
    }
}

@MainActor
struct WeeklyAndReviewTests {
    @Test func ringResetsMondayAndCountsTheSetupSegment() {
        let tries = [date("2026-09-28"), date("2026-09-30"), date("2026-09-27")]  // Mon, Wed, previous Sun
        let state = PracticeState(status: .tried, triedAt: tries)
        let p = WeeklyProgress.make(states: [state], goal: 3, setupDoneAt: date("2026-09-28"), now: date("2026-10-01"), calendar: cal)
        #expect(p.done == 2)
        #expect(p.filled == 3)
        #expect(p.isComplete)
        let nextWeek = WeeklyProgress.make(states: [state], goal: 3, setupDoneAt: date("2026-09-28"), now: date("2026-10-05"), calendar: cal)
        #expect(nextWeek.filled == 0)
        #expect(nextWeek.fraction == 0)   // just empty, never "broken"
    }

    @Test func spacedReviewLadderAndTryAgain() {
        var s = PracticeState()
        SpacedReview.advance(&s, now: date("2026-10-01"), calendar: cal)
        #expect(s.nextReviewAt == cal.startOfDay(for: date("2026-10-04")))
        SpacedReview.advance(&s, now: date("2026-10-04"), calendar: cal)
        #expect(s.nextReviewAt == cal.startOfDay(for: date("2026-10-14")))
        SpacedReview.advance(&s, now: date("2026-10-14"), calendar: cal)
        #expect(s.nextReviewAt == cal.startOfDay(for: date("2026-11-13")))
        SpacedReview.advance(&s, now: date("2026-11-13"), calendar: cal)
        #expect(s.nextReviewAt == nil)
        SpacedReview.reset(&s, now: date("2026-11-13"), calendar: cal)
        #expect(s.reviewStep == 1)
        #expect(s.nextReviewAt == cal.startOfDay(for: date("2026-11-16")))
    }

    @Test func freshStartOnMondaysAndAfterABreak() {
        #expect(WeeklyProgress.freshStart(now: date("2026-10-05"), lastOpenedAt: date("2026-10-04"), calendar: cal) == .newWeek)
        #expect(WeeklyProgress.freshStart(now: date("2026-10-01"), lastOpenedAt: date("2026-09-20"), calendar: cal) == .afterBreak)
        #expect(WeeklyProgress.freshStart(now: date("2026-10-01"), lastOpenedAt: date("2026-09-30"), calendar: cal) == nil)
    }

    @Test func storeTriedThenReviewComesBackIn3Days() throws {
        let store = PracticeStore(directory: nil)
        let c = candidates(5)
        store.prepareToday(.learn, candidates: c, config: .learn, now: date("2026-10-01"), calendar: cal)
        let first = try #require(store.todayCards(.learn).first)
        store.tried(.learn, first, now: date("2026-10-01"))
        #expect(store.isDoneForToday(.learn))
        #expect(store.progress(.learn, now: date("2026-10-01")).done == 1)
        // 3 days later it's due as a "Still got it?"
        store.prepareToday(.learn, candidates: c, config: .learn, now: date("2026-10-04"), calendar: cal)
        #expect(store.todayCards(.learn).first == first)
        #expect(store.isReview(.learn, first, now: date("2026-10-04")))
    }

    @Test func userStateSurvivesReload() {
        let dir = URL.temporaryDirectory.appending(path: UUID().uuidString)
        let a = PracticeStore(directory: dir)
        a.tried(.learn, "x")
        a.finishSetup(.learn, goal: 5, slot: .morning)
        let b = PracticeStore(directory: dir)
        #expect(b.state(.learn, "x").triedAt.count == 1)
        #expect(b.screen(.learn).weeklyGoal == 5)
        #expect(b.screen(.learn).slot == .morning)
    }
}

@MainActor
struct ReminderPolicyTests {
    let opened = date("2026-10-01", 9)

    func tab(_ s: LegoScreen, _ slot: ReminderSlot = .evening, regular: @escaping @Sendable (Date) -> Bool = { _ in false }) -> ReminderPolicy.Tab {
        ReminderPolicy.Tab(screen: s, slot: slot, lastTemplate: nil, templateCount: 3, hasRegular: regular)
    }

    @Test func atMostOneADayAndBacksOffThenStops() {
        let plan = ReminderPolicy.plan(tabs: [tab(.learn)], lastOpenedAt: opened, now: opened, todayHandled: false, calendar: cal)
        let days = plan.map { cal.dateComponents([.day], from: cal.startOfDay(for: opened), to: cal.startOfDay(for: $0.date)).day! }
        #expect(days == [0, 1, 2, 4, 6, 7])
        #expect(Set(days).count == days.count)
        #expect(plan.last?.isFinal == true)
        #expect(plan.dropLast().allSatisfy { !$0.isFinal })
    }

    @Test func neverTheSameTemplateTwiceInARow() {
        let plan = ReminderPolicy.plan(tabs: [tab(.learn)], lastOpenedAt: opened, now: opened, todayHandled: false, calendar: cal)
        let templates = plan.filter { !$0.isFinal }.map(\.template)
        for (a, b) in zip(templates, templates.dropFirst()) { #expect(a != b) }
    }

    @Test func oneNudgeADayAcrossTabsAlternating() {
        let plan = ReminderPolicy.plan(tabs: [tab(.learn), tab(.fitness, .morning)], lastOpenedAt: opened, now: opened,
                                       todayHandled: true, calendar: cal)
        let perDay = Dictionary(grouping: plan) { cal.startOfDay(for: $0.date) }
        #expect(perDay.values.allSatisfy { $0.count == 1 })
        let screens = plan.filter { !$0.isFinal }.map(\.screen)
        for (a, b) in zip(screens, screens.dropFirst()) { #expect(a != b) }
    }

    @Test func noFitnessNudgeOnARegularDay() {
        let regularEveryDay: @Sendable (Date) -> Bool = { _ in true }
        let plan = ReminderPolicy.plan(tabs: [tab(.learn), tab(.fitness, .morning, regular: regularEveryDay)],
                                       lastOpenedAt: opened, now: opened, todayHandled: true, calendar: cal)
        #expect(plan.allSatisfy { $0.screen == .learn })
    }

    @Test func offMeansNothingAndOpeningRestarts() {
        #expect(ReminderPolicy.plan(tabs: [tab(.learn, .off)], lastOpenedAt: opened, now: opened, todayHandled: false, calendar: cal).isEmpty)
        let later = date("2026-10-20", 9)
        let plan = ReminderPolicy.plan(tabs: [tab(.learn)], lastOpenedAt: later, now: later, todayHandled: false, calendar: cal)
        #expect(plan.first.map { cal.isDate($0.date, inSameDayAs: later) } == true)
    }

    @Test func whenChips() {
        let thu = date("2026-10-01", 9)
        #expect(cal.component(.hour, from: ReminderPolicy.When.tonight.date(from: thu, slot: .morning, calendar: cal)) == 19)
        let lateNight = date("2026-10-01", 22)
        #expect(ReminderPolicy.When.tonight.date(from: lateNight, slot: .evening, calendar: cal) > lateNight)
        let weekend = ReminderPolicy.When.weekend.date(from: thu, slot: .morning, calendar: cal)
        #expect(cal.component(.weekday, from: weekend) == 7)
        #expect(cal.component(.hour, from: weekend) == 8)
    }

    @Test func regularSchedulesAreDescribedAndFire() {
        let r = RegularSchedule(routineID: "x", weekdays: [2, 4, 6], hour: 8, minute: 0)
        #expect(r.fires(on: date("2026-10-05"), calendar: cal))   // Monday
        #expect(!r.fires(on: date("2026-10-06"), calendar: cal))  // Tuesday
    }
}

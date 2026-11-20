import Foundation
import Testing
@testable import Hindsight

/// Save states, Today's set, topic jobs, the Keep close shelf, Do lists and Ask.
@MainActor
struct TodayJobsTests {
    private let calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "America/New_York")!
        return c
    }()

    private func at(_ string: String, hour: Int = 12) -> Date {
        let p = string.split(separator: "-").compactMap { Int($0) }
        return calendar.date(from: DateComponents(year: p[0], month: p[1], day: p[2], hour: hour))!
    }

    private func post(_ id: String, saved: String? = "2025-01-10", caption: String? = nil, author: String = "a",
                      hashtags: [String] = []) -> ContractPost {
        ContractPost(id: id, url: URL(string: "https://www.instagram.com/p/\(id)/")!, author: author, caption: caption ?? id,
                     hashtags: hashtags, savedAt: saved)
    }

    private func tempDir() -> URL {
        FileManager.default.temporaryDirectory.appending(path: "hs-tests-\(UUID().uuidString)", directoryHint: .isDirectory)
    }

    private func ctx(_ posts: [ContractPost], states: [String: SaveState] = [:], jobs: [String: TopicJob] = [:],
                     now: Date) -> TodayPlan.Context {
        TodayPlan.Context(posts: posts, states: states, job: { jobs[$0] }, now: now, calendar: calendar)
    }

    private var olderPosts: [ContractPost] {
        (0..<30).map { post("p\($0)", saved: String(format: "2025-%02d-%02d", 1 + $0 % 9, 1 + $0)) }
    }

    // MARK: - Save state store

    @Test func saveStatesPersistAndReload() {
        let dir = tempDir()
        let store = SaveStateStore(directory: dir)
        store.setStatus("a", .done)
        store.setStatus("b", .letGo)
        store.setNote("c", "  try on Sunday ")
        store.recordOpen("c", now: at("2026-11-20"))
        store.recordOpen("c", now: at("2026-11-21"))
        let reloaded = SaveStateStore(directory: dir)
        #expect(reloaded.status("a") == .done)
        #expect(reloaded.status("b") == .letGo)
        #expect(reloaded.status("zzz") == .new)
        #expect(reloaded.state("c").note == "try on Sunday")
        #expect(reloaded.state("c").opens == 2)
        #expect(reloaded.state("c").lastOpened == at("2026-11-21"))
        #expect(reloaded.letGoIDs == ["b"])
        try? FileManager.default.removeItem(at: dir)
    }

    @Test func saveStateTransitions() {
        let store = SaveStateStore(directory: nil)
        store.toggleDone("a")
        #expect(store.status("a") == .done)
        store.toggleDone("a")
        #expect(store.status("a") == .new)
        #expect(store.states["a"] == nil)            // back to default: not stored
        store.setNote("a", "   ")
        #expect(store.state("a").note == nil)
        store.setStatus("b", .letGo)
        let posts = [post("a"), post("b"), post("c")]
        #expect(store.visible(posts).map(\.id) == ["a", "c"])
        let now = at("2026-11-20")
        store.setReminder("a", now.addingTimeInterval(3600))
        #expect(store.state("a").isSnoozed(now: now))
        #expect(!store.state("a").isDue(now: now))
        #expect(store.state("a").isDue(now: now.addingTimeInterval(7200)))
    }

    @Test func topicPrefsPersist() {
        let dir = tempDir()
        let prefs = TopicPrefsStore(directory: dir)
        prefs.setJob(.keepClose, for: "ai:random")
        prefs.move("p1", to: "ai:cooking")
        let reloaded = TopicPrefsStore(directory: dir)
        #expect(reloaded.jobs == ["ai:random": .keepClose])
        #expect(reloaded.moves == ["p1": "ai:cooking"])
        reloaded.setJob(nil, for: "ai:random")
        #expect(TopicPrefsStore(directory: dir).jobs.isEmpty)
        try? FileManager.default.removeItem(at: dir)
    }

    // MARK: - Today picks

    @Test func eligibilityByStateJobAndReminder() {
        let now = at("2026-11-20")
        let posts = [post("new"), post("done"), post("gone"), post("snoozed"), post("keep"), post("look"), post("know"),
                     post("do"), post("loose")]
        let states: [String: SaveState] = [
            "done": SaveState(status: .done), "gone": SaveState(status: .letGo),
            "snoozed": SaveState(remindAt: now.addingTimeInterval(3600)),
        ]
        let jobs: [String: TopicJob] = ["new": .learn, "keep": .keepClose, "look": .look, "know": .know, "do": .doIt,
                                        "done": .doIt, "snoozed": .go]
        let eligible = TodayPlan.eligible(ctx(posts, states: states, jobs: jobs, now: now)).map(\.id)
        // "loose" has no topic yet: eligible.
        #expect(Set(eligible) == ["new", "do", "loose"])
    }

    @Test func dueRemindersComeFirstButNeverKeepClose() {
        let now = at("2026-11-20", hour: 21)
        let posts = olderPosts + [post("late"), post("early"), post("private"), post("lookRemind")]
        let states: [String: SaveState] = [
            "late": SaveState(remindAt: at("2026-11-20", hour: 20)),
            "early": SaveState(remindAt: at("2026-11-19", hour: 20)),
            "private": SaveState(remindAt: at("2026-11-19", hour: 8)),
            "lookRemind": SaveState(remindAt: at("2026-11-21", hour: 8)),  // not yet
        ]
        let jobs: [String: TopicJob] = ["private": .keepClose, "lookRemind": .look]
        let picks = TodayPlan.picks(ctx(posts, states: states, jobs: jobs, now: now))
        #expect(picks.map(\.id).prefix(2) == ["early", "late"])
        #expect(picks[0].reason == "You asked to be reminded")
        #expect(picks.count == 3)
        #expect(!picks.contains { $0.id == "private" || $0.id == "lookRemind" })
    }

    @Test func picksAreDeterministicAndRespectTheDay() {
        let posts = olderPosts
        let a = TodayPlan.picks(ctx(posts, now: at("2026-11-20", hour: 8)))
        let b = TodayPlan.picks(ctx(posts.reversed(), now: at("2026-11-20", hour: 22)))
        #expect(a == b)
        #expect(a.count == 3)
        let days = ["2026-11-20", "2026-11-21", "2026-11-22", "2026-11-23"]
        #expect(Set(days.map { TodayPlan.picks(ctx(posts, now: at($0))).map(\.id) }).count > 1)
    }

    @Test func resumeSameDayNewDayResets() {
        let posts = olderPosts
        var record = TodayPlan.record(existing: nil, ctx(posts, now: at("2026-11-20", hour: 9)))
        record.outcomes[record.picks[0].id] = .opened
        #expect(record.position == 1)
        // Later the same day, even with states changed: the same set, same place ("2 of 3").
        let states = [record.picks[1].id: SaveState(status: .letGo)]
        let resumed = TodayPlan.record(existing: record, ctx(posts, states: states, now: at("2026-11-20", hour: 23)))
        #expect(resumed == record)
        #expect(resumed.position == 1)
        let tomorrow = TodayPlan.record(existing: record, ctx(posts, now: at("2026-11-21", hour: 7)))
        #expect(tomorrow.day == "2026-11-21")
        #expect(tomorrow.outcomes.isEmpty)
        #expect(tomorrow.position == 0)
    }

    @Test func anUnansweredSetIsRemadeWhenSortingMakesAPickIneligible() {
        let posts = olderPosts
        let morning = TodayPlan.record(existing: nil, ctx(posts, now: at("2026-11-20", hour: 8)))
        // Sorting finished: the first pick's topic turned out to be Know.
        let jobs = [morning.picks[0].id: TopicJob.know]
        let later = TodayPlan.record(existing: morning, ctx(posts, jobs: jobs, now: at("2026-11-20", hour: 9)))
        #expect(!later.picks.map(\.id).contains(morning.picks[0].id))
        #expect(later.picks.count == 3)
        // Nothing changed: the same set.
        #expect(TodayPlan.record(existing: later, ctx(posts, jobs: jobs, now: at("2026-11-20", hour: 10))) == later)
        // Once answered, it stays even if a pick stops being eligible.
        var answered = later
        answered.outcomes[later.picks[0].id] = .opened
        let jobs2 = jobs.merging([later.picks[1].id: .look]) { a, _ in a }
        #expect(TodayPlan.record(existing: answered, ctx(posts, jobs: jobs2, now: at("2026-11-20", hour: 11))) == answered)
    }

    /// The owner's phone: Today opened before the pull/sort delivered anything, the
    /// empty set was saved, and "Nothing for today" stuck with 1,415 saves in.
    @Test func anEmptySetIsRemadeOnceSavesArriveOrGetSorted() throws {
        let dir = tempDir()
        let saves = SaveStateStore(directory: dir)
        let store = TodayStore(directory: dir)
        // 1. No saves yet (or none eligible: every save in a Know topic for now).
        let early = olderPosts
        let allKnow = Dictionary(uniqueKeysWithValues: early.map { ($0.id, TopicJob.know) })
        store.prepare(ctx(early, jobs: allKnow, now: at("2026-11-20", hour: 9)), saves: saves)
        #expect(store.record?.picks.isEmpty == true)
        // 2. Sorting moved them into real topics: the next prepare picks three.
        store.prepare(ctx(early, now: at("2026-11-20", hour: 9)), saves: saves)
        #expect(store.record?.picks.count == 3)
        // Same for a set made with no saves at all, then the pull lands.
        let fresh = TodayPlan.record(existing: nil, ctx([], now: at("2026-11-20", hour: 9)))
        #expect(fresh.picks.isEmpty)
        #expect(TodayPlan.record(existing: fresh, ctx(early, now: at("2026-11-20", hour: 10))).picks.count == 3)
        // And it survives a relaunch: the saved empty file doesn't win either.
        let relaunched = TodayStore(directory: dir)
        #expect(relaunched.record?.picks.count == 3)
        try? FileManager.default.removeItem(at: dir)
    }

    @Test func emptyTodaySaysWhyHonestly() {
        #expect(TodayPlan.empty(hasSaves: false, isSorting: true) == .noSaves)
        #expect(TodayPlan.empty(hasSaves: true, isSorting: true) == .sorting)
        #expect(TodayPlan.empty(hasSaves: true, isSorting: false) == .allHandled)
    }

    @Test func savesSentToRemindersStayOutOfTodayFor30Days() {
        let now = at("2026-11-20")
        let posts = [post("sent"), post("old-sent"), post("fresh")]
        let states: [String: SaveState] = [
            "sent": SaveState(routedAt: now.addingTimeInterval(-86_400 * 29)),
            "old-sent": SaveState(routedAt: now.addingTimeInterval(-86_400 * 31)),
        ]
        #expect(Set(TodayPlan.eligible(ctx(posts, states: states, now: now)).map(\.id)) == ["old-sent", "fresh"])
        // Recording a send marks both: where, and the 30 quiet days. Status stays new.
        let store = SaveStateStore(directory: nil)
        store.recordSent("fresh", to: "Groceries", now: now)
        #expect(store.state("fresh").sentDate("Groceries") == now)
        #expect(store.state("fresh").isRouted(now: now))
        #expect(store.status("fresh") == .new)
    }

    @Test func oneMoreAddsAnUnseenPick() throws {
        let posts = Array(olderPosts.prefix(4))
        var record = TodayPlan.record(existing: nil, ctx(posts, now: at("2026-11-20")))
        for entry in record.picks { record.outcomes[entry.id] = .done }
        #expect(record.isFinished)
        let states = Dictionary(uniqueKeysWithValues: record.picks.map { ($0.id, SaveState(status: .done)) })
        let more = try #require(TodayPlan.oneMore(record, ctx(posts, states: states, now: at("2026-11-20"))))
        #expect(more.picks.count == 4)
        #expect(!more.isFinished)
        #expect(!record.picks.map(\.id).contains(more.picks[3].id))
        var all = more
        all.outcomes[more.picks[3].id] = .opened
        let doneStates = states.merging([more.picks[3].id: SaveState(status: .done)]) { a, _ in a }
        #expect(TodayPlan.oneMore(all, ctx(posts, states: doneStates, now: at("2026-11-20"))) == nil)
    }

    @Test func dueReminderJoinsTodaysSetAfterTheCurrentCard() {
        let posts = olderPosts + [post("r", saved: "2026-11-19")]
        var record = TodayPlan.record(existing: nil, ctx(posts, now: at("2026-11-20", hour: 9)))
        record.outcomes[record.picks[0].id] = .opened
        let states = ["r": SaveState(remindAt: at("2026-11-20", hour: 20))]
        let evening = TodayPlan.addingDue(record, ctx(posts, states: states, now: at("2026-11-20", hour: 20)))
        #expect(evening.picks.map(\.id)[1] == "r")
        #expect(evening.picks.count == 4)
    }

    @Test func todayStoreResumesAndAppliesOutcomes() throws {
        let dir = tempDir()
        let saves = SaveStateStore(directory: dir)
        let store = TodayStore(directory: dir)
        let posts = olderPosts
        store.prepare(ctx(posts, now: at("2026-11-20", hour: 9)), saves: saves)
        let record = try #require(store.record)
        #expect(record.picks.allSatisfy { saves.state($0.id).shownInToday == 1 })
        store.answer(record.picks[0].id, .letGo, saves: saves)
        store.answer(record.picks[1].id, .opened, saves: saves)
        #expect(saves.status(record.picks[0].id) == .letGo)
        #expect(saves.state(record.picks[1].id).opens == 1)

        // Relaunch the same day: "3 of 3", nothing counted twice.
        let again = TodayStore(directory: dir)
        again.prepare(ctx(posts, states: saves.states, now: at("2026-11-20", hour: 18)), saves: saves)
        #expect(again.record?.position == 2)
        #expect(saves.state(record.picks[2].id).shownInToday == 1)
        try? FileManager.default.removeItem(at: dir)
    }

    @Test func notificationTimes() {
        let morning = at("2026-11-20", hour: 7)   // a Friday
        #expect(TodayNotifications.nextDaily(after: morning, calendar: calendar) == at("2026-11-20", hour: 9))
        #expect(TodayNotifications.nextDaily(after: at("2026-11-20", hour: 10), calendar: calendar) == at("2026-11-21", hour: 9))
        #expect(TodayNotifications.tonight(after: morning, calendar: calendar) == at("2026-11-20", hour: 20))
        #expect(TodayNotifications.tonight(after: at("2026-11-20", hour: 21), calendar: calendar) == at("2026-11-21", hour: 20))
        #expect(TodayNotifications.weekend(after: morning, calendar: calendar) == at("2026-11-21", hour: 10))
        #expect(TodayNotifications.weekend(after: at("2026-11-21", hour: 11), calendar: calendar) == at("2026-11-28", hour: 10))
    }

    @Test func newSinceYesterday() {
        let posts = [post("today", saved: "2026-11-20"), post("yesterday", saved: "2026-11-19"), post("old", saved: "2026-11-17")]
        #expect(TodayPlan.newSinceYesterday(posts, now: at("2026-11-20"), calendar: calendar).map(\.id) == ["today", "yesterday"])
    }

    // MARK: - Jobs

    @Test func defaultJobFromTheView() {
        #expect(TopicJobs.suggested(legoScreen: .map, label: "Mental health") == .go)
        #expect(TopicJobs.suggested(legoScreen: .fitness, label: "Anything") == .doIt)
        #expect(TopicJobs.suggested(legoScreen: .learn, label: "Cooking") == .learn)
    }

    @Test func defaultJobFromTheLabel() {
        let cases: [(String, TopicJob)] = [
            ("Mental health", .keepClose), ("Health & wellness", .keepClose), ("Self-care", .keepClose),
            ("Affirmations", .keepClose), ("Motivation", .keepClose),
            ("Food & recipes", .doIt), ("Things to try", .doIt), ("Fitness & workouts", .doIt),
            ("Design", .look), ("Fashion & style", .look), ("Home & interior", .look), ("Art & photography", .look),
            ("Tattoo inspo", .look),
            ("Travel", .go), ("Restaurants & cafés", .go), ("NYC spots", .go),
            ("Music production", .learn), ("Guitar & instruments", .learn), ("Coding", .learn), ("Productivity", .learn),
            ("Finance & investing", .know), ("Humor & memes", .know), ("News & politics", .know), ("Career", .know),
            ("Notes", .know), ("Posts from X", .know),
            ("בריאות הנפש", .keepClose), ("מתכונים", .doIt), ("למתכונים", .doIt), ("עיצוב", .look), ("טיולים", .go),
            ("גיטרה", .learn),
        ]
        for (label, job) in cases {
            #expect(TopicJobs.suggested(legoScreen: nil, label: label) == job, "\(label)")
        }
        #expect(TopicJobs.suggested(legoScreen: nil, label: "Smart homework") == .know)  // whole words only
    }

    @Test func mentalHealthIsItsOwnFallbackTopic() {
        let therapy = post("t", caption: "What my therapist taught me about anxiety and burnout")
        let hebrew = post("h", caption: "קצת על חרדה ועל שחיקה בעבודה")
        let body = post("b", caption: "Vitamin D and better sleep for your gut health")
        #expect(TopicFallback.pick(therapy)?.slug == "mental-health")
        #expect(TopicFallback.pick(hebrew)?.slug == "mental-health")
        #expect(TopicFallback.pick(body)?.slug == "health-wellness")
        #expect(TopicJobs.suggested(legoScreen: nil, label: TopicFallback.pick(therapy)!.label) == .keepClose)
    }

    @Test func libraryAppliesJobOverridesAndMoves() {
        let posts = (0..<8).map { post("p\($0)", saved: "2026-11-\(String(format: "%02d", 10 - $0))") }
        let ids = posts.map(\.id)
        let data = HindsightData(file: ContractFile(
            contractVersion: 1, generatedAt: nil, user: ContractUser(handle: "me", platforms: ["instagram"]), posts: posts,
            topics: [ContractTopic(id: "food", label: "Food & recipes", legoScreen: nil, postIds: Array(ids[0..<4])),
                     ContractTopic(id: "calm", label: "Random", legoScreen: nil, postIds: Array(ids[4..<8]))],
            items: []))
        var prefs = TopicPrefsStore.Prefs()
        var library = LibraryIndex(data: data, posts: posts, prefs: prefs)
        #expect(library.job(forPost: "p0") == .doIt)
        #expect(library.job(forPost: "p5") == .know)
        prefs.jobs["ai:calm"] = .keepClose
        prefs.moves["p0"] = "ai:calm"
        prefs.moves["p1"] = "ai:gone"   // a topic that's not there: ignored
        library = LibraryIndex(data: data, posts: posts, prefs: prefs)
        #expect(library.job(forPost: "p5") == .keepClose)
        #expect(library.topic("ai:calm")?.postIDs == ["p0", "p4", "p5", "p6", "p7"])
        #expect(library.topic("ai:food")?.postIDs == ["p1", "p2", "p3"])
        #expect(library.job(forPost: "p0") == .keepClose)
        #expect(library.topics(doing: .keepClose).map(\.id) == ["ai:calm"])
    }

    // MARK: - Keep close

    @Test func keepCloseNeedsMatchCaptions() {
        let posts = [
            post("a", caption: "When your thoughts are racing, try this breathing exercise"),
            post("b", caption: "Can't sleep? A bedtime routine that works"),
            post("c", caption: "On burnout and small steps"),
            post("d", caption: "לפני השינה: שלוש נשימות עמוקות"),
            post("e", caption: "A recipe for banana bread"),
        ]
        let loud = KeepClose.picks(posts, need: .loud, seed: "x", round: 0)
        #expect(loud.matched)
        #expect(Set(loud.posts.map(\.id)) == ["a", "d"])
        let sleep = KeepClose.picks(posts, need: .sleep, seed: "x", round: 0)
        #expect(Set(sleep.posts.map(\.id)) == ["b", "d"])
        let low = KeepClose.picks(posts, need: .lowEnergy, seed: "x", round: 0)
        #expect(low.posts.map(\.id) == ["c"])
        // A note counts too.
        let noted = KeepClose.picks(posts, notes: ["e": "this calms me down"], need: .loud, seed: "x", round: 0)
        #expect(noted.posts.map(\.id).contains("e"))
    }

    @Test func justRemindMeIsAStableGentleShuffle() {
        let posts = (0..<10).map { post("p\($0)") }
        let a = KeepClose.picks(posts, need: .remind, seed: "2026-11-20", round: 0)
        let b = KeepClose.picks(posts.reversed(), need: .remind, seed: "2026-11-20", round: 0)
        #expect(a.posts == b.posts)
        #expect(a.posts.count == 3)
        #expect(!a.matched)
        let rounds = (0..<5).map { KeepClose.picks(posts, need: .remind, seed: "2026-11-20", round: $0).posts.map(\.id) }
        #expect(Set(rounds).count > 1)
        // Nothing matches a need: still something, marked as not matched.
        let fallback = KeepClose.picks([post("x", caption: "pasta")], need: .sleep, seed: "s", round: 0)
        #expect(!fallback.matched && fallback.posts.map(\.id) == ["x"])
    }

    @Test func showMeAnotherRotatesMatches() {
        let posts = (0..<5).map { post("p\($0)", caption: "anxiety tip \($0)") }
        let first = KeepClose.picks(posts, need: .loud, seed: "s", round: 0).posts.map(\.id)
        let second = KeepClose.picks(posts, need: .loud, seed: "s", round: 1).posts.map(\.id)
        #expect(first == ["p0", "p1", "p2"])
        #expect(second == ["p3", "p4", "p0"])
    }

    // MARK: - Do lists

    @Test func doListOrderAndProgress() {
        let posts = (0..<5).map { post("p\($0)") }
        let states: [String: SaveState] = ["p1": SaveState(status: .done), "p3": SaveState(status: .done),
                                           "p4": SaveState(status: .letGo)]
        let list = DoList.ordered(posts, states: states)
        #expect(list.todo.map(\.id) == ["p0", "p2"])
        #expect(list.done.map(\.id) == ["p1", "p3"])
        let progress = DoList.progress(posts, states: states)
        #expect(progress.done == 2 && progress.total == 4)
        let pick = DoList.pickOne(list.todo, seed: "2026-11-20|t|1")
        #expect(pick.map { ["p0", "p2"].contains($0.id) } == true)
        #expect(DoList.pickOne(list.todo, seed: "s") == DoList.pickOne(list.todo, seed: "s"))
        #expect(DoList.pickOne([], seed: "s") == nil)
    }

    @Test func lookBoardBalancesColumns() {
        let posts = (0..<20).map { post("p\($0)") }
        let columns = LookBoard.columns(posts)
        #expect(columns.left.count + columns.right.count == 20)
        let lh = columns.left.map(LookBoard.aspect).reduce(0, +)
        let rh = columns.right.map(LookBoard.aspect).reduce(0, +)
        #expect(abs(lh - rh) <= 1.5)
        #expect(posts.allSatisfy { (0.9...1.5).contains(LookBoard.aspect($0)) })
    }

    // MARK: - Ask

    @Test func askFilters() {
        let now = at("2026-11-20")
        let posts = [post("a", saved: "2026-11-03"), post("b", saved: "2026-10-30"), post("c"), post("d")]
        let states: [String: SaveState] = [
            "b": SaveState(status: .done, lastOpened: now), "c": SaveState(status: .letGo),
            "d": SaveState(note: "for the trip"),
        ]
        func ids(_ f: AskFilter) -> [String] { f.apply(posts, states: states, now: now, calendar: calendar).map(\.id) }
        #expect(ids(.neverOpened) == ["a", "d"])
        #expect(ids(.thisMonth) == ["a"])
        #expect(ids(.done) == ["b"])
        #expect(ids(.letGo) == ["c"])
        #expect(ids(.notes) == ["d"])
    }

    @Test func askSearchesTopicsNotesAndLetGoSaves() {
        let posts = [post("a", caption: "Lemon pasta"), post("b", caption: "Sunset", author: "chef.anna"),
                     post("c", caption: "Nothing"), post("d", caption: "pasta again")]
        let states: [String: SaveState] = ["c": SaveState(note: "Pasta for Friday"), "d": SaveState(status: .letGo)]
        let topics = ["b": "Cooking"]
        let byNote = AskSearch.results("pasta", posts: posts, states: states, topicLabel: { topics[$0] })
        #expect(Set(byNote.map(\.id)) == ["a", "c", "d"])
        #expect(byNote.first?.id == "c")                       // a note weighs most
        #expect(byNote.first?.matchedNote == true)
        let byTopic = AskSearch.results("cooking", posts: posts, states: states, topicLabel: { topics[$0] })
        #expect(byTopic.map(\.id) == ["b"])
        #expect(byTopic.first?.matchedTopic == "Cooking")
        #expect(AskSearch.results("  ", posts: posts, states: states, topicLabel: { _ in nil }).isEmpty)
    }
}

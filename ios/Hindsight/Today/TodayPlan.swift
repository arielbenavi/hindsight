import Foundation

/// How the user answered one of Today's cards.
enum TodayOutcome: String, Codable, Sendable {
    case opened, done, letGo
    /// Sent somewhere it's useful (Maps, Reminders, Calendar): handled for today.
    /// The save's status stays `new`.
    case sent

    var verb: String {
        switch self {
        case .opened: "Opened"
        case .done: "Did it"
        case .letGo: "Let go"
        case .sent: "Sent"
        }
    }

    var symbol: String {
        switch self {
        case .opened: "arrow.up.right.circle.fill"
        case .done: "checkmark.circle.fill"
        case .letGo: "xmark.circle.fill"
        case .sent: "paperplane.circle.fill"
        }
    }
}

/// Today's set, persisted so a relaunch mid-day resumes ("2 of 3"); a new day
/// starts a new one.
struct TodayRecord: Codable, Equatable, Sendable {
    struct Entry: Codable, Equatable, Sendable {
        var id: String
        /// `Resurface.Reason.label`, kept so the card reads the same after a relaunch.
        var reason: String
    }

    var day: String
    var picks: [Entry]
    var outcomes: [String: TodayOutcome] = [:]

    /// The card showing now: the first without an answer.
    var position: Int { picks.firstIndex { outcomes[$0.id] == nil } ?? picks.count }
    var current: Entry? { position < picks.count ? picks[position] : nil }
    var isFinished: Bool { !picks.isEmpty && position >= picks.count }
}

/// Which saves Today may serve and in what order. Pure.
///
/// Eligible: state `new`, not snoozed (a reminder still ahead), not sent to
/// Reminders/Calendar in the last 30 days (`SaveState.isRouted`), and its topic's job
/// allows Today (Do, Learn, Go; a save with no topic yet counts). Due reminders come
/// first, then `Resurface` over the eligible ones.
enum TodayPlan {
    static let dailyCount = 3

    struct Context {
        var posts: [ContractPost]
        var states: [String: SaveState]
        /// A save's job (its topic's), nil when it has no topic yet.
        var job: (String) -> TopicJob?
        var now: Date
        var calendar: Calendar = .current

        func state(_ id: String) -> SaveState { states[id] ?? .initial }
    }

    static func isEligible(_ post: ContractPost, in ctx: Context) -> Bool {
        let state = ctx.state(post.id)
        guard state.status == .new, !state.isSnoozed(now: ctx.now), !state.isRouted(now: ctx.now) else { return false }
        return ctx.job(post.id)?.allowsToday ?? true
    }

    /// Reminders whose time has come, oldest first. Any job but Keep close (the user
    /// asked for these, so a Look save can come back too).
    static func dueReminders(_ ctx: Context) -> [ContractPost] {
        ctx.posts.filter { post in
            let state = ctx.state(post.id)
            return state.status == .new && state.isDue(now: ctx.now) && ctx.job(post.id) != .keepClose
        }
        .sorted { (ctx.state($0.id).remindAt ?? .distantPast, $0.id) < (ctx.state($1.id).remindAt ?? .distantPast, $1.id) }
    }

    static func eligible(_ ctx: Context) -> [ContractPost] { ctx.posts.filter { isEligible($0, in: ctx) } }

    /// Up to `limit` picks, leaving out `excluding`.
    static func picks(_ ctx: Context, excluding: Set<String> = [], limit: Int = dailyCount) -> [TodayRecord.Entry] {
        var out: [TodayRecord.Entry] = []
        var used = excluding
        for post in dueReminders(ctx) where out.count < limit && used.insert(post.id).inserted {
            out.append(.init(id: post.id, reason: Resurface.Reason.reminder.label))
        }
        let pool = eligible(ctx).filter { !used.contains($0.id) }
        for pick in Resurface.picks(posts: pool, today: ctx.now, calendar: ctx.calendar, limit: limit - out.count) {
            out.append(.init(id: pick.id, reason: pick.reason.label))
        }
        return out
    }

    /// Today's set: the saved one if it's from today, else a fresh one. Two
    /// exceptions, both for a set nobody has answered yet: it's made again if a
    /// pick stopped being eligible (the first sort just gave its topic a Know job,
    /// say), and an empty set is never kept (it was made before the saves arrived
    /// or were sorted; it used to stick all day as "Nothing for today").
    static func record(existing: TodayRecord?, _ ctx: Context) -> TodayRecord {
        let day = TodayPicker.dayKey(ctx.now, calendar: ctx.calendar)
        if let existing, existing.day == day {
            guard existing.outcomes.isEmpty else { return existing }
            if existing.picks.isEmpty { return TodayRecord(day: day, picks: picks(ctx)) }
            let ok = Set(eligible(ctx).map(\.id)).union(dueReminders(ctx).map(\.id))
            let reminder = Resurface.Reason.reminder.label
            if existing.picks.allSatisfy({ ok.contains($0.id) || $0.reason == reminder }) { return existing }
        }
        return TodayRecord(day: day, picks: picks(ctx))
    }

    /// Reminders that came due since the set was made join it, right after the
    /// card showing now (or at the end, reopening a finished set).
    static func addingDue(_ record: TodayRecord, _ ctx: Context) -> TodayRecord {
        let have = Set(record.picks.map(\.id))
        let due = dueReminders(ctx).filter { !have.contains($0.id) }
        guard !due.isEmpty else { return record }
        var next = record
        let entries = due.map { TodayRecord.Entry(id: $0.id, reason: Resurface.Reason.reminder.label) }
        next.picks.insert(contentsOf: entries, at: record.position)
        return next
    }

    /// "One more": one extra pick after the set; nil when nothing's left.
    static func oneMore(_ record: TodayRecord, _ ctx: Context) -> TodayRecord? {
        guard let extra = picks(ctx, excluding: Set(record.picks.map(\.id)), limit: 1).first else { return nil }
        var next = record
        next.picks.append(extra)
        return next
    }

    /// What an empty Today says: no saves yet, still sorting (picks come once topics
    /// are in), or everything that could come up is handled.
    enum Empty: Equatable { case noSaves, sorting, allHandled }

    static func empty(hasSaves: Bool, isSorting: Bool) -> Empty {
        !hasSaves ? .noSaves : isSorting ? .sorting : .allHandled
    }

    /// Saves that arrived since the start of yesterday ("New since yesterday").
    static func newSinceYesterday(_ posts: [ContractPost], now: Date, calendar: Calendar = .current) -> [ContractPost] {
        guard let start = calendar.date(byAdding: .day, value: -1, to: calendar.startOfDay(for: now)) else { return [] }
        return posts.filter { ($0.savedDate ?? .distantPast) >= start }
    }
}

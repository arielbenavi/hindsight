import Foundation

/// Home's "Today": up to three old saves brought back, the same all day and
/// different tomorrow. Pure. Order: saved on this day in an earlier year, then
/// saves older than 30 days picked by a seed from the date, then the newest.
enum Resurface {
    static let oldAfterDays = 30

    enum Reason: Hashable, Sendable {
        /// Saved on this month and day, `years` ago.
        case anniversary(years: Int)
        /// An older save; `months` is nil when we don't know when it was saved.
        case fromThePast(months: Int?)
        case new

        var label: String {
            switch self {
            case .anniversary(let years): "Saved \(years) \(years == 1 ? "year" : "years") ago today"
            case .fromThePast(let months?) where months >= 12:
                "From \(months / 12) \(months / 12 == 1 ? "year" : "years") ago"
            case .fromThePast(let months?): "From \(max(1, months)) \(months <= 1 ? "month" : "months") ago"
            case .fromThePast(nil): "From your saves"
            case .new: "New"
            }
        }
    }

    struct Pick: Identifiable, Hashable, Sendable {
        let post: ContractPost
        let reason: Reason
        var id: String { post.id }
    }

    static func picks(posts: [ContractPost], today: Date, calendar: Calendar = .current, limit: Int = 3) -> [Pick] {
        guard limit > 0 else { return [] }
        var picks: [Pick] = []
        var used: Set<String> = []
        func take(_ post: ContractPost, _ reason: Reason) {
            guard picks.count < limit, used.insert(post.id).inserted else { return }
            picks.append(Pick(post: post, reason: reason))
        }
        let now = calendar.dateComponents([.year, .month, .day], from: today)
        let dated = posts.compactMap { post in post.savedDate.map { (post: post, date: $0) } }

        // 1. Saved on this day in an earlier year, most recent year first.
        let anniversaries = dated.compactMap { entry -> (post: ContractPost, date: Date, years: Int)? in
            let c = calendar.dateComponents([.year, .month, .day], from: entry.date)
            guard c.month == now.month, c.day == now.day, let year = c.year, let thisYear = now.year, year < thisYear else { return nil }
            return (entry.post, entry.date, thisYear - year)
        }
        .sorted { $0.date != $1.date ? $0.date > $1.date : $0.post.id > $1.post.id }
        for a in anniversaries { take(a.post, .anniversary(years: a.years)) }

        // 2. Older than 30 days (or undated), shuffled by a seed from today's date.
        let cutoff = calendar.date(byAdding: .day, value: -oldAfterDays, to: calendar.startOfDay(for: today)) ?? today
        let old = posts.filter { post in post.savedDate.map { $0 < cutoff } ?? true }
            .filter { !used.contains($0.id) }
            .sorted { $0.id < $1.id }  // input order must not change the picks
        var rng = SeededGenerator(seed: daySeed(now))
        for post in old.shuffled(using: &rng) {
            let months = post.savedDate.flatMap { calendar.dateComponents([.month], from: $0, to: today).month }
            take(post, .fromThePast(months: months))
        }

        // 3. Fill with the newest saves.
        let newest = posts.map { (post: $0, date: $0.savedDate ?? .distantPast) }
            .sorted { $0.date != $1.date ? $0.date > $1.date : $0.post.id > $1.post.id }
        for entry in newest { take(entry.post, .new) }
        return picks
    }

    private static func daySeed(_ c: DateComponents) -> UInt64 {
        let year: Int = c.year ?? 0, month: Int = c.month ?? 0, day: Int = c.day ?? 0
        return UInt64(year * 10_000 + month * 100 + day)
    }
}

/// SplitMix64: a tiny deterministic generator, so a seed gives the same shuffle every time.
struct SeededGenerator: RandomNumberGenerator, Sendable {
    private var state: UInt64

    init(seed: UInt64) { state = seed }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

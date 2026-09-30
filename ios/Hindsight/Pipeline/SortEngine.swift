import Foundation
import Observation

/// Sorts a user's own saves into a contract file (docs/data-contract.md) on the
/// phone, with Apple's models (ADR-001, E1–E2; spec: onboarding-chat.md):
///
/// 1. each post: rules if certain, else the model's bucket + topic slug; map
///    posts also get their places (checked against the text) — `sort`
/// 2. topic slugs → named topics, one model call — `assemble`
/// 3. in the background after approval: tip and routine details — `enrich`
///
/// Every result is cached by post id + caption, so a restart resumes and later
/// syncs only sort new posts. Models never block anything: a post no model can
/// answer falls back to the rules, and ends up in Everything else at worst.
@Observable
@MainActor
final class SortEngine {
    struct Record: Codable, Sendable {
        var captionHash: UInt64
        var decision: SortDecision
        var places: [ExtractedPlace]?
        var tip: ExtractedTip?
        var routine: ExtractedRoutine?
    }

    struct TopicInfo: Codable, Sendable {
        var id: String
        var label: String
        var emoji: String
        var screen: LegoScreen?
        var question: String?
    }

    private struct Cache: Codable {
        var records: [String: Record] = [:]
        /// "screen/slug" → topic id, fixed once named so tabs never shift.
        var topicByHint: [String: String] = [:]
        var topics: [String: TopicInfo] = [:]
        var usage = SortUsage()
    }

    private let backend: SortBackend
    private let file: JSONFile<Cache>
    private var cache: Cache
    private(set) var progress: SortProgress?
    private(set) var isSorting = false
    private var task: Task<Void, Never>?
    private var observers: [UUID: AsyncStream<SortProgress>.Continuation] = [:]

    /// `directory: nil` keeps the cache in memory (tests, previews).
    init(backend: SortBackend, directory: URL?) {
        self.backend = backend
        file = JSONFile(name: "sort-cache", directory: directory)
        cache = file.load() ?? Cache()
    }

    var usage: SortUsage { cache.usage }

    // MARK: - 1. Sorting

    /// Starts sorting whatever isn't sorted yet. Runs on its own: observers can
    /// stop listening (the chat moves on at 90%) without stopping the sort.
    func start(_ posts: [ContractPost], concurrency: Int = 4, onFinish: (@MainActor () -> Void)? = nil) {
        let todo = posts.filter { cache.records[$0.id]?.captionHash != Self.hash($0.caption) }
        publish(posts)
        guard !todo.isEmpty, task == nil else {
            if todo.isEmpty { finishStreams(); onFinish?() }
            return
        }
        isSorting = true
        DebugLog.write("sort: \(todo.count) of \(posts.count) posts to sort")
        task = Task {
            await withTaskGroup(of: (String, Record).self) { group in
                var queue = todo[...]
                func next() {
                    guard let post = queue.popFirst() else { return }
                    group.addTask { [backend] in (post.id, await Self.sortOne(post, backend: backend)) }
                }
                for _ in 0..<concurrency { next() }
                var done = 0
                for await (id, record) in group {
                    cache.records[id] = record
                    done += 1
                    publish(posts)
                    if done % 10 == 0 { save() }
                    next()
                }
            }
            cache.usage = await backend.usage()
            save()
            isSorting = false
            task = nil
            DebugLog.write("sort: done · \(cache.usage)")
            finishStreams()
            onFinish?()
        }
    }

    /// Progress for the chat's "Reading your saves…" message.
    func progressStream() -> AsyncStream<SortProgress> {
        AsyncStream { continuation in
            let id = UUID()
            if let progress { continuation.yield(progress) }
            if !isSorting, progress?.isComplete == true { continuation.finish(); return }
            observers[id] = continuation
            continuation.onTermination = { _ in Task { @MainActor [weak self] in self?.observers[id] = nil } }
        }
    }

    private static func sortOne(_ post: ContractPost, backend: SortBackend) async -> Record {
        let decision: SortDecision
        if let certain = SortRules.certain(post) {
            decision = certain
        } else {
            decision = await backend.bucket(post) ?? SortRules.fallback(post)
        }
        var record = Record(captionHash: hash(post.caption), decision: decision)
        if decision.screen == .map {
            // Places now, not later: the Map tab and the place check need them.
            record.places = SortRules.places(await backend.places(post) ?? [], in: post)
        }
        return record
    }

    private func publish(_ posts: [ContractPost]) {
        let decided = posts.filter { cache.records[$0.id] != nil }
        var counts: [String: (SortDecision, Int)] = [:]
        for post in decided {
            guard let d = cache.records[post.id]?.decision, d.screen != nil else { continue }
            let key = Self.hintKey(d)
            counts[key] = (d, (counts[key]?.1 ?? 0) + 1)
        }
        var topics: [SortProgress.TopicCount] = []
        for (key, value) in counts {
            let info: TopicInfo? = cache.topicByHint[key].flatMap { cache.topics[$0] }
            let label: String = info?.label ?? SortRules.label(forSlug: value.0.slug)
            let emoji: String = info?.emoji ?? value.0.screen?.defaultEmoji ?? "•"
            topics.append(SortProgress.TopicCount(id: key, label: label, emoji: emoji, count: value.1))
        }
        topics.sort { $0.count != $1.count ? $0.count > $1.count : $0.label < $1.label }
        let snapshot = SortProgress(decided: decided.count, total: posts.count, topics: Array(topics.prefix(24)))
        progress = snapshot
        for continuation in observers.values { continuation.yield(snapshot) }
    }

    private func finishStreams() {
        for continuation in observers.values { continuation.finish() }
        observers = [:]
    }

    // MARK: - 2. Assembling the contract file

    /// The contract file from everything decided so far. Names new topic slugs
    /// with one model call; slugs named before keep their topic. Posts not
    /// decided yet go to Everything else until they are.
    func assemble(_ posts: [ContractPost], user: ContractUser) async -> ContractFile {
        // Group decided posts by hint ("screen/slug").
        var hintPosts: [String: [ContractPost]] = [:]
        var hintDecision: [String: SortDecision] = [:]
        var undecided: [ContractPost] = []
        for post in posts {
            guard let d = cache.records[post.id]?.decision else { undecided.append(post); continue }
            let key = Self.hintKey(d)
            hintPosts[key, default: []].append(post)
            hintDecision[key] = d
        }

        // Name the hints we haven't named before (the "none" ones don't need a name).
        let newHints = hintPosts.keys.filter { cache.topicByHint[$0] == nil && hintDecision[$0]?.screen != nil }.sorted()
        if !newHints.isEmpty {
            let hints = newHints.map { key in
                let posts = hintPosts[key] ?? []
                return TopicHint(screen: hintDecision[key]?.screen, slug: hintDecision[key]?.slug ?? "other", count: posts.count,
                                 samples: posts.prefix(2).compactMap(\.firstLine),
                                 collections: Self.topCollections(posts))
            }
            let planned = await backend.topics(hints)
            name(hints, with: planned)
            cache.usage = await backend.usage()
        }

        // Topics, in the order their first post appears (newest first).
        var topicPosts: [String: [ContractPost]] = [:]
        var order: [String] = []
        func add(_ post: ContractPost, to topicID: String) {
            if topicPosts[topicID] == nil { order.append(topicID) }
            topicPosts[topicID, default: []].append(post)
        }
        for post in posts {
            if let d = cache.records[post.id]?.decision, d.screen != nil, let topicID = cache.topicByHint[Self.hintKey(d)] {
                add(post, to: topicID)
            } else {
                add(post, to: Self.randomTopicID)
            }
        }
        var topics: [ContractTopic] = order.compactMap { id in
            let members = topicPosts[id] ?? []
            if id == Self.randomTopicID {
                return ContractTopic(id: id, label: "Random", emoji: "🤷", legoScreen: nil, postIds: members.map(\.id))
            }
            guard let info = cache.topics[id] else { return nil }
            let ambiguity = info.question.map {
                ContractTopic.Ambiguity(question: $0, options: [
                    .init(label: "Places to go", legoScreen: .map),
                    .init(label: "Things to learn", legoScreen: .learn),
                    .init(label: "Leave them out", legoScreen: nil),
                ])
            }
            return ContractTopic(id: id, label: info.label, emoji: info.emoji, legoScreen: info.screen,
                                 confidence: info.question == nil ? .high : .low, postIds: members.map(\.id),
                                 samplePostIds: Array(members.prefix(4).map(\.id)),
                                 sourceCollections: Self.topCollections(members), ambiguity: ambiguity)
        }
        topics.sort { ($0.legoScreen == nil ? 1 : 0, -$0.postIds.count) < ($1.legoScreen == nil ? 1 : 0, -$1.postIds.count) }

        // Items: one per post in a real topic, with details or their stand-ins.
        let topicByPost = Dictionary(topics.flatMap { t in t.postIds.map { ($0, t) } }, uniquingKeysWith: { a, _ in a })
        let items: [ContractItem] = posts.compactMap { post in
            guard let topic = topicByPost[post.id], let screen = topic.legoScreen, let record = cache.records[post.id] else { return nil }
            switch screen {
            case .map:
                return ContractItem(postId: post.id, legoScreen: .map, topicId: topic.id, places: record.places ?? [])
            case .learn:
                return ContractItem(postId: post.id, legoScreen: .learn, topicId: topic.id, tip: record.tip ?? SortRules.placeholderTip(post))
            case .fitness:
                // Fitness posts also carry a tip: with fewer than 5 they're shown in Learn.
                return ContractItem(postId: post.id, legoScreen: .fitness, topicId: topic.id,
                                    tip: record.tip ?? SortRules.placeholderTip(post),
                                    routine: record.routine ?? SortRules.placeholderRoutine(post))
            }
        }
        save()
        return ContractFile(contractVersion: ContractFile.supportedVersion, generatedAt: Date().formatted(.iso8601),
                            user: user, posts: posts, topics: topics, items: items)
    }

    /// Store the model's names; any hint it skipped (or got wrong) gets its own topic.
    private func name(_ hints: [TopicHint], with planned: [PlannedTopic]?) {
        var remaining = Dictionary(uniqueKeysWithValues: hints.map { (Self.hintKey(SortDecision(screen: $0.screen, slug: $0.slug)), $0) })
        var usedIDs = Set(cache.topics.keys).union([Self.randomTopicID])
        func newID(_ label: String) -> String {
            var id = SortRules.slug(label), n = 2
            while usedIDs.contains(id) { id = "\(SortRules.slug(label))-\(n)"; n += 1 }
            usedIDs.insert(id)
            return id
        }
        for topic in planned ?? [] {
            // A planned topic may mix screens; keep one topic per screen.
            let members = topic.slugs.flatMap { slug in remaining.values.filter { $0.slug == SortRules.slug(slug) } }
            for (screen, group) in Dictionary(grouping: members, by: \.screen) {
                let id = newID(topic.label)
                cache.topics[id] = TopicInfo(id: id, label: String(topic.label.prefix(30)), emoji: topic.emoji.nilIfEmpty ?? screen?.defaultEmoji ?? "•",
                                             screen: screen, question: screen == nil ? nil : topic.question)
                for hint in group {
                    let key = Self.hintKey(SortDecision(screen: hint.screen, slug: hint.slug))
                    cache.topicByHint[key] = id
                    remaining[key] = nil
                }
            }
        }
        for (key, hint) in remaining {
            let id = newID(hint.slug)
            cache.topics[id] = TopicInfo(id: id, label: SortRules.label(forSlug: hint.slug), emoji: hint.screen?.defaultEmoji ?? "•",
                                         screen: hint.screen, question: nil)
            cache.topicByHint[key] = id
        }
    }

    // MARK: - 3. Details in the background

    /// Tips for Learn posts and routines for Fitness posts that are still on
    /// stand-ins. Returns how many got details.
    func enrich(_ posts: [ContractPost], concurrency: Int = 4) async -> Int {
        let fitnessCount = posts.count { cache.records[$0.id]?.decision.screen == .fitness }
        let todo = posts.filter { post in
            guard let r = cache.records[post.id] else { return false }
            switch r.decision.screen {
            case .learn: return r.tip == nil
            case .fitness: return fitnessCount < LayoutRules.threshold ? r.tip == nil : r.routine == nil
            default: return false
            }
        }
        guard !todo.isEmpty else { return 0 }
        DebugLog.write("sort: details for \(todo.count) posts")
        let backend = backend
        let asTip = fitnessCount < LayoutRules.threshold
        let screens = Dictionary(todo.map { ($0.id, cache.records[$0.id]?.decision.screen) }, uniquingKeysWith: { a, _ in a })
        var updated = 0
        await withTaskGroup(of: (String, ExtractedTip?, ExtractedRoutine?).self) { group in
            var queue = todo[...]
            func next() {
                guard let post = queue.popFirst() else { return }
                let screen = screens[post.id] ?? nil
                group.addTask {
                    if screen == .fitness && !asTip { return (post.id, nil, await backend.routine(post)) }
                    return (post.id, await backend.tip(post), nil)
                }
            }
            for _ in 0..<concurrency { next() }
            for await (id, tip, routine) in group {
                if let tip { cache.records[id]?.tip = tip; updated += 1 }
                if let routine { cache.records[id]?.routine = routine; updated += 1 }
                if updated % 10 == 0 { save() }
                next()
            }
        }
        cache.usage = await backend.usage()
        save()
        DebugLog.write("sort: details done (+\(updated)) · \(cache.usage)")
        return updated
    }

    // MARK: - Helpers

    static let randomTopicID = "random"

    private static func hintKey(_ d: SortDecision) -> String { "\(d.screen?.rawValue ?? "none")/\(d.slug)" }

    /// Collections most of these posts share ("NYC Restaurants").
    private static func topCollections(_ posts: [ContractPost]) -> [String] {
        var counts: [String: Int] = [:]
        for post in posts { for c in post.collections { counts[c, default: 0] += 1 } }
        return counts.filter { $0.value * 2 >= posts.count }.sorted { $0.value > $1.value }.map(\.key)
    }

    /// FNV-1a: stable across launches (unlike `hashValue`).
    static func hash(_ text: String?) -> UInt64 {
        var h: UInt64 = 0xcbf29ce484222325
        for byte in (text ?? "").utf8 { h = (h ^ UInt64(byte)) &* 0x100000001b3 }
        return h
    }

    private func save() { file.save(cache) }
}

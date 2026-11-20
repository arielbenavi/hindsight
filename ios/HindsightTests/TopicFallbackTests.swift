import Foundation
import Testing
import UIKit
@testable import Hindsight

/// A model that can be switched on: none at first (simulator), then one that
/// answers every post the same way.
actor SwitchableBackend: SortBackend {
    private(set) var available: Bool
    private let answer: SortDecision?
    private(set) var bucketCalls = 0

    init(available: Bool, answer: SortDecision? = nil) { self.available = available; self.answer = answer }

    func switchOn() { available = true }
    func bucket(_ post: ContractPost) async -> SortDecision? { bucketCalls += 1; return available ? answer : nil }
    func places(_ post: ContractPost) async -> [(name: String, type: PlaceType)]? { nil }
    func topics(_ hints: [TopicHint]) async -> [PlannedTopic]? { nil }
    func tip(_ post: ContractPost) async -> ExtractedTip? { nil }
    func routine(_ post: ContractPost) async -> ExtractedRoutine? { nil }
    func usage() async -> SortUsage { SortUsage() }
    func isAvailable() async -> Bool { available }
}

/// The no-model topic assigner (`TopicFallback`) and how the engine uses it.
@MainActor
struct TopicFallbackTests {
    private func post(_ id: String, _ caption: String?, author: String = "someone", platform: Platform = .instagram,
                      kind: SavedPost.Kind = .reel, hashtags: [String] = [], collections: [String] = []) -> ContractPost {
        ContractPost(id: id, platform: platform, url: URL(string: "https://example.com/\(id)")!, kind: kind, author: author,
                     caption: caption, hashtags: hashtags, collections: collections)
    }

    private func slug(_ p: ContractPost) -> String? { TopicFallback.pick(p)?.slug }

    // MARK: - Tokens

    @Test func tokensAreFoldedWithoutTagsOrHandles() {
        #expect(TopicFallback.words("Best #nyc PIZZA @joes.pizza in the Café!") == ["best", "pizza", "in", "the", "cafe"])
        #expect(TopicFallback.words("איך משתפרים במיקס? ככה") == ["איך", "משתפרים", "במיקס", "ככה"])
    }

    @Test func hebrewPrefixesComeOff() {
        #expect(TopicFallback.variants("במיקס").contains("מיקס"))
        #expect(TopicFallback.variants("והטבעונות").contains("טבעונות"))
        // Two letters only after ו/ש: "למספר" (to the number) isn't "ספר" (book).
        #expect(!TopicFallback.variants("למספר").contains("ספר"))
        #expect(TopicFallback.variants("pizza") == ["pizza"])
        #expect(slug(post("1", "איך משתפרים במיקס? ככה")) == "music-production")
    }

    @Test func diacriticsAndCaseDontMatter() {
        #expect(slug(post("1", "Receita fácil de PANQUECA, ingredientes abaixo")) == "food-recipes")
    }

    // MARK: - Matching

    @Test func noSubstringFalsePositives() {
        // "art" is in "start", "heart", "#startup"; "ai" in "said", "#airbnb".
        let p = post("1", "Start your heart said the party starter", hashtags: ["start", "airbnb"])
        #expect(!TopicFallback.scores(p).contains { $0.topic.id == "art-photography" || $0.topic.id == "tech-ai" })
        #expect(TopicFallback.matchesTag("guitar", "guitartutorial"))
        #expect(TopicFallback.matchesTag("producer", "musicproducerlife"))
        #expect(!TopicFallback.matchesTag("art", "start"))
        #expect(!TopicFallback.matchesTag("ai", "airbnb"))
        #expect(slug(post("2", "3 chords, 3 ways", hashtags: ["guitartutorial"])) == "guitar-instruments")
    }

    @Test func oneAmbiguousWordIsNotEnough() {
        #expect(slug(post("1", "I love this so much")) == nil)
        #expect(slug(post("2", "Looks tasty")) == nil)
        #expect(slug(post("3", "Easy protein pancakes recipe")) == "food-recipes")
    }

    @Test func theAuthorsNameBacksAMatchButNeverMakesOne() {
        #expect(slug(post("1", "Woman arrested after a fight at the mall", author: "rap")) != "music")
        #expect(slug(post("2", "New single out now", author: "rap")) == "music")
    }

    // MARK: - Priority

    @Test func collectionBeatsHashtagBeatsCaption() {
        let collected = post("1", "Easy recipe", hashtags: ["guitar"], collections: ["Saved", "Weeknight dinners"])
        #expect(TopicFallback.pick(collected) == .init(slug: "weeknight-dinners", label: "Weeknight dinners", signal: .collection))

        // One hashtag (3) beats one caption word (2).
        let tagged = post("2", "My guitar is out of tune", hashtags: ["recipe"])
        #expect(TopicFallback.pick(tagged)?.slug == "food-recipes")
        #expect(TopicFallback.pick(tagged)?.signal == .hashtag)
        #expect(TopicFallback.pick(post("3", "My new guitar"))?.signal == .caption)
    }

    @Test func authorsOtherSavesThenPlatformThenNothing() {
        let posts = [
            post("a1", "Pentatonic riffs", author: "jon", hashtags: ["guitarlesson"]),
            post("a2", "Fingerstyle lesson", author: "jon", hashtags: ["guitar"]),
            post("a3", "wait for it", author: "jon"),
            post("n1", "call mom back", author: "me", platform: .whatsapp, kind: .note),
            post("x1", "hmm", author: "someone", platform: .x, kind: .tweet),
            post("i1", "🙂", author: "nobody"),
        ]
        let picks = TopicFallback.picks(for: posts)
        #expect(picks["a3"] == .init(slug: "guitar-instruments", label: "Guitar & instruments", signal: .author))
        #expect(picks["n1"]?.slug == "notes")
        #expect(picks["x1"]?.label == "Posts from X")
        #expect(picks["i1"] == nil)
    }

    @Test func authorNeedsAMajority() {
        let posts = [
            post("1", "Fingerstyle lesson", author: "mix", hashtags: ["guitar"]),
            post("2", "Easy recipe", author: "mix", hashtags: ["recipe"]),
            post("3", "…", author: "mix"),
        ]
        #expect(TopicFallback.picks(for: posts)["3"] == nil)
    }

    @Test func tiesGoToTheMoreSpecificTopicEveryTime() {
        // One strong word each: "producer" (Music production) and "rapper" (Music).
        let p = post("1", "The producer and the rapper")
        let first = TopicFallback.scores(p)
        #expect(first.prefix(2).map(\.score) == [2, 2])
        #expect(first.first?.topic.id == "music-production")
        for _ in 0..<20 { #expect(TopicFallback.scores(p).map(\.topic.id) == first.map(\.topic.id)) }
    }

    @Test func everyLexiconTopicHasAUniqueIDLabelAndSymbol() {
        let all = TopicFallback.lexicon + TopicFallback.platformTopics
        #expect(Set(all.map(\.id)).count == all.count)
        #expect(Set(all.map(\.label)).count == all.count)
        #expect(all.allSatisfy { !$0.emoji.isEmpty })
        for topic in all { #expect(UIImage(systemName: topic.symbol) != nil, "\(topic.symbol) isn't an SF Symbol") }
        #expect(all.allSatisfy { SortRules.slug($0.id) == $0.id })
        #expect(TopicFallback.symbol(forLabel: "guitar & INSTRUMENTS") == "guitars.fill")
    }

    // MARK: - The engine

    private func sortAll(_ engine: SortEngine, _ posts: [ContractPost]) async {
        await withCheckedContinuation { (done: CheckedContinuation<Void, Never>) in
            engine.start(posts) { done.resume() }
        }
    }

    private let user = ContractUser(handle: "me", platforms: ["instagram"])

    private var samplePosts: [ContractPost] {
        [
            post("g1", "Pentatonic riffs", hashtags: ["guitarlesson"]),
            post("g2", "Fingerstyle lesson", hashtags: ["guitar"]),
            post("g3", "Neo soul guitar chords"),
            post("c1", "The best one", collections: ["Weeknight dinners"]),
            post("c2", "so good", collections: ["Weeknight dinners"]),
            post("c3", "trust me", collections: ["Weeknight dinners"]),
            post("o1", "🙂", author: "nobody"),
        ]
    }

    @Test func withoutAModelTopicsComeFromTheFallback() async throws {
        let posts = samplePosts
        let engine = SortEngine(backend: SwitchableBackend(available: false), directory: nil)
        await sortAll(engine, posts)
        let file = await engine.assemble(posts, user: user)
        let labels = Dictionary(uniqueKeysWithValues: file.topics.map { ($0.label, Set($0.postIds)) })
        #expect(labels["Guitar & instruments"] == ["g1", "g2", "g3"])
        #expect(labels["Weeknight dinners"] == ["c1", "c2", "c3"])
        #expect(labels["Other"] == ["o1"])
        #expect(file.topics.allSatisfy { $0.legoScreen == nil })
        #expect(file.items.isEmpty)
        #expect(await engine.canImproveFallbacks(posts) == false)

        let topics = HomeTopics.build(data: HindsightData(file: file), posts: posts)
        #expect(topics.first { $0.label == "Guitar & instruments" }?.symbol == "guitars.fill")
        #expect(topics.first { $0.label == "Weeknight dinners" }?.symbol == "folder.fill")
    }

    @Test func aModelLaterReplacesFallbackDecisions() async throws {
        let posts = samplePosts
        let backend = SwitchableBackend(available: false, answer: SortDecision(screen: .learn, slug: "music-lessons"))
        let dir = URL.temporaryDirectory.appending(path: UUID().uuidString)
        let engine = SortEngine(backend: backend, directory: dir)
        await sortAll(engine, posts)
        _ = await engine.assemble(posts, user: user)
        let calls = await backend.bucketCalls

        // Still no model: nothing to ask again.
        let reopened = SortEngine(backend: backend, directory: dir)
        #expect(await reopened.canImproveFallbacks(posts) == false)
        await sortAll(reopened, posts)
        #expect(await backend.bucketCalls == calls)

        // A model arrives (Apple Intelligence turned on): every fallback post is asked again.
        await backend.switchOn()
        #expect(await reopened.canImproveFallbacks(posts))
        await sortAll(reopened, posts)
        #expect(await backend.bucketCalls == calls + posts.count)
        let file = await reopened.assemble(posts, user: user)
        #expect(file.topics.count == 1)
        #expect(file.topics.first?.legoScreen == .learn)
        #expect(await reopened.canImproveFallbacks(posts) == false)
    }

    @Test func aModelThatDeclinesIsNotAskedAgain() async throws {
        let posts = samplePosts
        let backend = SwitchableBackend(available: true, answer: nil)
        let engine = SortEngine(backend: backend, directory: nil)
        await sortAll(engine, posts)
        let file = await engine.assemble(posts, user: user)
        #expect(file.topics.contains { $0.label == "Guitar & instruments" })
        let calls = await backend.bucketCalls
        #expect(await engine.canImproveFallbacks(posts) == false)
        await sortAll(engine, posts)
        #expect(await backend.bucketCalls == calls)
    }

    /// A cache from before fallback decisions were marked: its "none/other" posts
    /// (no model then) get fallback topics, and a model's answer later.
    @Test func oldCachesDecodeAndTheirOtherPostsGetTopics() async throws {
        let posts = samplePosts
        let dir = URL.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let records = posts.map { "\"\($0.id)\": {\"captionHash\": \(SortEngine.hash($0.caption)), \"decision\": {\"slug\": \"other\"}}" }
        let json = """
        {"records": {\(records.joined(separator: ", "))},
         "topicByHint": {"none/other": "other"},
         "topics": {"other": {"id": "other", "label": "Other", "emoji": "•"}},
         "usage": {"inputTokens": 0, "outputTokens": 0, "cloudRequests": 0, "onDeviceRequests": 0, "failedRequests": 0}}
        """
        try Data(json.utf8).write(to: dir.appending(path: "sort-cache.json"))

        let backend = SwitchableBackend(available: false)
        let engine = SortEngine(backend: backend, directory: dir)
        await sortAll(engine, posts)
        #expect(await backend.bucketCalls == 0)
        let file = await engine.assemble(posts, user: user)
        #expect(Set(file.topics.first { $0.label == "Guitar & instruments" }?.postIds ?? []) == ["g1", "g2", "g3"])
        #expect(file.topics.first { $0.label == "Other" }?.postIds == ["o1"])

        await backend.switchOn()
        #expect(await engine.canImproveFallbacks(posts))
    }

    // MARK: - Real data

    /// The bundled seed (1,216 real Instagram saves, captions cut at 160
    /// characters, no collections): with no model at all, most captioned saves
    /// still get a real topic. Before `TopicFallback` all but the 📍 ones were "Other".
    @Test func coversMostOfTheSeed() {
        let posts = SeedData.posts().map(ContractPost.init)
        #expect(posts.count == 1216)
        let picks = TopicFallback.picks(for: posts)
        let captioned = posts.filter { $0.caption?.nilIfEmpty != nil }
        let covered = captioned.filter { picks[$0.id] != nil }
        let share = Double(covered.count) / Double(captioned.count)

        var counts: [String: Int] = [:]
        for pick in picks.values { counts[pick.label, default: 0] += 1 }
        let top = counts.sorted { ($1.value, $0.key) < ($0.value, $1.key) }.prefix(15)
        var unmatched: [String: Int] = [:]
        for p in posts where picks[p.id] == nil { for tag in p.hashtags { unmatched[tag, default: 0] += 1 } }
        let signals = Dictionary(grouping: picks.values, by: \.signal).mapValues(\.count)
        print("COVERAGE seed: \(picks.count)/\(posts.count) posts topic'd; captioned \(covered.count)/\(captioned.count) = \(Int(share * 1000) / 10)%")
        print("COVERAGE signals: \(signals.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }.joined(separator: " "))")
        print("COVERAGE top15: \(top.map { "\($0.key) \($0.value)" }.joined(separator: " | "))")
        print("COVERAGE unmatched tags: \(unmatched.sorted { ($1.value, $0.key) < ($0.value, $1.key) }.prefix(20).map { "#\($0.key) \($0.value)" }.joined(separator: " "))")
        // Measured 2026-11-20: ~72%. The rest is mostly memes with no words to go on.
        #expect(share >= 0.6)
        #expect(top.count >= 15)
        #expect(top.first.map { $0.value * 3 < posts.count } == true)  // no new giant bucket
    }

    /// The labeled fixtures: posts whose collection names exist keep them as topics.
    @Test func fixturesUseTheirCollections() throws {
        let reut = try Fixtures.load("reut")
        let picks = TopicFallback.picks(for: reut.posts)
        let withCollections = reut.posts.filter { !$0.collections.isEmpty }
        #expect(withCollections.allSatisfy { picks[$0.id]?.signal == .collection })
        #expect(Double(picks.count) / Double(reut.posts.count) >= 0.75)
    }
}

import Foundation
import Testing
@testable import Hindsight

/// A model stand-in that answers from a fixture's labels (what the real models
/// are scored against), and counts its calls.
actor FixtureBackend: SortBackend {
    let data: HindsightData
    let answers: Bool
    private(set) var bucketCalls = 0
    private(set) var topicCalls = 0

    init(_ data: HindsightData, answers: Bool = true) { self.data = data; self.answers = answers }

    func bucket(_ post: ContractPost) async -> SortDecision? {
        bucketCalls += 1
        guard answers, let topic = data.topic(forPost: post.id) else { return nil }
        return SortDecision(screen: topic.legoScreen, slug: topic.id)
    }
    func places(_ post: ContractPost) async -> [(name: String, type: PlaceType)]? {
        guard answers else { return nil }
        return data.item(for: post.id)?.places?.map { ($0.name, $0.type) }
    }
    func topics(_ hints: [TopicHint]) async -> [PlannedTopic]? {
        topicCalls += 1
        guard answers else { return nil }
        return hints.map { hint in
            let topic = data.topic(hint.slug)
            return PlannedTopic(label: topic?.label ?? hint.slug, emoji: topic?.emoji ?? "•", slugs: [hint.slug], question: topic?.ambiguity?.question)
        }
    }
    func tip(_ post: ContractPost) async -> ExtractedTip? { answers ? data.item(for: post.id)?.tip : nil }
    func routine(_ post: ContractPost) async -> ExtractedRoutine? { answers ? data.item(for: post.id)?.routine : nil }
    func usage() async -> SortUsage { SortUsage() }
}

@MainActor
struct SortEngineTests {
    private func sortAll(_ engine: SortEngine, _ posts: [ContractPost]) async {
        await withCheckedContinuation { (done: CheckedContinuation<Void, Never>) in
            engine.start(posts) { done.resume() }
        }
    }

    private let user = ContractUser(handle: "me", platforms: ["instagram"])

    @Test func producesAValidContractFileThatProposesTheSpecLayout() async throws {
        let fixture = try Fixtures.load("reut")
        let engine = SortEngine(backend: FixtureBackend(fixture), directory: nil)
        await sortAll(engine, fixture.posts)
        let file = await engine.assemble(fixture.posts, user: user)

        // Contract rules (validate.py): each post in exactly one topic; one item per
        // post in a real topic, on that topic's screen; no empty strings.
        let memberships = file.topics.flatMap(\.postIds)
        #expect(memberships.count == fixture.posts.count)
        #expect(Set(memberships) == Set(fixture.posts.map(\.id)))
        let topicByID = Dictionary(uniqueKeysWithValues: file.topics.map { ($0.id, $0) })
        for item in file.items { #expect(topicByID[item.topicId]?.legoScreen == item.legoScreen) }
        #expect(file.items.count == file.topics.filter { $0.legoScreen != nil }.reduce(0) { $0 + $1.postIds.count })
        #expect(!file.topics.contains { $0.label.isEmpty })

        // Survives the round trip the app does, and proposes Map + Learn (layout-proposal "Done when").
        let data = HindsightData(file: try ContractFile.decode(file.encoded()))
        let tabs = LayoutRules.propose(data).draft.tabs.map(\.legoScreen)
        #expect(tabs.first == .map)
        #expect(tabs.contains(.learn))
        // Only places actually named in the post survive.
        let places = file.items.compactMap(\.places).flatMap { $0 }
        #expect(places.count > 100)
        #expect(places.allSatisfy { !$0.evidence.isEmpty })
    }

    @Test func secondRunOnlySortsNewOrChangedPosts() async throws {
        let fixture = try Fixtures.load("reut")
        let posts = Array(fixture.posts.prefix(30))
        let backend = FixtureBackend(fixture)
        let engine = SortEngine(backend: backend, directory: nil)
        await sortAll(engine, posts)
        let first = await backend.bucketCalls
        await sortAll(engine, posts)
        #expect(await backend.bucketCalls == first)

        var changed = posts
        changed[0].caption = (changed[0].caption ?? "") + " edited"
        await sortAll(engine, changed + [fixture.posts[40]])
        #expect(await backend.bucketCalls <= first + 2)
    }

    @Test func topicsAreNamedOnceAndKeepTheirIDs() async throws {
        let fixture = try Fixtures.load("reut")
        let backend = FixtureBackend(fixture)
        let engine = SortEngine(backend: backend, directory: nil)
        let early = Array(fixture.posts.prefix(200))
        await sortAll(engine, early)
        let before = await engine.assemble(early, user: user)
        await sortAll(engine, fixture.posts)
        let after = await engine.assemble(fixture.posts, user: user)
        let ids = Set(before.topics.map(\.id))
        #expect(ids.isSubset(of: Set(after.topics.map(\.id))))
    }

    @Test func withNoModelEverythingStillLands() async throws {
        let fixture = try Fixtures.load("reut")
        let engine = SortEngine(backend: FixtureBackend(fixture, answers: false), directory: nil)
        await sortAll(engine, fixture.posts)
        let file = await engine.assemble(fixture.posts, user: user)
        #expect(Set(file.topics.flatMap(\.postIds)).count == fixture.posts.count)
        // 📍 posts are still recognized as places by the rules.
        #expect(file.topics.contains { $0.legoScreen == .map })
    }

    @Test func detailsReplaceTheStandIns() async throws {
        let fixture = try Fixtures.load("ariel")
        let engine = SortEngine(backend: FixtureBackend(fixture), directory: nil)
        let posts = Array(fixture.posts.prefix(150))
        await sortAll(engine, posts)
        let before = await engine.assemble(posts, user: user)
        #expect(before.items.contains { $0.tip?.isThin == true })
        let updated = await engine.enrich(posts)
        #expect(updated > 0)
    }

    @Test func savedPostsBecomeContractPostsWithoutTheSeed() {
        let mine = SavedPost(url: URL(string: "https://www.instagram.com/reel/ABC/")!, kind: .reel, author: "saltHanks",
                             authorDisplayName: "Salt Hank's", caption: "📍 Salt Hank's #nyc", collections: ["NYC"],
                             savedAt: Date(timeIntervalSince1970: 0), source: .igExport)
        let seed = SavedPost(url: URL(string: "https://www.instagram.com/reel/XYZ/")!, kind: .reel, author: "a", caption: "x", source: .seedMD)
        let posts = ContractPost.userPosts(from: [seed, mine])
        #expect(posts.map(\.id) == ["instagram:ABC"])
        #expect(posts[0].author.displayName == "Salt Hank's")
        #expect(posts[0].collections == ["NYC"])
        #expect(posts[0].hashtags == ["nyc"])
        #expect(posts[0].savedDate != nil)
    }
}

struct SeedMergeTests {
    /// A post the user imports that's also in the bundled seed becomes theirs;
    /// before, it kept the seed label and the sort engine skipped it.
    @Test func importingASeedPostMakesItTheUsers() throws {
        let url = URL(string: "https://www.instagram.com/p/DdwJgsNABze/")!
        let seed = SavedPost(url: url, kind: .post, author: "a", caption: "short", source: .seedMD)
        let muse = SavedPost(url: url, kind: .post, author: "a", caption: "the full caption", source: .muse)
        let merged = seed.filling(from: muse)
        #expect(merged.source == .muse)
        #expect(ContractPost.userPosts(from: [merged]).count == 1)
        // …but a seed record never downgrades a real import.
        #expect(muse.filling(from: seed).source == .muse)
    }
}

import Foundation
import Testing
@testable import Hindsight

/// Home's pure parts: Today's picks (`Resurface`) and the Topics (`HomeTopics`).
@MainActor
struct HomeTests {
    private let calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "America/New_York")!
        return c
    }()

    private func day(_ string: String) -> Date {
        let p = string.split(separator: "-").compactMap { Int($0) }
        return calendar.date(from: DateComponents(year: p[0], month: p[1], day: p[2], hour: 12))!
    }

    private func post(_ id: String, saved: String? = nil, collections: [String] = []) -> ContractPost {
        ContractPost(id: id, url: URL(string: "https://www.instagram.com/p/\(id)/")!, author: "a", caption: id,
                     collections: collections, savedAt: saved)
    }

    /// `count` posts, one a day going back from `start` (none on an anniversary of 2026-11-15).
    private func olderPosts(_ count: Int, before start: String = "2026-09-01") -> [ContractPost] {
        (0..<count).map { i in
            let date = calendar.date(byAdding: .day, value: -i, to: day(start))!
            let c = calendar.dateComponents([.year, .month, .day], from: date)
            return post("old\(i)", saved: String(format: "%04d-%02d-%02d", c.year!, c.month!, c.day!))
        }.filter { !$0.savedAt!.hasSuffix("-11-15") }
    }

    // MARK: - Resurface

    @Test func anniversariesComeFirst() {
        let posts = olderPosts(40) + [post("anniv", saved: "2025-11-15"), post("anniv2", saved: "2023-11-15")]
        let picks = Resurface.picks(posts: posts, today: day("2026-11-15"), calendar: calendar)
        #expect(picks.map(\.post.id).prefix(2) == ["anniv", "anniv2"])
        #expect(picks[0].reason == .anniversary(years: 1))
        #expect(picks[0].reason.label == "Saved 1 year ago today")
        #expect(picks[1].reason == .anniversary(years: 3))
        #expect(picks.count == 3)
        if case .fromThePast = picks[2].reason {} else { Issue.record("third pick should be an older save") }
    }

    @Test func sameAllDayInAnyOrder() {
        let posts = olderPosts(60)
        let morning = Resurface.picks(posts: posts, today: day("2026-11-15"), calendar: calendar)
        let evening = Resurface.picks(posts: posts.reversed(), today: day("2026-11-15").addingTimeInterval(8 * 3600), calendar: calendar)
        #expect(morning.map(\.post.id) == evening.map(\.post.id))
        #expect(morning.count == 3)
    }

    @Test func differentOnOtherDays() {
        let posts = olderPosts(60)
        let days = ["2026-11-15", "2026-11-16", "2026-11-17", "2026-11-18"]
        let picks = days.map { Resurface.picks(posts: posts, today: day($0), calendar: calendar).map(\.post.id) }
        #expect(Set(picks).count > 1)
    }

    @Test func noDuplicatesAndLimitRespected() {
        let posts = olderPosts(5) + [post("anniv", saved: "2024-11-15"), post("new", saved: "2026-11-14")]
        for limit in [0, 1, 3, 7, 20] {
            let picks = Resurface.picks(posts: posts, today: day("2026-11-15"), calendar: calendar, limit: limit)
            #expect(picks.count == min(limit, posts.count))
            #expect(Set(picks.map(\.id)).count == picks.count)
        }
    }

    @Test func newestFillWhenNothingIsOld() {
        let posts = [post("a", saved: "2026-11-10"), post("b", saved: "2026-11-14"), post("c", saved: "2026-11-01")]
        let picks = Resurface.picks(posts: posts, today: day("2026-11-15"), calendar: calendar)
        #expect(picks.map(\.post.id) == ["b", "a", "c"])
        #expect(picks.allSatisfy { $0.reason == .new })
    }

    @Test func undatedSavesOnlyFillTheSeededSlots() {
        // An undated save is never an anniversary, but can come back as an older save.
        let posts = [post("undated"), post("anniv", saved: "2025-11-15")]
        let picks = Resurface.picks(posts: posts, today: day("2026-11-15"), calendar: calendar)
        #expect(picks.map(\.post.id) == ["anniv", "undated"])
        #expect(picks[1].reason == .fromThePast(months: nil))
        #expect(Resurface.picks(posts: [], today: day("2026-11-15"), calendar: calendar).isEmpty)
    }

    @Test func reasonLabels() {
        #expect(Resurface.Reason.anniversary(years: 2).label == "Saved 2 years ago today")
        #expect(Resurface.Reason.fromThePast(months: 8).label == "From 8 months ago")
        #expect(Resurface.Reason.fromThePast(months: 1).label == "From 1 month ago")
        #expect(Resurface.Reason.fromThePast(months: 25).label == "From 2 years ago")
        #expect(Resurface.Reason.new.label == "New")
    }

    // MARK: - HomeTopics

    private func data(_ topics: [ContractTopic], posts: [ContractPost]) -> HindsightData {
        HindsightData(file: ContractFile(contractVersion: ContractFile.supportedVersion, generatedAt: nil,
                                         user: ContractUser(handle: "me", platforms: ["instagram"]),
                                         posts: posts, topics: topics, items: []))
    }

    @Test func aiTopicsAndCollectionsByCountWithSmallOnesFolded() {
        let posts = (0..<20).map { i in
            post("p\(i)", collections: i < 6 ? ["NYC Restaurants"] : i < 10 ? ["Recipes"] : i < 11 ? ["Tiny"] : [])
        }
        let ids = posts.map(\.id)
        let topics = [
            ContractTopic(id: "nyc-food", label: "NYC food", emoji: "🍜", legoScreen: .map, postIds: Array(ids[0..<6]),
                          sourceCollections: ["NYC Restaurants"]),
            ContractTopic(id: "memes", label: "Memes", legoScreen: nil, postIds: Array(ids[6..<15])),
            ContractTopic(id: "guitar", label: "Guitar", legoScreen: .learn, postIds: Array(ids[15..<17])),
            ContractTopic(id: SortEngine.unsortedTopicID, label: "Unsorted", legoScreen: nil, postIds: Array(ids[17..<20])),
        ]
        let home = HomeTopics.build(data: data(topics, posts: posts), posts: posts)
        // Memes 9, NYC food 6, Recipes 4 (a collection no topic covers), then Other: Guitar 2 + Tiny 1.
        #expect(home.map(\.label) == ["Memes", "NYC food", "Recipes", "Other"])
        #expect(home.map(\.count) == [9, 6, 4, 3])
        #expect(home.map(\.kind) == [.ai, .ai, .collection, .other])
        #expect(home[0].legoScreen == nil)                                   // a topic without a view is a normal topic
        #expect(home[1].legoScreen == .map)
        #expect(home[1].topicID == "nyc-food")
        #expect(home[1].emoji == "🍜")
        #expect(home[2].id == "collection:recipes")
        #expect(!home.contains { $0.topicID == SortEngine.unsortedTopicID }) // not sorted yet: only in Recent
        #expect(!home.contains { $0.label == "NYC Restaurants" })           // already a topic
        #expect(Set(home[3].postIDs) == ["p15", "p16", "p10"])
        #expect(home[3].postIDs == ["p10", "p15", "p16"])                    // in the saves' order
    }

    @Test func collectionsAloneBeforeSorting() {
        let posts = (0..<5).map { post("p\($0)", collections: ["Saved", "Trips"]) }
        let home = HomeTopics.build(data: nil, posts: posts)
        #expect(home.map(\.label) == ["Trips"])   // "Saved" is a default folder, not the user's
        #expect(home[0].count == 5)
        #expect(HomeTopics.build(data: nil, posts: []).isEmpty)
    }

    @Test func ties() {
        let posts = (0..<6).map { post("p\($0)", collections: [$0 < 3 ? "Beta" : "Alpha"]) }
        #expect(HomeTopics.build(data: nil, posts: posts).map(\.label) == ["Alpha", "Beta"])
    }

    @Test func theSorterNamedOtherJoinsOurOther() {
        let posts = (0..<8).map { post("p\($0)") }
        let ids = posts.map(\.id)
        let topics = [
            ContractTopic(id: "memes", label: "Memes", legoScreen: nil, postIds: Array(ids[0..<4])),
            ContractTopic(id: "other", label: "Other", legoScreen: nil, postIds: Array(ids[4..<8])),
        ]
        let home = HomeTopics.build(data: data(topics, posts: posts), posts: posts)
        #expect(home.map(\.label) == ["Memes", "Other"])
        #expect(home.map(\.kind) == [.ai, .other])
    }

    @Test func samplesHaveATopicForEverySave() throws {
        for id in ["reut", "ariel"] {
            let data = try Fixtures.load(id)
            let home = HomeTopics.build(data: data, posts: data.posts)
            let covered = Set(home.flatMap(\.postIDs))
            #expect(data.posts.allSatisfy { covered.contains($0.id) })
            #expect(home.contains { $0.kind == .ai && $0.legoScreen == nil })   // memes, ads…
        }
        let data = try Fixtures.load("reut")
        let home = HomeTopics.build(data: data, posts: data.posts)
        #expect(home.last?.kind == .other)
        #expect(home.dropLast().map(\.count) == home.dropLast().map(\.count).sorted(by: >))
    }

    // MARK: - No setup screen

    @Test func sampleDataGetsTheNaturalLayoutRightAway() {
        let app = AppModel(datasets: Dataset.bundled(), selected: "reut", persist: false)
        #expect(app.setupDone)
        #expect(app.layout?.tabs.map(\.legoScreen) == [.map, .learn])
        #expect(app.tab(for: .map).title == "Places")
        #expect(app.allPosts.count == 324)
    }
}

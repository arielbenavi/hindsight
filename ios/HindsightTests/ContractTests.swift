import Foundation
import Testing
@testable import Hindsight

@MainActor
enum Fixtures {
    static func load(_ id: String) throws -> HindsightData {
        let dataset = try #require(Dataset.bundled().first { $0.id == id })
        return try HindsightData.load(from: dataset.url)
    }
}

@MainActor
struct ContractTests {
    @Test func bothFixturesAreBundledAndDecode() throws {
        let ids = Dataset.bundled().map(\.id)
        #expect(ids.contains("reut"))
        #expect(ids.contains("ariel"))
        let reut = try Fixtures.load("reut")
        let ariel = try Fixtures.load("ariel")
        #expect(reut.posts.count == 324)
        #expect(ariel.posts.count == 1216)
        #expect(reut.file.contractVersion == ContractFile.supportedVersion)
    }

    @Test func everyPostIsInOneTopicAndItemsMatchTheirTopic() throws {
        for id in ["reut", "ariel"] {
            let data = try Fixtures.load(id)
            for post in data.posts { #expect(data.topic(forPost: post.id) != nil) }
            for item in data.file.items {
                #expect(data.topic(item.topicId)?.legoScreen == item.legoScreen)
            }
        }
    }

    @Test func noneTopicsAreEverythingElse() throws {
        let data = try Fixtures.load("reut")
        let noneCount = data.topics.filter { $0.legoScreen == nil }.reduce(0) { $0 + $1.postIds.count }
        #expect(data.everythingElse(layout: nil).count == noneCount)
    }

    @Test func decodesTheContractExample() throws {
        let json = """
        {"contract_version":1,"user":{"handle":"x","platforms":["instagram"]},
         "posts":[{"id":"instagram:A","platform":"instagram","url":"https://www.instagram.com/reel/A/","kind":"reel",
           "author":{"username":"a","display_name":null},"caption":"📍 Salt Hank's","hashtags":[],"mentions":[],
           "collections":["NYC Restaurants"],"saved_at":"2025-08-17","posted_at":null,"thumbnail_url":null,
           "location_tag":null,"language":"en","on_screen_text":null,"transcript":null,"source":"ig_export","extra":1}],
         "topics":[{"id":"nyc","label":"NYC","emoji":null,"lego_screen":"map","confidence":"high","post_ids":["instagram:A"],
           "sample_post_ids":["instagram:A"],"source_collections":[],"ambiguity":null}],
         "items":[{"post_id":"instagram:A","lego_screen":"map","topic_id":"nyc","places":[{"name":"Salt Hank's","handle":null,
           "area_hint":"Greenwich Village, New York","address":null,"type":"food","reason":null,
           "evidence":"📍 Salt Hank's","evidence_kind":"pin_emoji","confidence":"high"}]}]}
        """
        let data = HindsightData(file: try ContractFile.decode(Data(json.utf8)))
        let place = try #require(data.item(for: "instagram:A")?.places?.first)
        #expect(place.evidenceKind == .pinEmoji)
        #expect(place.areaHint == "Greenwich Village, New York")
        // date-only strings are local midnight (LESSONS)
        let saved = try #require(data.post("instagram:A")?.savedDate)
        #expect(Calendar.current.component(.day, from: saved) == 17)
    }
}

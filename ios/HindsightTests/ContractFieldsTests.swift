import Foundation
import Testing
@testable import Hindsight

/// docs/data-contract.md `posts[]` fields on SavedPost.
struct ContractFieldsTests {
    private let repoRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

    @Test func hashtagsAndMentionsComeFromTheCaption() {
        let post = SavedPost(
            url: URL(string: "https://www.instagram.com/reel/ABC/")!, kind: .reel, author: "a",
            caption: "Best meatball hero @capponesnyc in the West Village 📍 #NYCfood #nycfood #eats email me: a@b.com",
            source: .muse
        )
        #expect(post.hashtags == ["nycfood", "eats"])
        #expect(post.mentions.map(\.username) == ["capponesnyc"])
    }

    @Test func parsesTheContractJSONShape() throws {
        let text = """
        ```json
        [{"platform": "instagram", "url": "https://www.instagram.com/reel/C1/", "kind": "reel",
          "author": {"username": "elizabethfowlerx", "display_name": "Liz"},
          "caption": "Top 3 sandwich 📍 Salt Hank's (Greenwich Village, NYC) #nycfood",
          "mentions": [{"username": "salthanks", "display_name": "Salt Hank's"}],
          "collections": ["NYC Restaurants"], "saved_at": "2025-08-17T20:12:00Z", "posted_at": "2025-08-01",
          "thumbnail_url": null, "location_tag": {"name": "Salt Hank's", "address": null, "lat": 40.73, "lng": -74.0}}]
        ```
        """
        let post = try #require(SavedPostParser.parse(text).posts.first)
        #expect(post.author == "elizabethfowlerx")
        #expect(post.authorDisplayName == "Liz")
        #expect(post.collections == ["NYC Restaurants"])
        #expect(post.mentions == [SavedPost.Mention(username: "salthanks", displayName: "Salt Hank's")])
        #expect(post.hashtags == ["nycfood"])
        #expect(post.savedAt == (try Date("2025-08-17T20:12:00Z", strategy: .iso8601)))
        #expect(post.postedAt != nil)
        #expect(post.thumbnailURL == nil)
        #expect(post.locationTag?.lat == 40.73)
        #expect(post.source == .muse)
    }

    @Test func legacyStoredPostsStillDecode() throws {
        let old = """
        [{"id": "instagram:DdwJgsNABze", "platform": "instagram", "author": "evolving.ai", "kind": "post",
          "date": 780537600, "caption": "hi #ai", "url": "https://www.instagram.com/p/DdwJgsNABze/"}]
        """
        let post = try #require(try JSONDecoder().decode([SavedPost].self, from: Data(old.utf8)).first)
        #expect(post.savedAt == Date(timeIntervalSinceReferenceDate: 780537600))
        #expect(post.hashtags == ["ai"])
        #expect(post.collections.isEmpty)
        #expect(post.source == .seedMD)
    }

    @Test func mergeFillsGapsWithoutDuplicating() {
        let url = URL(string: "https://www.instagram.com/reel/XYZ/")!
        let seed = SavedPost(url: url, kind: .reel, author: "chef", caption: "Pasta night…", source: .seedMD)
        let export = SavedPost(url: url, kind: .reel, author: "chef", authorDisplayName: "The Chef",
                               caption: "Pasta night at @lilia in Williamsburg #pasta", collections: ["NYC"],
                               savedAt: .now, source: .igExport)
        let merged = seed.filling(from: export)
        #expect(merged.caption == export.caption)
        #expect(merged.collections == ["NYC"])
        #expect(merged.authorDisplayName == "The Chef")
        #expect(merged.mentions.map(\.username) == ["lilia"])
        // Changed 2026-09-30 (all/merge, needs Ariel's OK): a real import of a seed
        // post makes it the user's, so the sort engine (which skips the seed) keeps it.
        #expect(merged.source == .igExport)
    }

    @Test @MainActor func storeMergeUpdatesKnownPosts() {
        let url = URL(string: "https://www.instagram.com/reel/XYZ/")!
        let store = SavedPostStore(fileURL: nil, seed: {
            [SavedPost(url: url, kind: .reel, author: "chef", caption: "short", source: .seedMD)]
        })
        let added = store.merge([SavedPost(url: url, kind: .reel, author: "chef", caption: "a much longer caption",
                                           collections: ["NYC"], source: .igExport)])
        #expect(added == 0)
        #expect(store.posts.count == 1)
        #expect(store.posts[0].caption == "a much longer caption")
        #expect(store.posts[0].collections == ["NYC"])
    }

    @Test func reutsInstagramExport() throws {
        let dir = repoRoot.appending(path: "data/ig-reut-export")
        let posts = try ["saved_posts.json", "saved_collections.json"].flatMap {
            DataExportParser.parse(json: try Data(contentsOf: dir.appending(path: $0)))
        }
        let combined = DataExportParser.combined(posts)
        #expect(combined.count == 324)
        #expect(combined.allSatisfy { $0.platform == .instagram && $0.source == .igExport })
        #expect(combined.count { $0.savedAt != nil } == 113)
        #expect(combined.count { !$0.collections.isEmpty } >= 250)
        #expect(combined.contains { $0.collections.contains("NYC Restaurants") })
        // Instagram's Latin-1 escaping is undone: no "â\u{80}" sequences left.
        #expect(!combined.contains { $0.caption?.contains("\u{00E2}\u{0080}") == true })
    }
}

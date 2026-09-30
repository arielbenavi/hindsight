import Foundation
import Testing
@testable import Hindsight

struct SavedPostParserTests {
    @Test func parsesTheWholeSeed() throws {
        let result = SavedPostParser.parse(try #require(SeedData.markdown()))
        #expect(result.posts.count == 1216)
        #expect(result.skipped == 0)
        #expect(result.posts.count { $0.kind == .reel } == 792)
        #expect(result.posts.count { $0.kind == .post } == 424)
        #expect(Set(result.posts.map(\.id)).count == 1216)
        #expect(result.posts.allSatisfy { $0.platform == .instagram })
    }

    @Test func parsesSeedEntryFields() throws {
        let post = try #require(SeedData.posts().dropFirst().first)
        #expect(post.id == "instagram:DdwJgsNABze")
        #expect(post.author == "evolving.ai")
        #expect(post.kind == .post)
        #expect(post.caption?.hasPrefix("Claude Opus 5.5") == true)
        let day = post.date.map { Calendar.current.dateComponents([.year, .month, .day], from: $0) }
        #expect(day == DateComponents(year: 2026, month: 9, day: 26))
    }

    @Test func markdownWithoutBoldOrCaption() {
        let text = """
        1. @macro_quant_rick · reel · 2026-07-15
           https://www.instagram.com/reel/Da0WC0FN1lF/

        2. **@someone** · carousel · 2026-07-14
           first line
           second line
           https://www.instagram.com/p/ABC123/
        """
        let posts = SavedPostParser.parse(text).posts
        #expect(posts.count == 2)
        #expect(posts[0].caption == nil)
        #expect(posts[0].author == "macro_quant_rick")
        #expect(posts[1].kind == .carousel)
        #expect(posts[1].caption == "first line second line")
    }

    @Test func markdownEntryWithoutURLIsSkipped() {
        let result = SavedPostParser.parse("1. **@a** · reel · 2026-01-01\n   just a caption\n")
        #expect(result.posts.isEmpty)
        #expect(result.skipped == 1)
    }

    @Test func parsesFencedJSON() {
        let text = """
        Here are your saved posts:
        ```json
        [
          {"platform": "facebook", "author": "@chef", "kind": "video", "date": "2026-09-28",
           "caption": "Pasta", "url": "https://www.facebook.com/reel/123456/"},
          {"platform": "instagram", "author": "x", "kind": "reel", "url": "https://www.instagram.com/reel/XYZ/"},
          {"author": "no url"}
        ]
        ```
        """
        let result = SavedPostParser.parse(text)
        #expect(result.posts.count == 2)
        #expect(result.skipped == 1)
        #expect(result.posts[0].platform == .facebook)
        #expect(result.posts[0].author == "chef")
        #expect(result.posts[0].id == "facebook:123456")
        #expect(result.posts[1].date == nil)
        #expect(result.posts.allSatisfy { $0.source == .muse })
    }

    @Test func junkDoesNotCrash() {
        #expect(SavedPostParser.parse("").posts.isEmpty)
        #expect(SavedPostParser.parse("[not json").posts.isEmpty)
        #expect(SavedPostParser.parse("hello\n1. nope").posts.isEmpty)
    }
}

@MainActor
struct SavedPostStoreTests {
    private func post(_ code: String) -> SavedPost {
        SavedPost(url: URL(string: "https://www.instagram.com/reel/\(code)/")!, kind: .reel,
                  author: "a", caption: nil, source: .seedMD)
    }

    @Test func mergeSkipsDuplicates() {
        let store = SavedPostStore(fileURL: nil, seed: { [post("A"), post("B"), post("A")] })
        #expect(store.posts.count == 2)
        #expect(store.merge([post("B"), post("C"), post("C")]) == 1)
        #expect(store.posts.map(\.id) == ["instagram:C", "instagram:A", "instagram:B"])
    }

    @Test func persistsAcrossInstances() throws {
        let file = URL.temporaryDirectory.appending(path: "store-\(UUID()).json")
        defer { try? FileManager.default.removeItem(at: file) }
        let first = SavedPostStore(fileURL: file, seed: { [post("A")] })
        first.merge([post("B")])
        let second = SavedPostStore(fileURL: file, seed: { [] })
        #expect(second.posts.map(\.id) == ["instagram:B", "instagram:A"])
    }
}

import Foundation
import Testing
@testable import Hindsight

struct XTests {
    @Test func pkceChallengeIsBase64URLSHA256() {
        // Expected value computed independently:
        // base64.urlsafe_b64encode(hashlib.sha256(v.encode()).digest()).rstrip(b"=")
        #expect(XAuth.PKCE.challenge(for: "dBjftJeZ4CVP-mJ92K9sUNnm1g2VrO6I1mEfL1ErbcM")
                == "huohBW6uB-U2WadAFmJCvIAJgs7YgNHYH1khuC8Xdv8")
        let pkce = XAuth.PKCE.make()
        #expect(pkce.verifier.count >= 43)
        #expect(!pkce.verifier.contains("=") && !pkce.verifier.contains("+"))
    }

    @Test func authorizeURLCarriesPKCE() throws {
        let pkce = XAuth.PKCE(verifier: "v", challenge: "c", state: "s")
        let items = URLComponents(url: XAuth.authorizeURL(pkce: pkce), resolvingAgainstBaseURL: false)?.queryItems ?? []
        let query = Dictionary(uniqueKeysWithValues: items.map { ($0.name, $0.value ?? "") })
        #expect(query["code_challenge"] == "c")
        #expect(query["code_challenge_method"] == "S256")
        #expect(query["redirect_uri"] == "hindsight://oauth/x")
        #expect(query["scope"]?.contains("bookmark.read") == true)
    }

    @Test func callbackStateIsChecked() throws {
        let pkce = XAuth.PKCE(verifier: "v", challenge: "c", state: "good")
        #expect(try XAuth.code(from: URL(string: "hindsight://oauth/x?state=good&code=abc")!, pkce: pkce) == "abc")
        #expect(throws: XAuth.AuthError.self) {
            try XAuth.code(from: URL(string: "hindsight://oauth/x?state=evil&code=abc")!, pkce: pkce)
        }
    }

    @Test func bookmarksPageMapsToPosts() throws {
        let json = """
        {"data": [
          {"id": "1830000000000000001", "text": "RL from scratch 🧵", "created_at": "2026-09-01T12:30:00.000Z", "author_id": "9"},
          {"id": "1830000000000000002", "text": "no author", "author_id": "404"}
        ],
         "includes": {"users": [{"id": "9", "username": "karpathy", "name": "Andrej"}]},
         "meta": {"result_count": 2, "next_token": "abc"}}
        """
        let page = try JSONDecoder().decode(XBookmarks.BookmarksPage.self, from: Data(json.utf8))
        let posts = XBookmarks.posts(from: page)
        #expect(posts.count == 2)
        #expect(posts[0].id == "x:1830000000000000001")
        #expect(posts[0].author == "karpathy")
        #expect(posts[0].url.absoluteString == "https://x.com/karpathy/status/1830000000000000001")
        #expect(posts[0].kind == .tweet)
        #expect(posts[0].date != nil)
        #expect(posts[1].author == "")
        #expect(posts[1].url.absoluteString == "https://x.com/i/status/1830000000000000002")
    }
}

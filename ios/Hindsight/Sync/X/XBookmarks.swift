import Foundation

/// Reads the signed-in user's bookmarks (GET /2/users/:id/bookmarks).
/// Pay-per-use: about $0.001 per bookmark read, billed to hindsight's X account.
enum XBookmarks {
    /// X returns at most 800 bookmarks (8 pages of 100).
    static let maxPages = 8

    static func fetchAll(accessToken: String) async throws -> [SavedPost] {
        let me: MeResponse = try await get("https://api.x.com/2/users/me", token: accessToken)
        var posts: [SavedPost] = []
        var nextToken: String?
        for _ in 0..<maxPages {
            var components = URLComponents(string: "https://api.x.com/2/users/\(me.data.id)/bookmarks")!
            components.queryItems = [
                .init(name: "max_results", value: "100"),
                .init(name: "tweet.fields", value: "created_at,author_id"),
                .init(name: "expansions", value: "author_id"),
                .init(name: "user.fields", value: "username"),
            ] + (nextToken.map { [.init(name: "pagination_token", value: $0)] } ?? [])
            let page: BookmarksPage = try await get(components.url!.absoluteString, token: accessToken)
            posts += Self.posts(from: page)
            DebugLog.write("x bookmarks page: \(page.data?.count ?? 0), next=\(page.meta?.next_token != nil)")
            guard let token = page.meta?.next_token else { break }
            nextToken = token
        }
        return posts
    }

    // MARK: - Mapping (pure, tested with fixtures)

    struct BookmarksPage: Decodable {
        struct Tweet: Decodable { let id: String; let text: String; let created_at: String?; let author_id: String? }
        struct User: Decodable { let id: String; let username: String }
        struct Includes: Decodable { let users: [User]? }
        struct Meta: Decodable { let next_token: String? }
        let data: [Tweet]?
        let includes: Includes?
        let meta: Meta?
    }

    struct MeResponse: Decodable {
        struct User: Decodable { let id: String }
        let data: User
    }

    static func posts(from page: BookmarksPage) -> [SavedPost] {
        let usernames = Dictionary(
            (page.includes?.users ?? []).map { ($0.id, $0.username) },
            uniquingKeysWith: { first, _ in first }
        )
        return (page.data ?? []).compactMap { tweet in
            let username = tweet.author_id.flatMap { usernames[$0] } ?? "i"
            guard let url = URL(string: "https://x.com/\(username)/status/\(tweet.id)") else { return nil }
            return SavedPost(
                platform: .x,
                url: url,
                kind: .tweet,
                author: username == "i" ? "" : username,
                caption: tweet.text,
                // X doesn't expose when it was bookmarked, only when it was posted.
                postedAt: tweet.created_at.flatMap { try? Date($0, strategy: .iso8601.year().month().day().time(includingFractionalSeconds: true)) },
                source: .xAPI
            )
        }
    }

    // MARK: - HTTP

    enum APIError: LocalizedError {
        case status(Int, String)
        var errorDescription: String? {
            switch self {
            case .status(401, _): "X sign-in expired. Connect again."
            case .status(429, _): "X is rate-limiting us. Try again in a few minutes."
            case .status(let code, let body): "X error \(code): \(body)"
            }
        }
    }

    private static func get<T: Decodable>(_ url: String, token: String) async throws -> T {
        var request = URLRequest(url: URL(string: url)!)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 else {
            throw APIError.status(status, String(decoding: data.prefix(300), as: UTF8.self))
        }
        return try JSONDecoder().decode(T.self, from: data)
    }
}

import Foundation

/// A decoded contract file, indexed for the screens. Immutable; user state lives
/// in separate stores so replacing the file never wipes it.
struct HindsightData: Sendable {
    let file: ContractFile
    let postsByID: [String: ContractPost]
    let topicsByID: [String: ContractTopic]
    let itemsByPostID: [String: ContractItem]
    let topicIDByPostID: [String: String]

    init(file: ContractFile) {
        self.file = file
        postsByID = Dictionary(file.posts.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        topicsByID = Dictionary(file.topics.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        itemsByPostID = Dictionary(file.items.map { ($0.postId, $0) }, uniquingKeysWith: { first, _ in first })
        var topicByPost: [String: String] = [:]
        for topic in file.topics {
            for id in topic.postIds where topicByPost[id] == nil { topicByPost[id] = topic.id }
        }
        topicIDByPostID = topicByPost
    }

    var posts: [ContractPost] { file.posts }
    var topics: [ContractTopic] { file.topics }

    func post(_ id: String) -> ContractPost? { postsByID[id] }
    func topic(_ id: String) -> ContractTopic? { topicsByID[id] }
    func item(for postID: String) -> ContractItem? { itemsByPostID[postID] }
    func topic(forPost postID: String) -> ContractTopic? { topicIDByPostID[postID].flatMap { topicsByID[$0] } }

    /// Posts of the given topics, in file order (newest saved first).
    func posts(inTopics ids: some Collection<String>) -> [ContractPost] {
        let wanted = Set(ids)
        return posts.filter { topicIDByPostID[$0.id].map(wanted.contains) ?? false }
    }

    /// Saves that don't show in any tab: `none` topics, topics not placed in the
    /// layout, and posts with no topic. Newest first.
    func everythingElse(layout: LayoutConfig?) -> [ContractPost] {
        let shown = Set(layout?.tabs.flatMap(\.topicIDs) ?? topics.filter { $0.legoScreen != nil }.map(\.id))
        return posts.filter { post in
            guard let topicID = topicIDByPostID[post.id] else { return true }
            return !shown.contains(topicID)
        }
    }

    static func load(from url: URL) throws -> HindsightData {
        HindsightData(file: try ContractFile.decode(Data(contentsOf: url)))
    }
}

/// A bundled dataset (one per tester): `data/fixtures/<id>.hindsight.json`.
struct Dataset: Identifiable, Hashable, Sendable {
    let id: String
    let url: URL

    var displayName: String { isMine ? "My saves" : id.prefix(1).uppercased() + id.dropFirst() }

    /// The user's own saves, sorted on the phone (Pipeline/SortEngine).
    static let mineID = "me"
    var isMine: Bool { id == Self.mineID }

    /// `Application Support/Hindsight/me/hindsight.json`; may not exist yet.
    static func mine() -> Dataset {
        let directory = URL.applicationSupportDirectory.appending(path: "Hindsight/\(mineID)", directoryHint: .isDirectory)
        return Dataset(id: mineID, url: directory.appending(path: "hindsight.json"))
    }

    static let suffix = ".hindsight.json"

    static func bundled(in bundle: Bundle = .main) -> [Dataset] {
        let urls = (bundle.urls(forResourcesWithExtension: "json", subdirectory: nil) ?? [])
            .filter { $0.lastPathComponent.hasSuffix(suffix) }
        return urls.map { Dataset(id: String($0.lastPathComponent.dropLast(suffix.count)), url: $0) }
            .sorted { $0.id < $1.id }
    }
}

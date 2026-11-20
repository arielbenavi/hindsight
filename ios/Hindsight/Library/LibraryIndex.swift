import Foundation

/// The Library as the user sees it: `HomeTopics` with the user's moves applied,
/// each topic's job (theirs, else the suggested one), and which topic a save is in.
/// Pure (main actor only because `HomeTopics` is).
@MainActor
struct LibraryIndex {
    let topics: [HomeTopic]
    let jobs: [String: TopicJob]
    /// Post id → the first topic it's in (Other last).
    let topicByPost: [String: HomeTopic]

    init(data: HindsightData?, posts: [ContractPost], prefs: TopicPrefsStore.Prefs) {
        let built = HomeTopics.build(data: data, posts: posts)
        topics = Self.applyMoves(built, moves: prefs.moves, order: posts)
        var jobs: [String: TopicJob] = [:]
        for topic in topics { jobs[topic.id] = prefs.jobs[topic.id] ?? TopicJobs.suggested(for: topic) }
        self.jobs = jobs
        var byPost: [String: HomeTopic] = [:]
        // Real topics first, so a save in a topic and in "Other" counts as the topic's.
        for topic in topics.sorted(by: { ($0.kind == .other ? 1 : 0) < ($1.kind == .other ? 1 : 0) }) {
            for id in topic.postIDs where byPost[id] == nil { byPost[id] = topic }
        }
        topicByPost = byPost
    }

    func job(_ topic: HomeTopic) -> TopicJob { jobs[topic.id] ?? TopicJobs.suggested(for: topic) }
    func topic(_ id: String) -> HomeTopic? { topics.first { $0.id == id } }

    /// The job behind a save (its topic's), nil when it has no topic yet.
    func job(forPost id: String) -> TopicJob? { topicByPost[id].map(job) }

    /// The topics doing `job`, biggest first ("Other" is never in a job section).
    func topics(doing job: TopicJob) -> [HomeTopic] {
        topics.filter { $0.kind != .other && self.job($0) == job }
    }

    var other: HomeTopic? { topics.first { $0.kind == .other } }

    /// Moved saves leave every topic they were in and join their new one (kept in
    /// the saves' order). A move to a topic that's gone is ignored.
    static func applyMoves(_ topics: [HomeTopic], moves: [String: String], order posts: [ContractPost]) -> [HomeTopic] {
        let ids = Set(topics.map(\.id))
        let valid = moves.filter { ids.contains($0.value) }
        guard !valid.isEmpty else { return topics }
        let rank = Dictionary(posts.enumerated().map { ($1.id, $0) }, uniquingKeysWith: { first, _ in first })
        return topics.map { topic in
            var t = topic
            var postIDs = t.postIDs.filter { valid[$0] == nil }
            let incoming = valid.filter { $0.value == t.id }.keys.filter { rank[$0] != nil }
            if !incoming.isEmpty {
                postIDs = Array(Set(postIDs + incoming)).sorted { (rank[$0] ?? .max, $0) < (rank[$1] ?? .max, $1) }
            }
            t.postIDs = postIDs
            return t
        }
    }
}

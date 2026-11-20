import Foundation

/// One entry in Home's Topics: an AI topic, one of the user's own collections
/// (Instagram collections, WhatsApp chat names), or "Other" for the small ones.
struct HomeTopic: Identifiable, Hashable, Sendable {
    enum Kind: Hashable, Sendable { case ai, collection, other }

    /// "ai:<topic id>", "collection:<name>" or "other". Stable across launches.
    var id: String
    var label: String
    var emoji: String?
    /// SF Symbol stand-in (the simulator can't draw emoji; LESSONS.md).
    var symbol: String
    /// Newest saved first.
    var postIDs: [String]
    /// The view that fits this topic's saves (map/learn/fitness), if any.
    var legoScreen: LegoScreen?
    var kind: Kind
    /// The AI topic behind it, for opening a view scoped to it.
    var topicID: String?

    var count: Int { postIDs.count }
}

/// Builds Home's Topics from the sorted file (if any) and the saves. Every AI topic
/// shows, with or without a view (`legoScreen` nil: memes, fashion, …); only
/// "Unsorted" (posts not sorted yet) is left out, since Recent already has them.
/// Pure (main actor only because `SortEngine.unsortedTopicID` is).
@MainActor
enum HomeTopics {
    /// Topics smaller than this fold into "Other".
    static let minimumSize = 3
    static let otherID = "other"
    /// Default folders some sources report as collections; they say nothing.
    static let genericCollections = TopicFallback.genericCollections

    /// The view's symbol, a lexicon topic's (`TopicFallback`), or a folder for a
    /// topic named after the user's own collection.
    private static func symbol(for topic: ContractTopic) -> String {
        if let symbol = topic.legoScreen?.symbol ?? TopicFallback.symbol(forLabel: topic.label) { return symbol }
        let label = TextMatch.fold(topic.label)
        return topic.sourceCollections.contains { TextMatch.fold($0) == label } ? "folder.fill" : "sparkles"
    }

    static func build(data: HindsightData?, posts: [ContractPost]) -> [HomeTopic] {
        let order = Dictionary(posts.enumerated().map { ($1.id, $0) }, uniquingKeysWith: { first, _ in first })
        func newestFirst(_ ids: some Sequence<String>) -> [String] {
            Array(Set(ids)).filter { order[$0] != nil }.sorted { order[$0]! < order[$1]! }
        }

        var topics: [HomeTopic] = []
        var represented: Set<String> = []
        for topic in data?.topics ?? [] where topic.id != SortEngine.unsortedTopicID {
            let ids = newestFirst(topic.postIds)
            guard !ids.isEmpty else { continue }
            represented.insert(TextMatch.fold(topic.label))
            topic.sourceCollections.forEach { represented.insert(TextMatch.fold($0)) }
            topics.append(HomeTopic(id: "ai:\(topic.id)", label: topic.label, emoji: topic.emoji,
                                    symbol: Self.symbol(for: topic), postIDs: ids,
                                    legoScreen: topic.legoScreen, kind: .ai, topicID: topic.id))
        }

        var byCollection: [String: [String]] = [:]
        var names: [String: String] = [:]
        for post in posts {
            for name in post.collections {
                let key = TextMatch.fold(name.trimmingCharacters(in: .whitespacesAndNewlines))
                guard !key.isEmpty, !genericCollections.contains(key), !represented.contains(key) else { continue }
                byCollection[key, default: []].append(post.id)
                if names[key] == nil { names[key] = name.trimmingCharacters(in: .whitespacesAndNewlines) }
            }
        }
        for (key, ids) in byCollection {
            topics.append(HomeTopic(id: "collection:\(key)", label: names[key] ?? key, emoji: nil, symbol: "folder.fill",
                                    postIDs: newestFirst(ids), legoScreen: nil, kind: .collection, topicID: nil))
        }

        // A topic the sorter itself called "Other" (its fallback) joins ours.
        let foldsIntoOther = { (t: HomeTopic) in t.count < minimumSize || TextMatch.fold(t.label) == otherID }
        let big = topics.filter { !foldsIntoOther($0) }
            .sorted { ($1.count, $0.label) < ($0.count, $1.label) }
        let small = topics.filter(foldsIntoOther)
        guard !small.isEmpty else { return big }
        let other = HomeTopic(id: otherID, label: "Other", emoji: nil, symbol: "ellipsis.circle.fill",
                              postIDs: newestFirst(small.flatMap(\.postIDs)), legoScreen: nil, kind: .other, topicID: nil)
        return big + [other]
    }
}

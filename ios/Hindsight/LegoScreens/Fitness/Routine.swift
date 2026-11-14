import Foundation

/// A Fitness routine: one saved post (1+ exercises). Read-only; the user's side
/// lives in `PracticeState` and `RegularSchedule`.
struct Routine: Identifiable, Hashable, Sendable {
    var id: String { post.id }
    var post: ContractPost
    var topicID: String
    var info: ExtractedRoutine

    var title: String { info.title }
    var primaryArea: BodyArea { info.bodyAreas.first ?? .fullBody }

    /// The card's prompt: the "Suggested" do prompt, or follow-along for thin posts.
    var prompt: String {
        if !info.isThin, let p = info.doPrompt { return p }
        return "Follow along with this reel (~\(info.estMinutes ?? 1) min)"
    }

    var isFollowAlong: Bool { info.isThin || info.doPrompt == nil }
    var minutesLabel: String? { info.estMinutes.map { "~\($0) min" } }
    static let safetyNote = "Gentle does it. Stop if it hurts."
}

/// Everything in the Fitness tab.
struct FitnessCatalog: Sendable {
    var routines: [Routine]
    var byID: [String: Routine]

    init(data: HindsightData, topicIDs: [String]) {
        var list: [Routine] = []
        for id in topicIDs {
            guard let topic = data.topic(id) else { continue }
            for pid in topic.postIds {
                guard let post = data.post(pid) else { continue }
                if let info = data.item(for: pid)?.routine {
                    list.append(Routine(post: post, topicID: id, info: info))
                } else if let tip = data.item(for: pid)?.tip {
                    // A Learn topic moved into Fitness: keep it usable as a follow-along.
                    list.append(Routine(post: post, topicID: id, info: ExtractedRoutine(
                        title: String(tip.title.prefix(40)), bodyAreas: [.fullBody], goal: .mobility, isThin: true)))
                }
            }
        }
        routines = list
        byID = Dictionary(uniqueKeysWithValues: list.map { ($0.id, $0) })
    }

    var candidates: [PracticeCandidate] {
        routines.map { PracticeCandidate(id: $0.id, topicKey: $0.primaryArea.rawValue, isPickable: true) }
    }

    /// Areas that have at least one routine, with counts, biggest first (never empty tiles).
    var areas: [(area: BodyArea, count: Int)] {
        let counts = Dictionary(routines.flatMap(\.info.bodyAreas).map { ($0, 1) }, uniquingKeysWith: +)
        return BodyArea.allCases.compactMap { a in counts[a].map { (a, $0) } }.sorted { $0.count > $1.count }
    }

    func routines(in area: BodyArea) -> [Routine] { routines.filter { $0.info.bodyAreas.contains(area) } }
}

/// F6: plain-language problem search through a fixed synonym table, plus text search. Pure.
enum ProblemSearch {
    struct Hit: Equatable { var areas: Set<BodyArea>; var goal: FitnessGoal? }

    /// Phrase → body areas + goal. Longest phrases are checked first.
    static let synonyms: [(phrases: [String], areas: Set<BodyArea>, goal: FitnessGoal?)] = [
        (["lower back pain", "back hurts", "back pain", "sciatica", "low back", "lower back", "lumbar"], [.lowerBack], .painRelief),
        (["stiff neck", "tech neck", "neck pain", "neck"], [.neck], nil),
        (["desk posture", "hunched", "posture", "rounded shoulders"], [.upperBack], .posture),
        (["upper back", "thoracic", "shoulder blades", "knot"], [.upperBack], nil),
        (["tight hips", "hip flexors", "hips", "hip"], [.hips], .mobility),
        (["shoulder", "shoulders", "rotator cuff"], [.shoulders], nil),
        (["knee", "knees"], [.knees], nil),
        (["ankle", "ankles"], [.ankles], nil),
        (["abs", "core", "six pack", "plank"], [.core], nil),
        (["mobility", "stiff", "stiffness", "flexibility"], [], .mobility),
        (["strength", "muscle", "stronger"], [], .strength),
        (["recovery", "sore"], [], .recovery),
    ]

    static func interpret(_ query: String) -> Hit? {
        let q = TextMatch.fold(query)
        var areas: Set<BodyArea> = []
        var goal: FitnessGoal?
        for entry in synonyms where entry.phrases.contains(where: { q.contains($0) }) {
            areas.formUnion(entry.areas)
            if goal == nil { goal = entry.goal }
        }
        return areas.isEmpty && goal == nil ? nil : Hit(areas: areas, goal: goal)
    }

    static func search(_ query: String, in routines: [Routine]) -> [Routine] {
        let terms = TextMatch.terms(query)
        guard !terms.isEmpty else { return [] }
        let hit = interpret(query)
        return routines.compactMap { r -> (Routine, Int)? in
            var score = 0
            if let hit {
                if !hit.areas.isDisjoint(with: r.info.bodyAreas) { score += 10 }
                if let goal = hit.goal, r.info.goal == goal { score += hit.areas.isEmpty ? 10 : 3 }
                if !hit.areas.isEmpty && hit.areas.isDisjoint(with: r.info.bodyAreas) { score = 0 }
            }
            let text = TextMatch.score(terms: terms, fields: [
                (r.title, 5), (r.info.exercises.map(\.name).joined(separator: " "), 4),
                (r.post.caption, 2), (r.post.hashtags.joined(separator: " "), 2),
            ])
            score += text
            return score > 0 ? (r, score) : nil
        }
        .sorted { $0.1 > $1.1 }
        .map(\.0)
    }
}

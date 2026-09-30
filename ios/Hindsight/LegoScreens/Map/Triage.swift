import Foundation

/// Who gets asked what (confirm.md → Triage). Pure; no MapKit.
enum Triage {
    /// Cards in the post-onboarding pass. The spec targets a handful (≤ 10) with a
    /// hard cap of 20; the rest wait in Needs review.
    static let onboardingLimit = 10
    static let hardCap = 20

    /// A search area: the center and radius of the area hint's bounding region.
    struct Area: Codable, Hashable, Sendable {
        var center: Coordinate
        var radius: Double   // meters

        /// Area lookups often return a near-point region ("Paros, Greece"), so the
        /// check allows at least 15 km: it's there to catch wrong-city matches.
        static let minimumRadius: Double = 15_000

        func contains(_ c: Coordinate) -> Bool { center.distance(to: c) <= max(radius, Self.minimumRadius) }
    }

    /// Placed / ask / can't tell for one extracted place.
    /// - results: search results, best first.
    /// - agreedByOtherPost: another post's place matched the same top result.
    static func status(for place: ExtractedPlace, results: [MatchedPlace], area: Area?,
                       agreedByOtherPost: Bool = false) -> MatchStatus {
        guard let top = results.first else { return .cantTell }
        let plausible = results.filter { namesMatch(place.name, $0.name) && (area?.contains($0.coordinate) ?? false) }
        let topIsGood = namesMatch(place.name, top.name) && (area?.contains(top.coordinate) ?? false)
        guard topIsGood else { return .ask }
        let strong = place.evidenceKind.isStrong && place.confidence == .high
        if strong || plausible.count == 1 || agreedByOtherPost { return .auto }
        return .ask
    }

    /// How sure we are, for ordering the Ask cards (strongest first).
    static func strength(of place: ExtractedPlace, match: MatchedPlace?, area: Area?) -> Int {
        var score = 0
        if place.evidenceKind.isStrong { score += 2 }
        if place.confidence == .high { score += 1 }
        if let match {
            if namesMatch(place.name, match.name) { score += 2 }
            if area?.contains(match.coordinate) == true { score += 1 }
        }
        return score
    }

    /// Loose name equality: case, accents, punctuation, "the" and "'s" don't matter;
    /// one containing the other or ≥ 60% shared words counts.
    static func namesMatch(_ a: String, _ b: String) -> Bool {
        let x = normalize(a), y = normalize(b)
        guard !x.isEmpty, !y.isEmpty else { return false }
        let joinedX = x.joined(), joinedY = y.joined()
        if joinedX == joinedY || joinedX.contains(joinedY) || joinedY.contains(joinedX) { return true }
        let shared = Set(x).intersection(y).count
        return Double(shared) / Double(min(x.count, y.count)) >= 0.6
    }

    static func normalize(_ s: String) -> [String] {
        let folded = s.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            .replacingOccurrences(of: "'s", with: "")
            .replacingOccurrences(of: "’s", with: "")
            .replacingOccurrences(of: "&", with: " and ")
        let words = folded.components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty }
        let stop: Set<String> = ["the", "nyc", "new", "york", "cafe", "restaurant", "bar", "and"]
        let kept = words.filter { !stop.contains($0) }
        return kept.isEmpty ? words : kept
    }

    /// The onboarding pass: posts with Ask places, strongest first, one card per
    /// post (a Top-N post is one checklist card), at most `limit` cards.
    static func onboardingCards(_ asks: [(ref: PlaceRef, strength: Int)], limit: Int = onboardingLimit) -> [[PlaceRef]] {
        var byPost: [String: [(PlaceRef, Int)]] = [:]
        for a in asks { byPost[a.ref.postID, default: []].append((a.ref, a.strength)) }
        let cards = byPost.values.map { refs in
            (refs: refs.map(\.0).sorted(), score: refs.map(\.1).max() ?? 0)
        }
        return cards.sorted { ($0.score, $1.refs[0].postID) > ($1.score, $0.refs[0].postID) }
            .prefix(min(limit, hardCap))
            .map(\.refs)
    }
}

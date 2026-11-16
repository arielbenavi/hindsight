import Foundation

/// Who gets asked what (confirm.md → Triage). Pure; no MapKit.
enum Triage {
    /// A search area: the center and radius of the area hint's bounding region.
    struct Area: Codable, Hashable, Sendable {
        var center: Coordinate
        var radius: Double   // meters

        /// Area lookups often return a near-point region ("Paros, Greece"), so the
        /// check allows at least 25 km (an island and its neighbor, a metro area): it's there to catch wrong-city matches.
        static let minimumRadius: Double = 25_000

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
        // Don't strip a name down to a scrap ("New York AC" must not become just "ac").
        return kept.joined().count < 4 ? words : kept
    }

    /// Does any result's name match the place (by name or by its @handle)?
    static func hasNameMatch(_ results: [MatchedPlace], for place: ExtractedPlace) -> Bool {
        results.contains { matches($0, place) }
    }

    /// Name matches first (keeping MapKit's order otherwise), duplicates removed.
    static func rank(_ results: [MatchedPlace], for place: ExtractedPlace) -> [MatchedPlace] {
        var seen = Set<String>()
        let unique = results.filter { seen.insert($0.id).inserted }
        return unique.filter { matches($0, place) } + unique.filter { !matches($0, place) }
    }

    static func matches(_ result: MatchedPlace, _ place: ExtractedPlace) -> Bool {
        if namesMatch(place.name, result.name) { return true }
        guard let handle = place.handle else { return false }
        // "thegoldenswan_nyc" contains "goldenswan"
        let h = TextMatch.fold(handle).filter { $0.isLetter || $0.isNumber }
        let n = normalize(result.name).joined()
        return n.count >= 4 && h.contains(n)
    }

    /// A search query from an @handle: separators become spaces.
    static func handleQuery(_ handle: String?) -> String? {
        guard let handle, !handle.isEmpty else { return nil }
        let words = handle.replacingOccurrences(of: "_", with: " ").replacingOccurrences(of: ".", with: " ")
            .split(separator: " ").map(String.init).filter { !$0.isEmpty }
        return words.isEmpty ? nil : TextMatch.fold(words.joined(separator: " "))
    }
}

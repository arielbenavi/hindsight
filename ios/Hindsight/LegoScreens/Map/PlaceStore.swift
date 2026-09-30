import Foundation
import Observation

/// Map filters (map.md → Filters). Remembered between launches.
struct MapFilters: Codable, Equatable, Sendable {
    var type: PlaceType?
    var status: StatusFilter = .all
    var collection: String?

    enum StatusFilter: String, Codable, CaseIterable, Sendable {
        case all, wantToGo, beenThere
        var title: String {
            switch self {
            case .all: "All"
            case .wantToGo: "Want to go"
            case .beenThere: "Been there"
            }
        }
    }

    func allows(_ place: Place) -> Bool {
        if let type, place.type != type { return false }
        switch status {
        case .all: break
        case .wantToGo: if place.visit != .wantToGo { return false }
        case .beenThere: if place.visit != .beenThere { return false }
        }
        if let collection, !place.collections.contains(collection) { return false }
        return true
    }

    var isActive: Bool { type != nil || status != .all || collection != nil }
}

/// Everything the Map and the confirmation flow know about places: matching
/// results, confirmation answers, been-there / hidden, filters. Persisted per dataset.
@Observable
@MainActor
final class PlaceStore {
    private(set) var data: HindsightData?
    private(set) var records: [String: MatchRecord] = [:]
    private(set) var userStates: [String: PlaceUserState] = [:]
    var filters: MapFilters { didSet { filtersFile.save(filters) } }

    /// Topics shown in the Map tab. Posts in them are what gets matched.
    private(set) var mapTopicIDs: Set<String> = []

    private(set) var isMatching = false
    private(set) var isOffline = false

    let searcher: PlaceSearching
    private let recordsFile: JSONFile<[String: MatchRecord]>
    private let statesFile: JSONFile<[String: PlaceUserState]>
    private let filtersFile: JSONFile<MapFilters>
    private var matchingTask: Task<Void, Never>?

    init(directory: URL?, data: HindsightData?, searcher: PlaceSearching? = nil, bundledCache: MatchCache? = nil) {
        self.data = data
        recordsFile = JSONFile(name: "places", directory: directory)
        statesFile = JSONFile(name: "place-state", directory: directory)
        filtersFile = JSONFile(name: "map-filters", directory: directory)
        records = recordsFile.load() ?? [:]
        userStates = statesFile.load() ?? [:]
        filters = filtersFile.load() ?? MapFilters()
        self.searcher = searcher ?? MapKitPlaceSearcher(directory: directory, bundled: bundledCache)
        if let data {
            mapTopicIDs = Set(data.topics.filter { $0.legoScreen == .map }.map(\.id))
        }
    }

    // MARK: - What's in the Map

    /// Set from the approved layout (a topic moved into or out of the Map).
    func setMapTopics(_ ids: [String]) {
        mapTopicIDs = Set(ids)
    }

    /// Every place reference in Map posts. A post with no named place gets index -1.
    var refs: [PlaceRef] {
        guard let data else { return [] }
        return data.posts(inTopics: mapTopicIDs).flatMap { post -> [PlaceRef] in
            let places = data.item(for: post.id)?.places ?? []
            return places.isEmpty ? [PlaceRef(postID: post.id, index: -1)] : places.indices.map { PlaceRef(postID: post.id, index: $0) }
        }
    }

    func extracted(_ ref: PlaceRef) -> ExtractedPlace? {
        guard ref.index >= 0, let places = data?.item(for: ref.postID)?.places, ref.index < places.count else { return nil }
        return places[ref.index]
    }

    func post(_ ref: PlaceRef) -> ContractPost? { data?.post(ref.postID) }

    func record(_ ref: PlaceRef) -> MatchRecord {
        if let r = records[ref.key] { return r }
        return MatchRecord(status: ref.index < 0 ? .cantTell : .pending)
    }

    /// Pins: on-map records grouped by the real place, with user state.
    var allPlaces: [Place] {
        var grouped: [String: Place] = [:]
        var order: [String] = []
        for ref in refs {
            let rec = record(ref)
            guard rec.status.isOnMap, let match = rec.match, let extracted = extracted(ref), let post = post(ref) else { continue }
            let source = PlaceSource(ref: ref, post: post, extracted: extracted)
            if grouped[match.id] != nil {
                grouped[match.id]?.sources.append(source)
            } else {
                let state = userStates[match.id] ?? PlaceUserState()
                grouped[match.id] = Place(match: match, type: extracted.type, sources: [source], visit: state.visit, isHidden: state.isHidden)
                order.append(match.id)
            }
        }
        return order.compactMap { grouped[$0] }
    }

    /// Visible pins under the current filters.
    var places: [Place] { allPlaces.filter { !$0.isHidden && filters.allows($0) } }

    var placeTypes: [PlaceType] {
        let present = Set(allPlaces.map(\.type))
        return PlaceType.allCases.filter(present.contains)
    }

    var collections: [String] {
        let counts = Dictionary(allPlaces.flatMap { Array($0.collections) }.map { ($0, 1) }, uniquingKeysWith: +)
        return counts.sorted { ($0.value, $1.key) > ($1.value, $0.key) }.map(\.key)
    }

    /// Cities with counts, biggest first ("New York · 142"). Apple often returns a
    /// neighborhood as the city (Astoria, Williamsburg), so localities within 20 km
    /// of a bigger one are folded into it.
    var cities: [(name: String, count: Int, center: Coordinate)] {
        CityName.group(allPlaces.filter { !$0.isHidden }).map { ($0.name, $0.places.count, $0.center) }
    }

    /// The pins grouped under a city from `cities`.
    func places(inCity name: String) -> [Place] {
        CityName.group(allPlaces.filter { !$0.isHidden }).first { $0.name == name }?.places ?? []
    }

    /// The city a place is grouped under (see `cities`).
    func cityName(of place: Place) -> String {
        CityName.group(allPlaces.filter { !$0.isHidden }).first { g in g.places.contains { $0.id == place.id } }?.name
            ?? CityName.normalize(place.locality)
    }

    // MARK: - Review

    /// Everything waiting for a look (Map M4), one entry per post.
    var needsReview: [[PlaceRef]] {
        let open = refs.filter { record($0).status.needsReview }
        return Dictionary(grouping: open, by: \.postID).values.map { $0.sorted() }
            .sorted { $0[0].postID > $1[0].postID }
    }

    var needsReviewCount: Int { needsReview.count }

    var pendingCount: Int { refs.count { record($0).status == .pending } }
    var totalFound: Int { refs.count { $0.index >= 0 } }
    var placedCount: Int { allPlaces.count }

    /// Cards for the post-onboarding pass (C2/C4), strongest first, a handful.
    func onboardingCards() -> [[PlaceRef]] {
        let asks = refs.compactMap { ref -> (ref: PlaceRef, strength: Int)? in
            let rec = record(ref)
            guard rec.status == .ask, let ex = extracted(ref) else { return nil }
            return (ref, Triage.strength(of: ex, match: rec.match, area: rec.area))
        }
        return Triage.onboardingCards(asks)
    }

    // MARK: - Matching

    /// Look up every pending place, in order. Safe to call repeatedly.
    func startMatching() {
        guard matchingTask == nil else { return }
        let pending = refs.filter { record($0).status == .pending }
        guard !pending.isEmpty else { return }
        isMatching = true
        isOffline = false
        matchingTask = Task { [weak self] in
            guard let self else { return }
            for ref in pending {
                guard !Task.isCancelled, let place = self.extracted(ref) else { continue }
                do {
                    let outcome = try await self.searcher.search(place)
                    self.apply(outcome, to: ref)
                } catch {
                    self.isOffline = true
                    break
                }
            }
            self.applyAgreement()
            self.save()
            await (self.searcher as? MapKitPlaceSearcher)?.flush()
            self.isMatching = false
            self.matchingTask = nil
        }
    }

    private func apply(_ outcome: SearchOutcome, to ref: PlaceRef) {
        guard let place = extracted(ref) else { return }
        var rec = record(ref)
        guard rec.status == .pending else { return }
        let results = outcome.results.filter { !rec.rejectedIDs.contains($0.id) }
        rec.status = Triage.status(for: place, results: results, area: outcome.area)
        rec.match = results.first
        rec.candidates = Array(results.dropFirst().prefix(5))
        rec.area = outcome.area
        records[ref.key] = rec
        if records.count % 20 == 0 { save() }
    }

    /// Two posts pointing at the same place is strong evidence (confirm.md).
    private func applyAgreement() {
        var postsByMatch: [String: Set<String>] = [:]
        for ref in refs {
            if let id = record(ref).match?.id { postsByMatch[id, default: []].insert(ref.postID) }
        }
        for ref in refs {
            var rec = record(ref)
            guard rec.status == .ask, let match = rec.match, let place = extracted(ref),
                  (postsByMatch[match.id]?.count ?? 0) > 1, Triage.namesMatch(place.name, match.name) else { continue }
            rec.status = .auto
            records[ref.key] = rec
        }
    }

    // MARK: - Confirmation answers

    func confirm(_ ref: PlaceRef) {
        update(ref) { $0.status = .confirmed; $0.confirmedAt = .now }
    }

    /// "No": remember the rejected guess; the caller shows alternatives.
    func reject(_ ref: PlaceRef) {
        update(ref) { rec in
            if let id = rec.match?.id, !rec.rejectedIDs.contains(id) { rec.rejectedIDs.append(id) }
        }
    }

    func pick(_ ref: PlaceRef, _ place: MatchedPlace) {
        update(ref) { rec in
            rec.match = place
            rec.candidates.removeAll { $0.id == place.id }
            rec.status = .confirmed
            rec.confirmedAt = .now
        }
    }

    func markNotAPlace(_ ref: PlaceRef) {
        update(ref) { $0.status = .notAPlace; $0.confirmedAt = .now }
    }

    func skip(_ ref: PlaceRef) {
        update(ref) { rec in
            if rec.status == .ask || rec.status == .pending { rec.status = .skipped }
        }
    }

    /// Undo: put a record back exactly as it was.
    func restore(_ ref: PlaceRef, to record: MatchRecord) {
        records[ref.key] = record
        save()
    }

    /// Candidates for "Which one is it?", without rejected ones.
    func alternatives(_ ref: PlaceRef) -> [MatchedPlace] {
        let rec = record(ref)
        return rec.candidates.filter { !rec.rejectedIDs.contains($0.id) && $0.id != rec.match?.id }
    }

    func search(_ query: String, for ref: PlaceRef) async -> [MatchedPlace] {
        let area = record(ref).area
        let hint = area == nil ? (extracted(ref)?.areaHint ?? post(ref)?.collections.first) : nil
        let fullQuery = [query, hint].compactMap { $0 }.joined(separator: ", ")
        return (try? await searcher.freeSearch(fullQuery, near: area)) ?? []
    }

    /// All posts whose every place was marked "not a place" (they leave the Map).
    var notAPlacePostIDs: Set<String> {
        let byPost = Dictionary(grouping: refs, by: \.postID)
        return Set(byPost.filter { _, refs in refs.allSatisfy { record($0).status == .notAPlace } }.keys)
    }

    private func update(_ ref: PlaceRef, _ change: (inout MatchRecord) -> Void) {
        var rec = record(ref)
        change(&rec)
        records[ref.key] = rec
        save()
    }

    // MARK: - User state

    func toggleBeenThere(_ place: Place) {
        var state = userStates[place.id] ?? PlaceUserState()
        state.visit = state.visit == .beenThere ? .wantToGo : .beenThere
        userStates[place.id] = state
        statesFile.save(userStates)
    }

    func hide(_ place: Place) {
        var state = userStates[place.id] ?? PlaceUserState()
        state.isHidden = true
        userStates[place.id] = state
        statesFile.save(userStates)
    }

    /// Place card → "Wrong place?": the source refs of this pin.
    func refs(for place: Place) -> [PlaceRef] { place.sources.map(\.ref) }

    func save() { recordsFile.save(records) }
}

/// City grouping for the picker: boroughs are New York (map.md → M3).
enum CityName {
    static let newYork: Set<String> = ["new york", "brooklyn", "manhattan", "queens", "bronx", "the bronx", "staten island", "long island city", "nyc"]

    struct Group { var name: String; var places: [Place]; var center: Coordinate }

    static func group(_ places: [Place], mergeWithin meters: Double = 20_000) -> [Group] {
        let byName = Dictionary(grouping: places) { normalize($0.locality) }
        var groups = byName.map { name, members in Group(name: name, places: members, center: centroid(members)) }
            .sorted { $0.places.count > $1.places.count }
        var merged: [Group] = []
        for g in groups {
            if let i = merged.firstIndex(where: { $0.center.distance(to: g.center) <= meters }) {
                merged[i].places += g.places
            } else {
                merged.append(g)
            }
        }
        groups = merged.map { Group(name: $0.name, places: $0.places, center: centroid($0.places)) }
        return groups.sorted { $0.places.count > $1.places.count }
    }

    private static func centroid(_ places: [Place]) -> Coordinate {
        let lat = places.map(\.coordinate.latitude).reduce(0, +) / Double(max(places.count, 1))
        let lng = places.map(\.coordinate.longitude).reduce(0, +) / Double(max(places.count, 1))
        return Coordinate(latitude: lat, longitude: lng)
    }

    static func normalize(_ locality: String) -> String {
        let lower = locality.lowercased()
        if newYork.contains(lower) || lower.hasPrefix("brooklyn") || lower.hasPrefix("new york") { return "New York" }
        return locality.split(separator: ",").first.map(String.init) ?? locality
    }
}

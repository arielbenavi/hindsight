import Foundation
import MapKit

/// Search results for one place plus the area it was searched in.
struct SearchOutcome: Codable, Hashable, Sendable {
    var results: [MatchedPlace]
    var area: Triage.Area?
}


/// Anything that can look places up (MapKit in the app, a stub in tests).
protocol PlaceSearching: Sendable {
    func search(_ place: ExtractedPlace) async throws -> SearchOutcome
    /// Free-text search for "Search for the place" (C3/C6), biased to an area.
    func freeSearch(_ query: String, near area: Triage.Area?) async throws -> [MatchedPlace]
}

enum PlaceSearchError: Error { case offline, throttled }

/// Everything already looked up, keyed by query. Persisted per dataset, and a
/// bundled `<dataset>.matches.json` (same shape) warms it on first launch.
struct MatchCache: Codable, Sendable {
    var areas: [String: Triage.Area?] = [:]
    var outcomes: [String: SearchOutcome] = [:]

    /// Bump when the search strategy changes, so old outcomes aren't reused.
    static let version = "v2"

    static func key(for place: ExtractedPlace) -> String {
        ([version, place.name, place.areaHint ?? "", place.address ?? "", place.type.rawValue] + [place.handle ?? ""])
            .joined(separator: "|").lowercased()
    }

    mutating func merge(_ other: MatchCache) {
        areas.merge(other.areas) { mine, _ in mine }
        outcomes.merge(other.outcomes) { mine, _ in mine }
    }
}

/// Apple Maps search, one request at a time, spaced out to stay under MapKit's
/// throttle (about 50 requests a minute).
actor MapKitPlaceSearcher: PlaceSearching {
    private var cache: MatchCache
    private let file: JSONFile<MatchCache>
    private var lastRequest = ContinuousClock.now - .seconds(10)
    private let spacing: Duration
    private var dirty = 0

    init(directory: URL?, bundled: MatchCache? = nil, spacing: Duration = .milliseconds(1300)) {
        file = JSONFile(name: "match-cache", directory: directory)
        var cache = file.load() ?? MatchCache()
        if let bundled { cache.merge(bundled) }
        self.cache = cache
        self.spacing = spacing
    }

    /// Uses the post's context, not just the name (a "FAV DINNER SPOT: Jean's" is a
    /// restaurant, not a jeans store):
    /// 1. the name in the area, limited to place categories that fit the type;
    /// 2. if nothing matches by name: the same without the category limit;
    /// 3. then the @handle's words ("thegoldenswan_nyc" → "thegoldenswan nyc");
    /// results whose name matches (the name or the handle) come first.
    func search(_ place: ExtractedPlace) async throws -> SearchOutcome {
        let key = MatchCache.key(for: place)
        if let cached = cache.outcomes[key] { return cached }
        let area = try await resolveArea(place.areaHint)
        var query = place.name
        if let address = place.address { query += ", \(address)" }
        else if area == nil, let hint = place.areaHint { query += ", \(hint)" }

        var found = try await run(query: query, area: area, types: .pointOfInterest, categories: place.type.poiCategories)
        if !Triage.hasNameMatch(found, for: place) {
            found += try await run(query: query, area: area, types: .pointOfInterest, categories: nil)
        }
        if !Triage.hasNameMatch(found, for: place), let handleQuery = Triage.handleQuery(place.handle),
           handleQuery != TextMatch.fold(place.name) {
            found += try await run(query: handleQuery, area: area, types: .pointOfInterest, categories: nil)
        }
        let outcome = SearchOutcome(results: Array(Triage.rank(found, for: place).prefix(6)), area: area)
        cache.outcomes[key] = outcome
        saveSoon()
        return outcome
    }

    func freeSearch(_ query: String, near area: Triage.Area?) async throws -> [MatchedPlace] {
        try await run(query: query, area: area, types: [.pointOfInterest, .address])
    }

    func flush() { file.save(cache) }

    /// The whole cache, e.g. to bundle it as a warm start (DEBUG export).
    func snapshot() -> MatchCache { cache }

    // MARK: -

    private func resolveArea(_ hint: String?) async throws -> Triage.Area? {
        guard let hint, !hint.isEmpty else { return nil }
        if let cached = cache.areas[hint.lowercased()] { return cached }
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = hint
        request.resultTypes = .address
        let area: Triage.Area?
        do {
            let response = try await perform(request)
            let span = response.boundingRegion.span
            // radius of the bounding box, a bit generous, at least 3 km
            let meters = max(span.latitudeDelta, span.longitudeDelta) * 111_000 / 2 * 1.5
            area = Triage.Area(center: Coordinate(response.boundingRegion.center), radius: max(meters, 3_000))
        } catch PlaceSearchError.offline {
            throw PlaceSearchError.offline
        } catch {
            area = nil
        }
        cache.areas[hint.lowercased()] = area
        return area
    }

    private func run(query: String, area: Triage.Area?, types: MKLocalSearch.ResultType,
                     categories: [MKPointOfInterestCategory]? = nil) async throws -> [MatchedPlace] {
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = query
        request.resultTypes = types
        if let categories { request.pointOfInterestFilter = MKPointOfInterestFilter(including: categories) }
        if let area {
            request.region = MKCoordinateRegion(center: area.center.clCoordinate,
                                                latitudinalMeters: area.radius * 2, longitudinalMeters: area.radius * 2)
        }
        do {
            return try await perform(request).mapItems.map(MatchedPlace.init(item:))
        } catch PlaceSearchError.offline {
            throw PlaceSearchError.offline
        } catch {
            return []
        }
    }

    private func perform(_ request: MKLocalSearch.Request) async throws -> MKLocalSearch.Response {
        for attempt in 0..<3 {
            let wait = lastRequest + spacing - ContinuousClock.now
            if wait > .zero { try await Task.sleep(for: wait) }
            lastRequest = ContinuousClock.now
            do {
                return try await MKLocalSearch(request: request).start()
            } catch let error as MKError where error.code == .loadingThrottled {
                try await Task.sleep(for: .seconds(20 * (attempt + 1)))
            } catch let error as MKError where error.code == .placemarkNotFound {
                throw error
            } catch let error as NSError where error.domain == NSURLErrorDomain {
                throw PlaceSearchError.offline
            } catch let error as MKError where error.code == .serverFailure {
                throw PlaceSearchError.offline
            }
        }
        throw PlaceSearchError.throttled
    }

    private func saveSoon() {
        dirty += 1
        if dirty >= 10 {
            dirty = 0
            file.save(cache)
        }
    }
}

extension MatchedPlace {
    init(item: MKMapItem) {
        let coordinate = Coordinate(item.location.coordinate)
        let name = item.name ?? "Unnamed place"
        self.init(
            id: item.identifier?.rawValue ?? "\(name)@\(String(format: "%.5f,%.5f", coordinate.latitude, coordinate.longitude))",
            name: name,
            coordinate: coordinate,
            address: item.address?.shortAddress ?? item.address?.fullAddress,
            locality: item.addressRepresentations?.cityName,
            cityWithContext: item.addressRepresentations?.cityWithContext,
            category: item.pointOfInterestCategory?.rawValue.replacingOccurrences(of: "MKPOICategory", with: "")
        )
    }
}

extension PlaceType {
    /// Apple Maps categories a place of this type can be. `other` isn't limited.
    var poiCategories: [MKPointOfInterestCategory]? {
        switch self {
        case .food: [.restaurant, .cafe, .bakery, .nightlife, .brewery, .winery]
        case .cafe: [.cafe, .bakery, .restaurant]
        case .bakery: [.bakery, .cafe, .restaurant]
        case .bar: [.nightlife, .brewery, .winery, .distillery, .restaurant]
        case .other: nil
        }
    }
}

import CoreLocation
import Foundation

/// A lat/lng that's Codable (CLLocationCoordinate2D isn't).
struct Coordinate: Codable, Hashable, Sendable {
    var latitude: Double
    var longitude: Double

    init(latitude: Double, longitude: Double) {
        self.latitude = latitude
        self.longitude = longitude
    }

    init(_ c: CLLocationCoordinate2D) {
        self.init(latitude: c.latitude, longitude: c.longitude)
    }

    var clCoordinate: CLLocationCoordinate2D { .init(latitude: latitude, longitude: longitude) }
    var location: CLLocation { CLLocation(latitude: latitude, longitude: longitude) }

    func distance(to other: Coordinate) -> CLLocationDistance { location.distance(from: other.location) }
}

/// One Apple Maps search result (map.md → "From matching").
struct MatchedPlace: Codable, Hashable, Sendable, Identifiable {
    /// MapKit's stable `MKMapItem.Identifier` when available, else name@coordinate.
    var id: String
    var name: String
    var coordinate: Coordinate
    var address: String?
    var locality: String?
    /// e.g. "Brooklyn, NY", used when there's no area hint.
    var cityWithContext: String?
    var category: String?

    var googleMapsURL: URL {
        let query = [name, address].compactMap { $0 }.joined(separator: ", ")
        var components = URLComponents(string: "https://www.google.com/maps/search/")!
        components.queryItems = [URLQueryItem(name: "api", value: "1"), URLQueryItem(name: "query", value: query)]
        return components.url!
    }

    var appleMapsURL: URL {
        var components = URLComponents(string: "https://maps.apple.com/")!
        components.queryItems = [
            URLQueryItem(name: "q", value: name),
            URLQueryItem(name: "ll", value: "\(coordinate.latitude),\(coordinate.longitude)"),
        ]
        return components.url!
    }
}

/// Where a place stands (map.md + confirm.md).
enum MatchStatus: String, Codable, Sendable {
    /// Not searched yet.
    case pending
    /// Placed without asking (strong evidence + good match).
    case auto
    /// Has a guess, needs a Yes/No.
    case ask
    /// No name in the text or no search result: "Search it yourself".
    case cantTell
    /// User said yes (or picked an alternative / searched it).
    case confirmed
    /// User said it's not a place.
    case notAPlace
    /// User skipped / said "I don't know"; stays in Needs review.
    case skipped

    var isOnMap: Bool { self == .auto || self == .confirmed }
    var needsReview: Bool { self == .ask || self == .cantTell || self == .skipped }
}

/// One place mentioned in one post: `postID#index` (index into `places`; -1 for a
/// map post with no named place).
struct PlaceRef: Hashable, Codable, Sendable, Comparable {
    var postID: String
    var index: Int

    var key: String { "\(postID)#\(index)" }

    static func < (a: PlaceRef, b: PlaceRef) -> Bool { (a.postID, a.index) < (b.postID, b.index) }
}

/// Matching result + confirmation answers for one `PlaceRef`. Persisted.
struct MatchRecord: Codable, Hashable, Sendable {
    var status: MatchStatus = .pending
    /// The pin (best guess until confirmed).
    var match: MatchedPlace?
    /// Up to 5 alternatives for "Which one is it?".
    var candidates: [MatchedPlace] = []
    /// IDs the user said No to; never suggested again.
    var rejectedIDs: [String] = []
    var confirmedAt: Date?
    /// The area hint's region the search ran in (for ordering and re-searching).
    var area: Triage.Area?
}

enum VisitStatus: String, Codable, Sendable, CaseIterable {
    case wantToGo, beenThere
}

/// What the user set on a matched place. Persisted, keyed by `MatchedPlace.id`.
struct PlaceUserState: Codable, Hashable, Sendable {
    var visit: VisitStatus = .wantToGo
    var isHidden = false
}

/// A post that mentions a place: the link back from a pin.
struct PlaceSource: Hashable, Sendable, Identifiable {
    var ref: PlaceRef
    var post: ContractPost
    var extracted: ExtractedPlace
    var id: String { ref.key }
}

/// A pin: one real place, possibly mentioned by several posts. Derived, not stored.
struct Place: Identifiable, Hashable, Sendable {
    var id: String { match.id }
    var match: MatchedPlace
    var type: PlaceType
    var sources: [PlaceSource]
    var visit: VisitStatus
    var isHidden: Bool

    var name: String { match.name }
    var coordinate: Coordinate { match.coordinate }
    var neighborhood: String? {
        sources.lazy.compactMap { $0.extracted.areaHint?.split(separator: ",").first.map(String.init) }.first
            ?? match.cityWithContext
    }
    var locality: String { match.locality ?? match.cityWithContext ?? "Somewhere" }
    var reason: String? { sources.lazy.compactMap(\.extracted.reason).first }
    var collections: Set<String> { Set(sources.flatMap(\.post.collections)) }
    var firstPost: ContractPost { sources[0].post }
}

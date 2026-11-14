import Foundation
import MapKit
import Testing
@testable import Hindsight

private func place(_ name: String, kind: EvidenceKind = .mention, confidence: Confidence = .high) -> ExtractedPlace {
    ExtractedPlace(name: name, handle: nil, areaHint: "West Village, New York", address: nil, type: .food,
                   reason: nil, evidence: name, evidenceKind: kind, confidence: confidence)
}

private func match(_ name: String, _ lat: Double = 40.7336, _ lng: Double = -74.0027, id: String? = nil) -> MatchedPlace {
    MatchedPlace(id: id ?? name, name: name, coordinate: Coordinate(latitude: lat, longitude: lng), address: nil, locality: "New York")
}

private let westVillage = Triage.Area(center: Coordinate(latitude: 40.7358, longitude: -74.0036), radius: 3_000)

/// Stub search for tests: fixed results by name.
private struct StubSearcher: PlaceSearching {
    var results: [String: [MatchedPlace]]
    func search(_ place: ExtractedPlace) async throws -> SearchOutcome {
        SearchOutcome(results: results[place.name] ?? [], area: westVillage)
    }
    func freeSearch(_ query: String, near area: Triage.Area?) async throws -> [MatchedPlace] { [] }
}

@MainActor
struct MapTests {
    @Test func namesMatchLoosely() {
        #expect(Triage.namesMatch("Cappone's", "Cappone's Salumeria"))
        #expect(Triage.namesMatch("Salt Hank's", "Salt Hanks"))
        #expect(Triage.namesMatch("Café Kitsuné", "Cafe Kitsune"))
        #expect(!Triage.namesMatch("Little Mint", "Mint Kitchen & Bar House"))
    }

    @Test func strongEvidenceExactMatchIsPlacedWithoutAsking() {
        #expect(Triage.status(for: place("Cappone's"), results: [match("Cappone's")], area: westVillage) == .auto)
    }

    @Test func weakEvidenceWithSeveralPlausibleResultsIsAsked() {
        let p = place("Little Mint", kind: .plainText)
        let results = [match("Little Mint"), match("Little Mint Cafe", 40.734, -74.001)]
        #expect(Triage.status(for: p, results: results, area: westVillage) == .ask)
    }

    @Test func onlyOnePlausibleResultIsPlacedEvenWithWeakEvidence() {
        let p = place("Semma", kind: .plainText)
        #expect(Triage.status(for: p, results: [match("Semma")], area: westVillage) == .auto)
    }

    @Test func outsideTheAreaOrWrongNameIsAsked() {
        #expect(Triage.status(for: place("Semma"), results: [match("Semma", 34.05, -118.24)], area: westVillage) == .ask)
        #expect(Triage.status(for: place("Semma"), results: [match("Joe's Pizza")], area: westVillage) == .ask)
    }

    @Test func namesAreNotStrippedToScraps() {
        // "New York AC" (the Athletic Club) must not match an air-conditioning company.
        #expect(!Triage.namesMatch("New York AC", "Friedrich AC"))
        #expect(Triage.namesMatch("The Golden Swan", "Golden Swan"))
    }

    @Test func nameMatchesAreRankedFirstAndHandlesCount() {
        var jeans = place("Jean's")
        jeans.handle = "jeanslafayette"
        let ranked = Triage.rank([match("Target"), match("Coach"), match("Jean's")], for: jeans)
        #expect(ranked.first?.name == "Jean's")
        var swan = place("Golden Swan")
        swan.handle = "thegoldenswan_nyc"
        #expect(Triage.matches(match("The Golden Swan"), swan))
        #expect(!Triage.hasNameMatch([match("Target")], for: jeans))
        #expect(Triage.handleQuery("thegoldenswan_nyc") == "thegoldenswan nyc")
    }

    @Test func placeTypesLimitAppleMapsCategories() {
        #expect(PlaceType.food.poiCategories?.contains(.restaurant) == true)
        #expect(PlaceType.food.poiCategories?.contains(.store) == false)
        #expect(PlaceType.food.poiCategories?.contains(.foodMarket) == false)
        #expect(PlaceType.other.poiCategories == nil)
    }

    @Test func noResultsIsCantTell() {
        #expect(Triage.status(for: place("Nowhere"), results: [], area: westVillage) == .cantTell)
    }

    @Test func onboardingCardsAreOnePerPostAndCapped() {
        let topN = (0..<12).map { (ref: PlaceRef(postID: "instagram:TOP", index: $0), strength: 3) }
        let singles = (0..<30).map { (ref: PlaceRef(postID: "instagram:S\($0)", index: 0), strength: $0 % 6) }
        let cards = Triage.onboardingCards(topN + singles)
        #expect(cards.count == Triage.onboardingLimit)
        #expect(cards.count <= Triage.hardCap)
        #expect(cards.filter { $0.first?.postID == "instagram:TOP" }.allSatisfy { $0.count == 12 })
        #expect(Set(cards.map { $0[0].postID }).count == cards.count)
    }

    @Test func topNPostMakesNPinsLinkingToTheSamePost() async throws {
        let data = try Fixtures.load("reut")
        let cookies = try #require(data.file.items.first { ($0.places?.count ?? 0) == 12 })
        var results: [String: [MatchedPlace]] = [:]
        for (i, p) in (cookies.places ?? []).enumerated() {
            results[p.name] = [match(p.name, 40.73 + Double(i) * 0.001, -74.0, id: "id\(i)")]
        }
        let store = PlaceStore(directory: nil, data: data, searcher: StubSearcher(results: results))
        store.setMapTopics([cookies.topicId])
        store.startMatching()
        while store.isMatching { try await Task.sleep(for: .milliseconds(20)) }
        let pins = store.allPlaces.filter { $0.sources.contains { $0.post.id == cookies.postId } }
        #expect(pins.count == 12)
        #expect(Set(pins.map(\.firstPost.id)) == [cookies.postId])
    }

    @Test func answersAndBeenThereArePersistedAndFiltered() throws {
        let data = try Fixtures.load("reut")
        let dir = URL.temporaryDirectory.appending(path: UUID().uuidString)
        let store = PlaceStore(directory: dir, data: data, searcher: StubSearcher(results: [:]))
        let ref = try #require(store.refs.first { $0.index >= 0 })
        store.pick(ref, match("Somewhere"))
        let pin = try #require(store.allPlaces.first)
        store.toggleBeenThere(pin)
        store.filters.status = .wantToGo
        #expect(store.places.isEmpty)
        store.filters.status = .all
        #expect(store.places.first?.visit == .beenThere)

        let reloaded = PlaceStore(directory: dir, data: data, searcher: StubSearcher(results: [:]))
        #expect(reloaded.record(ref).status == .confirmed)
        #expect(reloaded.allPlaces.first?.visit == .beenThere)
        #expect(reloaded.filters.status == .all)
    }

    @Test func notAPlaceLeavesTheMap() throws {
        let data = try Fixtures.load("reut")
        let store = PlaceStore(directory: nil, data: data, searcher: StubSearcher(results: [:]))
        let ref = try #require(store.refs.first { $0.index >= 0 && (data.item(for: $0.postID)?.places?.count ?? 0) == 1 })
        store.pick(ref, match("Somewhere"))
        store.markNotAPlace(ref)
        #expect(store.allPlaces.isEmpty)
        #expect(store.notAPlacePostIDs.contains(ref.postID))
    }

    @Test func homeCoffeeSetupsAreNotOnTheMap() throws {
        let data = try Fixtures.load("reut")
        let store = PlaceStore(directory: nil, data: data, searcher: StubSearcher(results: [:]))
        let coffee = Set(data.topic("coffee-at-home")?.postIds ?? [])
        #expect(!coffee.isEmpty)
        #expect(store.refs.allSatisfy { !coffee.contains($0.postID) })
    }

    @Test func googleMapsLinkSearchesNameAndAddress() {
        var m = match("Salt Hank's")
        m.address = "25 8th Ave"
        #expect(m.googleMapsURL.absoluteString == "https://www.google.com/maps/search/?api=1&query=Salt%20Hank's,%2025%208th%20Ave")
    }

    @Test func boroughsGroupAsNewYork() {
        #expect(CityName.normalize("Brooklyn") == "New York")
        #expect(CityName.normalize("Buenos Aires") == "Buenos Aires")
    }
}

import MapKit
import SwiftUI

/// Map tab root (map.md → M1): "I'm out. What have I saved near here?"
struct MapScreen: View {
    let app: AppModel
    let tab: TabConfig

    @State private var location = LocationModel()
    @State private var position: MapCameraPosition = .automatic
    @State private var region: MKCoordinateRegion?
    @State private var detent: SheetDetent = .peek
    @State private var selectedID: String?
    @State private var showCities = false
    @State private var showReview = false
    @State private var positioned = false
    @State private var positionedOnUser = false
    @State private var explainerDismissed = false
    @State private var wrongPlace: Place?

    private var store: PlaceStore { app.places }

    var body: some View {
        ZStack(alignment: .top) {
            map
            topBar
            BottomSheet(detent: $detent) { sheetContent }
            if location.notAskedYet && !explainerDismissed && !store.allPlaces.isEmpty {
                LocationExplainer {
                    explainerDismissed = true
                    location.request()
                } later: {
                    explainerDismissed = true
                    positionIfNeeded(force: true)
                }
            }
        }
        .onAppear {
            store.startMatching()
            positionIfNeeded()
        }
        .onChange(of: location.location) { _, loc in
            // the first fix arrives after we've fallen back to a city: move to you, once
            if loc != nil && !positionedOnUser { positionIfNeeded(force: true) }
        }
        .onChange(of: location.status) { _, _ in positionIfNeeded(force: location.isDenied) }
        .onChange(of: store.allPlaces.count) { old, new in if old == 0 && new > 0 { positionIfNeeded(force: true) } }
        .sheet(isPresented: $showCities) {
            CityPicker(store: store, hasLocation: location.location != nil) { choice in
                showCities = false
                switch choice {
                case .nearMe: centerOnMe()
                case .city(let center, let places): fit(places.map(\.coordinate), fallback: center)
                }
            }
        }
        .fullScreenCover(isPresented: $showReview) {
            ConfirmationFlow(app: app, mode: .review) { showReview = false }
        }
        .fullScreenCover(item: $wrongPlace) { place in
            ConfirmationFlow(app: app, mode: .wrongPlace(store.refs(for: place))) {
                wrongPlace = nil
                selectedID = nil
            }
        }
    }

    // MARK: - Map

    private var map: some View {
        Map(position: $position, selection: $selectedID) {
            UserAnnotation()
            ForEach(clusters) { cluster in
                if cluster.places.count == 1, let place = cluster.places.first {
                    Annotation(place.name, coordinate: place.coordinate.clCoordinate, anchor: .bottom) {
                        PlacePin(place: place, isSelected: selectedID == place.id)
                    }
                    .tag(place.id)
                    .annotationTitles(.hidden)
                } else {
                    Annotation("\(cluster.places.count) places", coordinate: cluster.center.clCoordinate) {
                        ClusterBubble(count: cluster.places.count) { zoom(into: cluster) }
                    }
                    .annotationTitles(.hidden)
                }
            }
        }
        .mapStyle(.standard(pointsOfInterest: .excludingAll))
        .mapControls { MapCompass(); MapScaleView() }
        .onMapCameraChange(frequency: .onEnd) { context in region = context.region }
        .onChange(of: selectedID) { _, id in
            if id != nil { detent = .half }
        }
        .preferredColorScheme(.dark)
    }

    private var clusters: [PlaceCluster] {
        PlaceCluster.make(store.places, region: region)
    }

    // MARK: - Floating controls

    private var topBar: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                Button { showCities = true } label: {
                    HStack(spacing: 6) {
                        Text(currentCityName).lineLimit(1)
                        Image(systemName: "chevron.down").font(.system(size: 12, weight: .heavy))
                    }
                    .font(Theme.body(16, weight: .heavy))
                    .padding(.horizontal, 16).frame(height: 44)
                    .background(Theme.surface, in: Capsule())
                    .overlay(Capsule().strokeBorder(Theme.stroke))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("City: \(currentCityName). Change city")
                Spacer()
                DevMenu(app: app)
                CircleIconButton(systemImage: location.isDenied ? "location.slash" : "location.fill", label: "Show my location") {
                    centerOnMe()
                }
                EverythingElseButton(app: app)
            }
            if store.needsReviewCount > 0 && !store.isMatching {
                Button { showReview = true } label: {
                    Label("\(store.needsReviewCount) \(store.needsReviewCount == 1 ? "spot needs" : "spots need") a look", systemImage: "questionmark.circle.fill")
                        .font(Theme.body(14, weight: .bold))
                        .padding(.horizontal, 14).padding(.vertical, 8)
                        .background(Theme.lime, in: Capsule())
                        .foregroundStyle(Theme.onLime)
                }
                .buttonStyle(.plain)
            }
            if location.isDenied {
                Button {
                    if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                } label: {
                    Label("Turn on location to see what's near you", systemImage: "location.slash")
                        .font(Theme.body(13, weight: .semibold))
                        .padding(.horizontal, 12).padding(.vertical, 7)
                        .background(Theme.surface, in: Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }

    private var currentCityName: String {
        guard let center = region?.center else { return store.cities.first?.name ?? "Map" }
        let c = Coordinate(center)
        return store.cities.min { $0.center.distance(to: c) < $1.center.distance(to: c) }
            .map { $0.center.distance(to: c) < 60_000 ? $0.name : "Map" } ?? "Map"
    }

    // MARK: - Sheet

    @ViewBuilder private var sheetContent: some View {
        if let id = selectedID, let place = store.allPlaces.first(where: { $0.id == id }) {
            PlaceCard(place: place, store: store, userLocation: location.location,
                      onClose: { selectedID = nil; detent = .half },
                      onWrongPlace: { wrongPlace = place })
        } else {
            NearbyList(store: store, places: visiblePlaces, headline: headline, userLocation: location.location,
                       isExpanded: detent != .peek,
                       onSelect: { place in
                           selectedID = place.id
                           position = .camera(MapCamera(centerCoordinate: place.coordinate.clCoordinate, distance: 1_500))
                       },
                       onJump: { city in fit(store.places(inCity: city).map(\.coordinate), fallback: nil) },
                       onReview: { showReview = true })
        }
    }

    /// The list follows what's visible on the map, sorted by distance.
    private var visiblePlaces: [Place] {
        var places = store.places
        if let region {
            let latHalf = region.span.latitudeDelta / 2, lngHalf = region.span.longitudeDelta / 2
            places = places.filter {
                abs($0.coordinate.latitude - region.center.latitude) <= latHalf
                    && abs($0.coordinate.longitude - region.center.longitude) <= lngHalf
            }
        }
        let origin = location.location ?? region.map { Coordinate($0.center) }
        guard let origin else { return places }
        return places.sorted { $0.coordinate.distance(to: origin) < $1.coordinate.distance(to: origin) }
    }

    private var headline: String {
        let n = visiblePlaces.count
        if store.isMatching && store.allPlaces.isEmpty { return "Finding your spots… \(store.totalFound - store.pendingCount)" }
        if let loc = location.location, let region, region.center.distance(from: loc.clCoordinate) < 5_000 {
            return "\(n) saved \(n == 1 ? "spot" : "spots") near you"
        }
        return "\(n) saved \(n == 1 ? "spot" : "spots") in this area"
    }

    // MARK: - Camera

    /// Open centered on you with your nearest places (max ~3 km); else on your biggest city.
    private func positionIfNeeded(force: Bool = false) {
        guard !positioned || force else { return }
        let places = store.allPlaces.filter { !$0.isHidden }
        if let me = location.location {
            let nearest = places.sorted { $0.coordinate.distance(to: me) < $1.coordinate.distance(to: me) }
            if let first = nearest.first, first.coordinate.distance(to: me) < 25_000 {
                let near = nearest.prefix(10).filter { $0.coordinate.distance(to: me) < 3_000 }
                fit([me] + (near.isEmpty ? [first.coordinate] : near.map(\.coordinate)), fallback: me)
                positioned = true
                positionedOnUser = true
                return
            }
            if !places.isEmpty && !positionedOnUser {
                // nothing within 25 km: open the city picker (map.md → M1)
                positionedOnUser = true
                showCities = true
            }
        }
        if (location.isDenied || force || !location.notAskedYet), let city = store.cities.first {
            fit(store.places(inCity: city.name).map(\.coordinate), fallback: city.center)
            positioned = true
        }
    }

    private func centerOnMe() {
        if location.notAskedYet { location.request(); return }
        guard let me = location.location else { return }
        position = .camera(MapCamera(centerCoordinate: me.clCoordinate, distance: 3_000))
    }

    private func fit(_ coords: [Coordinate], fallback: Coordinate?) {
        guard !coords.isEmpty else {
            if let fallback { position = .camera(MapCamera(centerCoordinate: fallback.clCoordinate, distance: 8_000)) }
            return
        }
        let lats = coords.map(\.latitude), lngs = coords.map(\.longitude)
        let center = CLLocationCoordinate2D(latitude: (lats.min()! + lats.max()!) / 2, longitude: (lngs.min()! + lngs.max()!) / 2)
        let span = MKCoordinateSpan(latitudeDelta: max(0.01, (lats.max()! - lats.min()!) * 1.6),
                                    longitudeDelta: max(0.01, (lngs.max()! - lngs.min()!) * 1.6))
        position = .region(MKCoordinateRegion(center: center, span: span))
    }

    private func zoom(into cluster: PlaceCluster) {
        fit(cluster.places.map(\.coordinate), fallback: cluster.center)
    }
}

private extension CLLocationCoordinate2D {
    func distance(from other: CLLocationCoordinate2D) -> Double {
        Coordinate(self).distance(to: Coordinate(other))
    }
}

// MARK: - Pins

/// An emoji pin per type; been-there places get a small lime ✓ badge (not faded).
struct PlacePin: View {
    let place: Place
    var isSelected = false

    var body: some View {
        ZStack(alignment: .topTrailing) {
            icon
                .frame(width: isSelected ? 46 : 36, height: isSelected ? 46 : 36)
                .background(Theme.surface, in: Circle())
                .overlay(Circle().strokeBorder(isSelected ? Theme.lime : Color.white.opacity(0.25), lineWidth: isSelected ? 3 : 1.5))
                .shadow(color: .black.opacity(0.5), radius: 4, y: 2)
            if place.visit == .beenThere {
                Image(systemName: "checkmark")
                    .font(.system(size: 9, weight: .black))
                    .foregroundStyle(Theme.onLime)
                    .frame(width: 16, height: 16)
                    .background(Theme.lime, in: Circle())
                    .offset(x: 3, y: -3)
            }
        }
        .animation(.spring(duration: 0.25), value: isSelected)
        .accessibilityLabel("\(place.name), \(place.type.title)\(place.visit == .beenThere ? ", been there" : "")")
    }

    @ViewBuilder private var icon: some View {
        #if targetEnvironment(simulator)
        // The simulator can't render emoji (LESSONS.md); real devices show the emoji.
        Image(systemName: place.type.symbol).font(.system(size: isSelected ? 18 : 15, weight: .bold)).foregroundStyle(Theme.text)
        #else
        Text(place.type.emoji).font(.system(size: isSelected ? 24 : 19))
        #endif
    }
}

struct ClusterBubble: View {
    let count: Int
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text("\(count)")
                .font(Theme.number(15))
                .foregroundStyle(Theme.onLime)
                .frame(minWidth: 38, minHeight: 38)
                .padding(.horizontal, count > 99 ? 6 : 0)
                .background(Theme.lime, in: Capsule())
                .overlay(Capsule().strokeBorder(.black.opacity(0.3), lineWidth: 2))
                .shadow(color: .black.opacity(0.5), radius: 4, y: 2)
        }
        .buttonStyle(.plain)
    }
}

/// Grid clustering: nearby pins merge into a count bubble when zoomed out.
struct PlaceCluster: Identifiable {
    var id: String
    var places: [Place]
    var center: Coordinate

    static func make(_ places: [Place], region: MKCoordinateRegion?) -> [PlaceCluster] {
        guard let region, region.span.latitudeDelta > 0.015 else {
            return places.map { PlaceCluster(id: $0.id, places: [$0], center: $0.coordinate) }
        }
        let cell = region.span.latitudeDelta / 9
        let groups = Dictionary(grouping: places) { p in
            "\(Int(floor(p.coordinate.latitude / cell)))|\(Int(floor(p.coordinate.longitude / cell)))"
        }
        return groups.map { key, members in
            let lat = members.map(\.coordinate.latitude).reduce(0, +) / Double(members.count)
            let lng = members.map(\.coordinate.longitude).reduce(0, +) / Double(members.count)
            return PlaceCluster(id: members.count == 1 ? members[0].id : "c:\(key)", places: members,
                                center: Coordinate(latitude: lat, longitude: lng))
        }
    }
}

/// First time on the Map: why we want location, before the system prompt.
struct LocationExplainer: View {
    let allow: () -> Void
    let later: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Image(systemName: "location.fill").font(.system(size: 28, weight: .bold)).foregroundStyle(Theme.lime)
            Text("See what you've saved near you").font(Theme.title(24))
            Text("Your map opens on the spots closest to where you are. Location stays on your phone.")
                .font(Theme.body(16)).foregroundStyle(Theme.secondary)
            Button("Sounds good", action: allow).buttonStyle(.pill)
            Button("Not now", action: later).buttonStyle(.plain).font(Theme.body(15, weight: .semibold))
                .foregroundStyle(Theme.secondary).frame(maxWidth: .infinity)
        }
        .card(padding: 22)
        .padding(.horizontal, 20)
        .frame(maxHeight: .infinity)
        .background(.black.opacity(0.5))
    }
}

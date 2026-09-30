import MapKit
import SwiftUI

// MARK: - M1a Nearby list

/// The sheet's list: headline + filters (peek), then rows by distance.
struct NearbyList: View {
    let store: PlaceStore
    let places: [Place]
    let headline: String
    let userLocation: Coordinate?
    let isExpanded: Bool
    let onSelect: (Place) -> Void
    let onJump: (String) -> Void
    let onReview: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(headline).font(Theme.title(22))
                if store.isMatching && !store.allPlaces.isEmpty {
                    Text("Finding \(store.pendingCount) more spots…").font(Theme.body(14)).foregroundStyle(Theme.secondary)
                } else if store.isOffline {
                    Text("We'll finish finding your spots when you're back online.").font(Theme.body(14)).foregroundStyle(Theme.secondary)
                }
            }
            .padding(.horizontal, Theme.padding)
            FilterBar(store: store)
            ScrollView {
                LazyVStack(spacing: 8) {
                    if store.allPlaces.isEmpty && !store.isMatching {
                        noPlaces
                    } else if places.isEmpty && !store.allPlaces.isEmpty {
                        nothingHere
                    }
                    ForEach(places) { place in
                        Button { onSelect(place) } label: { PlaceRow(place: place, userLocation: userLocation) }
                            .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, Theme.padding)
                .padding(.bottom, 24)
            }
            .scrollDisabled(!isExpanded)
            .opacity(isExpanded ? 1 : 0)
        }
    }

    private var nothingHere: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(store.filters.isActive ? "Nothing matches these filters here." : "Nothing saved around here.")
                .font(Theme.body(16, weight: .semibold))
            if !store.filters.isActive {
                Text("Your spots are in " + store.cities.prefix(3).map { "\($0.name) (\($0.count))" }.joined(separator: ", "))
                    .font(Theme.body(15)).foregroundStyle(Theme.secondary)
                WrapLayout {
                    ForEach(store.cities.prefix(4), id: \.name) { city in
                        Chip(label: city.name, detail: "\(city.count)") { onJump(city.name) }
                    }
                }
            } else {
                Button("Clear filters") { store.filters = MapFilters() }.buttonStyle(.pillCompact)
            }
        }
        .card()
    }

    private var noPlaces: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("No places yet").font(Theme.title(20))
            Text("Posts that name a restaurant, café, bar or spot get a pin here.")
                .font(Theme.body(15)).foregroundStyle(Theme.secondary)
            if store.needsReviewCount > 0 {
                Button("Review \(store.needsReviewCount) posts that might be places", action: onReview).buttonStyle(.pillCompact)
            }
        }
        .card()
    }
}

/// Type · status · collection chips. Filters the map and list together.
struct FilterBar: View {
    let store: PlaceStore

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                Chip(label: "All", isSelected: store.filters.type == nil) { store.filters.type = nil }
                ForEach(store.placeTypes) { type in
                    Chip(label: type.title, systemImage: type.symbol, isSelected: store.filters.type == type) {
                        store.filters.type = store.filters.type == type ? nil : type
                    }
                }
                Divider().frame(height: 22).overlay(Theme.stroke)
                Menu {
                    Picker("Status", selection: Binding(get: { store.filters.status }, set: { store.filters.status = $0 })) {
                        ForEach(MapFilters.StatusFilter.allCases, id: \.self) { Text($0.title).tag($0) }
                    }
                } label: {
                    chipLabel(store.filters.status == .all ? "Status" : store.filters.status.title, active: store.filters.status != .all)
                }
                if !store.collections.isEmpty {
                    Menu {
                        Button("All collections") { store.filters.collection = nil }
                        ForEach(store.collections, id: \.self) { c in
                            Button(c) { store.filters.collection = c }
                        }
                    } label: {
                        chipLabel(store.filters.collection ?? "Collection", active: store.filters.collection != nil)
                    }
                }
            }
            .padding(.horizontal, Theme.padding)
        }
    }

    private func chipLabel(_ text: String, active: Bool) -> some View {
        HStack(spacing: 4) {
            Text(text).lineLimit(1)
            Image(systemName: "chevron.down").font(.system(size: 10, weight: .heavy))
        }
        .font(Theme.body(15, weight: .bold))
        .padding(.horizontal, 14).padding(.vertical, 9)
        .foregroundStyle(active ? Theme.onLime : Theme.text)
        .background(active ? Theme.lime : Theme.surface, in: Capsule())
        .overlay(Capsule().strokeBorder(active ? .clear : Theme.stroke))
    }
}

struct PlaceRow: View {
    let place: Place
    let userLocation: Coordinate?

    var body: some View {
        HStack(spacing: 12) {
            ZStack(alignment: .topTrailing) {
                PostThumbnail(post: place.firstPost, symbol: place.type.symbol, size: 52)
                if place.visit == .beenThere {
                    Image(systemName: "checkmark").font(.system(size: 9, weight: .black)).foregroundStyle(Theme.onLime)
                        .frame(width: 18, height: 18).background(Theme.lime, in: Circle()).offset(x: 5, y: -5)
                }
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(place.name).font(Theme.body(17, weight: .bold)).lineLimit(1)
                Text([place.type.title, place.neighborhood].compactMap { $0 }.joined(separator: " · "))
                    .font(Theme.body(14)).foregroundStyle(Theme.secondary).lineLimit(1)
            }
            Spacer(minLength: 0)
            if let userLocation {
                Text(DistanceText.format(place.coordinate.distance(to: userLocation)))
                    .font(Theme.body(14, weight: .semibold)).foregroundStyle(Theme.secondary)
            }
        }
        .padding(12)
        .background(Theme.surface, in: .rect(cornerRadius: Theme.smallRadius))
        .contentShape(.rect)
    }
}

// MARK: - M2 Place card

struct PlaceCard: View {
    let place: Place
    let store: PlaceStore
    let userLocation: Coordinate?
    let onClose: () -> Void
    let onWrongPlace: () -> Void

    @State private var appleItem: MKMapItem?
    @State private var showAppleSheet = false
    @State private var lookAround: MKLookAroundScene?
    @Environment(\.openURL) private var openURL

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        Button { if appleItem != nil { showAppleSheet = true } } label: {
                            Text(place.name).font(Theme.title(28)).multilineTextAlignment(.leading)
                        }
                        .buttonStyle(.plain)
                        .accessibilityHint("Shows Apple Maps details")
                        Text(subtitle).font(Theme.body(15)).foregroundStyle(Theme.secondary)
                    }
                    Spacer()
                    CircleIconButton(systemImage: "xmark", label: "Close", size: 36, action: onClose)
                }

                VStack(spacing: 8) {
                    Button { openDirections() } label: {
                        Label("Directions", systemImage: "arrow.triangle.turn.up.right.diamond.fill")
                    }
                    .buttonStyle(.pill)
                    HStack(spacing: 8) {
                        Button { openURL(place.match.googleMapsURL) } label: {
                            Text("Google Maps").frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.pillCompact)
                        Button { store.toggleBeenThere(place) } label: {
                            Label("Been there", systemImage: place.visit == .beenThere ? "checkmark.circle.fill" : "circle")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(PillButtonStyle(kind: place.visit == .beenThere ? .compactPrimary : .compact))
                        .sensoryFeedback(.success, trigger: place.visit)
                    }
                    .lineLimit(1)
                }

                preview

                Text("Why I saved it").font(Theme.body(15, weight: .bold)).foregroundStyle(Theme.secondary)
                ForEach(place.sources) { source in
                    Button { PostOpener.open(source.post, openURL: openURL) } label: {
                        HStack(spacing: 12) {
                            PostThumbnail(post: source.post, symbol: "play.rectangle.fill", size: 56)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(source.extracted.reason ?? source.post.firstLine ?? "Saved post")
                                    .font(Theme.body(16, weight: .semibold)).lineLimit(2).multilineTextAlignment(.leading)
                                PostByline(post: source.post)
                            }
                            Spacer(minLength: 0)
                            Image(systemName: "arrow.up.right").foregroundStyle(Theme.muted)
                        }
                        .card(padding: 12)
                    }
                    .buttonStyle(.plain)
                }

                HStack {
                    Button("Wrong place?", action: onWrongPlace)
                    Spacer()
                    Button("Hide from map") { store.hide(place); onClose() }
                }
                .font(Theme.body(15, weight: .semibold))
                .foregroundStyle(Theme.secondary)
                .buttonStyle(.plain)
                .padding(.top, 4)
            }
            .padding(.horizontal, Theme.padding)
            .padding(.bottom, 40)
        }
        .task(id: place.id) { await loadApple() }
        .mapItemDetailSheet(isPresented: $showAppleSheet, item: appleItem)
    }

    private var subtitle: String {
        var parts = [place.type.title]
        if let n = place.neighborhood { parts.append(n) }
        if let userLocation { parts.append(DistanceText.format(place.coordinate.distance(to: userLocation))) }
        return parts.joined(separator: " · ")
    }

    /// Thumbnail fallback (map.md): Look Around where Apple has it, else a small map.
    @ViewBuilder private var preview: some View {
        Group {
            if let lookAround {
                LookAroundPreview(initialScene: lookAround, allowsNavigation: false, badgePosition: .bottomTrailing)
            } else {
                Map(initialPosition: .camera(MapCamera(centerCoordinate: place.coordinate.clCoordinate, distance: 600))) {
                    Marker(place.name, systemImage: place.type.symbol, coordinate: place.coordinate.clCoordinate).tint(Theme.lime)
                }
                .disabled(true)
            }
        }
        .frame(height: 150)
        .clipShape(.rect(cornerRadius: Theme.radius))
    }

    private func loadApple() async {
        lookAround = nil
        appleItem = nil
        if !place.match.id.contains("@"), let id = MKMapItem.Identifier(rawValue: place.match.id) {
            appleItem = try? await MKMapItemRequest(mapItemIdentifier: id).mapItem
        }
        let request = appleItem.map { MKLookAroundSceneRequest(mapItem: $0) }
            ?? MKLookAroundSceneRequest(coordinate: place.coordinate.clCoordinate)
        lookAround = try? await request.scene
    }

    private func openDirections() {
        if let appleItem {
            appleItem.openInMaps(launchOptions: [MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeDefault])
        } else {
            openURL(place.match.appleMapsURL)
        }
    }
}

// MARK: - M3 City picker

struct CityPicker: View {
    enum Choice { case nearMe, city(Coordinate, [Place]) }
    let store: PlaceStore
    let hasLocation: Bool
    let onPick: (Choice) -> Void

    var body: some View {
        NavigationStack {
            List {
                if hasLocation {
                    Button { onPick(.nearMe) } label: { Label("Near me", systemImage: "location.fill") }
                        .listRowBackground(Theme.surface)
                }
                ForEach(store.cities, id: \.name) { city in
                    Button {
                        onPick(.city(city.center, store.places(inCity: city.name)))
                    } label: {
                        HStack {
                            Text(city.name).font(Theme.body(17, weight: .semibold))
                            Spacer()
                            Text("\(city.count)").font(Theme.body(15)).foregroundStyle(Theme.secondary)
                        }
                    }
                    .listRowBackground(Theme.surface)
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.background)
            .foregroundStyle(Theme.text)
            .navigationTitle("Your cities")
            .navigationBarTitleDisplayMode(.inline)
        }
        .presentationDetents([.medium, .large])
        .preferredColorScheme(.dark)
    }
}

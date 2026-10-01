import MapKit
import SwiftUI

/// Place confirmation (confirm.md): "is this the place?" cards. One component for
/// the post-onboarding pass, Needs review (M4) and "Wrong place?" (M2).
struct ConfirmationFlow: View {
    enum Mode {
        case onboarding
        case review
        case wrongPlace([PlaceRef])
    }

    let app: AppModel
    let mode: Mode
    let onFinish: () -> Void

    private enum Phase: Equatable {
        case intro, cards, review, alternatives(PlaceRef), done
    }

    @State private var phase: Phase = .intro
    @State private var cards: [[PlaceRef]] = []
    @State private var index = 0
    @State private var undo: (refs: [(PlaceRef, MatchRecord)], index: Int, message: String)?
    @State private var toastTask: Task<Void, Never>?
    @State private var yesStreak = 0
    @State private var toneLine: String?
    /// After alternatives, go back to the review list instead of the next card.
    @State private var returnToReview = false

    private var store: PlaceStore { app.places }

    var body: some View {
        ZStack(alignment: .bottom) {
            Group {
                switch phase {
                case .intro: intro
                case .cards: cardsView
                case .review: reviewList
                case .alternatives(let ref): AlternativesView(store: store, ref: ref, onDone: { answered in afterAlternatives(ref, answered: answered) })
                case .done: done
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .transition(.opacity)
            if let undo {
                UndoToast(message: undo.message) { performUndo() }
                    .padding(.bottom, 12)
            }
        }
        .animation(.snappy, value: phase)
        .animation(.snappy, value: undo?.message)
        .themedScreen()
        .onAppear(perform: start)
    }

    // MARK: - Flow

    private func start() {
        switch mode {
        case .onboarding:
            store.startMatching()
            phase = .intro
        case .review:
            phase = .review
        case .wrongPlace(let refs):
            if let ref = refs.first {
                store.reject(ref)
                phase = .alternatives(ref)
            } else {
                onFinish()
            }
        }
    }

    private func beginCards() {
        cards = store.onboardingCards()
        index = 0
        phase = cards.isEmpty ? .done : .cards
    }

    private func advance() {
        if index + 1 < cards.count {
            index += 1
            phase = .cards
        } else if returnToReview || isReviewMode {
            phase = .review
        } else {
            phase = .done
        }
    }

    private var isReviewMode: Bool { if case .review = mode { true } else { false } }

    private func record(_ refs: [PlaceRef], message: String, _ change: () -> Void) {
        let before = refs.map { ($0, store.record($0)) }
        change()
        showUndo(before, message: message)
    }

    private func showUndo(_ before: [(PlaceRef, MatchRecord)], message: String) {
        undo = (before, index, message)
        toastTask?.cancel()
        toastTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(3))
            if !Task.isCancelled { undo = nil }
        }
    }

    private func performUndo() {
        guard let undo else { return }
        for (ref, rec) in undo.refs { store.restore(ref, to: rec) }
        index = undo.index
        phase = cards.indices.contains(index) ? .cards : (isReviewMode ? .review : .cards)
        self.undo = nil
    }

    private func answerYes(_ refs: [PlaceRef]) {
        record(refs, message: "Placed.") { refs.forEach(store.confirm) }
        yesStreak += 1
        toneLine = yesStreak >= 3 ? "You have taste." : nil
        advance()
    }

    private func answerNo(_ ref: PlaceRef) {
        record([ref], message: "Okay, not that one.") { store.reject(ref) }
        yesStreak = 0
        toneLine = "Good catch."
        phase = .alternatives(ref)
    }

    private func answerSkip(_ refs: [PlaceRef]) {
        record(refs, message: "Skipped. It's in Needs review.") { refs.forEach(store.skip) }
        yesStreak = 0
        toneLine = nil
        advance()
    }

    private func afterAlternatives(_ ref: PlaceRef, answered: AlternativesView.Answer) {
        switch answered {
        case .picked: toneLine = "Fixed."
        case .notAPlace: toneLine = "Fair. That's not a place."
        case .dontKnow: toneLine = nil
        case .cancel: toneLine = nil
        }
        if case .wrongPlace = mode { onFinish(); return }
        if answered == .cancel && cards.indices.contains(index) { phase = .cards; return }
        advance()
    }

    // MARK: - C1 Intro

    private var intro: some View {
        let found = store.totalFound
        let placed = store.placedCount
        let ready = store.onboardingCards().count
        // Cards can start once a full hand is ready; matching carries on behind them.
        let canStart = !store.isMatching || ready >= Triage.onboardingLimit
        let asks = ready
        return VStack(alignment: .leading, spacing: 18) {
            Spacer()
            if store.isMatching && !canStart {
                Text("Finding your spots… \(found - store.pendingCount)")
                    .font(Theme.number(40))
                    .contentTransition(.numericText(value: Double(found - store.pendingCount)))
                ProgressView(value: Double(found - store.pendingCount), total: Double(max(found, 1))).tint(Theme.lime)
                Text("Matching every place you saved with Apple Maps.").font(Theme.body(17)).foregroundStyle(Theme.secondary)
            } else if store.isOffline {
                Text("We'll finish finding your spots when you're back online.").font(Theme.title(30))
            } else {
                Text("We found \(found) spots in your saves.").font(Theme.number(44)).fixedSize(horizontal: false, vertical: true)
                Text(asks == 0 ? "\(placed) are on your map already." : store.isMatching ?
                        "\(placed) are on your map already, more on the way. Help us check \(asks)? Takes 30 seconds." :
                        "\(placed) are on your map already. Help us check \(asks) more? Takes 30 seconds.")
                    .font(Theme.body(19)).foregroundStyle(Theme.secondary)
            }
            Spacer()
            if store.isOffline {
                Button("Open the app") { onFinish() }.buttonStyle(.pill)
            } else {
                Button(asks == 0 && !store.isMatching ? "See my map" : "Let's go") { beginCards() }
                    .buttonStyle(.pill)
                    .disabled(!canStart)
                    .opacity(canStart ? 1 : 0.5)
                Button("Later") { onFinish() }
                    .buttonStyle(.pillSecondary)
            }
        }
        .padding(Theme.padding)
    }

    // MARK: - C2 / C4 / C6 cards

    @ViewBuilder private var cardsView: some View {
        if cards.indices.contains(index) {
            let refs = cards[index]
            VStack(spacing: 14) {
                header(title: isReviewMode ? "Needs review" : nil)
                if let toneLine {
                    Text(toneLine).font(Theme.body(15, weight: .semibold)).foregroundStyle(Theme.lime)
                        .transition(.opacity)
                }
                ScrollView {
                    Group {
                        if refs.count > 1 {
                            ChecklistCard(store: store, refs: refs,
                                          onConfirm: { ticked, unticked in
                                              record(refs, message: "Placed \(ticked.count).") {
                                                  ticked.forEach(store.confirm)
                                                  unticked.forEach(store.markNotAPlace)
                                              }
                                              advance()
                                          },
                                          onFix: { ref in returnToReview = isReviewMode; phase = .alternatives(ref) },
                                          onSkip: { answerSkip(refs) })
                            // a fresh card (and its ticks) per post, not the previous card's state
                            .id(refs[0].key)
                        } else if let ref = refs.first, store.record(ref).status == .cantTell || store.record(ref).match == nil {
                            SearchItYourselfCard(store: store, ref: ref,
                                                 onPlaced: { advance() },
                                                 onNotAPlace: {
                                                     record([ref], message: "Removed from the map.") { store.markNotAPlace(ref) }
                                                     toneLine = "Fair. That's not a place."
                                                     advance()
                                                 },
                                                 onSkip: { answerSkip([ref]) })
                            .id(ref.key)
                        } else if let ref = refs.first {
                            SwipeCard(onRight: { answerYes([ref]) }, onLeft: { answerNo(ref) }) {
                                PlaceQuestionCard(store: store, ref: ref)
                            }
                            .id(ref.key)
                        }
                    }
                    .padding(.horizontal, Theme.padding)
                    .padding(.bottom, 12)
                }
                if refs.count == 1, let ref = refs.first, store.record(ref).match != nil, store.record(ref).status != .cantTell {
                    VStack(spacing: 10) {
                        HStack(spacing: 10) {
                            Button("No") { answerNo(ref) }.buttonStyle(.pillSecondary)
                            Button("Yes") { answerYes([ref]) }.buttonStyle(.pill)
                        }
                        Button("Skip") { answerSkip([ref]) }
                            .font(Theme.body(15, weight: .semibold)).foregroundStyle(Theme.secondary).buttonStyle(.plain)
                    }
                    .padding(.horizontal, Theme.padding)
                    .padding(.bottom, undo == nil ? 8 : 70)
                }
            }
        }
    }

    private func header(title: String?) -> some View {
        VStack(spacing: 8) {
            HStack {
                Button {
                    if isReviewMode { phase = .review } else { onFinish() }
                } label: {
                    Image(systemName: isReviewMode ? "chevron.left" : "xmark")
                        .font(.system(size: 15, weight: .bold)).frame(width: 36, height: 36)
                        .background(Theme.surface, in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(isReviewMode ? "Back" : "Finish later")
                Spacer()
                Text(title ?? "\(index + 1) of \(cards.count)").font(Theme.body(15, weight: .bold)).foregroundStyle(Theme.secondary)
                Spacer()
                Color.clear.frame(width: 36, height: 36)
            }
            if !isReviewMode {
                ProgressView(value: Double(index), total: Double(max(cards.count, 1))).tint(Theme.lime)
            }
        }
        .padding(.horizontal, Theme.padding)
        .padding(.top, 8)
    }

    // MARK: - M4 Needs review

    private var reviewList: some View {
        let groups = store.needsReview
        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Needs review").font(Theme.title(30))
                Spacer()
                Button("Done") { onFinish() }.buttonStyle(.pillCompact)
            }
            .padding(.horizontal, Theme.padding)
            .padding(.top, 12)
            Text("Posts where we think there's a place but couldn't match it for sure.")
                .font(Theme.body(15)).foregroundStyle(Theme.secondary).padding(.horizontal, Theme.padding)
            if groups.isEmpty {
                ContentUnavailableView("All checked", systemImage: "checkmark.circle", description: Text("Nothing left to look at."))
            } else {
                List(Array(groups.enumerated()), id: \.element.first?.key) { i, refs in
                    Button {
                        cards = groups
                        index = i
                        returnToReview = true
                        phase = .cards
                    } label: {
                        ReviewRow(store: store, refs: refs)
                    }
                    .buttonStyle(.plain)
                    .listRowBackground(Theme.surface)
                }
                .scrollContentBackground(.hidden)
            }
        }
    }

    // MARK: - C5 Done

    private var done: some View {
        let places = store.allPlaces.filter { !$0.isHidden }
        let skipped = store.needsReviewCount
        let nothingAsked = cards.isEmpty
        return VStack(alignment: .leading, spacing: 16) {
            Spacer(minLength: 8)
            Text(nothingAsked ? "Nailed all of them. Didn't even need you." : "Map's ready. Go eat something.")
                .font(Theme.body(17, weight: .semibold)).foregroundStyle(Theme.lime)
            Text("Your map is ready. \(places.count) spots.").font(Theme.number(40)).fixedSize(horizontal: false, vertical: true)
            Map(initialPosition: .automatic) {
                ForEach(places.prefix(300)) { place in
                    Annotation(place.name, coordinate: place.coordinate.clCoordinate) {
                        Circle().fill(Theme.lime).frame(width: 9, height: 9).overlay(Circle().stroke(.black.opacity(0.4)))
                    }
                    .annotationTitles(.hidden)
                }
            }
            .disabled(true)
            .frame(height: 260)
            .clipShape(.rect(cornerRadius: Theme.radius))
            if skipped > 0 {
                Text("\(skipped) are in Needs review whenever you want.").font(Theme.body(16)).foregroundStyle(Theme.secondary)
            }
            Spacer()
            Button("Open map") { onFinish() }.buttonStyle(.pill)
        }
        .padding(Theme.padding)
    }
}

// MARK: - Pieces

/// C2's two halves: the saved post (evidence highlighted) and our best guess.
struct PlaceQuestionCard: View {
    let store: PlaceStore
    let ref: PlaceRef

    var body: some View {
        let rec = store.record(ref)
        VStack(alignment: .leading, spacing: 0) {
            if let post = store.post(ref) {
                SavedPostHalf(post: post, evidence: store.extracted(ref).map { [$0.evidence] } ?? [])
                    .padding(18)
            }
            Text("Is this the place?")
                .font(Theme.title(24))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(Theme.surfaceRaised)
            if let match = rec.match {
                GuessHalf(match: match, type: store.extracted(ref)?.type ?? .other).padding(18)
            }
        }
        .background(Theme.surface, in: .rect(cornerRadius: Theme.radius))
        .overlay(RoundedRectangle(cornerRadius: Theme.radius).strokeBorder(Theme.stroke))
        .clipShape(.rect(cornerRadius: Theme.radius))
    }
}

/// Top half: thumbnail (→ the post), author, the caption excerpt with the name in lime.
struct SavedPostHalf: View {
    let post: ContractPost
    let evidence: [String]
    @Environment(\.openURL) private var openURL

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Button { PostOpener.open(post, openURL: openURL) } label: {
                    ZStack {
                        PostThumbnail(post: post, symbol: "play.rectangle.fill", size: 64)
                        Image(systemName: "play.fill").font(.system(size: 16, weight: .bold)).foregroundStyle(.white.opacity(0.9))
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Watch on \(post.platform.displayName)")
                VStack(alignment: .leading, spacing: 4) {
                    Text("Your saved post").font(Theme.label(12)).foregroundStyle(Theme.muted)
                    PostByline(post: post)
                }
            }
            Text(EvidenceText.excerpt(post.caption ?? "", evidence: evidence))
                .font(Theme.body(16))
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// Bottom half: map + name, type, address, "Check in Google Maps ↗".
struct GuessHalf: View {
    let match: MatchedPlace
    let type: PlaceType
    @Environment(\.openURL) private var openURL

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Map(initialPosition: .camera(MapCamera(centerCoordinate: match.coordinate.clCoordinate, distance: 900))) {
                Marker(match.name, systemImage: type.symbol, coordinate: match.coordinate.clCoordinate).tint(Theme.lime)
            }
            .disabled(true)
            .frame(height: 130)
            .clipShape(.rect(cornerRadius: Theme.smallRadius))
            HStack(spacing: 8) {
                Image(systemName: type.symbol).foregroundStyle(Theme.lime)
                Text(match.name).font(Theme.title(21))
            }
            Text([match.address, match.cityWithContext].compactMap { $0 }.joined(separator: " · "))
                .font(Theme.body(15)).foregroundStyle(Theme.secondary)
            Button { openURL(match.googleMapsURL) } label: {
                Label("Check in Google Maps", systemImage: "arrow.up.right")
                    .font(Theme.body(15, weight: .bold)).foregroundStyle(Theme.lime)
            }
            .buttonStyle(.plain)
        }
    }
}

/// Caption excerpt around the evidence, the evidence bold + lime.
enum EvidenceText {
    static func excerpt(_ caption: String, evidence: [String], radius: Int = 110) -> AttributedString {
        let found = evidence.compactMap { e in caption.range(of: e).map { (e, $0) } }
        var text = caption
        if let first = found.first?.1 {
            let start = caption.index(first.lowerBound, offsetBy: -radius, limitedBy: caption.startIndex) ?? caption.startIndex
            let end = caption.index(first.upperBound, offsetBy: radius, limitedBy: caption.endIndex) ?? caption.endIndex
            text = (start > caption.startIndex ? "…" : "") + String(caption[start..<end]) + (end < caption.endIndex ? "…" : "")
        } else if text.count > radius * 2 {
            text = String(text.prefix(radius * 2)) + "…"
        }
        var attributed = AttributedString(text)
        for (e, _) in found {
            if let r = attributed.range(of: e) {
                attributed[r].foregroundColor = Theme.lime
                attributed[r].font = Theme.body(16, weight: .heavy)
            }
        }
        return attributed
    }
}

/// C4: one card for a post with many places.
struct ChecklistCard: View {
    let store: PlaceStore
    let refs: [PlaceRef]
    let onConfirm: ([PlaceRef], [PlaceRef]) -> Void
    let onFix: (PlaceRef) -> Void
    let onSkip: () -> Void
    @State private var unticked: Set<PlaceRef> = []

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let post = store.post(refs[0]) {
                SavedPostHalf(post: post, evidence: refs.compactMap { store.extracted($0)?.evidence })
            }
            Text("We found \(refs.count) places in this post").font(Theme.title(21))
            ForEach(refs, id: \.self) { ref in
                let rec = store.record(ref)
                HStack(spacing: 12) {
                    Button {
                        if unticked.contains(ref) { unticked.remove(ref) } else { unticked.insert(ref) }
                    } label: {
                        Image(systemName: unticked.contains(ref) ? "circle" : "checkmark.circle.fill")
                            .font(.system(size: 24)).foregroundStyle(unticked.contains(ref) ? Theme.muted : Theme.lime)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(unticked.contains(ref) ? "Include" : "Exclude")
                    Button { onFix(ref) } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(rec.match?.name ?? store.extracted(ref)?.name ?? "Unknown").font(Theme.body(16, weight: .bold))
                            Text(rec.match?.address ?? "Not found. Tap to search")
                                .font(Theme.body(13)).foregroundStyle(Theme.secondary).lineLimit(1)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.plain)
                    Image(systemName: "chevron.right").foregroundStyle(Theme.muted)
                }
                .padding(.vertical, 4)
            }
            let ticked = refs.filter { !unticked.contains($0) && store.record($0).match != nil }
            Button("Looks good") { onConfirm(ticked, Array(unticked)) }.buttonStyle(.pill)
            Button("Skip", action: onSkip).buttonStyle(.plain)
                .font(Theme.body(15, weight: .semibold)).foregroundStyle(Theme.secondary).frame(maxWidth: .infinity)
        }
        .card(padding: 18)
        .onAppear {
            // ✓ on by default only for good matches (confirm.md → C4).
            unticked = Set(refs.filter { !isGoodMatch($0) })
        }
    }

    private func isGoodMatch(_ ref: PlaceRef) -> Bool {
        let rec = store.record(ref)
        guard let match = rec.match, let extracted = store.extracted(ref) else { return false }
        let inArea = rec.area?.contains(match.coordinate) ?? false
        return Triage.namesMatch(extracted.name, match.name) && inArea
    }
}

/// C3: "Which one is it?" alternatives + search + not a place / don't know.
struct AlternativesView: View {
    enum Answer: Equatable { case picked, notAPlace, dontKnow, cancel }
    let store: PlaceStore
    let ref: PlaceRef
    let onDone: (Answer) -> Void

    @State private var query = ""
    @State private var results: [MatchedPlace] = []
    @State private var searching = false

    var body: some View {
        let alternatives = store.alternatives(ref)
        let area = store.record(ref).area
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Button { onDone(.cancel) } label: {
                    Image(systemName: "chevron.left").font(.system(size: 15, weight: .bold)).frame(width: 36, height: 36)
                        .background(Theme.surface, in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Back")
                Spacer()
            }
            Text("Which one is it?").font(Theme.title(30))
            if let post = store.post(ref) {
                Text(EvidenceText.excerpt(post.caption ?? "", evidence: store.extracted(ref).map { [$0.evidence] } ?? [], radius: 60))
                    .font(Theme.body(15)).foregroundStyle(Theme.secondary).lineLimit(3)
            }
            HStack {
                Image(systemName: "magnifyingglass").foregroundStyle(Theme.muted)
                TextField("Search for the place", text: $query)
                    .submitLabel(.search)
                    .onSubmit { runSearch() }
                if searching { ProgressView() }
            }
            .padding(12)
            .background(Theme.surface, in: .rect(cornerRadius: Theme.smallRadius))
            ScrollView {
                VStack(spacing: 8) {
                    ForEach(results.isEmpty ? alternatives : results) { candidate in
                        Button {
                            store.pick(ref, candidate)
                            onDone(.picked)
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(candidate.name).font(Theme.body(16, weight: .bold))
                                    Text(candidate.address ?? candidate.cityWithContext ?? "").font(Theme.body(13)).foregroundStyle(Theme.secondary)
                                }
                                Spacer()
                                if let area {
                                    Text(DistanceText.format(candidate.coordinate.distance(to: area.center)))
                                        .font(Theme.body(13)).foregroundStyle(Theme.muted)
                                }
                            }
                            .card(padding: 14)
                        }
                        .buttonStyle(.plain)
                    }
                    if alternatives.isEmpty && results.isEmpty {
                        Text("No other matches nearby. Try searching.").font(Theme.body(15)).foregroundStyle(Theme.secondary)
                            .padding(.vertical, 8)
                    }
                }
            }
            HStack(spacing: 10) {
                Button("It's not a place") { store.markNotAPlace(ref); onDone(.notAPlace) }.buttonStyle(.pillSecondary)
                Button("I don't know") { store.skip(ref); onDone(.dontKnow) }.buttonStyle(.pillSecondary)
            }
        }
        .padding(Theme.padding)
        .onAppear { query = store.extracted(ref)?.name ?? "" }
    }

    private func runSearch() {
        guard !query.isEmpty else { return }
        searching = true
        Task {
            results = await store.search(query, for: ref)
            searching = false
        }
    }
}

/// C6: "can't tell" posts (the place is only in the video): search it yourself.
struct SearchItYourselfCard: View {
    let store: PlaceStore
    let ref: PlaceRef
    let onPlaced: () -> Void
    let onNotAPlace: () -> Void
    let onSkip: () -> Void

    @State private var query = ""
    @State private var results: [MatchedPlace] = []
    @State private var searching = false
    @Environment(\.openURL) private var openURL

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let post = store.post(ref) {
                SavedPostHalf(post: post, evidence: [])
                Button { PostOpener.open(post, openURL: openURL) } label: {
                    Label("Watch on \(post.platform.displayName)", systemImage: "play.fill")
                }
                .buttonStyle(.pillCompact)
            }
            Text("Which place was it?").font(Theme.title(22))
            HStack {
                Image(systemName: "magnifyingglass").foregroundStyle(Theme.muted)
                TextField("Search it yourself", text: $query).submitLabel(.search).onSubmit(runSearch)
                if searching { ProgressView() }
            }
            .padding(12)
            .background(Theme.surfaceRaised, in: .rect(cornerRadius: Theme.smallRadius))
            ForEach(results) { r in
                Button {
                    store.pick(ref, r)
                    onPlaced()
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(r.name).font(Theme.body(16, weight: .bold))
                        Text(r.address ?? r.cityWithContext ?? "").font(Theme.body(13)).foregroundStyle(Theme.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .background(Theme.surfaceRaised, in: .rect(cornerRadius: Theme.smallRadius))
                }
                .buttonStyle(.plain)
            }
            HStack(spacing: 10) {
                Button("Not a place", action: onNotAPlace).buttonStyle(.pillSecondary)
                Button("Skip", action: onSkip).buttonStyle(.pillSecondary)
            }
        }
        .card(padding: 18)
        .onAppear { query = store.extracted(ref)?.name ?? "" }
    }

    private func runSearch() {
        guard !query.isEmpty else { return }
        searching = true
        Task {
            results = await store.search(query, for: ref)
            searching = false
        }
    }
}

/// A row in Needs review.
struct ReviewRow: View {
    let store: PlaceStore
    let refs: [PlaceRef]

    var body: some View {
        HStack(spacing: 12) {
            PostThumbnail(post: store.post(refs[0]), symbol: "mappin.and.ellipse", size: 48)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(Theme.body(16, weight: .bold)).lineLimit(1)
                Text(store.post(refs[0])?.firstLine ?? "").font(Theme.body(13)).foregroundStyle(Theme.secondary).lineLimit(1)
            }
            Spacer()
            Image(systemName: "chevron.right").foregroundStyle(Theme.muted)
        }
    }

    private var title: String {
        if refs.count > 1 { return "\(refs.count) places" }
        if let name = store.extracted(refs[0])?.name { return name }
        return "A place in the video"
    }
}

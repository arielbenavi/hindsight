import SwiftUI

/// The front door: three saves from the past, one card at a time. Not anymore /
/// Open it / Did it each move on; after three, "That's today."
struct TodayScreen: View {
    let app: AppModel
    let showSources: () -> Void
    let showLibrary: () -> Void
    @State private var exitEdge: Edge = .leading
    @State private var drag: CGSize = .zero
    @State private var answeredTick = 0
    @State private var sorting: SortProgress?
    /// "Added to Groceries · 7 items", for a moment after a card was sent somewhere.
    @State private var toast: String?
    /// Dev (beta menu): show the sorting state on demand.
    @AppStorage("debugPreviewTodaySorting") private var previewSorting = false
    /// Sources → Viewing: "Open it" plays the save here (`PlayerSheet`).
    @AppStorage(PlayerGate.playInAppKey) private var playsInApp = true
    /// The save in the player; closing it counts as opened unless answered inside.
    @State private var playing: ContractPost?
    /// Same save, kept past the sheet's binding going nil for `finishPlaying`.
    @State private var played: ContractPost?
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        let library = app.library()
        let posts = app.allPosts
        let byID = Dictionary(posts.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let record = app.today.record
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    header(record)
                    if posts.isEmpty {
                        EmptySavesCard(action: showSources)
                    } else if previewSorting {
                        sortingToday
                    } else if let record, let entry = record.current, let post = byID[entry.id] {
                        cardStack(post: post, entry: entry, record: record, library: library)
                    } else if let record, record.isFinished {
                        TodayDoneView(app: app, record: record, posts: byID, library: library,
                                      oneMore: { withAnimation(.snappy) { _ = app.today.oneMore(app.todayContext(library), saves: app.saves) } },
                                      showLibrary: showLibrary)
                    } else if TodayPlan.empty(hasSaves: true, isSorting: isSorting) == .sorting {
                        sortingToday
                    } else {
                        nothingToday
                    }
                }
                .padding(Theme.padding)
                .padding(.bottom, 24)
            }
            .scrollIndicators(.hidden)
            .scrollBounceBehavior(.basedOnSize) .statusBarStrip()
            .themedScreen()
            .toolbar(.hidden, for: .navigationBar)
            .overlay(alignment: .bottom) {
                if let toast {
                    Label(toast, systemImage: "checkmark.circle.fill")
                        .font(Theme.body(15, weight: .bold))
                        .foregroundStyle(Theme.onLime)
                        .padding(.horizontal, 18).padding(.vertical, 12)
                        .background(Theme.lime, in: Capsule())
                        .padding(.bottom, 16)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
        }
        .sheet(item: $playing, onDismiss: finishPlaying) { post in
            if case .player(let source) = PlayerGate.choice(for: post, playInApp: true) {
                PlayerSheet(app: app, post: post, source: source) { outcome in answer(post, outcome) }
            }
        }
        .sensoryFeedback(.impact(weight: .light), trigger: answeredTick)
        .onAppear { prepare() }
        // Saves arriving (a pull, an import) and sorting (each rewrite reloads the data,
        // moving saves into topics and jobs) can turn an empty set into a real one;
        // a new day starts a new set.
        .onChange(of: app.dataVersion) { _, _ in prepare() }
        .onChange(of: app.allPosts.count) { _, _ in prepare() }
        .onChange(of: scenePhase) { _, phase in if phase == .active { prepare() } }
        .task(id: app.sortRuns) { await followSorting() }
    }

    /// Still sorting the user's own saves (or the first sorted file isn't written yet).
    private var isSorting: Bool { sorting != nil || (app.isMySaves && app.data == nil) }

    private func followSorting() async {
        guard app.isMySaves else { sorting = nil; return }
        for await snapshot in app.sortProgress() {
            sorting = snapshot.isComplete ? nil : snapshot
        }
        sorting = nil
        prepare()
    }

    private func prepare() {
        guard !app.allPosts.isEmpty else { return }
        app.today.prepare(app.todayContext(app.library()), saves: app.saves)
    }

    // MARK: - Header

    private func header(_ record: TodayRecord?) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 4) {
                VStack(alignment: .leading, spacing: 0) {
                    Text(Date.now.formatted(.dateTime.weekday(.wide)).uppercased())
                        .font(Theme.label(13)).tracking(1.6)
                        .foregroundStyle(Theme.muted)
                    Text("Today").font(Theme.title(34))
                }
                Spacer()
                DevMenu(app: app)
                CircleIconButton(systemImage: "gearshape.fill", label: "Sources and settings", action: showSources)
            }
            if let record, !record.picks.isEmpty {
                let total = record.picks.count
                let shown = min(record.position + 1, total)
                HStack(spacing: 12) {
                    HStack(spacing: 5) {
                        ForEach(0..<total, id: \.self) { i in
                            Capsule()
                                .fill(i < record.position ? Theme.lime : i == record.position ? Theme.lime.opacity(0.45) : Theme.surfaceRaised)
                                .frame(height: 6)
                        }
                    }
                    Text(record.isFinished ? "Done" : "\(shown) of \(total)")
                        .font(Theme.body(14, weight: .bold))
                        .foregroundStyle(Theme.secondary)
                        .monospacedDigit()
                        .fixedSize()
                }
                .animation(.snappy, value: record.position)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(record.isFinished ? "Today's saves are done" : "Save \(shown) of \(total)")
            }
        }
    }

    // MARK: - The card

    private func cardStack(post: ContractPost, entry: TodayRecord.Entry, record: TodayRecord, library: LibraryIndex) -> some View {
        let remaining = record.picks.count - record.position
        return VStack(spacing: 22) {
            ZStack(alignment: .top) {
                // Two cards peeking behind: what's left of the set.
                if remaining > 2 { backCard(opacity: 0.45).scaleEffect(0.86, anchor: .bottom).offset(y: 30) }
                if remaining > 1 { backCard(opacity: 0.85).scaleEffect(0.93, anchor: .bottom).offset(y: 15) }
                TodayCard(post: post, reason: entry.reason, topic: library.topicByPost[post.id],
                          action: sendAction(post, library: library))
                    .offset(x: drag.width, y: drag.height * 0.15)
                    .rotationEffect(.degrees(Double(drag.width) / 22))
                    .overlay(alignment: .center) { swipeHint }
                    .gesture(swipe(post))
                    .id(post.id)
                    .transition(.asymmetric(insertion: .scale(scale: 0.94, anchor: .bottom).combined(with: .opacity),
                                            removal: .move(edge: exitEdge).combined(with: .opacity)))
            }
            .padding(.bottom, remaining > 2 ? 30 : remaining > 1 ? 15 : 0)
            actions(post)
        }
    }

    /// Where it's useful ("Open in Maps", "Add to Groceries"): one tap, and the card
    /// counts as handled today. Sits at the card's bottom, so the three buttons stay
    /// clear of the tab bar (LESSONS.md: 420pt card).
    private func sendAction(_ post: ContractPost, library: LibraryIndex) -> AnyView? {
        guard let destination = Destinations.forToday(app.destinationInput(for: post, library: library)) else { return nil }
        return AnyView(TodaySendAction(app: app, post: post, destination: destination) { message in
            showToast(message)
            answer(post, .sent)
        })
    }

    private func showToast(_ message: String) {
        withAnimation(.snappy) { toast = message }
        Task {
            try? await Task.sleep(for: .seconds(2.5))
            withAnimation(.snappy) { if toast == message { toast = nil } }
        }
    }

    private func backCard(opacity: Double) -> some View {
        RoundedRectangle(cornerRadius: 28)
            .fill(Theme.surfaceRaised)
            .overlay(RoundedRectangle(cornerRadius: 28).strokeBorder(Theme.stroke))
            .frame(height: TodayCard.height)
            .opacity(opacity)
    }

    @ViewBuilder private var swipeHint: some View {
        if abs(drag.width) > 30 {
            let done = drag.width > 0
            Label(done ? "Did it" : "Not anymore", systemImage: done ? "checkmark" : "xmark")
                .font(Theme.body(18, weight: .heavy))
                .foregroundStyle(done ? Theme.onLime : Theme.text)
                .padding(.horizontal, 18).padding(.vertical, 12)
                .background(done ? Theme.lime : Theme.surfaceRaised, in: Capsule())
                .opacity(min(1, Double(abs(drag.width) - 30) / 80))
        }
    }

    private func swipe(_ post: ContractPost) -> some Gesture {
        DragGesture(minimumDistance: 20)
            .onChanged { drag = $0.translation }
            .onEnded { value in
                let x = value.predictedEndTranslation.width
                if x > 160 { answer(post, .done) } else if x < -160 { answer(post, .letGo) }
                withAnimation(.spring(duration: 0.3)) { drag = .zero }
            }
    }

    private func actions(_ post: ContractPost) -> some View {
        let plays = PlayerGate.choice(for: post, playInApp: playsInApp) != .external
        return HStack(alignment: .top, spacing: 18) {
            RoundAction(symbol: "xmark", label: "Not anymore") { answer(post, .letGo) }
            Button {
                if plays {
                    played = post
                    playing = post  // counted when the player closes (`finishPlaying`)
                } else {
                    PostOpener.open(post, openURL: openURL)
                    // Counts the open (TodayStore.answer) and moves on.
                    answer(post, .opened)
                }
            } label: {
                Label("Open it", systemImage: plays ? "play.fill" : "arrow.up.right")
                    .font(Theme.body(19, weight: .heavy))
                    .foregroundStyle(Theme.onLime)
                    .frame(maxWidth: .infinity, minHeight: 64)
                    .background(Theme.lime, in: Capsule())
            }
            .buttonStyle(PressableStyle())
            RoundAction(symbol: "checkmark", label: "Did it") { answer(post, .done) }
        }
    }

    /// The player closed: "I did this" / "Not interested" / a destination inside it
    /// already answered; otherwise it counts as opened and Today moves on.
    private func finishPlaying() {
        guard let post = played else { return }
        played = nil
        if app.today.record?.outcomes[post.id] == nil { answer(post, .opened) }
    }

    private func answer(_ post: ContractPost, _ outcome: TodayOutcome) {
        exitEdge = outcome == .done ? .trailing : .leading
        answeredTick += 1
        withAnimation(.spring(duration: 0.38, bounce: 0.12)) {
            app.today.answer(post.id, outcome, saves: app.saves)
        }
        if app.today.record?.isFinished == true {
            let hasEligible = !TodayPlan.eligible(app.todayContext(app.library())).isEmpty
            Task { await TodayNotifications.askOnceAfterFinishing(hasEligible: hasEligible) }
        }
    }

    // MARK: - Nothing to serve

    /// Saves are here but topics aren't yet, so nothing can be picked honestly.
    private var sortingToday: some View {
        VStack(alignment: .leading, spacing: 14) {
            ProgressView().controlSize(.large).tint(Theme.lime)
            Text("Sorting your saves…").font(Theme.title(26))
            Text("Today's three will be ready in a moment.")
                .font(Theme.body(16)).foregroundStyle(Theme.secondary)
            if let sorting {
                Text("\(sorting.decided.formatted()) of \(sorting.total.formatted()) sorted")
                    .font(Theme.body(14, weight: .semibold)).foregroundStyle(Theme.muted)
                    .monospacedDigit()
                    .contentTransition(.numericText(value: Double(sorting.decided)))
            }
        }
        .card(padding: 22)
    }

    private var nothingToday: some View {
        VStack(alignment: .leading, spacing: 14) {
            Image(systemName: "sun.haze.fill").font(.system(size: 30, weight: .bold)).foregroundStyle(Theme.lime)
            Text("Nothing for today").font(Theme.title(26))
            Text("Everything that could come up is done, let go or waiting for a reminder. Your saves are all in the Library.")
                .font(Theme.body(16)).foregroundStyle(Theme.secondary)
            Button("Go to Library", action: showLibrary).buttonStyle(.pill)
        }
        .card(padding: 22)
    }
}

/// One of Today's saves, big: picture, why it's here, who and what, the caption, its topic.
struct TodayCard: View {
    let post: ContractPost
    let reason: String
    let topic: HomeTopic?
    /// Today's "where it's useful" action, at the bottom of the card (`TodaySendAction`).
    var action: AnyView?

    /// Fixed, so the cards behind it peek out by the same amount every time.
    static let height: CGFloat = 420
    static let artHeight: CGFloat = 176

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SaveArt(post: post, glyphSize: 64)
                .frame(height: Self.artHeight)
                .frame(maxWidth: .infinity)
            VStack(alignment: .leading, spacing: 10) {
                Text(reason.uppercased())
                    .font(Theme.label(12)).tracking(1)
                    .foregroundStyle(reason == Resurface.Reason.new.label ? Theme.secondary : Theme.lime)
                Text("\(post.byline) · \(post.kind.rawValue)")
                    .font(Theme.body(17, weight: .heavy))
                    .lineLimit(1)
                Text(post.caption?.nilIfEmpty ?? "No caption")
                    .font(Theme.body(16))
                    .foregroundStyle(post.caption?.nilIfEmpty == nil ? Theme.muted : Theme.secondary)
                    .lineLimit(action == nil ? 4 : 3)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if let topic {
                    HStack(spacing: 6) {
                        Image(systemName: topic.symbol)
                        Text(topic.label).lineLimit(1)
                    }
                    .font(Theme.body(13, weight: .bold))
                    .foregroundStyle(Theme.text)
                    .padding(.horizontal, 10).padding(.vertical, 6)
                    .background(Theme.surfaceRaised, in: Capsule())
                    .padding(.top, 2)
                }
                if let action {
                    Spacer(minLength: 0)
                    action
                }
            }
            .padding(18)
            .frame(height: TodayCard.height - TodayCard.artHeight, alignment: .top)
        }
        .background(Theme.surface)
        .clipShape(.rect(cornerRadius: 28))
        .overlay(RoundedRectangle(cornerRadius: 28).strokeBorder(Theme.stroke))
        .shadow(color: .black.opacity(0.35), radius: 16, y: 8)
        // One element to read, unless it holds a button VoiceOver must reach.
        .accessibilityElement(children: action == nil ? .combine : .contain)
    }
}

/// Round 64pt button with a small label under it (Not anymore, Did it).
private struct RoundAction: View {
    let symbol: String
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: symbol)
                    .font(.system(size: 22, weight: .heavy))
                    .foregroundStyle(Theme.text)
                    .frame(width: 64, height: 64)
                    .background(Theme.surfaceRaised, in: Circle())
                    .overlay(Circle().strokeBorder(Theme.stroke))
                Text(label).font(Theme.body(12, weight: .bold)).foregroundStyle(Theme.secondary)
                    .lineLimit(1).fixedSize()
            }
        }
        .buttonStyle(PressableStyle())
        .accessibilityLabel(label)
    }
}

private struct PressableStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.94 : 1)
            .animation(.spring(duration: 0.2), value: configuration.isPressed)
    }
}

/// "That's today.": what happened to the three, what's new, one more if wanted.
struct TodayDoneView: View {
    let app: AppModel
    let record: TodayRecord
    let posts: [String: ContractPost]
    let library: LibraryIndex
    let oneMore: () -> Void
    let showLibrary: () -> Void

    var body: some View {
        let fresh = TodayPlan.newSinceYesterday(app.allPosts, now: .now)
        let hasMore = !TodayPlan.picks(app.todayContext(library), excluding: Set(record.picks.map(\.id)), limit: 1).isEmpty
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 6) {
                Image(systemName: "checkmark.seal.fill").font(.system(size: 34, weight: .bold)).foregroundStyle(Theme.lime)
                Text("That's today.").font(Theme.title(36))
                Text("Back tomorrow with three more.").font(Theme.body(16)).foregroundStyle(Theme.secondary)
            }
            VStack(spacing: 0) {
                ForEach(Array(record.picks.enumerated()), id: \.element.id) { index, entry in
                    if index > 0 { Rectangle().fill(Theme.stroke).frame(height: 1).padding(.leading, 50) }
                    outcomeRow(entry)
                }
            }
            .padding(.horizontal, 14)
            .background(Theme.surface, in: .rect(cornerRadius: Theme.radius))
            .overlay(RoundedRectangle(cornerRadius: Theme.radius).strokeBorder(Theme.stroke))

            if !fresh.isEmpty { newCard(fresh) }

            if hasMore {
                Button(action: oneMore) { Label("One more", systemImage: "plus") }
                    .buttonStyle(.pillSecondary)
            }
            Text("Three new ones tomorrow at 9:00.")
                .font(Theme.body(13, weight: .semibold))
                .foregroundStyle(Theme.muted)
                .frame(maxWidth: .infinity)
        }
    }

    private func outcomeRow(_ entry: TodayRecord.Entry) -> some View {
        let outcome = record.outcomes[entry.id] ?? .opened
        let post = posts[entry.id]
        return HStack(spacing: 12) {
            Image(systemName: outcome.symbol)
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(outcome == .letGo ? Theme.muted : Theme.lime)
                .frame(width: 36)
            VStack(alignment: .leading, spacing: 2) {
                Text(outcome.verb.uppercased()).font(Theme.label(11)).tracking(0.8).foregroundStyle(Theme.muted)
                Text(post?.firstLine ?? post.map { "\($0.byline)'s \($0.kind.rawValue)" } ?? "A save")
                    .font(Theme.body(15, weight: .bold)).lineLimit(1)
                    .foregroundStyle(outcome == .letGo ? Theme.secondary : Theme.text)
            }
            Spacer(minLength: 0)
        }
        .frame(minHeight: 60)
    }

    private func newCard(_ fresh: [ContractPost]) -> some View {
        let labels = fresh.compactMap { library.topicByPost[$0.id]?.label }
        var seen: Set<String> = []
        let topics = labels.filter { seen.insert($0).inserted }.prefix(3)
        return Button(action: showLibrary) {
            HStack(spacing: 14) {
                Image(systemName: "sparkles").font(.system(size: 20, weight: .bold)).foregroundStyle(Theme.lime)
                    .frame(width: 44, height: 44)
                    .background(Theme.lime.opacity(0.12), in: Circle())
                VStack(alignment: .leading, spacing: 2) {
                    Text("New since yesterday").font(Theme.label(11)).tracking(0.8).foregroundStyle(Theme.muted)
                    Text(fresh.count.counted("save")).font(Theme.body(17, weight: .heavy))
                    if !topics.isEmpty {
                        Text(topics.joined(separator: " · ")).font(Theme.body(13, weight: .semibold))
                            .foregroundStyle(Theme.secondary).lineLimit(1)
                    }
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").foregroundStyle(Theme.muted)
            }
            .card(padding: 14)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }
}

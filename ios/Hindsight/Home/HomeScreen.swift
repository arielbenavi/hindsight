import SwiftUI

/// Where Home's stack can go. Views (Map, Learn, Fitness) are pushed, never
/// opened on their own.
enum HomeRoute: Hashable {
    /// A view; `topicID` scopes it to one topic (from a topic page).
    case lego(LegoScreen, topicID: String?)
    /// A `HomeTopic` by id.
    case topic(String)
    case allSaves
}

/// The app after onboarding, one fixed screen: Today (resurfaced saves), the
/// views that have content, Topics, and Recent. Works from the raw imports;
/// topics fill in as sorting finishes in the background.
struct HomeScreen: View {
    let app: AppModel
    /// A `NavigationPath`, not `[HomeRoute]`: the views push their own values
    /// (Learn's topics, Fitness's body areas) onto this stack too.
    @State private var path = NavigationPath()
    @State private var query = ""
    @State private var showsSources = false
    @State private var progress: SortProgress?
    @FocusState private var searchFocused: Bool
    @Environment(\.scenePhase) private var scenePhase

    static let recentCount = 15

    var body: some View {
        let posts = app.allPosts
        let topics = HomeTopics.build(data: app.data, posts: posts)
        NavigationStack(path: $path) {
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    VStack(alignment: .leading, spacing: 14) {
                        header
                        if !posts.isEmpty { SaveSearchField(text: $query, focused: $searchFocused) }
                        if let progress { sortingStrip(progress) }
                    }
                    if posts.isEmpty {
                        emptyCard
                    } else if !query.isEmpty {
                        results(posts)
                    } else {
                        today(posts)
                        views
                        topicsSection(topics)
                        recent(posts)
                    }
                }
                .padding(Theme.padding)
                .padding(.bottom, 24)
            }
            .scrollIndicators(.hidden)
            .scrollDismissesKeyboard(.immediately)
            // No nav bar here: keep scrolled cards out from under the status bar.
            .overlay(alignment: .top) { Theme.background.ignoresSafeArea(edges: .top).frame(height: 0) }
            .themedScreen()
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: HomeRoute.self) { destination($0, topics: topics) }
        }
        .sheet(isPresented: $showsSources, onDismiss: { app.importsChanged() }) {
            if let store = app.store { SourcesView(store: store) }
        }
        .task(id: app.sortRuns) { await followSorting() }
        // Pull from the server on launch and on every return to the app (at most once a minute).
        .task { await app.syncWithServer() }
        // New saves (a pull, an import): sort them. Not while Sources is open, since the
        // first own saves switch Home from the sample, which would close the sheet.
        .onChange(of: app.store?.posts.count) { _, _ in
            if !showsSources { app.importsChanged() }
        }
        .onAppear {
            ReminderScheduler.shared.setOnOpen { screen, id in
                app.practice.deepLink = (screen, id)
                path = NavigationPath([HomeRoute.lego(screen, topicID: nil)])
            }
            app.rescheduleReminders()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background { app.rescheduleReminders() }
            if phase == .active { Task { await app.syncWithServer() } }
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .center, spacing: 4) {
            Text("hindsight")
                .font(Theme.number(40))
                .foregroundStyle(Theme.lime)
            Spacer()
            DevMenu(app: app)
            CircleIconButton(systemImage: "gearshape.fill", label: "Sources and settings") { showsSources = true }
        }
    }

    private func sortingStrip(_ progress: SortProgress) -> some View {
        HStack(spacing: 10) {
            ProgressView().controlSize(.small).tint(Theme.lime)
            Text("Sorting your saves… \(progress.decided.formatted()) / \(progress.total.formatted())")
                .font(Theme.body(14, weight: .semibold))
                .foregroundStyle(Theme.secondary)
                .contentTransition(.numericText(value: Double(progress.decided)))
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
        .background(Theme.surface, in: Capsule())
        .overlay(Capsule().strokeBorder(Theme.stroke))
    }

    /// Only while the user's saves are being sorted.
    private func followSorting() async {
        guard app.isMySaves else { progress = nil; return }
        for await snapshot in app.sortProgress() {
            withAnimation(.snappy) { progress = snapshot.isComplete ? nil : snapshot }
        }
        progress = nil
    }

    private var emptyCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Image(systemName: "tray").font(.system(size: 30, weight: .bold)).foregroundStyle(Theme.lime)
            Text("No saves yet").font(Theme.title(26))
            Text("Bring in what you've saved on Instagram, Facebook, X or WhatsApp. It shows up here.")
                .font(Theme.body(16)).foregroundStyle(Theme.secondary)
            Button("Add your saves") { showsSources = true }.buttonStyle(.pill)
        }
        .card(padding: 22)
    }

    // MARK: - Sections

    private func sectionTitle(_ text: String, trailing: String? = nil) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(text)
                .font(Theme.label(13))
                .tracking(1.4)
                .foregroundStyle(Theme.muted)
            Spacer()
            if let trailing {
                Text(trailing).font(Theme.label(13)).foregroundStyle(Theme.muted)
            }
        }
    }

    @ViewBuilder private func today(_ posts: [ContractPost]) -> some View {
        let picks = Resurface.picks(posts: posts, today: .now)
        if !picks.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                sectionTitle("TODAY")
                ForEach(picks) { TodayCard(pick: $0) }
            }
        }
    }

    /// Places, Tips, Workouts: only the ones with something in them.
    @ViewBuilder private var views: some View {
        let cards = viewCards
        if !cards.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                sectionTitle("VIEWS")
                // Same 2-column grid as Topics: one card stays half width.
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                    ForEach(cards, id: \.screen) { card in
                        NavigationLink(value: HomeRoute.lego(card.screen, topicID: nil)) {
                            VStack(alignment: .leading, spacing: 8) {
                                Image(systemName: card.screen.symbol)
                                    .font(.system(size: 22, weight: .bold))
                                    .foregroundStyle(Theme.lime)
                                    .frame(height: 26, alignment: .leading)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(card.screen.homeTitle).font(Theme.body(17, weight: .heavy))
                                    Text(card.detail).font(Theme.body(13, weight: .semibold)).foregroundStyle(Theme.secondary)
                                        .lineLimit(1).minimumScaleFactor(0.8)
                                        .contentTransition(.numericText())
                                }
                            }
                            .card(padding: 14)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private var viewCards: [(screen: LegoScreen, detail: String)] {
        guard let data = app.data else { return [] }
        var cards: [(screen: LegoScreen, detail: String)] = []
        let mapPosts = data.topics.filter { $0.legoScreen == .map }.reduce(0) { $0 + $1.postIds.count }
        if mapPosts > 0 {
            // While places are still being matched the pin count is small and wrong: show saves.
            let spots = app.places.allPlaces.count
            cards.append((.map, app.places.isMatching || spots == 0 ? mapPosts.counted("save") : spots.counted("spot")))
        }
        if let tips = app.learn?.tips.count, tips > 0 { cards.append((.learn, tips.counted("tip"))) }
        if let routines = app.fitness?.routines.count, routines > 0 { cards.append((.fitness, routines.counted("move"))) }
        return cards
    }

    @ViewBuilder private func topicsSection(_ topics: [HomeTopic]) -> some View {
        if !topics.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                sectionTitle("TOPICS", trailing: progress == nil ? nil : "more on the way")
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                    ForEach(topics) { topic in
                        NavigationLink(value: HomeRoute.topic(topic.id)) {
                            HStack(spacing: 10) {
                                TopicIcon(topic: topic, size: 34)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(topic.label).font(Theme.body(15, weight: .bold)).lineLimit(2).minimumScaleFactor(0.85)
                                    Text(topic.count.formatted()).font(Theme.body(13, weight: .semibold)).foregroundStyle(Theme.muted)
                                }
                                Spacer(minLength: 0)
                            }
                            // Room for a two-line name, so a row's cards line up.
                            .frame(minHeight: 58)
                            .card(padding: 10)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private func recent(_ posts: [ContractPost]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle("RECENT")
            ForEach(posts.prefix(Self.recentCount)) { SaveCardRow(post: $0) }
            NavigationLink(value: HomeRoute.allSaves) {
                Text("See all \(posts.count.formatted())")
            }
            .buttonStyle(.pillSecondary)
            .padding(.top, 4)
        }
    }

    @ViewBuilder private func results(_ posts: [ContractPost]) -> some View {
        let shown = SaveSearch.filter(posts, query: query)
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle("\(shown.count.formatted()) \(shown.count == 1 ? "MATCH" : "MATCHES")")
            if shown.isEmpty {
                Text("Nothing for \"\(query)\".").font(Theme.body(17, weight: .semibold)).padding(.vertical, 8)
            }
            LazyVStack(spacing: 10) {
                ForEach(shown) { SaveCardRow(post: $0) }
            }
        }
    }

    // MARK: - Destinations

    @ViewBuilder private func destination(_ route: HomeRoute, topics: [HomeTopic]) -> some View {
        switch route {
        case .allSaves:
            AllSavesScreen(app: app)
        case .topic(let id):
            if let topic = topics.first(where: { $0.id == id }) {
                TopicScreen(app: app, topic: topic)
            } else {
                ContentUnavailableView("This topic is gone", systemImage: "questionmark.folder").themedScreen()
            }
        case .lego(let screen, let topicID):
            legoScreen(screen, topicID: topicID)
        }
    }

    @ViewBuilder private func legoScreen(_ screen: LegoScreen, topicID: String?) -> some View {
        let topic = topicID.flatMap { app.data?.topic($0) }
        let tab = topic.map { TabConfig(legoScreen: screen, title: $0.label, topicIDs: [$0.id]) } ?? app.tab(for: screen)
        switch screen {
        case .map:
            MapScreen(app: app, tab: tab)
        case .learn:
            // A Learn topic already has its own page.
            if let topicID, let section = app.learn?.section(topicID) {
                LearnTopicView(app: app, section: section)
            } else {
                LearnScreen(app: app, tab: tab)
            }
        case .fitness:
            FitnessScreen(app: app, tab: tab)
        }
    }
}

/// One resurfaced save: thumbnail (or the platform's glyph), who and what, the
/// first caption lines, and why it's here. Opens the post.
struct TodayCard: View {
    let pick: Resurface.Pick
    @Environment(\.openURL) private var openURL

    var body: some View {
        let post = pick.post
        Button { PostOpener.open(post, openURL: openURL) } label: {
            HStack(alignment: .top, spacing: 14) {
                PostLinkThumbnail(post: post, size: 72)
                VStack(alignment: .leading, spacing: 6) {
                    Text(pick.reason.label.uppercased())
                        .font(Theme.label(11))
                        .tracking(0.6)
                        .foregroundStyle(pick.reason == .new ? Theme.secondary : Theme.lime)
                    Text("\(post.byline) · \(post.kind.rawValue)")
                        .font(Theme.body(14, weight: .bold))
                        .lineLimit(1)
                    Text(post.caption?.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty ?? "No caption")
                        .font(Theme.body(14))
                        .foregroundStyle(post.caption == nil ? Theme.muted : Theme.secondary)
                        .lineLimit(3)
                        .multilineTextAlignment(.leading)
                }
                Spacer(minLength: 0)
            }
            .card(padding: 14)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }
}

private extension String {
    var nonEmpty: String? { isEmpty ? nil : self }
}

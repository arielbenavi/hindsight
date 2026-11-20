import SwiftUI

/// Where the Library's stack can go. Views (Map, Learn, Fitness) are pushed, never
/// opened on their own.
enum LibraryRoute: Hashable {
    /// A view; `topicID` scopes it to one topic (from a topic page).
    case lego(LegoScreen, topicID: String?)
    /// A `HomeTopic` by id.
    case topic(String)
    case allSaves
    case letGo
}

/// The Library tab: every topic, grouped by what it's for (Go, Do, Learn, Keep
/// close, Look, Know), search on top, "N saves still need a home" at the end.
/// Works from the raw imports; topics fill in as sorting finishes in the background.
struct LibraryScreen: View {
    let app: AppModel
    @Binding var path: NavigationPath
    let showSources: () -> Void
    @State private var query = ""
    @State private var progress: SortProgress?
    @FocusState private var searchFocused: Bool

    var body: some View {
        let posts = app.allPosts
        let library = app.library()
        NavigationStack(path: $path) {
            ScrollView {
                VStack(alignment: .leading, spacing: 26) {
                    VStack(alignment: .leading, spacing: 14) {
                        header
                        if !posts.isEmpty { SaveSearchField(text: $query, focused: $searchFocused) }
                        if let progress { sortingStrip(progress) }
                    }
                    if posts.isEmpty {
                        EmptySavesCard(action: showSources)
                    } else if !query.isEmpty {
                        results(posts)
                    } else {
                        ForEach(TopicJob.libraryOrder) { job in jobSection(job, library: library) }
                        footerLinks(library: library, posts: posts)
                    }
                }
                .padding(Theme.padding)
                .padding(.bottom, 24)
            }
            .scrollIndicators(.hidden)
            .scrollDismissesKeyboard(.immediately) .statusBarStrip()
            .themedScreen()
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: LibraryRoute.self) { destination($0, library: library) }
        }
        .saveDetailHost(app: app)
        .task(id: app.sortRuns) { await followSorting() }
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .center, spacing: 4) {
            Text("Library").font(Theme.title(34))
            Spacer()
            DevMenu(app: app)
            CircleIconButton(systemImage: "gearshape.fill", label: "Sources and settings", action: showSources)
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

    // MARK: - Sections by job

    @ViewBuilder private func jobSection(_ job: TopicJob, library: LibraryIndex) -> some View {
        let gone = app.saves.letGoIDs
        let topics = library.topics(doing: job).filter { $0.postIDs.contains { !gone.contains($0) } }
        if !topics.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                JobHeader(job: job, trailing: viewLink(for: job))
                if job == .keepClose {
                    keepCloseCard(topics)
                } else {
                    ForEach(topics) { topic in
                        NavigationLink(value: LibraryRoute.topic(topic.id)) {
                            TopicRow(topic: topic, detail: countLine(topic, job: job, gone: gone))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    /// Places / Tips / Workouts across topics, next to the section they belong to.
    private func viewLink(for job: TopicJob) -> (title: String, route: LibraryRoute)? {
        switch job {
        case .go where app.data?.topics.contains { $0.legoScreen == .map } == true:
            ("Map", .lego(.map, topicID: nil))
        case .learn where (app.learn?.tips.count ?? 0) > 0:
            ("All tips", .lego(.learn, topicID: nil))
        case .doIt where (app.fitness?.routines.count ?? 0) > 0:
            ("Workouts", .lego(.fitness, topicID: nil))
        default: nil
        }
    }

    /// Keep close is quieter: one calm card, no counts, its topics as plain lines.
    private func keepCloseCard(_ topics: [HomeTopic]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(topics.enumerated()), id: \.element.id) { index, topic in
                if index > 0 { Rectangle().fill(ShelfStyle.accent.opacity(0.12)).frame(height: 1) }
                NavigationLink(value: LibraryRoute.topic(topic.id)) {
                    HStack(spacing: 12) {
                        Image(systemName: "leaf.fill").foregroundStyle(ShelfStyle.accent).frame(width: 24)
                        Text(topic.label).font(Theme.body(17, weight: .bold)).foregroundStyle(ShelfStyle.text)
                        Spacer()
                        Image(systemName: "chevron.right").font(.system(size: 13, weight: .bold)).foregroundStyle(ShelfStyle.muted)
                    }
                    .frame(minHeight: 54)
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 16)
        .background(ShelfStyle.background, in: .rect(cornerRadius: Theme.radius))
        .overlay(RoundedRectangle(cornerRadius: Theme.radius).strokeBorder(ShelfStyle.accent.opacity(0.18)))
    }

    private func countLine(_ topic: HomeTopic, job: TopicJob, gone: Set<String>) -> String {
        let ids = topic.postIDs.filter { !gone.contains($0) }
        let saves = ids.count.counted("save")
        switch job {
        case .doIt:
            let done = ids.count { app.saves.status($0) == .done }
            return "\(saves) · \(done.formatted()) done"
        case .go:
            guard topic.legoScreen == .map, !app.places.isMatching else { return saves }
            let set = Set(ids)
            let spots = app.places.allPlaces.count { $0.sources.contains { set.contains($0.ref.postID) } }
            return spots > 0 ? "\(saves) · \(spots.counted("place"))" : saves
        default:
            return saves
        }
    }

    // MARK: - Footer

    @ViewBuilder private func footerLinks(library: LibraryIndex, posts: [ContractPost]) -> some View {
        let gone = app.saves.letGoIDs
        VStack(alignment: .leading, spacing: 10) {
            if let other = library.other, case let count = other.postIDs.count(where: { !gone.contains($0) }), count > 0 {
                NavigationLink(value: LibraryRoute.topic(other.id)) {
                    LinkRow(symbol: "tray.full.fill", title: "\(count.counted("save")) still need a home",
                            detail: "Small topics and saves with nothing to go on")
                }
                .buttonStyle(.plain)
            }
            NavigationLink(value: LibraryRoute.allSaves) {
                LinkRow(symbol: "square.stack.fill", title: "All saves", detail: "\(posts.count.counted("save")), newest first")
            }
            .buttonStyle(.plain)
            if !gone.isEmpty {
                NavigationLink(value: LibraryRoute.letGo) {
                    LinkRow(symbol: "xmark.circle", title: "Let go", detail: "\(gone.count.counted("save")) you're done with")
                }
                .buttonStyle(.plain)
            }
        }
    }

    @ViewBuilder private func results(_ posts: [ContractPost]) -> some View {
        let shown = SaveSearch.filter(posts, query: query)
        VStack(alignment: .leading, spacing: 10) {
            SectionLabel(text: "\(shown.count.formatted()) \(shown.count == 1 ? "MATCH" : "MATCHES")")
            if shown.isEmpty {
                Text("Nothing for \"\(query)\".").font(Theme.body(17, weight: .semibold)).padding(.vertical, 8)
            }
            LazyVStack(spacing: 10) {
                ForEach(shown) { SaveCardRow(post: $0, app: app) }
            }
        }
    }

    // MARK: - Destinations

    @ViewBuilder private func destination(_ route: LibraryRoute, library: LibraryIndex) -> some View {
        switch route {
        case .allSaves:
            AllSavesScreen(app: app)
        case .letGo:
            LetGoScreen(app: app)
        case .topic(let id):
            if let topic = library.topic(id) {
                TopicDestination(app: app, topic: topic, job: library.job(topic))
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

// MARK: - Pieces

/// "DO · shows in Today until done", with the job's symbol.
struct JobHeader: View {
    let job: TopicJob
    var trailing: (title: String, route: LibraryRoute)?

    var body: some View {
        let accent = job == .keepClose ? ShelfStyle.accent : Theme.lime
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: job.symbol)
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(accent)
                .frame(width: 36, height: 36)
                .background(accent.opacity(0.12), in: Circle())
            VStack(alignment: .leading, spacing: 1) {
                Text(job.title).font(Theme.title(22))
                Text("\(job.title) · \(job.whenLine)").font(Theme.body(13, weight: .semibold)).foregroundStyle(Theme.muted)
                    .lineLimit(1).minimumScaleFactor(0.8)
            }
            Spacer(minLength: 4)
            if let trailing {
                NavigationLink(value: trailing.route) {
                    Text(trailing.title)
                }
                .buttonStyle(.pillCompact)
            }
        }
        .accessibilityElement(children: .contain)
    }
}

/// One topic in a Library section.
struct TopicRow: View {
    let topic: HomeTopic
    let detail: String

    var body: some View {
        HStack(spacing: 12) {
            TopicIcon(topic: topic, size: 36)
            VStack(alignment: .leading, spacing: 2) {
                Text(topic.label).font(Theme.body(16, weight: .bold)).lineLimit(2)
                Text(detail).font(Theme.body(13, weight: .semibold)).foregroundStyle(Theme.muted)
                    .contentTransition(.numericText())
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right").font(.system(size: 13, weight: .bold)).foregroundStyle(Theme.muted)
        }
        .card(padding: 10)
        .contentShape(.rect)
    }
}

/// A quieter link row (All saves, Let go, saves that need a home).
struct LinkRow: View {
    let symbol: String
    let title: String
    let detail: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: symbol).font(.system(size: 17, weight: .bold)).foregroundStyle(Theme.secondary).frame(width: 40)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(Theme.body(16, weight: .bold))
                Text(detail).font(Theme.body(13, weight: .semibold)).foregroundStyle(Theme.muted)
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right").font(.system(size: 13, weight: .bold)).foregroundStyle(Theme.muted)
        }
        .padding(.vertical, 12).padding(.horizontal, 12)
        .background(Theme.surface.opacity(0.6), in: .rect(cornerRadius: Theme.radius))
        .contentShape(.rect)
    }
}

/// Small spaced caps label for a section.
struct SectionLabel: View {
    let text: String
    var trailing: String?

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(text).font(Theme.label(13)).tracking(1.4).foregroundStyle(Theme.muted)
            Spacer()
            if let trailing { Text(trailing).font(Theme.label(13)).foregroundStyle(Theme.muted) }
        }
    }
}

/// No saves at all: bring some in.
struct EmptySavesCard: View {
    let action: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Image(systemName: "tray").font(.system(size: 30, weight: .bold)).foregroundStyle(Theme.lime)
            Text("No saves yet").font(Theme.title(26))
            Text("Bring in what you've saved on Instagram, Facebook, X or WhatsApp. It shows up here.")
                .font(Theme.body(16)).foregroundStyle(Theme.secondary)
            Button("Add your saves", action: action).buttonStyle(.pill)
        }
        .card(padding: 22)
    }
}

/// Saves the user let go of: still here, one tap to bring back (in the detail sheet).
struct LetGoScreen: View {
    let app: AppModel

    var body: some View {
        let gone = app.saves.letGoIDs
        let posts = app.allPosts.filter { gone.contains($0.id) }
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 10) {
                ScreenHeader(title: "Let go", subtitle: "\(posts.count.counted("save")). Open one to bring it back.") { EmptyView() }
                    .padding(.bottom, 6)
                ForEach(posts) { SaveCardRow(post: $0, app: app) }
                if posts.isEmpty {
                    Text("Nothing here.").font(Theme.body(17, weight: .semibold)).padding(.vertical, 8)
                }
            }
            .padding(Theme.padding)
        }
        .scrollIndicators(.hidden)
        .themedScreen()
        .pushedScreen()
    }
}

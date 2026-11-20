import SwiftUI

/// A topic's page in the shape its job asks for: a checklist (Do), a picture
/// board (Look), the quiet shelf (Keep close), or the plain list (Go, Learn, Know;
/// with "Open map" / "Open tips" when the topic has a view).
struct TopicDestination: View {
    let app: AppModel
    let topic: HomeTopic
    let job: TopicJob

    var body: some View {
        switch job {
        case .doIt: DoListScreen(app: app, topic: topic)
        case .look: LookBoardScreen(app: app, topic: topic)
        case .keepClose: KeepCloseScreen(app: app, topic: topic)
        case .go, .learn, .know: TopicScreen(app: app, topic: topic)
        }
    }
}

extension AppModel {
    /// A topic's saves in order, without the ones the user let go of.
    func posts(in topic: HomeTopic) -> [ContractPost] {
        let byID = Dictionary(allPosts.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let gone = saves.letGoIDs
        return topic.postIDs.filter { !gone.contains($0) }.compactMap { byID[$0] }
    }
}

/// One topic's saves as a list: search, platform filter, and the view that fits
/// it ("Open map") when there is one.
struct TopicScreen: View {
    let app: AppModel
    let topic: HomeTopic
    @State private var query = ""
    @State private var platform: Platform?

    var body: some View {
        let all = app.posts(in: topic)
        let shown = SaveSearch.filter(all, query: query, platform: platform)
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 10) {
                TopicTitle(topic: topic, line: kindLine(all.count))
                    .padding(.bottom, 6)
                if let screen = topic.legoScreen {
                    NavigationLink(value: LibraryRoute.lego(screen, topicID: topic.topicID)) {
                        Label(screen.openTitle, systemImage: screen.symbol)
                    }
                    .buttonStyle(.pill)
                    .padding(.bottom, 4)
                }
                SaveSearchField(text: $query, prompt: "Search \(topic.label)")
                PlatformFilterChips(posts: all, selection: $platform)
                ForEach(shown) { SaveCardRow(post: $0, app: app) }
                if shown.isEmpty {
                    Text(query.isEmpty ? "Nothing here yet." : "Nothing for \"\(query)\".")
                        .font(Theme.body(17, weight: .semibold))
                        .padding(.vertical, 8)
                }
            }
            .padding(Theme.padding)
        }
        .scrollIndicators(.hidden)
        .scrollDismissesKeyboard(.immediately)
        .themedScreen()
        .pushedScreen()
        .topicJobMenu(app: app, topic: topic)
    }

    private func kindLine(_ count: Int) -> String {
        let saves = count.counted("save")
        let job = app.library().job(topic)
        switch topic.kind {
        case .ai: return "\(saves) · \(job.title)"
        case .collection: return "\(saves) · your collection · \(job.title)"
        case .other: return "\(saves) · small topics and collections"
        }
    }
}

/// Icon, name and a line under it, at the top of a topic page.
struct TopicTitle: View {
    let topic: HomeTopic
    let line: String
    var accent: Color?

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            TopicIcon(topic: topic, size: 52, tint: accent)
            VStack(alignment: .leading, spacing: 2) {
                Text(topic.label).font(Theme.title(30)).lineLimit(2).minimumScaleFactor(0.7)
                Text(line).font(Theme.body(15)).foregroundStyle(Theme.secondary)
            }
            Spacer(minLength: 0)
        }
    }
}

/// A topic's emoji on a device; its SF Symbol in the simulator, which can't draw emoji (LESSONS.md).
struct TopicIcon: View {
    let topic: HomeTopic
    var size: CGFloat = 36
    var tint: Color?

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.3).fill(Theme.surfaceRaised)
            #if targetEnvironment(simulator)
            symbol
            #else
            if let emoji = topic.emoji { Text(emoji).font(.system(size: size * 0.5)) } else { symbol }
            #endif
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }

    private var symbol: some View {
        Image(systemName: topic.symbol)
            .font(.system(size: size * 0.4, weight: .bold))
            .foregroundStyle(tint ?? (topic.kind == .ai ? Theme.lime : Theme.secondary))
    }
}

// MARK: - "What is this for?"

extension View {
    /// The topic page's header menu: "What is this for?" opens the job picker.
    func topicJobMenu(app: AppModel, topic: HomeTopic) -> some View {
        modifier(TopicJobMenu(app: app, topic: topic))
    }
}

private struct TopicJobMenu: ViewModifier {
    let app: AppModel
    let topic: HomeTopic
    @State private var picking = false

    func body(content: Content) -> some View {
        content
            .toolbar {
                if topic.kind != .other {
                    ToolbarItem(placement: .topBarTrailing) {
                        Menu {
                            Button("What is this for?", systemImage: "questionmark.circle") { picking = true }
                        } label: {
                            Image(systemName: "ellipsis")
                        }
                        .accessibilityLabel("Topic options")
                    }
                }
            }
            .sheet(isPresented: $picking) { JobPickerSheet(app: app, topic: topic) }
    }
}

/// The six jobs with what each means; the suggested one badged, the current one
/// selected. "Use this" applies.
struct JobPickerSheet: View {
    let app: AppModel
    let topic: HomeTopic
    @State private var selection: TopicJob?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let current = app.library().job(topic)
        let suggested = TopicJobs.suggested(for: topic)
        let chosen = selection ?? current
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    Text("What is \(topic.label) for?")
                        .font(Theme.title(26))
                        .padding(.bottom, 2)
                    Text("It decides where these saves come up, and how the page looks.")
                        .font(Theme.body(15)).foregroundStyle(Theme.secondary)
                        .padding(.bottom, 8)
                    ForEach(TopicJob.libraryOrder) { job in
                        jobRow(job, selected: chosen == job, suggested: suggested == job)
                    }
                }
                .padding(Theme.padding)
            }
            .safeAreaInset(edge: .bottom) {
                Button(chosen == current ? "Keep it as \(current.title)" : "Make it \(chosen.title)") {
                    // The suggested job isn't stored, so a later better guess still applies.
                    app.topicPrefs.setJob(chosen == suggested ? nil : chosen, for: topic.id)
                    dismiss()
                }
                .buttonStyle(.pill)
                .padding(.horizontal, Theme.padding)
                .padding(.vertical, 10)
                .background(Theme.background)
            }
            .themedScreen()
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
        }
        .tint(Theme.lime)
        .presentationDragIndicator(.visible)
    }

    private func jobRow(_ job: TopicJob, selected: Bool, suggested: Bool) -> some View {
        let accent = job == .keepClose ? ShelfStyle.accent : Theme.lime
        return Button { withAnimation(.snappy) { selection = job } } label: {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: job.symbol)
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(accent)
                    .frame(width: 36, height: 36)
                    .background(accent.opacity(0.12), in: Circle())
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text(job.title).font(Theme.body(17, weight: .heavy))
                        if suggested { Tag(text: "Suggested", color: accent) }
                    }
                    Text(job.pitch).font(Theme.body(13)).foregroundStyle(Theme.secondary)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(selected ? accent : Theme.muted)
            }
            .padding(.horizontal, 14).padding(.vertical, 11)
            .background(selected ? Theme.surfaceRaised : Theme.surface, in: .rect(cornerRadius: Theme.radius))
            .overlay(RoundedRectangle(cornerRadius: Theme.radius).strokeBorder(selected ? accent.opacity(0.6) : Theme.stroke))
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

extension LegoScreen {
    /// The Library's names for the views: Places, Tips, Workouts.
    var homeTitle: String {
        switch self {
        case .map: "Places"
        case .learn: "Tips"
        case .fitness: "Workouts"
        }
    }

    var openTitle: String {
        switch self {
        case .map: "Open map"
        case .learn: "Open tips"
        case .fitness: "Open workouts"
        }
    }
}

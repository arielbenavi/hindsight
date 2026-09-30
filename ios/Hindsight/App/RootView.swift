import SwiftUI

/// Everything after the Connect screen: the setup chat (receipt → reading →
/// proposal → place check → "You're in"), then the tabs. `HindsightApp` shows
/// this once onboarding is done. Spec: docs/specs/onboarding-chat.md.
struct RootView: View {
    @State private var app: AppModel

    init(store: SavedPostStore? = nil, useMySaves: Bool = false) {
        _app = State(initialValue: AppModel(store: store, useMySaves: useMySaves))
        ReminderScheduler.shared.install()
    }

    var body: some View {
        Group {
            if let error = app.loadError {
                ContentUnavailableView("Couldn't load your saves", systemImage: "exclamationmark.triangle", description: Text(error))
            } else if !app.setupDone && (app.data != nil || app.isMySaves) {
                // My saves: the chat starts before the file exists (it's written at the end of reading).
                SetupChatView(app: app)
            } else if app.data == nil {
                ContentUnavailableView("No saves yet", systemImage: "tray", description: Text("No data file is bundled."))
            } else {
                MainTabView(app: app)
            }
        }
        .themedScreen()
        .tint(Theme.lime)
        // Start matching places right away: by the time the chat is done, most are.
        .task(id: app.dataset?.id) { app.places.startMatching() }
        .animation(.snappy(duration: 0.35), value: app.setupDone)
        .id(app.dataset?.id)
    }
}

/// The app's tab bar, built only from the approved `LayoutConfig`.
struct MainTabView: View {
    let app: AppModel
    @State private var selection: String?
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        let tabs = app.layout?.tabs ?? []
        TabView(selection: $selection) {
            ForEach(tabs) { tab in
                Tab(tab.title, systemImage: tab.legoScreen.symbol, value: tab.id) {
                    screen(for: tab)
                }
            }
        }
        .onAppear {
            if selection == nil { selection = tabs.first?.id }
            ReminderScheduler.shared.setOnOpen { screen, id in
                selection = screen.rawValue
                app.practice.deepLink = (screen, id)
            }
            app.rescheduleReminders()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background { app.rescheduleReminders() }
        }
    }

    @ViewBuilder private func screen(for tab: TabConfig) -> some View {
        switch tab.legoScreen {
        case .map: MapScreen(app: app, tab: tab)
        case .learn: LearnScreen(app: app, tab: tab)
        case .fitness: FitnessScreen(app: app, tab: tab)
        }
    }
}

/// Top-right button on every tab: "Everything else · 44".
struct EverythingElseButton: View {
    let app: AppModel
    @State private var showing = false

    var body: some View {
        CircleIconButton(systemImage: "tray.full", label: "Everything else, \(app.everythingElse.count) saves") { showing = true }
            .sheet(isPresented: $showing) { EverythingElseSheet(app: app) }
    }
}

/// Saves that fit no tab, newest first. Nothing is lost.
struct EverythingElseSheet: View {
    let app: AppModel
    var initialQuery = ""
    @State private var query = ""
    @Environment(\.openURL) private var openURL
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let all = app.everythingElse
        let shown = query.isEmpty ? all : all.filter { post in
            TextMatch.score(terms: TextMatch.terms(query), fields: [(post.caption, 1), (post.author.username, 1), (post.hashtags.joined(separator: " "), 1)]) > 0
        }
        NavigationStack {
            List(shown) { post in
                Button { PostOpener.open(post, openURL: openURL) } label: {
                    PostRow(post: post, emoji: app.data?.topic(forPost: post.id)?.emoji)
                }
                .buttonStyle(.plain)
                .listRowBackground(Theme.surface)
            }
            .scrollContentBackground(.hidden)
            .background(Theme.background)
            .overlay {
                if shown.isEmpty {
                    ContentUnavailableView(query.isEmpty ? "Nothing here" : "No matches", systemImage: "tray",
                                           description: Text(query.isEmpty ? "Everything you saved has a home." : "Nothing in Everything else for \"\(query)\"."))
                }
            }
            .searchable(text: $query, prompt: "Search everything else")
            .navigationTitle("Everything else · \(all.count)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
        .onAppear { if query.isEmpty { query = initialQuery } }
        .presentationDragIndicator(.visible)
        .preferredColorScheme(.dark)
    }
}

/// Beta menu: switch testers' data and redo the layout. In every build while
/// we're on TestFlight with bundled data.
struct DevMenu: View {
    let app: AppModel
    @State private var showsModelTest = false

    var body: some View {
        Menu {
            Section("Data") {
                ForEach(app.datasets) { d in
                    Button { app.select(d) } label: {
                        if d.id == app.dataset?.id { Label(d.displayName, systemImage: "checkmark") } else { Text(d.displayName) }
                    }
                }
            }
            Button("Model test", systemImage: "cpu") { showsModelTest = true }
            Button("Redo layout & reset \(app.dataset?.displayName ?? "")", role: .destructive) { app.resetCurrentDataset() }
        } label: {
            Image(systemName: "ladybug").font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Theme.muted)
                .frame(width: 36, height: 36)
        }
        .accessibilityLabel("Beta menu")
        .sheet(isPresented: $showsModelTest) { ModelEvalView() }
    }
}

import SwiftUI

/// Everything after onboarding: three tabs, Today · Library · Ask. `HindsightApp`
/// shows this once onboarding is done.
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
            } else {
                MainTabs(app: app)
            }
        }
        .themedScreen()
        .tint(Theme.lime)
        // Start matching places right away, so the map is ready when it's opened.
        .task(id: app.dataset?.id) { app.places.startMatching() }
        .id(app.dataset?.id)
    }
}

enum AppTab: Hashable { case today, library, ask }

/// The tab bar, and what used to hang off Home: Sources, the server pull, sorting
/// new imports, practice reminders, Today's 9:00 notification and topics' auto-route.
struct MainTabs: View {
    let app: AppModel
    @State private var tab: AppTab = .today
    @State private var libraryPath = NavigationPath()
    @State private var showsSources = false
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        TabView(selection: $tab) {
            Tab("Today", systemImage: "sun.max.fill", value: AppTab.today) {
                TodayScreen(app: app, showSources: { showsSources = true }, showLibrary: { tab = .library })
            }
            Tab("Library", systemImage: "books.vertical.fill", value: AppTab.library) {
                LibraryScreen(app: app, path: $libraryPath, showSources: { showsSources = true })
            }
            Tab("Ask", systemImage: "magnifyingglass", value: AppTab.ask) {
                AskScreen(app: app)
            }
        }
        .sheet(isPresented: $showsSources, onDismiss: { app.importsChanged() }) {
            if let store = app.store { SourcesView(store: store) }
        }
        // Pull from the server on launch and on every return to the app (at most once a minute).
        .task { await app.syncWithServer() }
        // New saves (a pull, an import): sort them. Not while Sources is open, since the
        // first own saves switch from the sample, which would close the sheet.
        .onChange(of: app.store?.posts.count) { _, _ in
            if !showsSources { app.importsChanged() }
        }
        .onAppear {
            ReminderScheduler.shared.setOnOpen { screen, id in
                app.practice.deepLink = (screen, id)
                tab = .library
                libraryPath = NavigationPath([LibraryRoute.lego(screen, topicID: nil)])
            }
            app.rescheduleReminders()
            app.rescheduleToday()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background {
                app.rescheduleReminders()
                app.rescheduleToday()
            }
            if phase == .active {
                Task {
                    await app.syncWithServer()
                    await app.runAutoRoutes()
                }
            }
        }
        // Sorted saves landed in their topics: topics set to auto-route send the new ones.
        .onChange(of: app.dataVersion) { _, _ in Task { await app.runAutoRoutes() } }
    }
}

/// Beta menu (next to the gear on Today and Library): model test, a new Today set,
/// onboarding over, reset. In every build while we're on TestFlight.
struct DevMenu: View {
    let app: AppModel
    @State private var showsModelTest = false
    /// Dev: Today shows its "Sorting your saves…" state, to check it without a real first sort.
    @AppStorage("debugPreviewTodaySorting") private var previewTodaySorting = false

    var body: some View {
        Menu {
            Section("Model: \(ModelStatus.current.rawValue)") {
                Button("Model test", systemImage: "cpu") { showsModelTest = true }
            }
            Button("New Today set", systemImage: "sun.max") {
                app.today.reset()
                app.today.prepare(app.todayContext(app.library()), saves: app.saves)
            }
            #if DEBUG
            Button("Add destination test saves", systemImage: "paperplane") {
                let added = app.store?.merge(DestinationSamples.posts()) ?? 0
                DebugLog.write("beta menu: destination test saves, +\(added)")
                app.importsChanged()
            }
            Toggle("Preview Today while sorting", systemImage: "hourglass", isOn: $previewTodaySorting)
            #endif
            // Back to onboarding, keeping everything imported so far.
            Button("Start onboarding over", systemImage: "arrow.counterclockwise") {
                AppModel.resetMySetup()
                UserDefaults.standard.set("", forKey: AppModel.setupSourceKey)
                UserDefaults.standard.set(false, forKey: OnboardingModel.completedKey)
            }
            Button("Reset \(app.dataset?.displayName ?? "") state", role: .destructive) { app.resetCurrentDataset() }
        } label: {
            Image(systemName: "ladybug").font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Theme.muted)
                .frame(width: 44, height: 44)
        }
        .accessibilityLabel("Beta menu")
        .sheet(isPresented: $showsModelTest) { ModelEvalView() }
    }
}

/// Keeps the edge swipe back on pushed screens that hide the navigation bar (the
/// Map draws its own back button); SwiftUI turns the gesture off with the bar.
/// Never on a stack's root screen.
extension UINavigationController: @retroactive UIGestureRecognizerDelegate {
    override open func viewDidLoad() {
        super.viewDidLoad()
        interactivePopGestureRecognizer?.delegate = self
    }

    public func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        viewControllers.count > 1
    }
}

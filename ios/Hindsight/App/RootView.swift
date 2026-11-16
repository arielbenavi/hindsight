import SwiftUI

/// Everything after onboarding: one fixed Home screen. `HindsightApp` shows
/// this once onboarding is done.
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
                HomeScreen(app: app)
            }
        }
        .themedScreen()
        .tint(Theme.lime)
        // Start matching places right away, so the map is ready when it's opened.
        .task(id: app.dataset?.id) { app.places.startMatching() }
        .id(app.dataset?.id)
    }
}

/// Beta menu (next to Home's gear): model test, onboarding over, reset. In
/// every build while we're on TestFlight.
struct DevMenu: View {
    let app: AppModel
    @State private var showsModelTest = false

    var body: some View {
        Menu {
            Section("Model: \(ModelStatus.current.rawValue)") {
                Button("Model test", systemImage: "cpu") { showsModelTest = true }
            }
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

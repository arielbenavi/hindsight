import SwiftUI

@main
struct HindsightApp: App {
    @AppStorage(OnboardingModel.completedKey) private var hasCompletedOnboarding = false
    /// The user's own imports only: no bundled seed (the sample lives in data/fixtures).
    @State private var store = SavedPostStore(seed: { [] })

    init() {
        // Launch with -resetOnboarding to replay the first-run flow.
        if CommandLine.arguments.contains("-resetOnboarding") {
            UserDefaults.standard.removeObject(forKey: OnboardingModel.completedKey)
        }
    }

    var body: some Scene {
        WindowGroup {
            if hasCompletedOnboarding {
                // "mine" once the user starts with (or later brings in) their own saves; else the sample.
                // Read, not observed: AppModel switches itself over in place (`importsChanged`), and a
                // new RootView here would build a second AppModel.
                RootView(store: store, useMySaves: UserDefaults.standard.string(forKey: AppModel.setupSourceKey) == OnboardingChoice.mySaves.rawValue)
            } else {
                OnboardingFlow(store: store) { choice in
                    UserDefaults.standard.set(choice.rawValue, forKey: AppModel.setupSourceKey)
                    hasCompletedOnboarding = true
                }
            }
        }
    }
}

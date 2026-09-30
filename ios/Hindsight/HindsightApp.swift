import SwiftUI

@main
struct HindsightApp: App {
    @AppStorage(OnboardingModel.completedKey) private var hasCompletedOnboarding = false
    /// "mine" once the user starts with their own saves; empty = the sample.
    @AppStorage("setupSource") private var setupSource = ""
    @State private var store = SavedPostStore()

    init() {
        // Launch with -resetOnboarding to replay the first-run flow.
        if CommandLine.arguments.contains("-resetOnboarding") {
            UserDefaults.standard.removeObject(forKey: OnboardingModel.completedKey)
        }
    }

    var body: some Scene {
        WindowGroup {
            if hasCompletedOnboarding {
                RootView(store: store, useMySaves: setupSource == OnboardingChoice.mySaves.rawValue)
            } else {
                OnboardingFlow(store: store) { choice in
                    setupSource = choice.rawValue
                    hasCompletedOnboarding = true
                }
            }
        }
    }
}

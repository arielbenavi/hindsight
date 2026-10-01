import SwiftUI

@main
struct HindsightApp: App {
    @AppStorage(OnboardingModel.completedKey) private var hasCompletedOnboarding = false
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
                RootView()
            } else {
                OnboardingFlow(store: store) { hasCompletedOnboarding = true }
            }
        }
    }
}

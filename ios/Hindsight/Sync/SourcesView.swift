import SwiftUI

/// "Sources": connect and sync saves after onboarding (Home's gear). Same cards
/// as the onboarding step, plus a way to run onboarding again.
struct SourcesView: View {
    let store: SavedPostStore
    @Environment(\.dismiss) private var dismiss
    @AppStorage(OnboardingModel.completedKey) private var hasCompletedOnboarding = true

    var body: some View {
        NavigationStack {
            OnboardingPage {
                Text("Sources.")
                    .font(OnboardingStyle.display())
                Text("\(store.posts.count.counted("save")) so far. Sync again anytime.")
                    .font(OnboardingStyle.body)
                    .foregroundStyle(OnboardingStyle.muted)

                SourceCards(store: store)

                AssistantAccessCard()
            } actions: {
                Button("Run setup again") {
                    // Same as the beta menu's "Start onboarding over": back to onboarding,
                    // keeping everything imported. HindsightApp watches the flag.
                    AppModel.resetMySetup()
                    UserDefaults.standard.set("", forKey: AppModel.setupSourceKey)
                    hasCompletedOnboarding = false
                    dismiss()
                }
                .buttonStyle(.onboardingSecondary)
            }
            .foregroundStyle(OnboardingStyle.text)
            .background(OnboardingStyle.background.ignoresSafeArea())
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() } }
            }
        }
        .preferredColorScheme(.dark)
        .tint(OnboardingStyle.accent)
    }
}

#Preview {
    SourcesView(store: SavedPostStore(fileURL: nil))
}

import SwiftUI

/// "Sources": connect and sync saves after onboarding. Same cards as the
/// onboarding step, plus a way to run the whole setup again. Meant to be
/// opened from a profile/settings entry in the main app.
struct SourcesView: View {
    let store: SavedPostStore
    @Environment(\.dismiss) private var dismiss
    @AppStorage(OnboardingModel.completedKey) private var hasCompletedOnboarding = true

    var body: some View {
        NavigationStack {
            OnboardingPage {
                Text("Sources.")
                    .font(OnboardingStyle.display())
                Text("\(store.posts.count.formatted()) saves so far. Sync again anytime.")
                    .font(OnboardingStyle.body)
                    .foregroundStyle(OnboardingStyle.muted)

                SourceCards(store: store)
            } actions: {
                Button("Run setup again") {
                    // HindsightApp watches this flag and shows onboarding again.
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

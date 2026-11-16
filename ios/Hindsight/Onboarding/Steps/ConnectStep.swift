import SwiftUI

/// Bring your saves in, then on to "You're in" (`DoneStep`).
struct ConnectStep: View {
    let model: OnboardingModel
    let store: SavedPostStore
    /// Done connecting: the user's saves or the sample.
    let onChoose: (OnboardingChoice) -> Void

    var body: some View {
        OnboardingPage {
            Text("Plug in\nyour apps.")
                .font(OnboardingStyle.display())

            SourceCards(store: store)
        } actions: {
            Button(finishTitle) { onChoose(.mySaves) }
                .buttonStyle(.onboardingPrimary)
                .disabled(importedCount == 0)
                .opacity(importedCount == 0 ? 0.5 : 1)
            // For testing during the beta; remove before the App Store release.
            Button("Just looking? Try it with sample saves") { onChoose(.sample) }
                .font(OnboardingStyle.caption)
                .foregroundStyle(OnboardingStyle.accent)
        }
    }

    /// Counts only what the user brought in (not the bundled seed).
    private var importedCount: Int { store.posts.count { $0.source != .seedMD } }

    private var finishTitle: String {
        importedCount > 0 ? "Start with \(importedCount.counted("save"))" : "Connect at least one to start"
    }
}

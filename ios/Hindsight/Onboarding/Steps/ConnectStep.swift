import SwiftUI

/// The first screen of the app: bring your saves in. Once the user says they're
/// done, the setup chat takes over (docs/specs/onboarding-chat.md).
struct ConnectStep: View {
    let model: OnboardingModel
    let store: SavedPostStore
    /// Done connecting → the setup chat, on the user's saves or the sample.
    let onFinish: (OnboardingChoice) -> Void

    var body: some View {
        OnboardingPage {
            // Folded in from the old Welcome and How it works screens.
            Text("Your saves,\nin \(Text("hindsight.").foregroundStyle(OnboardingStyle.accent))")
                .font(OnboardingStyle.display())
                .minimumScaleFactor(0.7)
            Text("You've saved thousands of posts “for later”. This is later. Connect where you save things, and I'll build your app around them.")
                .font(OnboardingStyle.body)
                .foregroundStyle(OnboardingStyle.muted)

            SourceCards(store: store)
        } actions: {
            Button(finishTitle) { onFinish(.mySaves) }
                .buttonStyle(.onboardingPrimary)
                .disabled(importedCount == 0)
                .opacity(importedCount == 0 ? 0.5 : 1)
            Button("Just looking? Try it with sample saves") { onFinish(.sample) }
                .font(OnboardingStyle.caption)
                .foregroundStyle(OnboardingStyle.accent)
        }
    }

    /// Counts only what the user brought in (not the bundled seed).
    private var importedCount: Int { store.posts.count { $0.source != .seedMD } }

    private var finishTitle: String {
        importedCount > 0 ? "Start with \(importedCount.formatted()) saves" : "Connect at least one to start"
    }
}

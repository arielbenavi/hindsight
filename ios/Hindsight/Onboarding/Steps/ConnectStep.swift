import SwiftUI

struct ConnectStep: View {
    @Bindable var model: OnboardingModel
    let store: SavedPostStore

    var body: some View {
        OnboardingPage {
            Text("Plug in\nyour apps.")
                .font(OnboardingStyle.display())

            SourceCards(store: store)
        } actions: {
            Button("Continue", action: model.next)
                .buttonStyle(.onboardingPrimary)
            Text("You can connect more later.")
                .font(OnboardingStyle.caption)
                .foregroundStyle(OnboardingStyle.muted)
        }
    }
}

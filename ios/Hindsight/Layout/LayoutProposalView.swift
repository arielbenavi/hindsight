import SwiftUI

/// "Here's your app" (layout-proposal.md). Placeholder until the real chat lands.
struct LayoutProposalView: View {
    let app: AppModel

    var body: some View {
        Button("Looks good") {
            if let data = app.data { app.approve(LayoutRules.propose(data).draft.config()) }
        }
        .buttonStyle(.pill).padding()
    }
}

import SwiftUI

/// Place confirmation (confirm.md). Placeholder until the real flow lands.
struct ConfirmationFlow: View {
    enum Mode { case onboarding, review }
    let app: AppModel
    let mode: Mode
    let onFinish: () -> Void

    var body: some View {
        Button("Open map", action: onFinish).buttonStyle(.pill).padding()
    }
}

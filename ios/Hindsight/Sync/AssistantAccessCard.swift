import SwiftUI

/// Sources → "Use your saves in Claude": the hindsight connector (connector/server.py)
/// also answers AI assistants' questions from the user's saves. Off by default; turning
/// it on asks first and says exactly what's shared. When off, only the switch shows.
struct AssistantAccessCard: View {
    @AppStorage(MuseConnector.assistantSearchKey) private var enabled = false
    /// Watched so the URL follows a new account.
    @AppStorage(MuseConnector.accountBaseKey) private var accountBase = ""
    @State private var confirming = false
    @State private var copied = false
    @State private var error: String?

    private var base: URL? { _ = accountBase; return MuseConnector.baseURL }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                Image(systemName: "sparkles")
                    .font(.system(size: 15, weight: .bold))
                    .frame(width: 36, height: 36)
                    .background(OnboardingStyle.stroke, in: .circle)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Use your saves in Claude").font(OnboardingStyle.title)
                    Text("Ask Claude (or any AI assistant) about what you saved.")
                        .font(OnboardingStyle.caption)
                        .foregroundStyle(OnboardingStyle.muted)
                }
            }
            Toggle("Let AI assistants search my saves", isOn: Binding(
                get: { enabled },
                set: { on in if on { confirming = true } else { Task { await apply(false) } } }
            ))
            .font(.system(.subheadline, design: .rounded, weight: .bold))
            .tint(OnboardingStyle.accent)

            if enabled {
                Text("Add this address as a connector in Claude. It searches your saves' captions, transcripts and links.")
                    .font(OnboardingStyle.caption)
                    .foregroundStyle(OnboardingStyle.muted)
                if let base {
                    let url = MuseConnector.mcpURL(base: base).absoluteString
                    Text(url)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(OnboardingStyle.muted)
                        .lineLimit(2)
                        .truncationMode(.middle)
                        .textSelection(.enabled)
                    Button(copied ? "Copied" : "Copy connector address", systemImage: copied ? "checkmark" : "doc.on.doc") {
                        UIPasteboard.general.string = url
                        withAnimation(.snappy) { copied = true }
                    }
                    .buttonStyle(.onboardingSecondary)
                } else {
                    Text("This phone isn't connected to the hindsight server yet.")
                        .font(OnboardingStyle.caption)
                        .foregroundStyle(.orange)
                }
            }
            if let error {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(OnboardingStyle.caption)
                    .foregroundStyle(.orange)
            }
        }
        .onboardingCard()
        .alert("Let AI assistants search your saves?", isPresented: $confirming) {
            Button("Allow") { Task { await apply(true) } }
            Button("Not now", role: .cancel) {}
        } message: {
            Text("Assistants you connect can read your saves' captions, transcripts and links. Your notes are never shared. You can turn this off here anytime.")
        }
    }

    /// Saved on the phone, then sent to the server. If the server can't be reached the
    /// switch goes back, so it never shows "on" while the server still refuses (or the reverse).
    private func apply(_ on: Bool) async {
        error = nil
        let before = enabled
        enabled = on
        copied = false
        guard let base else { return }
        do {
            try await MuseConnector.setAssistantSearch(on, base: base)
        } catch {
            enabled = before
            self.error = "Couldn't reach the hindsight server. Try again in a moment."
            DebugLog.write("assistant search \(on ? "on" : "off") failed: \(error.localizedDescription)")
        }
    }
}

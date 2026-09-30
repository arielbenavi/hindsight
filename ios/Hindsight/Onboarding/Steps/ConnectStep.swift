import SwiftUI

struct ConnectStep: View {
    @Bindable var model: OnboardingModel
    let store: SavedPostStore
    /// The last step: done connecting → the layout proposal.
    let onFinish: () -> Void

    var body: some View {
        OnboardingPage {
            Text("Plug in\nyour apps.")
                .font(OnboardingStyle.display())

            museCard

            XConnectRow(store: store)
            comingSoonRow(Platform.tiktok.displayName, symbol: Platform.tiktok.symbol,
                          detail: "Share any TikTok to hindsight. Coming soon.")
            comingSoonRow("WhatsApp notes", symbol: "message.fill",
                          detail: "Links and notes you send yourself on WhatsApp.")
        } actions: {
            Button(finishTitle, action: onFinish)
                .buttonStyle(.onboardingPrimary)
            Text("Connected everything you want to start with? You can add more later.")
                .font(OnboardingStyle.caption)
                .foregroundStyle(OnboardingStyle.muted)
        }
        .sheet(isPresented: $model.isMuseSheetPresented) {
            MuseSyncView(store: store)
        }
    }

    /// Counts only what the user brought in (not the bundled seed).
    private var importedCount: Int { store.posts.count { $0.source != .seedMD } }

    private var finishTitle: String {
        importedCount > 0 ? "Start with \(importedCount.formatted()) saves" : "I'm done connecting"
    }

    private var museCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                HStack(spacing: 10) {
                    PlatformBadge(platform: .instagram)
                    PlatformBadge(platform: .facebook)
                }
                Spacer()
                let count = store.count(for: .instagram) + store.count(for: .facebook)
                if count > 0 {
                    Label("\(count.formatted()) saves", systemImage: "checkmark.circle.fill")
                        .font(OnboardingStyle.caption)
                        .foregroundStyle(OnboardingStyle.accent)
                }
            }
            VStack(alignment: .leading, spacing: 4) {
                Text("Instagram + Facebook").font(OnboardingStyle.title)
                Text("Through Muse, Meta's AI. It can already see your saves. One tap, no passwords.")
                    .font(OnboardingStyle.body)
                    .foregroundStyle(OnboardingStyle.muted)
            }
            Button("Sync with Muse") { model.isMuseSheetPresented = true }
                .buttonStyle(.onboardingSecondary)
        }
        .onboardingCard()
    }

    private func comingSoonRow(_ name: String, symbol: String, detail: String) -> some View {
        HStack(spacing: 14) {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .bold))
                .frame(width: 36, height: 36)
                .background(OnboardingStyle.stroke, in: .circle)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(name).font(OnboardingStyle.title)
                Text(detail)
                    .font(OnboardingStyle.caption)
                    .foregroundStyle(OnboardingStyle.muted)
            }
            Spacer()
            Text("soon")
                .font(.system(.caption, design: .rounded, weight: .heavy))
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(OnboardingStyle.stroke, in: .capsule)
        }
        .onboardingCard(padding: 16)
        .opacity(0.7)
    }
}

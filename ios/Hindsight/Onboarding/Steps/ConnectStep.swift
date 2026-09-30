import SwiftUI

struct ConnectStep: View {
    @Bindable var model: OnboardingModel
    let store: SavedPostStore

    var body: some View {
        OnboardingPage {
            Text("Plug in\nyour apps.")
                .font(OnboardingStyle.display())

            museCard

            XConnectRow(store: store)
            comingSoonRow(Platform.tiktok.displayName, symbol: Platform.tiktok.symbol,
                          detail: "Share any TikTok to hindsight. Coming soon.")
            whatsAppRow
        } actions: {
            Button("Continue", action: model.next)
                .buttonStyle(.onboardingPrimary)
            Text("You can connect more later.")
                .font(OnboardingStyle.caption)
                .foregroundStyle(OnboardingStyle.muted)
        }
        .sheet(isPresented: $model.isMuseSheetPresented) {
            MuseSyncView(store: store)
        }
        .sheet(isPresented: $model.isWhatsAppSheetPresented) {
            WhatsAppImportView(store: store)
        }
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

    private var whatsAppRow: some View {
        HStack(spacing: 14) {
            PlatformBadge(platform: .whatsapp)
            VStack(alignment: .leading, spacing: 2) {
                Text("WhatsApp notes").font(OnboardingStyle.title)
                let count = store.count(for: .whatsapp)
                Text(count > 0 ? "\(count.formatted()) notes imported." : "Links and notes you send yourself.")
                    .font(OnboardingStyle.caption)
                    .foregroundStyle(OnboardingStyle.muted)
            }
            Spacer()
            Button("Import") { model.isWhatsAppSheetPresented = true }
                .font(.system(.subheadline, design: .rounded, weight: .heavy))
                .foregroundStyle(OnboardingStyle.onAccent)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(OnboardingStyle.accent, in: .capsule)
        }
        .onboardingCard(padding: 16)
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

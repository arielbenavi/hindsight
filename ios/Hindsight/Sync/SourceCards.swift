import SwiftUI

/// The source cards (Instagram + Facebook via Muse or Meta's data file, X, TikTok, WhatsApp notes).
/// Shared by onboarding's "Plug in your apps" step and the Sources page, so
/// both always offer the same ways to connect and sync.
struct SourceCards: View {
    let store: SavedPostStore
    @State private var isMuseSheetPresented = false
    @State private var isWhatsAppSheetPresented = false
    @State private var isMetaImportPresented = false

    var body: some View {
        VStack(spacing: 20) {
            museCard
            XConnectRow(store: store)
            comingSoonRow(Platform.tiktok.displayName, symbol: Platform.tiktok.symbol,
                          detail: "Share any TikTok to hindsight. Coming soon.")
            whatsAppRow
        }
        .sheet(isPresented: $isMuseSheetPresented) {
            MuseSyncView(store: store)
        }
        .sheet(isPresented: $isWhatsAppSheetPresented) {
            WhatsAppImportView(store: store)
        }
        .sheet(isPresented: $isMetaImportPresented) {
            MetaImportSheet(store: store)
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
                Text("Through Muse, Meta's AI: it can already see your saves. Or import the file Meta can send you.")
                    .font(OnboardingStyle.body)
                    .foregroundStyle(OnboardingStyle.muted)
            }
            Button("Sync with Muse") { isMuseSheetPresented = true }
                .buttonStyle(.onboardingSecondary)
            // The dependable second way while Muse is unreliable.
            Button("Import your Meta data file") { isMetaImportPresented = true }
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
                Text(count > 0 ? "\(count.formatted()) notes saved." : "Links and notes you send yourself.")
                    .font(OnboardingStyle.caption)
                    .foregroundStyle(OnboardingStyle.muted)
            }
            Spacer()
            Button("Connect") { isWhatsAppSheetPresented = true }
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

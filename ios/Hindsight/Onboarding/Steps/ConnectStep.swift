import SwiftUI

/// The first screen of the app: bring your saves in. Once the user says they're
/// done, the setup chat takes over (docs/specs/onboarding-chat.md).
struct ConnectStep: View {
    @Bindable var model: OnboardingModel
    let store: SavedPostStore
    /// Done connecting → the setup chat, on the user's saves or the sample.
    let onFinish: (OnboardingChoice) -> Void

    @State private var showsMetaImport = false

    var body: some View {
        OnboardingPage {
            // Folded in from the old Welcome and How it works screens.
            Text("Your saves,\nin \(Text("hindsight.").foregroundStyle(OnboardingStyle.accent))")
                .font(OnboardingStyle.display())
                .minimumScaleFactor(0.7)
            Text("You've saved thousands of posts “for later”. This is later. Connect where you save things, and I'll build your app around them.")
                .font(OnboardingStyle.body)
                .foregroundStyle(OnboardingStyle.muted)

            metaCard

            XConnectRow(store: store)
            comingSoonRow(Platform.tiktok.displayName, symbol: Platform.tiktok.symbol,
                          detail: "Share any TikTok to hindsight. Coming soon.")
            comingSoonRow("WhatsApp notes", symbol: "message.fill",
                          detail: "Links and notes you send yourself on WhatsApp.")
        } actions: {
            Button(finishTitle) { onFinish(.mySaves) }
                .buttonStyle(.onboardingPrimary)
                .disabled(importedCount == 0)
                .opacity(importedCount == 0 ? 0.5 : 1)
            Button("Just looking? Try it with sample saves") { onFinish(.sample) }
                .font(OnboardingStyle.caption)
                .foregroundStyle(OnboardingStyle.accent)
        }
        .sheet(isPresented: $model.isMuseSheetPresented) {
            MuseSyncView(store: store)
        }
        .sheet(isPresented: $showsMetaImport) {
            MetaImportSheet(store: store)
        }
    }

    /// Counts only what the user brought in (not the bundled seed).
    private var importedCount: Int { store.posts.count { $0.source != .seedMD } }

    private var finishTitle: String {
        importedCount > 0 ? "Start with \(importedCount.formatted()) saves" : "Connect at least one to start"
    }

    /// Instagram + Facebook: Meta's data download is the dependable way in; Muse is
    /// the quicker one when it works (beta).
    private var metaCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                HStack(spacing: 10) {
                    PlatformBadge(platform: .instagram)
                    PlatformBadge(platform: .facebook)
                }
                Spacer()
                let count = store.posts.count { ($0.platform == .instagram || $0.platform == .facebook) && $0.source != .seedMD }
                if count > 0 {
                    Label("\(count.formatted()) saves", systemImage: "checkmark.circle.fill")
                        .font(OnboardingStyle.caption)
                        .foregroundStyle(OnboardingStyle.accent)
                }
            }
            VStack(alignment: .leading, spacing: 4) {
                Text("Instagram + Facebook").font(OnboardingStyle.title)
                Text("Ask Meta for a file of everything you've saved, then import it here. We'll walk you through it.")
                    .font(OnboardingStyle.body)
                    .foregroundStyle(OnboardingStyle.muted)
            }
            Button("Get your saves from Meta") { showsMetaImport = true }
                .buttonStyle(.onboardingSecondary)
            Button("Or try Muse, Meta's AI (beta)") { model.isMuseSheetPresented = true }
                .font(OnboardingStyle.caption)
                .foregroundStyle(OnboardingStyle.muted)
                .frame(maxWidth: .infinity)
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

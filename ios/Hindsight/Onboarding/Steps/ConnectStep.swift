import SwiftUI
import UniformTypeIdentifiers

/// The first screen of the app: bring your saves in. Once the user says they're
/// done, the setup chat takes over (docs/specs/onboarding-chat.md).
struct ConnectStep: View {
    @Bindable var model: OnboardingModel
    let store: SavedPostStore
    /// Done connecting → the setup chat, on the user's saves or the sample.
    let onFinish: (OnboardingChoice) -> Void

    @State private var isImporting = false
    @State private var importMessage: String?

    var body: some View {
        OnboardingPage {
            // Folded in from the old Welcome and How it works screens.
            Text("Your saves,\nin \(Text("hindsight.").foregroundStyle(OnboardingStyle.accent))")
                .font(OnboardingStyle.display())
                .minimumScaleFactor(0.7)
            Text("You've saved thousands of posts “for later”. This is later. Connect where you save things, and I'll build your app around them.")
                .font(OnboardingStyle.body)
                .foregroundStyle(OnboardingStyle.muted)

            museCard

            XConnectRow(store: store)
            importRow
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
        .fileImporter(isPresented: $isImporting, allowedContentTypes: [.zip, .json], allowsMultipleSelection: true) { result in
            importFiles(result)
        }
    }

    /// "Import a file": an Instagram / Facebook / TikTok data download (zip or json).
    private var importRow: some View {
        Button { isImporting = true } label: {
            HStack(spacing: 14) {
                Image(systemName: "square.and.arrow.down")
                    .font(.system(size: 15, weight: .bold))
                    .frame(width: 36, height: 36)
                    .background(OnboardingStyle.stroke, in: .circle)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Import a file").font(OnboardingStyle.title)
                    Text(importMessage ?? "Your Instagram, Facebook or TikTok data download (.zip or .json).")
                        .font(OnboardingStyle.caption)
                        .foregroundStyle(importMessage == nil ? OnboardingStyle.muted : OnboardingStyle.accent)
                }
                Spacer()
            }
            .onboardingCard(padding: 16)
        }
        .buttonStyle(.plain)
    }

    private func importFiles(_ result: Result<[URL], Error>) {
        guard case .success(let urls) = result else { return }
        var posts: [SavedPost] = []
        for url in urls {
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            posts += (try? DataExportParser.parse(fileAt: url)) ?? []
        }
        guard !posts.isEmpty else {
            importMessage = "Couldn't find saves in that file. Try the whole .zip."
            return
        }
        let added = store.merge(DataExportParser.combined(posts))
        importMessage = "+\(added.formatted()) saves imported"
        DebugLog.write("file import: \(urls.count) files, \(posts.count) posts, +\(added) new")
    }

    /// Counts only what the user brought in (not the bundled seed).
    private var importedCount: Int { store.posts.count { $0.source != .seedMD } }

    private var finishTitle: String {
        importedCount > 0 ? "Start with \(importedCount.formatted()) saves" : "Connect at least one to start"
    }

    private var museCard: some View {
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

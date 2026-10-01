import SwiftUI
import UniformTypeIdentifiers

/// Import a WhatsApp notes chat from its "Export chat" file. Works as the
/// backfill and, repeated now and then, as the ongoing sync: re-importing the
/// same chat only adds what's new (see WhatsAppExportParser.noteURL).
///
/// For now the user saves the export to Files and picks it here. Once the app
/// declares that it opens chat exports (Info.plist document types), WhatsApp's
/// share sheet can hand the file straight to hindsight.
struct WhatsAppImportView: View {
    let store: SavedPostStore
    @Environment(\.dismiss) private var dismiss
    @State private var isPicking = false
    @State private var status: Status = .ready
    @AppStorage("whatsAppLastImport") private var lastImport: Double = 0
    @State private var pullMessage: String?

    enum Status: Equatable {
        case ready
        case importing
        case done(added: Int, links: Int, notes: Int, othersSkipped: Int)
        case failed(String)
    }

    var body: some View {
        NavigationStack {
            OnboardingPage {
                Text("WhatsApp\nnotes.")
                    .font(OnboardingStyle.display(40))

                Text("Links and notes you send yourself. Connect once for everything new; bring your past notes in once.")
                    .font(OnboardingStyle.body)
                    .foregroundStyle(OnboardingStyle.muted)

                sectionLabel("1 · NEW NOTES, AUTOMATICALLY")
                automaticCard

                sectionLabel("2 · PAST NOTES, ONCE")
                VStack(alignment: .leading, spacing: 12) {
                    WhatsAppGuide(flow: .export)
                        .frame(maxWidth: .infinity)
                    Text("In WhatsApp: your notes chat → tap its name → Export chat → **Without media** → Save to Files. Then tap “Choose the export file” below.")
                        .font(OnboardingStyle.caption)
                        .foregroundStyle(OnboardingStyle.muted)
                    if lastImport > 0 {
                        Text("Last imported \(Date(timeIntervalSince1970: lastImport), format: .relative(presentation: .named)). Import again anytime; only new notes are added.")
                            .font(OnboardingStyle.caption)
                            .foregroundStyle(OnboardingStyle.muted)
                    }
                    statusBanner
                }
                .onboardingCard()
            } actions: {
                if case .done = status {
                    Button("Done") { dismiss() }
                        .buttonStyle(.onboardingPrimary)
                } else {
                    Button("Choose the export file") { isPicking = true }
                        .buttonStyle(.onboardingPrimary)
                        .disabled(status == .importing)
                    Button("Open WhatsApp") {
                        UIApplication.shared.open(MuseLauncher.whatsAppURL)
                    }
                    .buttonStyle(.onboardingSecondary)
                }
            }
            .foregroundStyle(OnboardingStyle.text)
            .background(OnboardingStyle.background.ignoresSafeArea())
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() } }
            }
        }
        .preferredColorScheme(.dark)
        .tint(OnboardingStyle.accent)
        .fileImporter(isPresented: $isPicking, allowedContentTypes: [.zip, .plainText, .text]) { result in
            switch result {
            case .success(let url): Task { await importFile(url) }
            case .failure(let error): status = .failed(error.localizedDescription)
            }
        }
    }

    @ViewBuilder
    private var statusBanner: some View {
        switch status {
        case .ready:
            EmptyView()
        case .importing:
            HStack(spacing: 10) {
                ProgressView()
                Text("Reading your chat…").font(OnboardingStyle.title)
            }
        case .done(let added, let links, let notes, let othersSkipped):
            VStack(alignment: .leading, spacing: 4) {
                Label(added > 0 ? "+\(added) new saves" : "Nothing new since last time", systemImage: "checkmark.circle.fill")
                    .font(OnboardingStyle.title)
                    .foregroundStyle(OnboardingStyle.accent)
                Text("\(links) links and \(notes) notes in the chat." + (othersSkipped > 0
                     ? " Other people's messages were left out; their links were kept." : ""))
                    .font(OnboardingStyle.caption)
                    .foregroundStyle(OnboardingStyle.muted)
            }
        case .failed(let message):
            Label(message, systemImage: "exclamationmark.triangle.fill")
                .font(OnboardingStyle.caption)
                .foregroundStyle(.orange)
        }
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(.caption, design: .rounded, weight: .heavy))
            .tracking(1.4)
            .foregroundStyle(OnboardingStyle.muted)
    }

    /// The bot path: add hindsight's WhatsApp number to your notes chat once;
    /// new messages (and, if shared, the last 100) arrive on their own.
    @ViewBuilder
    private var automaticCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let number = WhatsAppBot.number {
                WhatsAppGuide(flow: .addBot)
                    .frame(maxWidth: .infinity)
                Text("Add hindsight to your notes group (or just write to it directly). When WhatsApp asks, share the last 100 messages too.")
                    .font(OnboardingStyle.caption)
                    .foregroundStyle(OnboardingStyle.muted)
                Button("Add hindsight on WhatsApp") {
                    UIApplication.shared.open(WhatsAppBot.chatURL(number: number))
                }
                .buttonStyle(.onboardingSecondary)
                Button("Check for new notes") {
                    Task {
                        do {
                            let result = try await ServerSync.pull(into: store)
                            pullMessage = result.added > 0 ? "+\(result.added) new from WhatsApp and Muse." : "Nothing new yet."
                        } catch {
                            pullMessage = "Couldn't reach hindsight: \(error.localizedDescription)"
                        }
                    }
                }
                .font(OnboardingStyle.caption)
                if let pullMessage {
                    Text(pullMessage).font(OnboardingStyle.caption).foregroundStyle(OnboardingStyle.accent)
                }
            } else {
                Text("Coming soon: add hindsight to your notes group once, and new notes show up here on their own.")
                    .font(OnboardingStyle.caption)
                    .foregroundStyle(OnboardingStyle.muted)
            }
        }
        .onboardingCard()
    }

    private func importFile(_ url: URL) async {
        status = .importing
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        do {
            let result = try await Task.detached { try WhatsAppExportParser.parse(fileAt: url) }.value
            let added = store.merge(result.posts)
            lastImport = Date.now.timeIntervalSince1970
            DebugLog.write("whatsapp import: \(result.messages) messages, \(result.links) links, \(result.notes) notes, +\(added) new, others skipped \(result.othersSkipped)")
            status = .done(added: added, links: result.links, notes: result.notes, othersSkipped: result.othersSkipped)
        } catch {
            DebugLog.write("whatsapp import failed: \(error)")
            status = .failed(error.localizedDescription)
        }
    }
}

#Preview {
    WhatsAppImportView(store: SavedPostStore(fileURL: nil))
}

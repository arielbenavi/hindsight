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
                Text("Your WhatsApp\nnotes.")
                    .font(OnboardingStyle.display(40))

                Text("Bring in the links and notes you send yourself. Do it again anytime; we only add what's new.")
                    .font(OnboardingStyle.body)
                    .foregroundStyle(OnboardingStyle.muted)

                if let number = WhatsAppBot.number {
                    automaticCard(number: number)
                    Text("PAST NOTES: IMPORT ONCE")
                        .font(.system(.caption, design: .rounded, weight: .heavy))
                        .tracking(1.4)
                        .foregroundStyle(OnboardingStyle.muted)
                }

                VStack(spacing: 10) {
                    step(1, "Open your notes chat", "In WhatsApp, open the chat or group you write notes in, then tap its name at the top.")
                    step(2, "Export chat", "Scroll down → Export chat → Without media.")
                    step(3, "Save to Files", "Pick “Save to Files”, then come back here.")
                    step(4, "Choose the file", "We pull out every link and note.")
                }

                if lastImport > 0 {
                    Text("Last imported \(Date(timeIntervalSince1970: lastImport), format: .relative(presentation: .named)).")
                        .font(OnboardingStyle.caption)
                        .foregroundStyle(OnboardingStyle.muted)
                }

                statusBanner
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

    /// The bot path: add hindsight's number to your notes chat once; new
    /// messages arrive on their own (pulled from the server).
    private func automaticCard(number: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Automatic").font(OnboardingStyle.title)
            Text("Add hindsight to your notes group (or just write to it directly). Everything new shows up here on its own.")
                .font(OnboardingStyle.caption)
                .foregroundStyle(OnboardingStyle.muted)
            Button("Add hindsight on WhatsApp") {
                UIApplication.shared.open(WhatsAppBot.chatURL(number: number))
            }
            .buttonStyle(.onboardingSecondary)
            Text("Then in your notes group: tap its name → Add members → hindsight.")
                .font(OnboardingStyle.caption)
                .foregroundStyle(OnboardingStyle.muted)
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
        }
        .onboardingCard()
    }

    private func step(_ number: Int, _ title: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Text("\(number)")
                .font(.system(.headline, design: .rounded, weight: .black))
                .frame(width: 32, height: 32)
                .background(OnboardingStyle.stroke, in: .circle)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(OnboardingStyle.title)
                Text(detail).font(OnboardingStyle.caption).foregroundStyle(OnboardingStyle.muted)
            }
            Spacer(minLength: 0)
        }
        .onboardingCard(padding: 14)
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

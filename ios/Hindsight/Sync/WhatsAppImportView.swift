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
    @AppStorage("whatsAppNotesPlace") private var notesPlace: NotesPlace = .myself
    @State private var botNumber: String? = WhatsAppBot.number
    @State private var isLoadingNumber = WhatsAppBot.number == nil
    @State private var isSavingContact = false
    @State private var pullMessage: String?

    enum Status: Equatable {
        case ready
        case importing
        case done(added: Int, links: Int, notes: Int, othersSkipped: Int)
        case failed(String)
    }

    /// Where the user keeps notes today. WhatsApp's "message yourself" chat can't
    /// take a third member, so those users switch to their hindsight chat instead.
    enum NotesPlace: String, CaseIterable {
        case myself, group
        var label: String { self == .myself ? "Chat with myself" : "A group" }
    }

    var body: some View {
        NavigationStack {
            OnboardingPage {
                Text("WhatsApp\nnotes.")
                    .font(OnboardingStyle.display(40))

                Text("The links and notes you send yourself on WhatsApp, saved in hindsight.")
                    .font(OnboardingStyle.body)
                    .foregroundStyle(OnboardingStyle.muted)

                if botNumber == nil && isLoadingNumber {
                    ProgressView().frame(maxWidth: .infinity).padding(.vertical, 40)
                } else if let botNumber {
                    sectionLabel("1 · SAY HI TO HINDSIGHT")
                    connectCard(botNumber)

                    sectionLabel("2 · WHERE DO YOU WRITE NOTES?")
                    placeCard

                    sectionLabel("3 · BRING YOUR OLD NOTES")
                    pastNotesCard(sendToBot: true)
                } else {
                    Label("Can't reach hindsight right now, so new notes can't be connected yet. You can still bring in old notes from a file.", systemImage: "wifi.exclamationmark")
                        .font(OnboardingStyle.caption)
                        .foregroundStyle(.orange)
                    sectionLabel("PAST NOTES")
                    pastNotesCard(sendToBot: false)
                }
            } actions: {
                if botNumber != nil {
                    Button("Check for new notes") { Task { await pull() } }
                        .buttonStyle(.onboardingPrimary)
                    if let pullMessage {
                        Text(pullMessage).font(OnboardingStyle.caption).foregroundStyle(OnboardingStyle.accent)
                    }
                } else if case .done = status {
                    Button("Done") { dismiss() }
                        .buttonStyle(.onboardingPrimary)
                } else if !isLoadingNumber {
                    Button("Open WhatsApp") { UIApplication.shared.open(MuseLauncher.whatsAppURL) }
                        .buttonStyle(.onboardingPrimary)
                    Button("Choose the export file") { isPicking = true }
                        .buttonStyle(.onboardingSecondary)
                        .disabled(status == .importing)
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
        .task {
            botNumber = await WhatsAppBot.refreshNumber()
            isLoadingNumber = false
        }
        .sheet(isPresented: $isSavingContact) {
            if let botNumber { NewContactSheet(number: botNumber) }
        }
        .fileImporter(isPresented: $isPicking, allowedContentTypes: [.zip, .plainText, .text]) { result in
            switch result {
            case .success(let url): Task { await importFile(url) }
            case .failure(let error): status = .failed(error.localizedDescription)
            }
        }
    }

    // MARK: - Steps

    private func connectCard(_ number: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Opens your chat with hindsight with a hello already typed. **Just tap send.** It replies “Connected to hindsight”.")
                .font(OnboardingStyle.caption)
                .foregroundStyle(OnboardingStyle.muted)
            Button("Open WhatsApp") {
                let code = WhatsAppBot.connectCode(base: MuseConnector.baseURL)
                DebugLog.write("whatsapp connect: code \(code)")
                UIApplication.shared.open(WhatsAppBot.connectURL(number: number, code: code))
            }
            .buttonStyle(.onboardingPrimary)
            Button {
                isSavingContact = true
            } label: {
                Label("Save hindsight to my contacts", systemImage: "person.crop.circle.badge.plus")
            }
            .font(OnboardingStyle.caption)
            Text("So it shows up when you add it to a group.")
                .font(OnboardingStyle.caption)
                .foregroundStyle(OnboardingStyle.muted)
        }
        .onboardingCard()
    }

    private var placeCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Picker("Where do you write notes?", selection: $notesPlace) {
                ForEach(NotesPlace.allCases, id: \.self) { Text($0.label).tag($0) }
            }
            .pickerStyle(.segmented)

            switch notesPlace {
            case .myself:
                tip("bubble.left.and.text.bubble.right", "**Your hindsight chat is your new notes chat.** WhatsApp doesn't let anyone into your chat with yourself, so send notes and links to hindsight instead. Everything you send there is saved.")
                tip("pin", "Pin it so it sits where your old chat was: swipe right on the chat → **Pin**.")
            case .group:
                WhatsAppGuide(flow: .addBot)
                    .frame(maxWidth: .infinity)
                tip("person.badge.plus", "In your notes group: tap its name → **Add members** → **hindsight**. If WhatsApp offers to share recent messages, pick **Last 100**.")
                tip("lock", "Links anyone shares are saved. Plain text only from you; other people's messages aren't stored.")
            }
        }
        .onboardingCard()
    }

    private func pastNotesCard(sendToBot: Bool) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            WhatsAppGuide(flow: sendToBot ? .exportToBot : .export)
                .frame(maxWidth: .infinity)
            Text(sendToBot
                 ? "In your old notes chat: tap its name → **Export chat** → **Without media** → **WhatsApp** → **hindsight** → send. hindsight replies with what it imported."
                 : "In WhatsApp: your notes chat → tap its name → Export chat → **Without media** → Save to Files. Then tap “Choose the export file” below.")
                .font(OnboardingStyle.caption)
                .foregroundStyle(OnboardingStyle.muted)
            if lastImport > 0 {
                Text("Last imported here \(Date(timeIntervalSince1970: lastImport), format: .relative(presentation: .named)). Importing again only adds what's new.")
                    .font(OnboardingStyle.caption)
                    .foregroundStyle(OnboardingStyle.muted)
            }
            if sendToBot {
                Button("Or choose an export saved in Files") { isPicking = true }
                    .font(OnboardingStyle.caption)
                    .disabled(status == .importing)
            }
            statusBanner
        }
        .onboardingCard()
    }

    private func tip(_ symbol: String, _ text: LocalizedStringKey) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: symbol)
                .foregroundStyle(OnboardingStyle.accent)
                .frame(width: 22)
            Text(text)
                .font(OnboardingStyle.caption)
                .foregroundStyle(OnboardingStyle.muted)
        }
    }

    private func pull() async {
        do {
            let result = try await ServerSync.pull(into: store)
            pullMessage = result.added > 0 ? "+\(result.added) new from WhatsApp." : "Nothing new yet."
        } catch {
            pullMessage = "Couldn't reach hindsight: \(error.localizedDescription)"
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

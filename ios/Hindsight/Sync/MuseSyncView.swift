import SwiftUI

/// "Sync with Muse". Two ways:
/// - **Automatic (connector):** Muse is asked to add the hindsight connector
///   (connector/server.py) and send the saves to it; when the user comes back,
///   we pull what arrived. No copying.
/// - **Copy & paste (fallback):** Muse replies with a JSON list; the user
///   copies it and pastes it here.
/// Either way, Muse is opened in its app or via WhatsApp with our message ready.
struct MuseSyncView: View {
    let store: SavedPostStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @State private var phase: Phase = .ready
    @State private var launchOutcome: MuseLauncher.Outcome?
    @State private var launchedViaWhatsApp = false
    @State private var method: Method = MuseConnector.baseURL == nil ? .paste : .connector
    @State private var pollID: UUID?
    /// Set by "Get older saves": the next prompt asks for saves before this date.
    @State private var olderThan: Date?
    @AppStorage(MuseConnector.baseURLKey) fileprivate var connectorBaseURL = ""
    @AppStorage(MuseConnector.connectedKey) fileprivate var connectorConnected = false

    enum Method: String, CaseIterable, Identifiable {
        case connector = "Automatic"
        case paste = "Copy & paste"
        var id: Self { self }
    }

    enum Phase: Equatable {
        case ready
        /// User went to Muse; waiting for the reply (paste) or the connector.
        case waiting
        /// Connector: checking for what Muse sent. `added` so far.
        case receiving(added: Int, received: Int)
        case imported(added: Int, found: Int)
        case failed(String)
    }

    private var base: URL? { MuseConnector.normalized(connectorBaseURL) ?? MuseConnector.baseURL }

    private var prompt: String {
        switch method {
        case .paste:
            return MusePrompt.text(window: window)
        case .connector:
            guard let base else { return MusePrompt.text(window: window) }
            return connectorConnected
                ? MuseConnector.syncPrompt(window: window)
                : MuseConnector.connectPrompt(mcpURL: MuseConnector.mcpURL(base: base), window: window)
        }
    }

    /// Decided from what we already have, so the user never has to choose:
    /// nothing of theirs yet → **all** their saves (the first pull is the whole
    /// history); asked for older ones → before the oldest we have; otherwise →
    /// only what's newer than the newest Instagram/Facebook save we have.
    /// Only the user's own imports count: the bundled seed is someone else's
    /// saves, and its newest date (2026-09-27) used to turn the very first
    /// prompt into "saved after 2026-09-27".
    private var window: MusePrompt.Window {
        if method == .connector && !connectorConnected { return .all }
        if let olderThan { return .before(olderThan) }
        return userSavedDates.max().map(MusePrompt.Window.after) ?? .all
    }

    /// `savedAt` of the Instagram/Facebook saves the user imported themselves.
    private var userSavedDates: [Date] {
        store.posts
            .filter { ($0.platform == .instagram || $0.platform == .facebook) && $0.source != .seedMD }
            .compactMap(\.savedAt)
    }

    var body: some View {
        NavigationStack {
            OnboardingPage {
                Text("Sync with\nMuse.")
                    .font(OnboardingStyle.display(40))

                Text("Muse is Meta's AI. It can already see your Instagram and Facebook saves, so we just ask it nicely.")
                    .font(OnboardingStyle.body)
                    .foregroundStyle(OnboardingStyle.muted)

                if case .ready = phase {
                    MuseGuide(flow: method == .connector ? .connector : .paste)
                        .frame(maxWidth: .infinity)
                        .id(method)
                }

                VStack(spacing: 10) {
                    switch method {
                    case .connector:
                        stepRow(1, connectorConnected ? "Open Muse" : "Connect hindsight to Muse", detail: openDetail, isActive: phase == .ready)
                        stepRow(2, "Send it", detail: connectorConnected
                                    ? "Muse sends your new saves straight to hindsight."
                                    : "When Muse asks, tap \u{201C}Always allow this site\u{201D} so future syncs just work.", isActive: phase == .waiting)
                        stepRow(3, "Come back here", detail: "We check automatically. No copying.", isActive: isReceiving)
                    case .paste:
                        stepRow(1, "Open Muse", detail: openDetail, isActive: phase == .ready)
                        stepRow(2, "Copy Muse's reply", detail: "Long-press the code block → Copy.", isActive: phase == .waiting)
                        stepRow(3, "Paste it here", detail: "We'll pull out every post.", isActive: phase == .waiting)
                    }
                }

                statusBanner

                if base != nil, case .ready = phase {
                    Button(method == .connector ? "Muse won't connect? Paste its reply instead" : "Use the automatic way instead") {
                        method = method == .connector ? .paste : .connector
                    }
                    .font(OnboardingStyle.caption)
                }

                if launchOutcome == .notInstalled, case .ready = phase {
                    Link("Get Muse on the App Store", destination: MuseLauncher.appStoreURL)
                        .font(OnboardingStyle.caption)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("MESSAGE WE SEND MUSE")
                        .font(.system(.caption, design: .rounded, weight: .heavy))
                        .tracking(1.4)
                        .foregroundStyle(OnboardingStyle.muted)
                    Text(prompt)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(OnboardingStyle.muted)
                        .textSelection(.enabled)
                        .onboardingCard(padding: 14)
                    HStack {
                        Button("Copy message") { UIPasteboard.general.string = prompt }
                        Spacer()
                        ShareLink("Share to Muse…", item: prompt)
                    }
                    .font(OnboardingStyle.caption)
                }

                #if DEBUG
                connectorSettings
                MuseLinkLab()
                #endif
            } actions: {
                actions
            }
            .foregroundStyle(OnboardingStyle.text)
            .background(OnboardingStyle.background.ignoresSafeArea())
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .preferredColorScheme(.dark)
        .tint(OnboardingStyle.accent)
        .onChange(of: scenePhase) { _, newPhase in
            // Back from Muse: paste → show the paste step; connector → start checking.
            guard newPhase == .active, launchOutcome != nil else { return }
            switch (method, phase) {
            case (.paste, .ready): phase = .waiting
            case (.connector, .ready), (.connector, .waiting): startChecking()
            default: break
            }
        }
        .task(id: pollID) {
            guard pollID != nil else { return }
            await pollConnector()
        }
    }

    private var isReceiving: Bool {
        if case .receiving = phase { return true }
        return false
    }

    @ViewBuilder
    private var actions: some View {
        switch phase {
        case .imported(let added, _):
            Button("Done") { dismiss() }
                .buttonStyle(.onboardingPrimary)
            // Muse replies with up to 50 saves at a time, so the first pull
            // pages back through the whole history, one reply at a time.
            if added > 0, let oldest = userSavedDates.min() {
                Button("Get older saves") {
                    olderThan = oldest
                    launchOutcome = nil
                    phase = .ready
                }
                .buttonStyle(.onboardingSecondary)
            }
        case .receiving:
            Button("Done") { dismiss() }
                .buttonStyle(.onboardingPrimary)
            Button("Check again") { startChecking() }
                .buttonStyle(.onboardingSecondary)
        default:
            if phase == .ready || method == .connector {
                Button(phase == .ready ? "Open Muse" : "Open Muse again") { Task { await openMuse(viaWhatsApp: false) } }
                    .buttonStyle(.onboardingPrimary)
                Button("Ask Muse in WhatsApp") { Task { await openMuse(viaWhatsApp: true) } }
                    .buttonStyle(.onboardingSecondary)
            }
            if method == .paste {
                PasteButton(payloadType: String.self) { strings in
                    let text = strings.joined(separator: "\n")
                    Task { @MainActor in importReply(text) }
                }
                .buttonBorderShape(.capsule)
                .controlSize(.large)
                .tint(phase == .ready ? OnboardingStyle.surface : OnboardingStyle.accent)
            } else if phase == .waiting {
                Button("Check now") { startChecking() }
                    .buttonStyle(.onboardingSecondary)
            }
            #if DEBUG
            Button("Use sample reply (dev)") { importReply(MuseSampleReply.text) }
                .buttonStyle(.onboardingSecondary)
            #endif
        }
    }

    @ViewBuilder
    private var statusBanner: some View {
        switch phase {
        case .ready, .waiting:
            EmptyView()
        case .receiving(let added, let received):
            HStack(spacing: 10) {
                if pollID != nil { ProgressView() }
                Text(receivingMessage(added: added, received: received))
                    .font(OnboardingStyle.title)
                    .foregroundStyle(received > 0 ? OnboardingStyle.accent : OnboardingStyle.text)
            }
        case .imported(let added, let found):
            Label(
                added > 0 ? "+\(added) new saves (\(found) in Muse's reply)" : "Nothing new. All \(found) were already here.",
                systemImage: "checkmark.circle.fill"
            )
            .font(OnboardingStyle.title)
            .foregroundStyle(OnboardingStyle.accent)
        case .failed(let message):
            Label(message, systemImage: "exclamationmark.triangle.fill")
                .font(OnboardingStyle.caption)
                .foregroundStyle(.orange)
        }
    }

    private func receivingMessage(added: Int, received: Int) -> String {
        let checking = pollID != nil ? " Still checking…" : ""
        switch (added, received) {
        case (0, 0): return pollID != nil ? "Waiting for Muse to send your saves…" : "Nothing arrived yet. Did Muse say it sent them?"
        case (0, _): return "Muse sent \(received), all already in hindsight.\(checking)"
        case (_, _) where added == received: return "+\(added) saves arrived from Muse.\(checking)"
        default: return "+\(added) new saves from Muse (\(received - added) you already had).\(checking)"
        }
    }

    private var openDetail: String {
        switch launchOutcome {
        case .opened:
            launchedViaWhatsApp
                ? "Message copied. Open your Muse chat in WhatsApp, paste it and send."
                : "Our message is on your clipboard. If it isn't typed in already, paste it and send."
        case .notInstalled: "Couldn't open Muse. The message is copied, so paste it into Muse yourself."
        case nil:
            method == .connector && !connectorConnected
                ? "One message sets it up and sends your saves."
                : "We'll open it with the message ready."
        }
    }

    private func stepRow(_ number: Int, _ title: String, detail: String, isActive: Bool) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Text("\(number)")
                .font(.system(.headline, design: .rounded, weight: .black))
                .foregroundStyle(isActive ? OnboardingStyle.onAccent : OnboardingStyle.text)
                .frame(width: 32, height: 32)
                .background(isActive ? OnboardingStyle.accent : OnboardingStyle.stroke, in: .circle)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(OnboardingStyle.title)
                Text(detail)
                    .font(OnboardingStyle.caption)
                    .foregroundStyle(OnboardingStyle.muted)
            }
            Spacer(minLength: 0)
        }
        .onboardingCard(padding: 14)
    }

    private func openMuse(viaWhatsApp: Bool) async {
        let outcome = viaWhatsApp
            ? await MuseLauncher.launchWhatsApp(prompt: prompt)
            : await MuseLauncher.launch(prompt: prompt)
        DebugLog.write("muse launch (\(viaWhatsApp ? "whatsapp" : "app"), \(method.rawValue), connected=\(connectorConnected)): \(outcome)")
        launchedViaWhatsApp = viaWhatsApp
        launchOutcome = outcome
        phase = outcome == .notInstalled ? .ready : .waiting
    }

    // MARK: - Connector

    private func startChecking() {
        if case .receiving = phase {} else { phase = .receiving(added: 0, received: 0) }
        pollID = UUID()
    }

    /// Muse can take a while to page through saves, so check every few seconds
    /// for up to 3 minutes, merging whatever has arrived.
    private func pollConnector() async {
        guard let base else { return }
        var added: Int = if case .receiving(let n, _) = phase { n } else { 0 }
        for attempt in 0..<45 {
            do {
                let text = try await MuseConnector.fetchSaves(base: base)
                let posts = SavedPostParser.parse(text, source: .muse).posts
                let new = store.merge(posts)
                added += new
                if !posts.isEmpty && !connectorConnected { connectorConnected = true }
                if new > 0 || attempt == 0 {
                    DebugLog.write("connector check #\(attempt): \(posts.count) on server, +\(new) new (total +\(added))")
                }
                phase = .receiving(added: added, received: posts.count)
            } catch is CancellationError {
                return
            } catch {
                DebugLog.write("connector check failed: \(error)")
                phase = .failed("Couldn't reach hindsight's connector: \(error.localizedDescription)")
                pollID = nil
                return
            }
            try? await Task.sleep(for: .seconds(4))
            if Task.isCancelled { return }
        }
        pollID = nil
    }

    // MARK: - Paste

    private func importReply(_ text: String) {
        let result = SavedPostParser.parse(text)
        let byPlatform = Dictionary(grouping: result.posts, by: \.platform).mapValues(\.count)
        let fullCaptions = result.posts.count { ($0.caption?.count ?? 0) > 160 }
        let withCollections = result.posts.count { !$0.collections.isEmpty }
        DebugLog.write("paste: \(text.count) chars, \(result.posts.count) posts \(byPlatform), \(result.skipped) skipped, captions>160: \(fullCaptions), with collections: \(withCollections)")
        if MuseConnector.isOurPrompt(text) {
            DebugLog.write("paste was our own prompt")
            phase = .failed("That's our message, not Muse's answer. Paste it into Muse and send it first, then copy Muse's reply.")
            return
        }
        guard !result.posts.isEmpty else {
            DebugLog.write("paste failed, text starts: \(text.prefix(400))")
            phase = .failed("Couldn't find any posts in what you pasted. Copy Muse's whole reply and try again.")
            return
        }
        let added = store.merge(result.posts)
        phase = .imported(added: added, found: result.posts.count)
    }
}

#Preview {
    MuseSyncView(store: SavedPostStore(fileURL: nil))
}

#if DEBUG
extension MuseSyncView {
    /// Simulates a brand-new user: a fresh, empty tenant on the server (so Muse's
    /// connector URL is new too), no local saves, and "not connected yet".
    func startFreshTest() async {
        guard let current = MuseConnector.normalized(connectorBaseURL) ?? MuseConnector.baseURL else { return }
        do {
            let tenant = try await MuseConnector.createTenant(base: current)
            connectorBaseURL = tenant.absoluteString
            connectorConnected = false
            store.removeAll()
            DebugLog.write("fresh muse test: tenant \(tenant.lastPathComponent), local store emptied")
        } catch {
            DebugLog.write("fresh muse test failed: \(error)")
        }
    }

    /// Dev-only: where the connector runs (`https://<tunnel>/<token>`, see connector/README.md).
    var connectorSettings: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("MUSE CONNECTOR URL (DEV)")
                .font(.system(.caption, design: .rounded, weight: .heavy))
                .tracking(1.4)
                .foregroundStyle(OnboardingStyle.muted)
            TextField("https://…trycloudflare.com/<token>", text: $connectorBaseURL)
                .font(.system(.caption, design: .monospaced))
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .onboardingCard(padding: 12)
            Toggle("Muse already has the connector", isOn: $connectorConnected)
                .font(OnboardingStyle.caption)
            Button("Fresh Muse test (new user)") { Task { await startFreshTest() } }
                .buttonStyle(.onboardingSecondary)
            Text("New empty store on the server + empties this app's saves. The message tells Muse to replace its old hindsight connector.")
                .font(OnboardingStyle.caption)
                .foregroundStyle(OnboardingStyle.muted)
        }
    }
}

/// Dev-only: try candidate Muse links on a real device and log which open.
private struct MuseLinkLab: View {
    @State private var results: [String: Bool] = [:]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("LINK LAB (DEV)")
                .font(.system(.caption, design: .rounded, weight: .heavy))
                .tracking(1.4)
                .foregroundStyle(OnboardingStyle.muted)
            Text("Tap each. Note whether Muse opens, and whether \"hello from hindsight\" is already typed.")
                .font(OnboardingStyle.caption)
                .foregroundStyle(OnboardingStyle.muted)
            ForEach(MuseLauncher.linkLabCandidates, id: \.url) { candidate in
                Button {
                    Task { await tryLink(candidate.url) }
                } label: {
                    HStack {
                        Text(candidate.label).font(.system(.subheadline, design: .monospaced))
                        Spacer()
                        switch results[candidate.url] {
                        case true?: Image(systemName: "checkmark.circle.fill").foregroundStyle(OnboardingStyle.accent)
                        case false?: Image(systemName: "xmark.circle").foregroundStyle(.orange)
                        case nil: Image(systemName: "arrow.up.right").foregroundStyle(OnboardingStyle.muted)
                        }
                    }
                    .onboardingCard(padding: 12)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func tryLink(_ string: String) async {
        guard let url = URL(string: string) else { return }
        let options: [UIApplication.OpenExternalURLOptionsKey: Any] =
            url.scheme == "https" ? [.universalLinksOnly: true] : [:]
        let opened = await UIApplication.shared.open(url, options: options)
        results[string] = opened
        DebugLog.write("link lab: \(string) opened=\(opened)")
    }
}
#endif

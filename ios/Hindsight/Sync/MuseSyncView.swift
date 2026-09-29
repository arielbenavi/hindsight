import SwiftUI

/// "Sync with Muse": open Muse with our prompt, then paste its reply back.
/// The paste step goes away once a hindsight MCP connector exists
/// (see docs/DATA_FETCHING_RESEARCH.md).
struct MuseSyncView: View {
    let store: SavedPostStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @State private var phase: Phase = .ready
    @State private var launchOutcome: MuseLauncher.Outcome?

    enum Phase: Equatable {
        case ready
        /// User went to Muse; waiting for them to come back with the reply.
        case waiting
        case imported(added: Int, found: Int)
        case failed(String)
    }

    private var prompt: String {
        MusePrompt.text(since: newestMetaSave)
    }

    /// Only ask Muse for what's newer than what we already have.
    private var newestMetaSave: Date? {
        store.posts.lazy
            .filter { $0.platform == .instagram || $0.platform == .facebook }
            .compactMap(\.date)
            .max()
    }

    var body: some View {
        NavigationStack {
            OnboardingPage {
                Text("Sync with\nMuse.")
                    .font(OnboardingStyle.display(40))

                Text("Muse is Meta's AI. It can already see your Instagram and Facebook saves, so we just ask it nicely.")
                    .font(OnboardingStyle.body)
                    .foregroundStyle(OnboardingStyle.muted)

                VStack(spacing: 10) {
                    stepRow(1, "Open Muse", detail: openDetail, isActive: phase == .ready)
                    stepRow(2, "Copy Muse's reply", detail: "Long-press the code block → Copy.", isActive: phase == .waiting)
                    stepRow(3, "Paste it here", detail: "We'll pull out every post.", isActive: phase == .waiting)
                }

                statusBanner

                if launchOutcome == .notInstalled, case .ready = phase {
                    Link("Get Muse on the App Store", destination: MuseLauncher.appStoreURL)
                        .font(OnboardingStyle.caption)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("PROMPT WE SEND")
                        .font(.system(.caption, design: .rounded, weight: .heavy))
                        .tracking(1.4)
                        .foregroundStyle(OnboardingStyle.muted)
                    Text(prompt)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(OnboardingStyle.muted)
                        .textSelection(.enabled)
                        .onboardingCard(padding: 14)
                    HStack {
                        Button("Copy prompt") { UIPasteboard.general.string = prompt }
                        Spacer()
                        ShareLink("Share to Muse…", item: prompt)
                    }
                    .font(OnboardingStyle.caption)
                }

                #if DEBUG
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
            // Back from Muse: move straight to the paste step.
            if newPhase == .active, launchOutcome != nil, phase == .ready {
                phase = .waiting
            }
        }
    }

    @ViewBuilder
    private var actions: some View {
        switch phase {
        case .imported:
            Button("Done") { dismiss() }
                .buttonStyle(.onboardingPrimary)
        default:
            if phase == .ready {
                Button("Open Muse") { Task { await openMuse() } }
                    .buttonStyle(.onboardingPrimary)
            }
            PasteButton(payloadType: String.self) { strings in
                let text = strings.joined(separator: "\n")
                Task { @MainActor in importReply(text) }
            }
            .buttonBorderShape(.capsule)
            .controlSize(.large)
            .tint(phase == .ready ? OnboardingStyle.surface : OnboardingStyle.accent)
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

    private var openDetail: String {
        switch launchOutcome {
        case .opened: "Our question is on your clipboard. If it isn't typed in already, paste it and send."
        case .notInstalled: "Couldn't open Muse. The question is copied, so paste it into Muse yourself."
        case nil: "We'll open it with the question ready."
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

    private func openMuse() async {
        let outcome = await MuseLauncher.launch(prompt: prompt)
        DebugLog.write("muse launch: \(outcome)")
        launchOutcome = outcome
        if outcome == .notInstalled {
            phase = .ready
        }
    }

    private func importReply(_ text: String) {
        let result = SavedPostParser.parse(text)
        DebugLog.write("paste: \(text.count) chars, \(result.posts.count) posts, \(result.skipped) skipped")
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

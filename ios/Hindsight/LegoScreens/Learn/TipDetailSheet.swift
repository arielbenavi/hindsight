import SwiftUI

/// L4: one tip, in a sheet. A try from here counts too.
/// ("Move to…" another topic or lego screen is left out of the MVP.)
struct TipDetailSheet: View {
    let app: AppModel
    let tip: Tip

    @State private var askingWhen = false
    @State private var triedTick = 0
    @State private var quip: String?
    @Environment(\.openURL) private var openURL
    @Environment(\.dismiss) private var dismiss

    private var practice: PracticeStore { app.practice }
    private var state: PracticeState { practice.state(.learn, tip.id) }
    private var section: LearnSection? { app.learn?.section(tip.topicID) }
    private var emoji: String { section?.emoji ?? "📚" }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    PostHero(post: tip.post, emoji: emoji)
                    header
                    promptCard
                    if let gist = tip.gist { gistBlock(gist) }
                    if let keyword = tip.ctaKeyword { ctaNotice(keyword) }
                    CaptionDisclosure(caption: tip.post.caption)
                    actions
                }
                .padding(Theme.padding)
            }
            .scrollIndicators(.hidden)
            .background(Theme.background)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
            .navigationBarTitleDisplayMode(.inline)
        }
        .sensoryFeedback(.success, trigger: triedTick)
        .presentationDragIndicator(.visible)
        .preferredColorScheme(.dark)
    }

    // MARK: - Pieces

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let section {
                Text("\(section.emoji) \(section.title)").font(Theme.label(14)).foregroundStyle(Theme.secondary)
            }
            Text(tip.title).font(Theme.title(26)).fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 8) {
                PostByline(post: tip.post)
                if let saved = tip.post.savedDate {
                    Text("· saved \(saved.formatted(.dateTime.month(.abbreviated).year()))")
                        .font(Theme.body(13, weight: .semibold)).foregroundStyle(Theme.muted)
                }
            }
            Text(LearnStatus.line(state))
                .font(Theme.body(15, weight: .semibold))
                .foregroundStyle(LearnStatus.isTried(state) ? Theme.lime : Theme.secondary)
                .contentTransition(.opacity)
        }
    }

    @ViewBuilder private var promptCard: some View {
        if let prompt = tip.prompt, state.status != .archived {
            VStack(alignment: .leading, spacing: 12) {
                Tag(text: "Suggested", color: Theme.lime)
                Text(prompt).font(Theme.title(21)).fixedSize(horizontal: false, vertical: true)
                if let quip {
                    Label(quip, systemImage: "sparkles")
                        .font(Theme.body(15, weight: .semibold))
                        .foregroundStyle(Theme.lime)
                        .transition(.scale.combined(with: .opacity))
                } else {
                    Button(LearnStatus.isTried(state) ? "Tried it again" : "Tried it") { markTried() }
                        .buttonStyle(.pill)
                }
            }
            .card(padding: 18)
        } else if tip.isThin {
            Label("Not much to go on in the caption, so no try prompt for this one. It lives in your library.",
                  systemImage: "text.page.slash")
                .font(Theme.body(14)).foregroundStyle(Theme.secondary)
                .card(padding: 14)
        }
    }

    private func gistBlock(_ gist: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(gist).font(Theme.body(17)).fixedSize(horizontal: false, vertical: true)
            if !tip.keyPoints.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(Array(tip.keyPoints.enumerated()), id: \.offset) { _, point in
                        HStack(alignment: .firstTextBaseline, spacing: 10) {
                            Circle().fill(Theme.lime).frame(width: 6, height: 6).alignmentGuide(.firstTextBaseline) { $0[.bottom] + 1 }
                            Text(point).font(Theme.body(15)).foregroundStyle(Theme.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
        }
    }

    private func ctaNotice(_ keyword: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Comment \(keyword) on the post to get the link.", systemImage: "text.bubble")
                .font(Theme.body(15, weight: .semibold))
            Button { PostOpener.open(tip.post, openURL: openURL) } label: {
                Label("Open post to comment", systemImage: "arrow.up.right")
            }
            .buttonStyle(.pillCompact)
        }
        .card(padding: 14, background: Theme.surfaceRaised)
    }

    @ViewBuilder private var actions: some View {
        VStack(alignment: .leading, spacing: 14) {
            if state.status != .archived {
                if askingWhen {
                    WhenChips { when in
                        practice.remind(.learn, tip.id, at: when.date(from: .now, slot: practice.screen(.learn).slot))
                        app.rescheduleReminders()
                        withAnimation(.snappy) { askingWhen = false }
                    }
                    .transition(.opacity)
                } else {
                    Button { withAnimation(.snappy) { askingWhen = true } } label: {
                        Label("Remind me…", systemImage: "alarm")
                    }
                    .buttonStyle(.pillSecondary)
                }
                Button("Not for me") {
                    practice.archive(.learn, tip.id)
                    app.rescheduleReminders()
                }
                .font(Theme.body(15, weight: .semibold))
                .foregroundStyle(Theme.secondary)
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity)
            } else {
                Button {
                    practice.unarchive(.learn, tip.id)
                    app.rescheduleReminders()
                } label: {
                    Label("Bring back", systemImage: "arrow.uturn.backward")
                }
                .buttonStyle(.pillSecondary)
            }
        }
        .animation(.snappy, value: state.status)
    }

    private func markTried() {
        withAnimation(.spring(duration: 0.5, bounce: 0.4)) {
            practice.tried(.learn, tip.id)
            quip = PracticeQuip.pick(PracticeQuip.tried, seed: "\(tip.id)|\(state.triedAt.count)")
        }
        triedTick += 1
        app.rescheduleReminders()
    }
}

#if DEBUG
#Preview("Tip detail") {
    let app = LearnPreview.app()
    let tip = app.learn?.tips.first { $0.isPickable } ?? app.learn!.tips[0]
    Color.clear.sheet(isPresented: .constant(true)) { TipDetailSheet(app: app, tip: tip) }
}

#Preview("Tip detail · comment for the link") {
    let app = LearnPreview.app()
    let tip = app.learn?.tips.first { $0.ctaKeyword != nil } ?? app.learn!.tips[0]
    Color.clear.sheet(isPresented: .constant(true)) { TipDetailSheet(app: app, tip: tip) }
}
#endif

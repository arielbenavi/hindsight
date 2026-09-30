import SwiftUI

/// L0: first open of Learn. Three quick, skippable steps: swipe 5 saves,
/// tries a week, when to nudge. Then the ring starts with its setup segment filled.
struct LearnSetupView: View {
    let app: AppModel
    let onDone: () -> Void

    private enum Step: Int, CaseIterable { case pick, goal, time }

    @State private var step: Step = .pick
    @State private var picks: [Tip] = []
    @State private var index = 0
    @State private var goal = 3
    @State private var slot: ReminderSlot = .evening
    @State private var finishing = false

    private var practice: PracticeStore { app.practice }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            topBar
            Group {
                switch step {
                case .pick: pickStep
                case .goal: goalStep
                case .time: timeStep
                }
            }
            .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity), removal: .opacity))
            .frame(maxHeight: .infinity, alignment: .top)
        }
        .padding(Theme.padding)
        .themedScreen()
        .animation(.snappy(duration: 0.35), value: step)
        .onAppear { if picks.isEmpty { picks = Self.setupPicks(app.learn, practice: practice) } }
    }

    // MARK: - Chrome

    private var topBar: some View {
        HStack {
            Button("Not now") {
                practice.skipSetup(.learn)
                onDone()
            }
            .foregroundStyle(Theme.secondary)
            Spacer()
            HStack(spacing: 6) {
                ForEach(Step.allCases, id: \.self) { s in
                    Capsule().fill(s.rawValue <= step.rawValue ? Theme.lime : Theme.surfaceRaised)
                        .frame(width: s == step ? 22 : 8, height: 8)
                }
            }
            .accessibilityHidden(true)
            Spacer()
            Button("Skip") { advance() }
                .foregroundStyle(Theme.secondary)
                .opacity(step == .time ? 0 : 1)
                .disabled(step == .time)
        }
        .font(Theme.body(15, weight: .semibold))
        .buttonStyle(.plain)
        .padding(.bottom, 28)
    }

    private func heading(_ title: String, _ subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(Theme.title(30)).fixedSize(horizontal: false, vertical: true)
            Text(subtitle).font(Theme.body(16)).foregroundStyle(Theme.secondary)
        }
        .padding(.bottom, 24)
    }

    // MARK: - Step 1: swipe

    private var pickStep: some View {
        VStack(alignment: .leading, spacing: 0) {
            heading("Pick what you actually want to learn.", "Swipe right for yes, left for not for me.")
            if index < picks.count {
                let tip = picks[index]
                ZStack {
                    // next card peeking behind
                    if index + 1 < picks.count {
                        pickCard(picks[index + 1]).scaleEffect(0.94).offset(y: 14).opacity(0.5).allowsHitTesting(false)
                    }
                    SwipeCard(onRight: { swipe(tip, yes: true) }, onLeft: { swipe(tip, yes: false) }) {
                        pickCard(tip)
                    }
                    .id(tip.id)
                }
                Text("\(index + 1) of \(picks.count)")
                    .font(Theme.label(13)).foregroundStyle(Theme.muted)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 20)
                HStack(spacing: 12) {
                    Button { swipe(tip, yes: false) } label: { Label("Not for me", systemImage: "xmark") }
                        .buttonStyle(.pillSecondary)
                    Button { swipe(tip, yes: true) } label: { Label("I want to try this", systemImage: "checkmark") }
                        .buttonStyle(.pill)
                }
                .padding(.top, 14)
            } else {
                Text(picks.isEmpty ? "Nothing with a try prompt yet. Your library still works." : "Got it.")
                    .font(Theme.body(17)).foregroundStyle(Theme.secondary)
                Button("Next") { advance() }.buttonStyle(.pill).padding(.top, 24)
            }
        }
    }

    private func pickCard(_ tip: Tip) -> some View {
        let section = app.learn?.section(tip.topicID)
        return VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                PostThumbnail(post: tip.post, emoji: section?.emoji, size: 56)
                VStack(alignment: .leading, spacing: 3) {
                    if let section {
                        Text("\(section.emoji) \(section.title)").font(Theme.label(13)).foregroundStyle(Theme.secondary)
                    }
                    Text(tip.title).font(Theme.title(19)).lineLimit(2)
                }
            }
            if let prompt = tip.prompt {
                Tag(text: "Suggested", color: Theme.lime)
                Text(prompt).font(Theme.body(18, weight: .semibold)).fixedSize(horizontal: false, vertical: true)
            }
            PostByline(post: tip.post)
        }
        .card(padding: 20, background: Theme.surface)
    }

    private func swipe(_ tip: Tip, yes: Bool) {
        if yes { practice.markWantToTry(.learn, tip.id) } else { practice.archive(.learn, tip.id) }
        withAnimation(.snappy) { index += 1 }
        if index >= picks.count { advance() }
    }

    // MARK: - Step 2: goal

    private var goalStep: some View {
        VStack(alignment: .leading, spacing: 0) {
            heading("How many tries a week?", "Small is fine. You can change it.")
            HStack(spacing: 10) {
                ForEach([1, 3, 5, 7], id: \.self) { n in
                    Chip(label: "\(n)", isSelected: goal == n) { goal = n }
                }
            }
            Spacer()
            Button("Next") { advance() }.buttonStyle(.pill)
        }
    }

    // MARK: - Step 3: time

    private var timeStep: some View {
        VStack(alignment: .leading, spacing: 0) {
            heading("When should we nudge you?", "One nudge a day, tops. About one specific save.")
            WrapLayout(spacing: 10) {
                ForEach(ReminderSlot.allCases) { s in
                    Chip(label: s.title, isSelected: slot == s) { slot = s }
                }
            }
            Spacer()
            Button(finishing ? "One sec…" : "Let's go") { finish() }
                .buttonStyle(.pill)
                .disabled(finishing)
        }
    }

    private func advance() {
        switch step {
        case .pick: step = .goal
        case .goal: step = .time
        case .time: finish()
        }
    }

    private func finish() {
        finishing = true
        let chosen = slot
        Task {
            if chosen != .off { _ = await ReminderScheduler.shared.requestAuthorization() }
            practice.finishSetup(.learn, goal: goal, slot: chosen)
            app.rescheduleReminders()
            onDone()
        }
    }

    /// 5 pickable tips from the biggest topics, round-robin so one topic doesn't take all 5.
    static func setupPicks(_ catalog: LearnCatalog?, practice: PracticeStore, count: Int = 5) -> [Tip] {
        guard let catalog else { return [] }
        var queues = catalog.sections.prefix(3).map { section in
            section.tips.filter { $0.isPickable && practice.state(.learn, $0.id).status == .new }
        }
        var picks: [Tip] = []
        while picks.count < count, queues.contains(where: { !$0.isEmpty }) {
            for i in queues.indices where !queues[i].isEmpty && picks.count < count {
                picks.append(queues[i].removeFirst())
            }
        }
        return picks
    }
}

#if DEBUG
#Preview("Setup") {
    let app = LearnPreview.app(setupDone: false)
    LearnSetupView(app: app) {}
}
#endif

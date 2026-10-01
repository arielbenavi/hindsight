import SwiftUI

/// L5: about identity, not points. This week, the last 8 weeks (no "failed"
/// styling), per-topic counts, and the practice settings.
struct LearnProgressSheet: View {
    let app: AppModel

    @State private var notificationsDenied = false
    @Environment(\.dismiss) private var dismiss

    private var practice: PracticeStore { app.practice }
    private var screen: ScreenPractice { practice.screen(.learn) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 26) {
                    WeeklyRing(progress: practice.progress(.learn))
                    history
                    topics
                    Text(identityLine)
                        .font(Theme.title(20))
                        .fixedSize(horizontal: false, vertical: true)
                    settings
                }
                .padding(Theme.padding)
            }
            .scrollIndicators(.hidden)
            .background(Theme.background)
            .navigationTitle("Your practice")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
        .presentationDragIndicator(.visible)
        .preferredColorScheme(.dark)
    }

    // MARK: - History

    private var history: some View {
        let weeks = WeeklyProgress.history(states: Array(screen.states.values), goal: screen.weeklyGoal, now: .now)
        return VStack(alignment: .leading, spacing: 12) {
            Text("Last 8 weeks").font(Theme.body(15, weight: .bold)).foregroundStyle(Theme.secondary)
            HStack(spacing: 0) {
                ForEach(Array(weeks.enumerated()), id: \.offset) { _, week in
                    VStack(spacing: 6) {
                        MiniRing(done: week.done, goal: screen.weeklyGoal)
                        Text("\(week.done)").font(Theme.label(12))
                        Text(week.start.formatted(.dateTime.day().month(.defaultDigits)))
                            .font(Theme.label(10)).foregroundStyle(Theme.muted)
                    }
                    .frame(maxWidth: .infinity)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("Week of \(week.start.formatted(.dateTime.day().month())): \(week.done) tries")
                }
            }
        }
        .card(padding: 16)
    }

    // MARK: - Topics

    private struct TopicCount: Identifiable {
        var section: LearnSection
        var tried: Int
        var stillGotIt: Int
        var id: String { section.id }
    }

    private var topicCounts: [TopicCount] {
        (app.learn?.sections ?? []).map { section in
            let states = section.tips.map { practice.state(.learn, $0.id) }
            return TopicCount(section: section, tried: states.count(where: LearnStatus.isTried),
                              stillGotIt: states.count(where: LearnStatus.stillGotIt))
        }
    }

    private var topics: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("By topic").font(Theme.body(15, weight: .bold)).foregroundStyle(Theme.secondary)
            ForEach(topicCounts) { t in
                HStack {
                    Text("\(t.section.emoji) \(t.section.title)").font(Theme.body(16, weight: .bold)).lineLimit(1)
                    Spacer()
                    Text(t.stillGotIt > 0 ? "\(t.tried) tried · \(t.stillGotIt) still got it" : "\(t.tried) tried")
                        .font(Theme.body(14)).foregroundStyle(t.tried > 0 ? Theme.lime : Theme.muted)
                }
                .padding(.vertical, 4)
            }
        }
        .card(padding: 16)
    }

    private var identityLine: String {
        guard let best = topicCounts.max(by: { $0.tried < $1.tried }), best.tried > 0 else {
            return "Every try counts, even the first one."
        }
        let total = topicCounts.reduce(0) { $0 + $1.tried }
        let noun = best.tried == 1 ? "tip" : "tips"
        if best.tried == total {
            return "You've tried \(best.tried) \(best.section.title.lowercased()) \(noun). You're someone who practices."
        }
        return "You've tried \(total) tips, \(best.tried) of them \(best.section.title.lowercased()). You're someone who practices."
    }

    // MARK: - Settings

    private var settings: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Settings").font(Theme.body(15, weight: .bold)).foregroundStyle(Theme.secondary)
            VStack(alignment: .leading, spacing: 10) {
                Text("Tries a week").font(Theme.body(16, weight: .bold))
                HStack(spacing: 8) {
                    ForEach([1, 3, 5, 7], id: \.self) { goal in
                        Chip(label: "\(goal)", isSelected: screen.weeklyGoal == goal) {
                            withAnimation(.snappy) { practice.setGoal(.learn, goal) }
                        }
                    }
                }
            }
            Toggle(isOn: Binding(get: { screen.slot != .off }, set: { setReminders($0) })) {
                Text("Daily nudge").font(Theme.body(16, weight: .bold))
            }
            .tint(Theme.lime)
            if screen.slot != .off {
                HStack(spacing: 8) {
                    ForEach(ReminderSlot.allCases.filter { $0 != .off }) { slot in
                        Chip(label: slot.title, isSelected: screen.slot == slot) { setSlot(slot) }
                    }
                }
                .transition(.opacity)
            }
            if notificationsDenied && screen.slot != .off {
                Label("Notifications are off for Hindsight in Settings, so reminders show at the top of Learn instead.",
                      systemImage: "bell.slash")
                    .font(Theme.body(13)).foregroundStyle(Theme.secondary)
            }
        }
        .card(padding: 16)
        .animation(.snappy, value: screen.slot)
    }

    private func setReminders(_ on: Bool) {
        setSlot(on ? .evening : .off)
    }

    private func setSlot(_ slot: ReminderSlot) {
        practice.setSlot(.learn, slot)
        guard slot != .off else { app.rescheduleReminders(); return }
        Task {
            let granted = await ReminderScheduler.shared.requestAuthorization()
            notificationsDenied = !granted
            app.rescheduleReminders()
        }
    }
}

#if DEBUG
#Preview("Progress") {
    let app = LearnPreview.app()
    Color.clear.sheet(isPresented: .constant(true)) { LearnProgressSheet(app: app) }
}
#endif

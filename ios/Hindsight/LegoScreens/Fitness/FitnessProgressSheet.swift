import SwiftUI

/// Fitness progress (Learn's L5 with sessions): this week's ring, the last 8 weeks
/// as small rings, per-area counts, one identity line, and settings. No points.
struct FitnessProgressSheet: View {
    let app: AppModel
    @Environment(\.dismiss) private var dismiss

    private var practice: PracticeStore { app.practice }
    private var screen: ScreenPractice { practice.screen(.fitness) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 26) {
                    WeeklyRing(progress: practice.progress(.fitness), unit: "sessions").card()

                    Text(identityLine).font(Theme.title(22)).fixedSize(horizontal: false, vertical: true)

                    weeks
                    areas
                    settings
                }
                .padding(Theme.padding)
                .padding(.bottom, 30)
            }
            .themedScreen()
            .navigationTitle("Progress")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
        .presentationDragIndicator(.visible)
        .preferredColorScheme(.dark)
    }

    // MARK: - Sections

    private var weeks: some View {
        let history = WeeklyProgress.history(states: Array(screen.states.values), goal: screen.weeklyGoal, now: .now)
        return VStack(alignment: .leading, spacing: 12) {
            SectionTitle(text: "Last 8 weeks")
            HStack(spacing: 0) {
                ForEach(Array(history.enumerated()), id: \.offset) { _, week in
                    VStack(spacing: 6) {
                        MiniRing(done: week.done, goal: screen.weeklyGoal)
                        Text("\(week.done)").font(Theme.label(12)).foregroundStyle(Theme.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("Week of \(week.start.formatted(.dateTime.month().day())): \(week.done) sessions")
                }
            }
            .card(padding: 14)
        }
    }

    @ViewBuilder private var areas: some View {
        let counts = areaCounts
        if !counts.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                SectionTitle(text: "By body area")
                VStack(spacing: 0) {
                    ForEach(counts, id: \.area) { item in
                        HStack(spacing: 12) {
                            Image(systemName: item.area.symbol).foregroundStyle(Theme.lime).frame(width: 26)
                            Text(item.area.title).font(Theme.body(16, weight: .bold))
                            Spacer()
                            Text(item.count == 1 ? "1 session" : "\(item.count) sessions")
                                .font(Theme.body(15)).foregroundStyle(Theme.secondary)
                        }
                        .padding(.horizontal, 16).padding(.vertical, 12)
                        if item.area != counts.last?.area { Divider().overlay(Theme.stroke) }
                    }
                }
                .card(padding: 0)
            }
        }
    }

    private var settings: some View {
        VStack(alignment: .leading, spacing: 16) {
            SectionTitle(text: "Settings")
            VStack(alignment: .leading, spacing: 10) {
                Text("Sessions a week").font(Theme.body(15, weight: .bold)).foregroundStyle(Theme.secondary)
                HStack(spacing: 8) {
                    ForEach([1, 3, 5, 7], id: \.self) { g in
                        Chip(label: "\(g)", isSelected: screen.weeklyGoal == g) { practice.setGoal(.fitness, g) }
                    }
                }
            }
            VStack(alignment: .leading, spacing: 10) {
                Text("Daily nudge").font(Theme.body(15, weight: .bold)).foregroundStyle(Theme.secondary)
                WrapLayout(spacing: 8) {
                    ForEach(ReminderSlot.allCases) { slot in
                        Chip(label: slot.title, isSelected: screen.slot == slot) { setSlot(slot) }
                    }
                }
            }
        }
    }

    // MARK: - Counts

    /// All-time sessions per area ("Lower back · 6 sessions"), biggest first.
    private var areaCounts: [(area: BodyArea, count: Int)] {
        guard let catalog = app.fitness else { return [] }
        var counts: [BodyArea: Int] = [:]
        for routine in catalog.routines {
            let done = practice.state(.fitness, routine.id).triedAt.count
            guard done > 0 else { continue }
            for area in routine.info.bodyAreas { counts[area, default: 0] += done }
        }
        return BodyArea.allCases.compactMap { a in counts[a].map { (a, $0) } }.sorted { $0.count > $1.count }
    }

    /// "6 sessions this month. You're someone who looks after their back."
    private var identityLine: String {
        guard let catalog = app.fitness, let month = Calendar.current.dateInterval(of: .month, for: .now) else {
            return "Two minutes counts."
        }
        var total = 0
        var byArea: [BodyArea: Int] = [:]
        for routine in catalog.routines {
            let n = practice.state(.fitness, routine.id).triedAt.count { month.contains($0) }
            total += n
            if n > 0 { byArea[routine.primaryArea, default: 0] += n }
        }
        guard total > 0 else { return "A fresh month. One routine is a lovely start." }
        let top = byArea.max { $0.value < $1.value }?.key ?? .fullBody
        let sessions = total == 1 ? "1 session" : "\(total) sessions"
        return "\(sessions) this month. You're someone who looks after \(Self.caresFor(top))."
    }

    static func caresFor(_ area: BodyArea) -> String {
        switch area {
        case .lowerBack, .upperBack: "their back"
        case .neck: "their neck"
        case .shoulders: "their shoulders"
        case .hips: "their hips"
        case .knees: "their knees"
        case .ankles: "their ankles"
        case .core: "their core"
        case .fullBody: "their body"
        }
    }

    private func setSlot(_ slot: ReminderSlot) {
        practice.setSlot(.fitness, slot)
        Task {
            if slot != .off { _ = await ReminderScheduler.shared.requestAuthorization() }
            app.rescheduleReminders()
        }
    }
}

#Preview {
    let app = FitnessPreview.app()
    if let routines = app.fitness?.routines {
        for routine in routines.prefix(3) { app.practice.tried(.fitness, routine.id) }
    }
    return Color.clear.sheet(isPresented: .constant(true)) { FitnessProgressSheet(app: app) }
}

import SwiftUI

/// F0: first open of the Fitness tab. Three quick steps, skippable:
/// body areas → sessions a week → nudge time.
struct FitnessSetupView: View {
    let app: AppModel

    @State private var step = 0
    @State private var picked: Set<BodyArea> = []
    @State private var goal = 3
    @State private var slot: ReminderSlot = .morning
    @State private var finishing = false
    @Environment(\.dismiss) private var dismiss

    private let goals = [1, 3, 5, 7]

    var body: some View {
        VStack(alignment: .leading, spacing: 28) {
            HStack {
                HStack(spacing: 6) {
                    ForEach(0..<3) { i in
                        Capsule().fill(i <= step ? Theme.lime : Theme.surfaceRaised).frame(width: i == step ? 28 : 10, height: 6)
                    }
                }
                .animation(.snappy, value: step)
                Spacer()
                Button("Skip") {
                    app.practice.skipSetup(.fitness)
                    dismiss()
                }
                .font(Theme.body(16, weight: .semibold))
                .foregroundStyle(Theme.secondary)
                .buttonStyle(.plain)
            }

            Group {
                switch step {
                case 0: areasStep
                case 1: goalStep
                default: slotStep
                }
            }
            .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity),
                                    removal: .move(edge: .leading).combined(with: .opacity)))

            Spacer()

            HStack(spacing: 12) {
                if step > 0 {
                    Button("Back") { withAnimation(.snappy) { step -= 1 } }
                        .buttonStyle(.pillSecondary)
                        .frame(width: 110)
                }
                Button(step < 2 ? "Next" : "Let's go", action: next)
                    .buttonStyle(.pill)
                    .disabled(finishing)
            }
        }
        .padding(Theme.padding)
        .themedScreen()
    }

    // MARK: - Steps

    private var areasStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("What needs some love?").font(Theme.title(32))
            Text("Pick any. We'll lean on these for your daily pick.")
                .font(Theme.body(16)).foregroundStyle(Theme.secondary)
            WrapLayout(spacing: 8) {
                ForEach(app.fitness?.areas ?? [], id: \.area) { item in
                    Chip(label: item.area.title, systemImage: item.area.symbol, detail: "\(item.count)",
                         isSelected: picked.contains(item.area)) {
                        if picked.contains(item.area) { picked.remove(item.area) } else { picked.insert(item.area) }
                    }
                }
            }
        }
    }

    private var goalStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("How many sessions a week?").font(Theme.title(32))
            Text("A session is one routine. Two minutes counts.")
                .font(Theme.body(16)).foregroundStyle(Theme.secondary)
            HStack(spacing: 10) {
                ForEach(goals, id: \.self) { g in
                    Chip(label: "\(g)", isSelected: goal == g) { goal = g }
                }
            }
        }
    }

    private var slotStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("When should we nudge you?").font(Theme.title(32))
            Text("One gentle nudge a day, at most. You can change it.")
                .font(Theme.body(16)).foregroundStyle(Theme.secondary)
            WrapLayout(spacing: 8) {
                ForEach(ReminderSlot.allCases) { s in
                    Chip(label: s.title, isSelected: slot == s) { slot = s }
                }
            }
        }
    }

    // MARK: - Actions

    private func next() {
        guard step == 2 else {
            withAnimation(.snappy) { step += 1 }
            return
        }
        finishing = true
        Task {
            if slot != .off { _ = await ReminderScheduler.shared.requestAuthorization() }
            app.practice.finishSetup(.fitness, goal: goal, slot: slot,
                                     pickedTopicKeys: BodyArea.allCases.filter(picked.contains).map(\.rawValue))
            app.rescheduleReminders()
            dismiss()
        }
    }
}

#Preview {
    FitnessSetupView(app: FitnessPreview.app(setupDone: false))
}

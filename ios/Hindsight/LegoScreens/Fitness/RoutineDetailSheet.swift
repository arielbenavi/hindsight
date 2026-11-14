import SwiftUI

/// F4: routine detail. Hero (opens the reel), facts, exercises (caption only),
/// history, actions (Did it · Make it a regular · Remind me… · Not for me / Bring back),
/// the original caption and the safety note.
struct RoutineDetailSheet: View {
    let app: AppModel
    let routine: Routine

    @State private var askingWhen = false
    @State private var showSchedule = false
    @State private var justDid = false
    @State private var reminded: Date?
    @Environment(\.dismiss) private var dismiss

    private var practice: PracticeStore { app.practice }
    private var state: PracticeState { practice.state(.fitness, routine.id) }
    private var regular: RegularSchedule? { practice.screen(.fitness).regulars[routine.id] }
    private var isArchived: Bool { state.status == .archived }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    PostHero(post: routine.post, symbol: routine.primaryArea.symbol, height: 210)
                    facts
                    if routine.info.isPainRelated {
                        Label(Routine.safetyNote, systemImage: "heart.text.square")
                            .font(Theme.body(15, weight: .semibold)).foregroundStyle(Theme.secondary)
                    }
                    promptBlock
                    if !routine.info.exercises.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Exercises").font(Theme.title(20))
                            ExerciseList(exercises: routine.info.exercises)
                        }
                        .card()
                    }
                    history
                    actions
                    CaptionDisclosure(caption: routine.post.caption)
                }
                .padding(Theme.padding)
                .padding(.bottom, 30)
                .animation(.snappy, value: askingWhen)
                .animation(.snappy, value: justDid)
            }
            .themedScreen()
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
            .navigationBarTitleDisplayMode(.inline)
        }
        .sheet(isPresented: $showSchedule) { RegularScheduleSheet(app: app, routine: routine) }
        .sensoryFeedback(.success, trigger: justDid)
        .presentationDragIndicator(.visible)
        .preferredColorScheme(.dark)
    }

    // MARK: - Sections

    private var facts: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(routine.title).font(Theme.title(28)).fixedSize(horizontal: false, vertical: true)
            PostByline(post: routine.post)
            RoutineMeta(routine: routine)
            WrapLayout(spacing: 6) {
                Tag(text: routine.info.goal.title, color: Theme.violet)
                ForEach(equipment, id: \.self) { item in
                    Tag(text: item.title)
                }
            }
        }
    }

    /// "No equipment" when the post names none.
    private var equipment: [Equipment] {
        routine.info.equipment.isEmpty ? [.none] : routine.info.equipment
    }

    private var promptBlock: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !routine.isFollowAlong { Tag(text: "Suggested", color: Theme.lime) }
            Text(routine.prompt).font(Theme.title(20)).fixedSize(horizontal: false, vertical: true)
        }
    }

    private var history: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(historyLine, systemImage: "checkmark.circle")
            if let regular {
                Label("Regular · \(regular.summary)", systemImage: "pin.fill")
            }
            if let remindAt = reminded ?? state.remindAt, remindAt > .now {
                Label("Reminder \(remindAt.formatted(.dateTime.weekday(.wide).hour().minute()))", systemImage: "alarm")
            }
        }
        .font(Theme.body(15, weight: .semibold))
        .foregroundStyle(Theme.secondary)
    }

    /// "Done 4 times · last on Tuesday".
    private var historyLine: String {
        let dates = state.triedAt
        guard let last = dates.max() else { return "Not done yet. Two minutes counts." }
        let times = dates.count == 1 ? "Done once" : "Done \(dates.count) times"
        let cal = Calendar.current
        let when: String
        if cal.isDateInToday(last) {
            when = "last today"
        } else if cal.isDateInYesterday(last) {
            when = "last yesterday"
        } else if let days = cal.dateComponents([.day], from: last, to: .now).day, days < 7 {
            when = "last on \(last.formatted(.dateTime.weekday(.wide)))"
        } else {
            when = "last on \(last.formatted(.dateTime.month(.abbreviated).day()))"
        }
        return "\(times) · \(when)"
    }

    @ViewBuilder private var actions: some View {
        VStack(spacing: 10) {
            if !isArchived {
                Button(justDid ? "Nice. That counts." : "Did it") {
                    app.fitnessDidIt(routine.id)
                    justDid = true
                }
                .buttonStyle(.pill)
                .disabled(justDid)

                Button {
                    showSchedule = true
                } label: {
                    Label(regular == nil ? "Make it a regular" : "Edit regular", systemImage: "pin")
                }
                .buttonStyle(.pillSecondary)

                if askingWhen {
                    WhenChips { when in
                        app.fitnessRemind(routine.id, when)
                        reminded = when.date(from: .now, slot: practice.screen(.fitness).slot)
                        askingWhen = false
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .card(padding: 14)
                } else {
                    Button { askingWhen = true } label: { Label("Remind me…", systemImage: "alarm") }
                        .buttonStyle(.pillSecondary)
                }

                Button("Not for me") {
                    practice.archive(.fitness, routine.id)
                    app.rescheduleReminders()
                }
                .font(Theme.body(15, weight: .semibold))
                .foregroundStyle(Theme.secondary)
                .buttonStyle(.plain)
                .padding(.top, 4)
            } else {
                Text("Not for you, so it's out of rotation.")
                    .font(Theme.body(15)).foregroundStyle(Theme.secondary)
                Button("Bring back") {
                    practice.unarchive(.fitness, routine.id)
                    app.rescheduleReminders()
                }
                .buttonStyle(.pillSecondary)
            }
        }
    }
}

#Preview("Follow-along reel") {
    let app = FitnessPreview.app()
    Color.clear.sheet(isPresented: .constant(true)) {
        RoutineDetailSheet(app: app, routine: app.fitness!.routines.first { $0.info.isPainRelated } ?? app.fitness!.routines[0])
    }
}

#Preview("Multi-exercise") {
    let app = FitnessPreview.app()
    Color.clear.sheet(isPresented: .constant(true)) {
        RoutineDetailSheet(app: app, routine: FitnessPreview.multiExercise(app)!)
    }
}

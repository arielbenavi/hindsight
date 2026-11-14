import SwiftUI

/// F2: Today's 1 for Fitness. The shared practice card with Fitness content:
/// "Did it", area chips, "~3 min", the exercise list, the follow-along variant for
/// thin reels, and the safety note on pain-related routines.
struct RoutineCard: View {
    let routine: Routine
    let onDidIt: () -> Void
    let onNotToday: (ReminderPolicy.When) -> Void
    let onNotForMe: () -> Void
    var onTap: (() -> Void)?

    var body: some View {
        PracticeCardView(
            title: routine.title,
            post: routine.post,
            symbol: routine.primaryArea.symbol,
            prompt: routine.prompt,
            // The follow-along line is ours, not an AI suggestion.
            promptIsSuggested: !routine.isFollowAlong,
            primaryTitle: "Did it",
            note: routine.info.isPainRelated ? Routine.safetyNote : nil,
            openReelIsProminent: routine.isFollowAlong,
            details: {
                VStack(alignment: .leading, spacing: 12) {
                    RoutineMeta(routine: routine)
                    ExerciseList(exercises: routine.info.exercises, limit: 5)
                }
            },
            onPrimary: onDidIt,
            onNotToday: onNotToday,
            onNotForMe: onNotForMe,
            onTap: onTap
        )
    }
}

/// Area chips and "~3 min".
struct RoutineMeta: View {
    let routine: Routine

    var body: some View {
        WrapLayout(spacing: 6) {
            ForEach(routine.info.bodyAreas) { area in
                AreaChip(area: area)
            }
            if let minutes = routine.minutesLabel {
                Label(minutes, systemImage: "clock")
                    .font(Theme.body(13, weight: .bold))
                    .foregroundStyle(Theme.secondary)
                    .padding(.horizontal, 10).padding(.vertical, 6)
            }
        }
    }
}

/// Small non-interactive body-area pill (SF Symbol + name).
struct AreaChip: View {
    let area: BodyArea

    var body: some View {
        Label(area.title, systemImage: area.symbol)
            .font(Theme.body(13, weight: .bold))
            .foregroundStyle(Theme.text)
            .padding(.horizontal, 10).padding(.vertical, 6)
            .background(Theme.surfaceRaised, in: Capsule())
            .overlay(Capsule().strokeBorder(Theme.stroke))
    }
}

/// "90/90 hip switch · 10 each side". Only what the caption listed; never invented.
struct ExerciseList: View {
    let exercises: [Exercise]
    var limit: Int?

    var body: some View {
        let shown = limit.map { Array(exercises.prefix($0)) } ?? exercises
        if !shown.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(Array(shown.enumerated()), id: \.offset) { index, exercise in
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Text("\(index + 1)")
                            .font(Theme.label(12))
                            .foregroundStyle(Theme.lime)
                            .frame(width: 18, alignment: .trailing)
                        Text(exercise.name).font(Theme.body(15, weight: .semibold))
                        if let detail = exercise.detail {
                            Text(detail).font(Theme.body(14)).foregroundStyle(Theme.secondary)
                        }
                        Spacer(minLength: 0)
                    }
                }
                if let limit, exercises.count > limit {
                    Text("+ \(exercises.count - limit) more in the post")
                        .font(Theme.body(13)).foregroundStyle(Theme.muted)
                        .padding(.leading, 28)
                }
            }
        }
    }
}

/// Compact routine row (search results, area pages, lists): thumbnail, title,
/// areas and minutes, how often it's been done.
struct RoutineRow: View {
    let routine: Routine
    var doneCount = 0
    var regular: RegularSchedule?

    var body: some View {
        HStack(spacing: 14) {
            PostThumbnail(post: routine.post, symbol: routine.primaryArea.symbol, size: 56)
            VStack(alignment: .leading, spacing: 4) {
                Text(routine.title).font(Theme.body(16, weight: .bold)).lineLimit(2).multilineTextAlignment(.leading)
                Text(subtitle).font(Theme.body(13)).foregroundStyle(Theme.secondary).lineLimit(1)
            }
            Spacer(minLength: 0)
            if regular != nil {
                Image(systemName: "pin.fill").font(.system(size: 13, weight: .bold)).foregroundStyle(Theme.lime)
                    .accessibilityLabel("Regular")
            }
            Image(systemName: "chevron.right").font(.system(size: 13, weight: .bold)).foregroundStyle(Theme.muted)
        }
        .card(padding: 12)
        .contentShape(.rect)
    }

    private var subtitle: String {
        var parts = [routine.info.bodyAreas.map(\.title).joined(separator: ", ")]
        if let minutes = routine.minutesLabel { parts.append(minutes) }
        if doneCount > 0 { parts.append(doneCount == 1 ? "Done once" : "Done \(doneCount)×") }
        return parts.joined(separator: " · ")
    }
}

#Preview("Routine card") {
    let app = FitnessPreview.app()
    let routines = app.fitness?.routines ?? []
    ScrollView {
        VStack(spacing: 16) {
            if let multi = FitnessPreview.multiExercise(app) {
                RoutineCard(routine: multi, onDidIt: {}, onNotToday: { _ in }, onNotForMe: {})
            }
            ForEach(routines.prefix(3)) { routine in
                RoutineCard(routine: routine, onDidIt: {}, onNotToday: { _ in }, onNotForMe: {})
            }
            ForEach(routines.prefix(3)) { routine in
                RoutineRow(routine: routine, doneCount: 2)
            }
        }
        .padding(Theme.padding)
    }
    .themedScreen()
}

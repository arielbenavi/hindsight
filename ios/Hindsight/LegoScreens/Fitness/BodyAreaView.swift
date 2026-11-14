import SwiftUI

/// F3: one body area. "Done N times this month", goal filters (only goals present),
/// routines most-done first, then newest saved.
struct BodyAreaView: View {
    let app: AppModel
    let area: BodyArea

    @State private var goal: FitnessGoal?
    @State private var detail: Routine?

    var body: some View {
        let routines = app.fitness?.routines(in: area) ?? []
        let goals = FitnessGoal.allCases.filter { g in routines.contains { $0.info.goal == g } }
        let shown = sorted(routines.filter { goal == nil || $0.info.goal == goal })

        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack(spacing: 14) {
                    Image(systemName: area.symbol)
                        .font(.system(size: 28, weight: .semibold))
                        .foregroundStyle(Theme.lime)
                        .frame(width: 56, height: 56)
                        .background(Theme.surface, in: .rect(cornerRadius: Theme.smallRadius))
                    ScreenHeader(title: area.title, subtitle: doneLine(routines)) { EmptyView() }
                }

                if goals.count > 1 {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            Chip(label: "All", isSelected: goal == nil) { goal = nil }
                            ForEach(goals) { g in
                                Chip(label: g.title, isSelected: goal == g) { goal = g }
                            }
                        }
                    }
                    .scrollClipDisabled()
                }

                ForEach(shown) { routine in
                    Button { detail = routine } label: {
                        RoutineRow(routine: routine, doneCount: doneCount(routine),
                                   regular: app.practice.screen(.fitness).regulars[routine.id])
                    }
                    .buttonStyle(.plain)
                    .opacity(app.practice.state(.fitness, routine.id).status == .archived ? 0.5 : 1)
                }
            }
            .padding(Theme.padding)
            .padding(.bottom, 40)
            .animation(.snappy, value: goal)
        }
        .themedScreen()
        .toolbar(.visible, for: .navigationBar)
        .toolbarBackground(.hidden, for: .navigationBar)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $detail) { routine in RoutineDetailSheet(app: app, routine: routine) }
    }

    private func doneCount(_ routine: Routine) -> Int {
        app.practice.state(.fitness, routine.id).triedAt.count
    }

    /// Most done first, then newest saved.
    private func sorted(_ routines: [Routine]) -> [Routine] {
        routines.sorted { a, b in
            let (da, db) = (doneCount(a), doneCount(b))
            if da != db { return da > db }
            return (a.post.savedDate ?? .distantPast) > (b.post.savedDate ?? .distantPast)
        }
    }

    private func doneLine(_ routines: [Routine]) -> String {
        guard let month = Calendar.current.dateInterval(of: .month, for: .now) else { return "" }
        let n = routines.reduce(0) { sum, r in
            sum + app.practice.state(.fitness, r.id).triedAt.count { month.contains($0) }
        }
        switch n {
        case 0: return "\(routines.count == 1 ? "1 routine" : "\(routines.count) routines") saved"
        case 1: return "Done once this month"
        default: return "Done \(n) times this month"
        }
    }
}

#Preview {
    let app = FitnessPreview.app()
    NavigationStack {
        BodyAreaView(app: app, area: app.fitness?.areas.first?.area ?? .lowerBack)
    }
}

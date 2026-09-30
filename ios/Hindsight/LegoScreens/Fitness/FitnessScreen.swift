import SwiftUI

/// Fitness tab root (F1): weekly ring, fresh-start card, Today's 1, Regulars,
/// problem search and the body-area grid. First open shows setup (F0).
struct FitnessScreen: View {
    let app: AppModel
    let tab: TabConfig

    @State private var query = ""
    @State private var fresh: WeeklyProgress.FreshStart?
    @State private var opened = false
    @State private var showSetup = false
    @State private var showProgress = false
    @State private var showEverythingElse = false
    @State private var detail: Routine?
    @State private var notificationsAllowed = true
    @State private var noMore = false
    @State private var undo: (id: String, old: PracticeState)?
    @State private var undoTask: Task<Void, Never>?

    private var practice: PracticeStore { app.practice }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    ScreenHeader(title: tab.title) {
                        HStack(spacing: 6) {
                            DevMenu(app: app)
                            EverythingElseButton(app: app)
                        }
                    }
                    if let catalog = app.fitness, !catalog.routines.isEmpty {
                        content(catalog)
                    } else {
                        ContentUnavailableView("No stretches yet", systemImage: "figure.flexibility",
                                               description: Text("Save a stretch you like and it'll show up here."))
                    }
                }
                .padding(Theme.padding)
                .padding(.bottom, 40)
            }
            .scrollDismissesKeyboard(.interactively)
            .themedScreen()
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: BodyArea.self) { area in
                BodyAreaView(app: app, area: area)
            }
        }
        .overlay(alignment: .bottom) {
            if let undo {
                UndoToast(message: "Not for me. Moved out of rotation.") {
                    practice.restore(.fitness, undo.id, to: undo.old)
                    withAnimation(.snappy) { self.undo = nil }
                    app.rescheduleReminders()
                }
                .padding(.bottom, 12)
            }
        }
        .onAppear(perform: appear)
        .task { notificationsAllowed = await ReminderScheduler.shared.isAuthorized() }
        .onChange(of: practice.deepLink?.id) { handleDeepLink() }
        .fullScreenCover(isPresented: $showSetup, onDismiss: prepare) {
            FitnessSetupView(app: app)
        }
        .sheet(isPresented: $showProgress) { FitnessProgressSheet(app: app) }
        .sheet(item: $detail) { routine in RoutineDetailSheet(app: app, routine: routine) }
        .sheet(isPresented: $showEverythingElse) { EverythingElseSheet(app: app, initialQuery: query) }
        .sensoryFeedback(.success, trigger: practice.progress(.fitness).done)
    }

    // MARK: - Sections

    @ViewBuilder private func content(_ catalog: FitnessCatalog) -> some View {
        Button { showProgress = true } label: {
            WeeklyRing(progress: practice.progress(.fitness), unit: "sessions").card()
        }
        .buttonStyle(.plain)
        .accessibilityHint("Shows your progress")

        if let fresh {
            HStack(spacing: 12) {
                Image(systemName: "sunrise.fill").font(.system(size: 22)).foregroundStyle(Theme.lime)
                Text(fresh.line).font(Theme.body(16, weight: .bold))
            }
            .card(padding: 16, background: Theme.surfaceRaised)
        }

        if practice.screen(.fitness).slot == .off {
            getANudge
        }

        today(catalog)
        regulars(catalog)
        search(catalog)
        if query.trimmingCharacters(in: .whitespaces).isEmpty {
            areas(catalog)
        }
    }

    @ViewBuilder private func today(_ catalog: FitnessCatalog) -> some View {
        let cards = practice.todayCards(.fitness).compactMap { catalog.byID[$0] }
        VStack(alignment: .leading, spacing: 12) {
            SectionTitle(text: "Today's 1")
            if cards.isEmpty {
                Text(allArchived(catalog)
                     ? "Nothing left to do here. Save a stretch you like and it'll show up."
                     : "Nothing picked yet. Check back in a moment.")
                    .font(Theme.body(16)).foregroundStyle(Theme.secondary)
                    .card()
            }
            ForEach(cards) { routine in
                if let handling = practice.handling(.fitness, routine.id) {
                    Button { detail = routine } label: { HandledRow(title: routine.title, handling: handling) }
                        .buttonStyle(.plain)
                } else {
                    RoutineCard(
                        routine: routine,
                        onDidIt: { withAnimation(.snappy) { app.fitnessDidIt(routine.id) } },
                        onNotToday: { when in withAnimation(.snappy) { app.fitnessRemind(routine.id, when) } },
                        onNotForMe: { archive(routine.id) },
                        onTap: { detail = routine }
                    )
                    .transition(.asymmetric(insertion: .opacity, removal: .scale(scale: 0.95).combined(with: .opacity)))
                }
            }
            if practice.isDoneForToday(.fitness) {
                DoneForToday(
                    quip: PracticeQuip.pick(PracticeQuip.fitnessDone, seed: TodayPicker.dayKey(.now)),
                    canDoMore: !noMore
                ) {
                    withAnimation(.snappy) {
                        if practice.oneMore(.fitness, candidates: catalog.candidates, config: .fitness) == nil {
                            noMore = true
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder private func regulars(_ catalog: FitnessCatalog) -> some View {
        let regulars = practice.screen(.fitness).regulars.values
            .compactMap { r in catalog.byID[r.routineID].map { (routine: $0, schedule: r) } }
            .sorted { $0.routine.title < $1.routine.title }
        VStack(alignment: .leading, spacing: 12) {
            SectionTitle(text: "Regulars")
            if regulars.isEmpty {
                Text("Pin a routine you want to do regularly.")
                    .font(Theme.body(15)).foregroundStyle(Theme.secondary)
                    .card(padding: 16)
            } else {
                VStack(spacing: 0) {
                    ForEach(regulars, id: \.routine.id) { item in
                        Button { detail = item.routine } label: {
                            regularRow(item.routine, item.schedule)
                        }
                        .buttonStyle(.plain)
                        if item.routine.id != regulars.last?.routine.id { Divider().overlay(Theme.stroke) }
                    }
                }
                .card(padding: 0)
            }
        }
    }

    private func regularRow(_ routine: Routine, _ schedule: RegularSchedule) -> some View {
        // Notifications denied: Regulars still show on their days, without a push.
        let dueToday = !notificationsAllowed && schedule.fires(on: .now)
        return HStack(spacing: 12) {
            Image(systemName: dueToday ? "sun.max.fill" : "pin.fill")
                .foregroundStyle(Theme.lime)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text(dueToday ? "Today: \(routine.title)" : routine.title)
                    .font(Theme.body(16, weight: .bold)).lineLimit(1)
                Text(schedule.summary).font(Theme.body(14)).foregroundStyle(Theme.secondary)
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right").font(.system(size: 13, weight: .bold)).foregroundStyle(Theme.muted)
        }
        .padding(.horizontal, 16).padding(.vertical, 14)
        .contentShape(.rect)
    }

    @ViewBuilder private func search(_ catalog: FitnessCatalog) -> some View {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass").foregroundStyle(Theme.muted)
                TextField("", text: $query, prompt: Text("What hurts? \"back hurts\", \"tight hips\"…").foregroundStyle(Theme.muted))
                    .font(Theme.body(16))
                    .submitLabel(.search)
                    .autocorrectionDisabled()
                if !query.isEmpty {
                    Button { query = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(Theme.muted) }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Clear search")
                }
            }
            .padding(.horizontal, 16).padding(.vertical, 14)
            .background(Theme.surface, in: Capsule())
            .overlay(Capsule().strokeBorder(Theme.stroke))

            if !trimmed.isEmpty {
                let results = ProblemSearch.search(trimmed, in: catalog.routines)
                if results.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Nothing saved for that yet.").font(Theme.body(16, weight: .semibold))
                        Button("Search Everything else") { showEverythingElse = true }
                            .buttonStyle(.pillCompact)
                    }
                    .card()
                } else {
                    ForEach(results) { routine in
                        Button { detail = routine } label: {
                            RoutineRow(routine: routine, doneCount: practice.state(.fitness, routine.id).triedAt.count,
                                       regular: practice.screen(.fitness).regulars[routine.id])
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    @ViewBuilder private func areas(_ catalog: FitnessCatalog) -> some View {
        let areas = catalog.areas
        VStack(alignment: .leading, spacing: 12) {
            if areas.count == 1, let only = areas.first {
                // Only one area: a plain list instead of a one-tile grid.
                SectionTitle(text: only.area.title)
                ForEach(catalog.routines) { routine in
                    Button { detail = routine } label: {
                        RoutineRow(routine: routine, doneCount: practice.state(.fitness, routine.id).triedAt.count,
                                   regular: practice.screen(.fitness).regulars[routine.id])
                    }
                    .buttonStyle(.plain)
                }
            } else {
                SectionTitle(text: "Body areas")
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                    ForEach(areas, id: \.area) { item in
                        NavigationLink(value: item.area) {
                            BodyAreaTile(area: item.area, count: item.count)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private var getANudge: some View {
        HStack(spacing: 12) {
            Image(systemName: "bell.badge").font(.system(size: 20)).foregroundStyle(Theme.lime)
            VStack(alignment: .leading, spacing: 2) {
                Text("Get a nudge?").font(Theme.body(16, weight: .bold))
                Text("One gentle reminder in the morning.").font(Theme.body(14)).foregroundStyle(Theme.secondary)
            }
            Spacer(minLength: 0)
            Button("Sure") {
                practice.setSlot(.fitness, .morning)
                Task {
                    notificationsAllowed = await ReminderScheduler.shared.requestAuthorization()
                    app.rescheduleReminders()
                }
            }
            .buttonStyle(.pillCompactPrimary)
        }
        .card(padding: 16)
    }

    // MARK: - Actions

    private func appear() {
        if !practice.screen(.fitness).setupDone, app.fitness?.routines.isEmpty == false {
            showSetup = true
        }
        if !opened {
            opened = true
            fresh = practice.markOpened(.fitness)
        }
        prepare()
        handleDeepLink()
    }

    private func prepare() {
        guard let catalog = app.fitness else { return }
        practice.prepareToday(.fitness, candidates: catalog.candidates, config: .fitness)
        app.rescheduleReminders()
    }

    private func handleDeepLink() {
        guard let link = practice.deepLink, link.screen == .fitness else { return }
        practice.deepLink = nil
        if let routine = app.fitness?.byID[link.id] { detail = routine }
    }

    private func archive(_ id: String) {
        let old = withAnimation(.snappy) { practice.archive(.fitness, id) }
        app.rescheduleReminders()
        withAnimation(.snappy) { undo = (id, old) }
        undoTask?.cancel()
        undoTask = Task {
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled else { return }
            withAnimation(.snappy) { undo = nil }
        }
    }

    private func allArchived(_ catalog: FitnessCatalog) -> Bool {
        catalog.routines.allSatisfy { practice.state(.fitness, $0.id).status == .archived }
    }
}

/// Big tile in the body-area grid: SF Symbol, name, count.
struct BodyAreaTile: View {
    let area: BodyArea
    let count: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: area.symbol)
                .font(.system(size: 26, weight: .semibold))
                .foregroundStyle(Theme.lime)
            Spacer(minLength: 0)
            Text(area.title).font(Theme.title(18)).lineLimit(1).minimumScaleFactor(0.8)
            Text(count == 1 ? "1 routine" : "\(count) routines").font(Theme.body(14)).foregroundStyle(Theme.secondary)
        }
        .frame(height: 112, alignment: .topLeading)
        .card(padding: 16)
        .accessibilityElement(children: .combine)
    }
}

/// Section title used across Fitness screens.
struct SectionTitle: View {
    let text: String

    var body: some View {
        Text(text).font(Theme.title(22))
    }
}

// MARK: - Shared Fitness actions

@MainActor
extension AppModel {
    /// "Did it": fills the Fitness ring; the routine stays in rotation.
    func fitnessDidIt(_ id: String) {
        practice.tried(.fitness, id)
        rescheduleReminders()
    }

    /// "Not today" → When?: a reminder about this routine.
    func fitnessRemind(_ id: String, _ when: ReminderPolicy.When) {
        practice.remind(.fitness, id, at: when.date(from: .now, slot: practice.screen(.fitness).slot))
        Task {
            _ = await ReminderScheduler.shared.requestAuthorization()
            rescheduleReminders()
        }
    }
}

// MARK: - Previews

/// Ariel's real saves with an approved layout (his ~13 routines, all thin).
@MainActor
enum FitnessPreview {
    static func app(setupDone: Bool = true) -> AppModel {
        let app = AppModel(datasets: Dataset.bundled(), selected: "ariel", persist: false)
        if let data = app.data { app.approve(LayoutRules.propose(data).draft.config()) }
        if setupDone { app.practice.skipSetup(.fitness) }
        return app
    }

    static func tab(_ app: AppModel) -> TabConfig {
        app.layout?.tab(for: .fitness) ?? TabConfig(legoScreen: .fitness, topicIDs: [])
    }

    /// Ariel's saves are all follow-along reels; this one shows the multi-exercise card.
    static func multiExercise(_ app: AppModel) -> Routine? {
        guard var routine = app.fitness?.routines.first else { return nil }
        routine.info = ExtractedRoutine(
            title: "Shoulder mobility: 5 exercises", bodyAreas: [.shoulders, .upperBack], goal: .mobility,
            exercises: [Exercise(name: "Wall slides", reps: 10), Exercise(name: "Thoracic rotation", holdSeconds: 30, eachSide: true),
                        Exercise(name: "Band pull-apart", reps: 15, sets: 2), Exercise(name: "Thread the needle", reps: 8, eachSide: true),
                        Exercise(name: "Child's pose reach", holdSeconds: 45), Exercise(name: "Cat-cow", reps: 10)],
            estMinutes: 4, equipment: [.mat, .band], doPrompt: "Do the first 2 moves, 30 seconds each side.",
            isThin: false, isPainRelated: true)
        return routine
    }
}

#Preview("Fitness home") {
    let app = FitnessPreview.app()
    FitnessScreen(app: app, tab: FitnessPreview.tab(app))
}

#Preview("First open (setup)") {
    let app = FitnessPreview.app(setupDone: false)
    FitnessScreen(app: app, tab: FitnessPreview.tab(app))
}

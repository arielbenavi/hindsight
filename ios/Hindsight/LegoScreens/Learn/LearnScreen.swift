import SwiftUI

/// Learn tab root (L1): the practice loop on top (weekly ring + Today's 1), the
/// library below (search + topic sections).
struct LearnScreen: View {
    let app: AppModel
    let tab: TabConfig

    @State private var path: [String] = []
    @State private var detail: Tip?
    @State private var showingProgress = false
    @State private var showingSetup = false
    @State private var everythingElseQuery: String?
    @State private var query = ""
    @State private var freshStart: WeeklyProgress.FreshStart?
    @State private var didOpen = false
    @State private var notificationsAllowed = true
    @State private var triedTick = 0
    @State private var triedQuip: String?
    @State private var undo: PendingUndo?
    /// "Not for me" on today's pick replaces it once a day.
    @AppStorage("learn.replacedMissDay") private var replacedMissDay = ""

    private struct PendingUndo: Equatable {
        var id: String
        var old: PracticeState
        var token = UUID()
    }

    private var practice: PracticeStore { app.practice }
    private var screen: ScreenPractice { practice.screen(.learn) }

    var body: some View {
        NavigationStack(path: $path) {
            Group {
                if let catalog = app.learn, !catalog.sections.isEmpty {
                    content(catalog)
                } else {
                    VStack(alignment: .leading) {
                        header
                        ContentUnavailableView("Nothing in Learn yet", systemImage: "books.vertical",
                                               description: Text("Tips you save will show up here."))
                    }
                    .padding(Theme.padding)
                }
            }
            .themedScreen()
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: String.self) { id in
                if let section = app.learn?.section(id) { LearnTopicView(app: app, section: section) }
            }
        }
        .overlay(alignment: .bottom) {
            if let undo, let tip = app.learn?.tipsByID[undo.id] {
                UndoToast(message: "\"\(tip.title)\" set aside.") { undoArchive() }
                    .padding(.bottom, 12)
            }
        }
        .animation(.snappy, value: undo)
        .sensoryFeedback(.success, trigger: triedTick)
        .sheet(item: $detail) { TipDetailSheet(app: app, tip: $0) }
        .sheet(isPresented: $showingProgress) { LearnProgressSheet(app: app) }
        .sheet(isPresented: Binding(get: { everythingElseQuery != nil }, set: { if !$0 { everythingElseQuery = nil } })) {
            EverythingElseSheet(app: app, initialQuery: everythingElseQuery ?? "")
        }
        .fullScreenCover(isPresented: $showingSetup, onDismiss: prepare) {
            LearnSetupView(app: app) { showingSetup = false }
        }
        .onAppear(perform: appear)
        .task { notificationsAllowed = await ReminderScheduler.shared.isAuthorized() }
        .onChange(of: deepLinkKey) { handleDeepLink() }
    }

    // MARK: - Lifecycle

    private func appear() {
        prepare()
        if !didOpen {
            didOpen = true
            freshStart = practice.markOpened(.learn)
            app.rescheduleReminders()
        }
        if !screen.setupDone { showingSetup = true }
        handleDeepLink()
    }

    private func prepare() {
        guard let catalog = app.learn else { return }
        practice.prepareToday(.learn, candidates: catalog.candidates, config: .learn)
    }

    private var deepLinkKey: String? {
        practice.deepLink.map { "\($0.screen.rawValue)|\($0.id)" }
    }

    private func handleDeepLink() {
        guard let link = practice.deepLink, link.screen == .learn else { return }
        practice.deepLink = nil
        guard let tip = app.learn?.tipsByID[link.id] else { return }
        path = []
        detail = tip
    }

    // MARK: - Layout

    private var header: some View {
        ScreenHeader(title: tab.title) {
            HStack(spacing: 6) {
                DevMenu(app: app)
                EverythingElseButton(app: app)
            }
        }
    }

    private func content(_ catalog: LearnCatalog) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                header
                Button { showingProgress = true } label: {
                    WeeklyRing(progress: practice.progress(.learn)).card(padding: 18)
                }
                .buttonStyle(.plain)
                .accessibilityHint("Shows your progress")

                if let freshStart {
                    Label(freshStart.line, systemImage: freshStart == .newWeek ? "sunrise.fill" : "leaf.fill")
                        .font(Theme.body(16, weight: .bold))
                        .foregroundStyle(Theme.onLime)
                        .padding(.horizontal, 16).padding(.vertical, 12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Theme.lime, in: .rect(cornerRadius: Theme.smallRadius))
                }

                today(catalog)

                if screen.slot == .off { nudgeRow }

                searchField
                if query.trimmingCharacters(in: .whitespaces).isEmpty {
                    ForEach(catalog.sections) { sectionRow($0) }
                } else {
                    searchResults(catalog)
                }
            }
            .padding(Theme.padding)
            .padding(.bottom, 60)
        }
        .scrollIndicators(.hidden)
        .scrollDismissesKeyboard(.immediately)
    }

    // MARK: - Today's 1

    @ViewBuilder private func today(_ catalog: LearnCatalog) -> some View {
        let cards = practice.todayCards(.learn).filter { catalog.tipsByID[$0] != nil }
        VStack(alignment: .leading, spacing: 12) {
            Text("Today's 1").font(Theme.title(22))

            if !notificationsAllowed { inAppReminders(catalog) }

            if cards.isEmpty {
                emptyToday(catalog)
            }
            ForEach(cards, id: \.self) { id in
                if let tip = catalog.tipsByID[id] {
                    if let handling = practice.handling(.learn, id) {
                        handledRow(tip, handling, isLast: id == cards.last, catalog: catalog)
                            .transition(.scale(scale: 0.9).combined(with: .opacity))
                    } else {
                        card(tip, catalog: catalog)
                            .transition(.opacity)
                    }
                }
            }
            if practice.isDoneForToday(.learn) {
                DoneForToday(quip: PracticeQuip.pick(PracticeQuip.doneForToday, seed: screen.pickDay ?? ""),
                             canDoMore: canPickAnother(catalog) && !lastIsReminder(cards)) { oneMore(catalog) }
                    .transition(.opacity)
            }
        }
        .animation(.spring(duration: 0.5, bounce: 0.3), value: cards)
        .animation(.spring(duration: 0.5, bounce: 0.3), value: practice.isDoneForToday(.learn))
    }

    private func card(_ tip: Tip, catalog: LearnCatalog) -> some View {
        let section = catalog.section(tip.topicID)
        let isReview = practice.isReview(.learn, tip.id)
        let state = practice.state(.learn, tip.id)
        return PracticeCardView(
            title: tip.title,
            post: tip.post,
            emoji: section?.emoji,
            subtitle: section.map { "\($0.emoji) \($0.title)" },
            prompt: isReview ? reviewPrompt(state) : tip.prompt,
            primaryTitle: isReview ? "Try again" : "Tried it",
            isReview: isReview,
            openReelIsProminent: tip.ctaKeyword != nil && !isReview,
            details: { EmptyView() },
            onPrimary: { isReview ? reviewTryAgain(tip) : markTried(tip) },
            onNotToday: { when in remind(tip, when) },
            onNotForMe: { notForMe(tip, catalog: catalog) },
            onReviewYep: { reviewYep(tip) },
            onTap: { detail = tip }
        )
    }

    private func reviewPrompt(_ state: PracticeState) -> String {
        guard let last = state.triedAt.max() else { return "Still got it?" }
        let days = Calendar.current.dateComponents([.day], from: Calendar.current.startOfDay(for: last),
                                                   to: Calendar.current.startOfDay(for: .now)).day ?? 0
        let ago = days <= 0 ? "today" : days == 1 ? "yesterday" : "\(days) days ago"
        return "You tried this \(ago). Still got it?"
    }

    @ViewBuilder private func handledRow(_ tip: Tip, _ handling: Handling, isLast: Bool, catalog: LearnCatalog) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Button { detail = tip } label: { HandledRow(title: tip.title, handling: handling) }
                .buttonStyle(.plain)
            if isLast, case .tried = handling, let triedQuip {
                Label(triedQuip, systemImage: "sparkles")
                    .font(Theme.body(15, weight: .semibold))
                    .foregroundStyle(Theme.lime)
                    .padding(.horizontal, 6)
            }
            if isLast, case .reminded = handling, canPickAnother(catalog) {
                Button("Pick another") { oneMore(catalog) }
                    .font(Theme.body(15, weight: .bold))
                    .foregroundStyle(Theme.lime)
                    .buttonStyle(.plain)
                    .padding(.horizontal, 6)
            }
        }
    }

    @ViewBuilder private func emptyToday(_ catalog: LearnCatalog) -> some View {
        let hasPickable = catalog.tips.contains(where: \.isPickable)
        VStack(alignment: .leading, spacing: 6) {
            if hasPickable {
                Text("You've tried everything you saved.").font(Theme.title(20))
                Text("Go save more. We'll bring back the ones you tried for a quick check-in.")
                    .font(Theme.body(15)).foregroundStyle(Theme.secondary)
            } else {
                Text("Nothing to practice yet.").font(Theme.title(20))
                Text("Your Learn saves don't say enough in their captions for a try prompt. They're all in the library below.")
                    .font(Theme.body(15)).foregroundStyle(Theme.secondary)
            }
        }
        .card(padding: 18)
    }

    /// Notifications denied: "When?" reminders show here instead.
    @ViewBuilder private func inAppReminders(_ catalog: LearnCatalog) -> some View {
        let now = Date.now
        let reminders = screen.states
            .compactMap { id, s -> (Tip, Date)? in
                guard s.status != .archived, let date = s.remindAt, let tip = catalog.tipsByID[id] else { return nil }
                return (tip, date)
            }
            .sorted { $0.1 < $1.1 }
        if !reminders.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(reminders, id: \.0.id) { tip, date in
                    Button { detail = tip } label: {
                        HStack(spacing: 10) {
                            Image(systemName: "alarm.fill").foregroundStyle(Theme.violet)
                            Text(tip.title).font(Theme.body(15, weight: .semibold)).lineLimit(1)
                            Spacer()
                            Text(date <= now ? "Now" : LearnStatus.reminderDay(date, now: now).capitalized)
                                .font(Theme.body(14)).foregroundStyle(Theme.secondary)
                        }
                        .card(padding: 12, background: Theme.surfaceRaised)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var nudgeRow: some View {
        Button(action: turnOnNudge) {
            HStack(spacing: 12) {
                Image(systemName: "bell.badge").font(.system(size: 18, weight: .semibold)).foregroundStyle(Theme.lime)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Get a nudge?").font(Theme.body(16, weight: .bold))
                    Text("One a day in the evening, about one save.").font(Theme.body(13)).foregroundStyle(Theme.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right").foregroundStyle(Theme.muted)
            }
            .card(padding: 14)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Library

    private var searchField: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass").foregroundStyle(Theme.muted)
            TextField("Search your tips", text: $query)
                .font(Theme.body(16))
                .autocorrectionDisabled()
                .submitLabel(.search)
            if !query.isEmpty {
                Button { query = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(Theme.muted) }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 13)
        .background(Theme.surface, in: Capsule())
        .overlay(Capsule().strokeBorder(Theme.stroke))
    }

    private func sectionRow(_ section: LearnSection) -> some View {
        let tried = section.tips.count { LearnStatus.isTried(practice.state(.learn, $0.id)) }
        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("\(section.emoji) \(section.title)").font(Theme.title(20)).lineLimit(1)
                Text("· \(tried) tried of \(section.tips.count)").font(Theme.body(14)).foregroundStyle(Theme.secondary)
                    .lineLimit(1)
                Spacer(minLength: 8)
                NavigationLink(value: section.id) {
                    HStack(spacing: 3) {
                        Text("See all")
                        Image(systemName: "arrow.right")
                    }
                    .font(Theme.body(14, weight: .bold))
                    .foregroundStyle(Theme.lime)
                }
            }
            ScrollView(.horizontal) {
                LazyHStack(spacing: 12) {
                    ForEach(section.tips.prefix(12)) { tip in
                        Button { detail = tip } label: {
                            TipCard(tip: tip, emoji: section.emoji, state: practice.state(.learn, tip.id))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, Theme.padding)
            }
            .scrollIndicators(.hidden)
            .padding(.horizontal, -Theme.padding)
        }
    }

    @ViewBuilder private func searchResults(_ catalog: LearnCatalog) -> some View {
        let results = TipSearch.search(query, in: catalog.tips) { catalog.section($0)?.title ?? $0 }
        if results.isEmpty {
            VStack(alignment: .leading, spacing: 14) {
                Text("Nothing in Learn for \"\(query)\".").font(Theme.body(17, weight: .semibold))
                Button { everythingElseQuery = query } label: {
                    Label("Search Everything else", systemImage: "tray.full")
                }
                .buttonStyle(.pillCompact)
            }
            .padding(.vertical, 8)
        } else {
            LazyVStack(spacing: 10) {
                ForEach(results) { tip in
                    let section = catalog.section(tip.topicID)
                    Button { detail = tip } label: {
                        TipCard(tip: tip, emoji: section?.emoji ?? "📚", state: practice.state(.learn, tip.id), style: .row,
                                topicLabel: section?.title)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: - Actions

    private func markTried(_ tip: Tip) {
        withAnimation(.spring(duration: 0.6, bounce: 0.4)) {
            practice.tried(.learn, tip.id)
            triedQuip = PracticeQuip.pick(PracticeQuip.tried, seed: "\(tip.id)|\(screen.pickDay ?? "")")
        }
        triedTick += 1
        app.rescheduleReminders()
    }

    private func reviewYep(_ tip: Tip) {
        withAnimation(.spring(duration: 0.6, bounce: 0.4)) {
            practice.reviewYep(.learn, tip.id)
            triedQuip = nil
        }
        triedTick += 1
        app.rescheduleReminders()
    }

    private func reviewTryAgain(_ tip: Tip) {
        withAnimation(.spring(duration: 0.6, bounce: 0.4)) {
            practice.reviewTryAgain(.learn, tip.id)
            triedQuip = "Fresh reps. That counts."
        }
        triedTick += 1
        app.rescheduleReminders()
    }

    private func remind(_ tip: Tip, _ when: ReminderPolicy.When) {
        withAnimation(.snappy) {
            practice.remind(.learn, tip.id, at: when.date(from: .now, slot: screen.slot))
        }
        app.rescheduleReminders()
    }

    private func notForMe(_ tip: Tip, catalog: LearnCatalog) {
        let old = withAnimation(.snappy) { practice.archive(.learn, tip.id) }
        let pending = PendingUndo(id: tip.id, old: old)
        undo = pending
        app.rescheduleReminders()
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(3))
            guard undo?.token == pending.token else { return }
            undo = nil
            // Today's pick was a miss: replace it, once a day.
            let day = screen.pickDay ?? ""
            if replacedMissDay != day, practice.isDoneForToday(.learn), canPickAnother(catalog) {
                replacedMissDay = day
                oneMore(catalog)
            }
        }
    }

    private func undoArchive() {
        guard let pending = undo else { return }
        withAnimation(.snappy) { practice.restore(.learn, pending.id, to: pending.old) }
        undo = nil
        app.rescheduleReminders()
    }

    private func oneMore(_ catalog: LearnCatalog) {
        withAnimation(.snappy) {
            triedQuip = nil
            _ = practice.oneMore(.learn, candidates: catalog.candidates, config: .learn)
        }
    }

    private func turnOnNudge() {
        practice.setSlot(.learn, .evening)
        Task {
            notificationsAllowed = await ReminderScheduler.shared.requestAuthorization()
            app.rescheduleReminders()
        }
    }

    // MARK: - Helpers

    private func lastIsReminder(_ cards: [String]) -> Bool {
        guard let last = cards.last, case .reminded = practice.handling(.learn, last) else { return false }
        return true
    }

    /// Would "One more?" / "Pick another" find anything?
    private func canPickAnother(_ catalog: LearnCatalog) -> Bool {
        let s = screen
        if s.shownCount < s.pickQueue.count { return true }
        let input = TodayPicker.Input(candidates: catalog.candidates, states: s.states, config: .learn,
                                      boostedTopicKeys: Set(s.pickedTopicKeys), now: .now)
        return !TodayPicker.weightedPool(input, excluding: Set(s.pickQueue)).isEmpty
    }
}

#if DEBUG
#Preview("Learn") {
    let app = LearnPreview.app()
    LearnScreen(app: app, tab: LearnPreview.tab(app))
}

#Preview("Learn · first open") {
    let app = LearnPreview.app(setupDone: false)
    LearnScreen(app: app, tab: LearnPreview.tab(app))
}
#endif

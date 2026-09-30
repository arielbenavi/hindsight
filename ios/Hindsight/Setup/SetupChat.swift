import SwiftUI

/// The setup chat (docs/specs/onboarding-chat.md): one transcript from "got your
/// saves" to "You're in". R1 receipt → R2 a taste → R3 reading & grouping (live)
/// → B1–B5 the layout proposal (layout-proposal.md) → C the place check
/// (confirm.md, opened from the chat) → done. Fixed wording with real numbers;
/// Apple's models do the sorting, not the talking.
struct SetupChatView: View {
    let app: AppModel
    @State private var model: SetupChatModel?

    var body: some View {
        Group {
            if let model {
                ChatContent(model: model, data: model.data, isSample: app.isSampleData)
                    .onChange(of: model.approvedConfig) { _, config in
                        if let config { app.approve(config) }
                    }
                    .fullScreenCover(isPresented: Binding(get: { model.isPlaceCheckOpen }, set: { if !$0 { model.placeCheckClosed() } })) {
                        ConfirmationFlow(app: app, mode: .fromChat) { model.placeCheckClosed() }
                    }
                    .onChange(of: model.isFinished) { _, finished in
                        if finished { app.finishSetup() }
                    }
            } else {
                Color.clear
            }
        }
        .onAppear {
            guard model == nil else { return }
            if app.isMySaves {
                // The user's own saves: sorted on the phone, then the file is written at hand-off.
                app.startSorting()
                model = SetupChatModel(data: app.data, receipt: app.myPosts, datasetID: Dataset.mineID,
                                       places: { app.places }, progress: { app.sortProgress() },
                                       load: { await app.buildMySaves() })
            } else if let data = app.data {
                model = SetupChatModel(data: data, receipt: data.posts, datasetID: app.dataset?.id ?? "default",
                                       places: { app.places }, progress: { SimulatedSort.progress(for: data) },
                                       load: { data })
            }
        }
    }
}

// MARK: - Model

/// Chat state. Persisted so quitting mid-chat resumes at the last bot message.
@Observable
@MainActor
final class SetupChatModel {
    enum Stage: String, Codable {
        case receipt, reading                                   // R1–R3
        case found, questions, proposal, editing, approved      // B1–B5
        case placeCheck, done                                   // C, end
    }

    struct Message: Identifiable, Codable, Equatable {
        enum Kind: String, Codable { case bot, user, topics, question, preview, receipt, samples, progress }
        var id = UUID()
        var kind: Kind
        var text: String = ""
        var topicID: String?
    }

    private(set) var messages: [Message] = []
    private(set) var stage: Stage = .receipt
    private(set) var draft: LayoutRules.Draft
    private(set) var questionIndex = 0
    private(set) var isTyping = false
    var lastTouched: LegoScreen?

    /// Live while reading (R3); only the final line is persisted.
    private(set) var progress: SortProgress?
    /// The place check deck is open (it's presented by the view).
    private(set) var isPlaceCheckOpen = false
    /// "Open my app" tapped.
    private(set) var isFinished = false

    /// The sorted saves. Empty until the end of reading for the user's own saves.
    private(set) var data: HindsightData
    /// What arrived (R1, R2): the user's imports, or the sample's posts.
    let receiptPosts: [ContractPost]
    private let placesStore: () -> PlaceStore
    private var places: PlaceStore { placesStore() }
    private let progressStream: () -> AsyncStream<SortProgress>
    private let loadData: () async -> HindsightData?
    private(set) var proposal: LayoutRules.Proposal
    private var assignment: LayoutRules.Assignment
    private let file: JSONFile<Saved>

    private struct Saved: Codable {
        var messages: [Message]
        var stage: Stage
        var questionIndex: Int
        var tabs: [TabConfig]
        var excluded: [String]
        var answers: [String: String]   // topicID → lego screen or "none"
    }

    private var answers: [String: String] = [:]

    init(data: HindsightData?, receipt: [ContractPost], datasetID: String, places: @escaping () -> PlaceStore,
         progress: @escaping () -> AsyncStream<SortProgress>, load: @escaping () async -> HindsightData?) {
        let data = data ?? .empty
        self.data = data
        receiptPosts = receipt
        placesStore = places
        progressStream = progress
        loadData = load
        let proposal = LayoutRules.propose(data)
        self.proposal = proposal
        draft = proposal.draft
        assignment = LayoutRules.naturalAssignment(data)
        file = JSONFile(name: "setup-chat", directory: JSONFile<Saved>.directory(for: datasetID))
        guard let saved = file.load(), !saved.messages.isEmpty, saved.stage != .receipt, saved.stage != .reading,
              !data.posts.isEmpty else {
            Task { await start() }
            return
        }
        messages = saved.messages
        stage = saved.stage
        questionIndex = saved.questionIndex
        draft = LayoutRules.Draft(tabs: saved.tabs, excludedTopicIDs: saved.excluded)
        answers = saved.answers
        for (topic, screen) in saved.answers { assignment[topic] = .some(LegoScreen(rawValue: screen)) }
        self.proposal = LayoutRules.propose(data, assignment: assignment)
        self.proposal.questions = proposal.questions
        // Quit between "Looks good" and the place check: approve again (idempotent) and carry on.
        if stage == .approved {
            approvedConfig = draft.config()
            Task { await afterApproval() }
        }
    }

    private func save() {
        file.save(Saved(messages: messages, stage: stage, questionIndex: questionIndex, tabs: draft.tabs,
                        excluded: draft.excludedTopicIDs, answers: answers))
    }

    private func say(_ text: String, kind: Message.Kind = .bot, topicID: String? = nil, delay: Duration = .milliseconds(650)) async {
        isTyping = true
        try? await Task.sleep(for: delay)
        isTyping = false
        messages.append(Message(kind: kind, text: text, topicID: topicID))
        save()
    }

    private func userSays(_ text: String) {
        messages.append(Message(kind: .user, text: text))
        save()
    }

    // R1–R3
    private func start() async {
        stage = .receipt
        await say(Self.receiptLine(receiptPosts), delay: .milliseconds(500))
        await say("", kind: .receipt, delay: .milliseconds(250))
        await say("Here's a taste of what's in there:", delay: .milliseconds(700))
        await say("", kind: .samples, delay: .milliseconds(300))
        await read()
        guard let loaded = await loadData(), !loaded.posts.isEmpty else {
            await say("Hmm, I couldn't finish reading your saves. Close the app and open it again, and I'll pick up where I stopped.")
            return
        }
        use(loaded)
        await found()
    }

    /// The sorted saves arrived (end of reading): build the proposal from them.
    private func use(_ loaded: HindsightData) {
        data = loaded
        proposal = LayoutRules.propose(loaded)
        draft = proposal.draft
        assignment = LayoutRules.naturalAssignment(loaded)
    }

    /// "Got them. 412 saves: 324 from Instagram and 88 from X."
    static func receiptLine(_ posts: [ContractPost]) -> String {
        let counts = Platform.allCases.map { p in (p, posts.count { $0.platform == p }) }.filter { $0.1 > 0 }
        let total = posts.count.formatted()
        guard !counts.isEmpty else { return "Got them." }
        if counts.count == 1 { return "Got them. \(total) saves from \(counts[0].0.displayName)." }
        let parts = counts.map { "\($0.1.formatted()) from \($0.0.displayName)" }.formatted(.list(type: .and))
        return "Got them. \(total) saves: \(parts)."
    }

    /// R3: one message that updates in place while the saves are sorted. Moves on
    /// at ≥ 90% decided or after 20 s (spec decision 3); the rest finish behind.
    private func read() async {
        stage = .reading
        messages.append(Message(kind: .progress))
        let index = messages.count - 1
        let clock = ContinuousClock()
        let started = clock.now
        for await snapshot in progressStream() {
            progress = snapshot
            if snapshot.shouldHandOff(after: clock.now - started) { break }
        }
        let total = receiptPosts.count.formatted()
        let decided = (progress?.decided ?? 0).formatted()
        messages[index].text = (progress?.isComplete ?? true)
            ? "Done. That's all \(total)."
            : "I've read \(decided) of \(total), enough to see the shape of it. I'll finish the rest in the background."
        progress = nil
        save()
    }

    // B1
    private func found() async {
        let total = data.posts.count
        switch proposal.situation {
        case .nothingFits where total < LayoutRules.fewSaves, .fewSaves:
            await say("That's only \(total) \(total == 1 ? "save" : "saves") so far, not enough to build much yet. Here's what's there:")
            await say("", kind: .topics, delay: .milliseconds(300))
            await say("Bring in more from Instagram, Facebook or X and I'll build more tabs.")
        case .nothingFits:
            await say("", kind: .topics, delay: .milliseconds(300))
            await say("Your saves are mostly memes and news, which I can't organize yet. Here's the closest I've got:")
        default:
            await say("Here's what I found:", delay: .milliseconds(500))
            await say("", kind: .topics, delay: .milliseconds(400))
            let none = data.topics.filter { $0.legoScreen == nil }.reduce(0) { $0 + $1.postIds.count }
            if none > 0 { await say("The random stuff (\(none) memes, news and ads) I'll leave out for now. It's all still in Everything else.") }
        }
        stage = .found
        await askNextQuestionOrPropose()
    }

    // B2
    private func askNextQuestionOrPropose() async {
        if questionIndex < proposal.questions.count {
            let topic = proposal.questions[questionIndex]
            stage = .questions
            await say(topic.ambiguity?.question ?? "Where should \(topic.label) go?", kind: .question, topicID: topic.id)
        } else {
            await propose()
        }
    }

    func answer(_ option: ContractTopic.Ambiguity.Option, for topic: ContractTopic) {
        userSays(option.label)
        answers[topic.id] = option.legoScreen?.rawValue ?? "none"
        assignment[topic.id] = .some(option.legoScreen)
        let questions = proposal.questions
        proposal = LayoutRules.propose(data, assignment: assignment)
        proposal.questions = questions
        draft = proposal.draft
        questionIndex += 1
        Task {
            let where_ = option.legoScreen.map { "\($0.defaultTitle)" }
            await say(where_.map { "Got it. They go in \($0)." } ?? "Got it. Leaving them out for now.", delay: .milliseconds(450))
            await askNextQuestionOrPropose()
        }
    }

    // B3
    private func propose() async {
        stage = .proposal
        if proposal.situation == .oneTab, let tab = draft.tabs.first {
            let what = tab.legoScreen == .map ? "one big map" : "one big \(tab.title.lowercased()) list"
            await say("Your saves are basically \(what). Here's your app:")
        } else if draft.tabs.isEmpty {
            await say("I couldn't build tabs from these yet. You can add one below, or keep everything in Everything else.")
        } else {
            await say("Here's your app:")
        }
        await say("", kind: .preview, delay: .milliseconds(350))
        if let offer = proposal.offers.first, draft.tab(for: offer) == nil,
           let count = LayoutEdit.addable(draft, data).first(where: { $0.screen == offer })?.count {
            await say("Also add a \(offer.defaultTitle.lowercased())? \(count) spots.", delay: .milliseconds(400))
        }
        await say("Want to change anything?", delay: .milliseconds(400))
    }

    // B4
    func startEditing() {
        userSays("Change something")
        stage = .editing
        Task { await say("Tap a tab to change it, or just tell me.", delay: .milliseconds(400)) }
    }

    func apply(_ edit: LayoutEdit, echo: String? = nil) {
        if let echo { userSays(echo) }
        let before = draft
        draft = edit.apply(to: draft, data: data)
        switch edit {
        case .add(let s), .remove(let s), .rename(let s, _), .changeEmoji(let s, _), .move(let s, _): lastTouched = s
        case .leaveOut: break
        }
        save()
        guard draft != before else {
            Task { await say("Hmm, nothing changed there.", delay: .milliseconds(300)) }
            return
        }
        let line = edit.confirmation(draft, data)
        Task { await say(line, delay: .milliseconds(350)) }
    }

    /// Typed text: parse into an edit, or ask with chips when unsure.
    func handleTyped(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        if ["looks good", "good", "done", "ok", "okay", "yes", "perfect", "ship it"].contains(TextMatch.fold(trimmed)) {
            userSays(trimmed)
            approveNow()
            return
        }
        if stage != .editing { stage = .editing }
        if let edit = TypedEditParser.parse(trimmed, draft: draft, data: data, lastTouched: lastTouched) {
            apply(edit, echo: trimmed)
        } else {
            userSays(trimmed)
            Task { await say("I didn't catch that. Try \"rename Map to Eats\", \"drop cooking\" or \"put Learn first\", or tap a tab.", delay: .milliseconds(400)) }
        }
    }

    // B5
    private(set) var approvedConfig: LayoutConfig?

    func approveNow() {
        if messages.last?.kind != .user { userSays("Looks good") }
        stage = .approved
        save()
        Task {
            await say("Building it… 🔨", delay: .milliseconds(350))
            try? await Task.sleep(for: .milliseconds(700))
            approvedConfig = draft.config()
            await afterApproval()
        }
    }

    // C: the place check, if there's a Map
    private(set) var placeCheckAsks = 0

    private func afterApproval() async {
        guard draft.tab(for: .map) != nil else {
            await finishLine()
            return
        }
        places.startMatching()
        // Matching started back at the receipt; wait until a full hand of cards is ready.
        var waited = false
        while places.isMatching && places.onboardingCards().count < Triage.onboardingLimit && !places.isOffline {
            if !waited { await say("Putting your spots on the map…", delay: .milliseconds(400)); waited = true }
            try? await Task.sleep(for: .milliseconds(500))
        }
        placeCheckAsks = places.onboardingCards().count
        let placed = places.placedCount
        if places.isOffline {
            await say("I'll finish putting your spots on the map when you're back online.")
            await finishLine()
        } else if placeCheckAsks == 0 {
            await say("I put \(placed.formatted()) spots on your map. Nailed all of them. Didn't even need you.")
            await finishLine()
        } else {
            stage = .placeCheck
            await say("One last thing. I put \(placed.formatted()) spots on your map. \(placeCheckAsks) I'm not sure about. Want to check them? About a minute.")
        }
    }

    func checkPlaces() {
        userSays("Check them")
        isPlaceCheckOpen = true
    }

    func placeCheckLater() {
        userSays("Later")
        Task {
            await say("No problem. They're in Needs review whenever you want.", delay: .milliseconds(400))
            await finishLine()
        }
    }

    func placeCheckClosed() {
        guard isPlaceCheckOpen else { return }
        isPlaceCheckOpen = false
        // Closed with cards left: say where they went instead of "Map's ready".
        let left = places.needsReviewCount
        Task {
            await say(left == 0 ? "Map's ready. Go eat something."
                                : "Map's ready. \(left) spots are in Needs review whenever you want.", delay: .milliseconds(500))
            await finishLine()
        }
    }

    private func finishLine() async {
        stage = .done
        await say("You're in. 🎉", delay: .milliseconds(600))
    }

    func finish() {
        file.delete()
        isFinished = true
    }
}

// MARK: - Views

private struct ChatContent: View {
    let model: SetupChatModel
    let data: HindsightData
    let isSample: Bool

    @State private var typed = ""
    @FocusState private var typing: Bool

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Hindsight").font(Theme.title(20))
                Spacer()
                if isSample {
                    Text("Sample saves")
                        .font(Theme.body(12, weight: .bold))
                        .foregroundStyle(Theme.secondary)
                        .padding(.horizontal, 10).padding(.vertical, 5)
                        .background(Theme.surface, in: Capsule())
                        .overlay(Capsule().strokeBorder(Theme.stroke))
                }
            }
            .padding(.horizontal, Theme.padding)
            .padding(.vertical, 10)
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(model.messages) { message in
                            row(message).id(message.id)
                                .transition(.move(edge: .bottom).combined(with: .opacity))
                        }
                        if model.isTyping { TypingBubble().id("typing") }
                        Color.clear.frame(height: 8).id("bottom")
                    }
                    .padding(.horizontal, Theme.padding)
                    .padding(.top, 8)
                    .animation(.snappy, value: model.messages.count)
                }
                .onChange(of: model.messages.count) { _, _ in
                    withAnimation { proxy.scrollTo("bottom", anchor: .bottom) }
                }
                .onChange(of: model.isTyping) { _, _ in
                    withAnimation { proxy.scrollTo("bottom", anchor: .bottom) }
                }
                .onChange(of: model.progress?.topics.count) { _, _ in
                    withAnimation { proxy.scrollTo("bottom", anchor: .bottom) }
                }
            }
            replies
        }
    }

    @ViewBuilder private func row(_ message: SetupChatModel.Message) -> some View {
        switch message.kind {
        case .bot:
            BotBubble(text: message.text)
        case .user:
            HStack {
                Spacer(minLength: 60)
                Text(message.text)
                    .font(Theme.body(16, weight: .semibold))
                    .foregroundStyle(Theme.onLime)
                    .padding(.horizontal, 14).padding(.vertical, 10)
                    .background(Theme.lime, in: .rect(cornerRadius: 18))
            }
        case .receipt:
            ReceiptCard(posts: model.receiptPosts)
        case .samples:
            TasteCards(posts: SetupChatModel.tastePosts(model.receiptPosts), data: data)
        case .progress:
            if let progress = model.progress {
                ReadingBubble(progress: progress)
            } else {
                BotBubble(text: message.text)
            }
        case .topics:
            TopicCloud(data: data)
        case .question:
            if let topic = message.topicID.flatMap({ data.topic($0) }) {
                VStack(alignment: .leading, spacing: 10) {
                    BotBubble(text: message.text)
                    SampleStrip(data: data, topic: topic)
                }
            }
        case .preview:
            AppPreviewCard(model: model, data: data, isEditing: model.stage == .editing)
        }
    }

    /// Reply chips for the current stage; typing is allowed, never needed.
    @ViewBuilder private var replies: some View {
        VStack(spacing: 10) {
            if !model.isTyping {
                switch model.stage {
                case .questions:
                    if model.questionIndex < model.proposal.questions.count {
                        let topic = model.proposal.questions[model.questionIndex]
                        WrapLayout {
                            ForEach(topic.ambiguity?.options ?? [], id: \.label) { option in
                                Chip(label: option.label) { model.answer(option, for: topic) }
                            }
                        }
                    }
                case .proposal:
                    HStack(spacing: 10) {
                        Button("Change something") { model.startEditing() }.buttonStyle(.pillSecondary)
                        Button("Looks good") { model.approveNow() }.buttonStyle(.pill)
                    }
                case .editing:
                    Button("Looks good") { model.approveNow() }.buttonStyle(.pill)
                case .placeCheck:
                    if !model.isPlaceCheckOpen {
                        HStack(spacing: 10) {
                            Button("Later") { model.placeCheckLater() }.buttonStyle(.pillSecondary)
                            Button("Check them") { model.checkPlaces() }.buttonStyle(.pill)
                        }
                    }
                case .done:
                    if model.messages.last?.kind == .bot {
                        Button("Open my app") { model.finish() }.buttonStyle(.pill)
                    }
                case .receipt, .reading, .found, .approved:
                    EmptyView()
                }
            }
            if model.stage == .proposal || model.stage == .editing {
                HStack {
                    TextField("Or tell me: \"call it Eats\"", text: $typed)
                        .focused($typing)
                        .submitLabel(.send)
                        .onSubmit(send)
                    Button(action: send) {
                        Image(systemName: "arrow.up.circle.fill").font(.system(size: 28)).foregroundStyle(typed.isEmpty ? Theme.muted : Theme.lime)
                    }
                    .disabled(typed.isEmpty)
                    .accessibilityLabel("Send")
                }
                .padding(.leading, 16).padding(.trailing, 6).padding(.vertical, 6)
                .background(Theme.surface, in: Capsule())
                .overlay(Capsule().strokeBorder(Theme.stroke))
            }
        }
        .padding(.horizontal, Theme.padding)
        .padding(.vertical, 10)
        .animation(.snappy, value: model.stage)
    }

    private func send() {
        let text = typed
        typed = ""
        model.handleTyped(text)
    }
}

extension SetupChatModel {
    /// R2: the 3 newest saves, one per platform first, then the next newest.
    static func tastePosts(_ posts: [ContractPost], count: Int = 3) -> [ContractPost] {
        var picked: [ContractPost] = []
        var platforms = Set<Platform>()
        for post in posts where picked.count < count && platforms.insert(post.platform).inserted { picked.append(post) }
        for post in posts where picked.count < count && !picked.contains(post) { picked.append(post) }
        return picked
    }
}

/// R1: one tile per platform with its count (Ariel's "You're in" numbers).
private struct ReceiptCard: View {
    let posts: [ContractPost]

    var body: some View {
        HStack(spacing: 8) {
            ForEach(Platform.allCases) { platform in
                let count = posts.count { $0.platform == platform }
                VStack(spacing: 6) {
                    PlatformGlyph(platform: platform, size: 30).clipShape(.rect(cornerRadius: 8))
                    Text(count.formatted()).font(Theme.body(15, weight: .bold))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(Theme.surface, in: .rect(cornerRadius: 16))
                .opacity(count > 0 ? 1 : 0.35)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(platform.displayName): \(count)")
            }
        }
    }
}

/// R2: a few real posts; tapping one opens it.
private struct TasteCards: View {
    let posts: [ContractPost]
    let data: HindsightData
    @Environment(\.openURL) private var openURL

    var body: some View {
        VStack(spacing: 8) {
            ForEach(posts) { post in
                Button { PostOpener.open(post, openURL: openURL) } label: {
                    HStack(alignment: .top, spacing: 12) {
                        PostLinkThumbnail(post: post, size: 48)
                        VStack(alignment: .leading, spacing: 3) {
                            Text("@\(post.author.username)").font(Theme.body(14, weight: .bold))
                            Text(post.caption ?? "No caption")
                                .font(Theme.body(14))
                                .foregroundStyle(post.caption == nil ? Theme.muted : Theme.secondary)
                                .lineLimit(2)
                                .multilineTextAlignment(.leading)
                        }
                        Spacer(minLength: 0)
                    }
                    .card(padding: 12)
                }
                .buttonStyle(.plain)
            }
        }
    }
}

/// R3, live: "Reading your saves… 180 of 412", a bar, and topic chips popping in.
private struct ReadingBubble: View {
    let progress: SortProgress

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Reading your saves… \(progress.decided.formatted()) of \(progress.total.formatted())")
                .font(Theme.body(17))
                .contentTransition(.numericText(value: Double(progress.decided)))
            ProgressView(value: progress.fraction).tint(Theme.lime)
            if !progress.topics.isEmpty {
                WrapLayout(spacing: 8) {
                    ForEach(progress.topics) { topic in
                        HStack(spacing: 6) {
                            Text(topic.emoji)
                            Text(topic.label).font(Theme.body(14, weight: .bold))
                            Text("\(topic.count)").font(Theme.body(14, weight: .bold)).foregroundStyle(Theme.secondary)
                                .contentTransition(.numericText(value: Double(topic.count)))
                        }
                        .padding(.horizontal, 12).padding(.vertical, 7)
                        .background(Theme.surfaceRaised, in: Capsule())
                        .transition(.opacity)
                    }
                }
            }
        }
        .padding(14)
        .background(Theme.surface, in: .rect(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(Theme.stroke))
        .animation(.snappy, value: progress)
    }
}

private struct BotBubble: View {
    let text: String

    var body: some View {
        HStack {
            Text(text)
                .font(Theme.body(17))
                .padding(.horizontal, 14).padding(.vertical, 10)
                .background(Theme.surface, in: .rect(cornerRadius: 18))
                .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(Theme.stroke))
            Spacer(minLength: 40)
        }
    }
}

private struct TypingBubble: View {
    @State private var phase = 0.0

    var body: some View {
        HStack(spacing: 5) {
            ForEach(0..<3) { i in
                Circle().fill(Theme.secondary).frame(width: 7, height: 7)
                    .opacity(0.3 + 0.7 * abs(sin(phase + Double(i) * 0.8)))
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 14)
        .background(Theme.surface, in: .rect(cornerRadius: 18))
        .onAppear { withAnimation(.linear(duration: 1.2).repeatForever(autoreverses: false)) { phase = .pi * 2 } }
        .accessibilityLabel("Typing")
    }
}

/// B1: chips with emoji + counts for every topic that has a home, plus Random.
private struct TopicCloud: View {
    let data: HindsightData

    var body: some View {
        let shown = data.topics.filter { $0.legoScreen != nil }.sorted { $0.postIds.count > $1.postIds.count }
        let random = data.topics.filter { $0.legoScreen == nil }.reduce(0) { $0 + $1.postIds.count }
        WrapLayout(spacing: 8) {
            ForEach(shown) { topic in
                topicChip(emoji: topic.emoji ?? topic.legoScreen?.defaultEmoji ?? "•", label: topic.label, count: topic.postIds.count)
            }
            if random > 0 { topicChip(emoji: "🤷", label: "Random", count: random) }
        }
        .card(padding: 14)
    }

    private func topicChip(emoji: String, label: String, count: Int) -> some View {
        HStack(spacing: 6) {
            Text(emoji)
            Text(label).font(Theme.body(14, weight: .bold))
            Text("\(count)").font(Theme.body(14, weight: .bold)).foregroundStyle(Theme.secondary)
        }
        .padding(.horizontal, 12).padding(.vertical, 7)
        .background(Theme.surfaceRaised, in: Capsule())
    }
}

/// B2 evidence: the topic's sample posts.
private struct SampleStrip: View {
    let data: HindsightData
    let topic: ContractTopic

    var body: some View {
        HStack(spacing: 10) {
            ForEach(topic.samplePostIds.prefix(3), id: \.self) { id in
                if let post = data.post(id) {
                    VStack(alignment: .leading, spacing: 6) {
                        PostThumbnail(post: post, emoji: topic.emoji, size: 96)
                        Text(post.firstLine ?? "").font(Theme.body(12)).foregroundStyle(Theme.secondary).lineLimit(2)
                    }
                    .frame(width: 96)
                }
            }
        }
    }
}

/// B3/B4: the proposed app as a card: a mini tab bar + one row per tab.
/// In edit mode: drag to reorder, tap a tab for Rename · Remove · Change emoji, "+ Add".
private struct AppPreviewCard: View {
    let model: SetupChatModel
    let data: HindsightData
    let isEditing: Bool

    @State private var renaming: TabConfig?
    @State private var newName = ""
    @State private var emojiFor: TabConfig?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            // mini phone tab bar
            HStack(spacing: 0) {
                ForEach(model.draft.tabs) { tab in
                    VStack(spacing: 4) {
                        Image(systemName: tab.legoScreen.symbol).font(.system(size: 18, weight: .semibold))
                        Text(tab.title).font(Theme.label(12)).lineLimit(1)
                    }
                    .foregroundStyle(tab.id == model.draft.tabs.first?.id ? Theme.lime : Theme.secondary)
                    .frame(maxWidth: .infinity)
                }
            }
            .padding(.vertical, 10)
            .background(Theme.surfaceRaised, in: Capsule())

            ForEach(Array(model.draft.tabs.enumerated()), id: \.element.id) { index, tab in
                tabRow(tab, index: index)
            }

            if isEditing {
                ForEach(LayoutEdit.addable(model.draft, data), id: \.screen) { item in
                    Button {
                        model.apply(.add(item.screen), echo: "Add \(item.screen.defaultTitle)")
                    } label: {
                        Label("\(item.screen.defaultTitle) · \(item.count) \(item.screen == .map ? "spots" : "posts")", systemImage: "plus.circle.fill")
                            .font(Theme.body(15, weight: .bold))
                            .foregroundStyle(Theme.lime)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .card(padding: 16)
        .overlay(RoundedRectangle(cornerRadius: Theme.radius).strokeBorder(isEditing ? Theme.lime.opacity(0.6) : .clear, lineWidth: 1.5))
        .animation(.snappy, value: model.draft)
        .alert("Rename tab", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
            TextField("Name", text: $newName)
            Button("Rename") {
                if let tab = renaming { model.apply(.rename(tab.legoScreen, newName), echo: "Call it \(newName)") }
                renaming = nil
            }
            Button("Cancel", role: .cancel) { renaming = nil }
        }
        .confirmationDialog("Change emoji", isPresented: Binding(get: { emojiFor != nil }, set: { if !$0 { emojiFor = nil } })) {
            ForEach(emojiChoices(emojiFor?.legoScreen), id: \.self) { e in
                Button(e) {
                    if let tab = emojiFor { model.apply(.changeEmoji(tab.legoScreen, e), echo: e) }
                    emojiFor = nil
                }
            }
        }
    }

    @ViewBuilder private func tabRow(_ tab: TabConfig, index: Int) -> some View {
        let row = HStack(spacing: 12) {
            Text(tab.emoji).font(.system(size: 26)).frame(width: 36)
            VStack(alignment: .leading, spacing: 3) {
                Text(tab.title).font(Theme.title(19))
                Text(LayoutRules.summary(tab, data)).font(Theme.body(14)).foregroundStyle(Theme.secondary).lineLimit(2)
                SamplesRow(data: data, tab: tab)
            }
            Spacer(minLength: 0)
            if isEditing {
                VStack(spacing: 4) {
                    if index > 0 {
                        Button { model.apply(.move(tab.legoScreen, toIndex: index - 1)) } label: { Image(systemName: "chevron.up") }
                            .accessibilityLabel("Move \(tab.title) up")
                    }
                    if index < model.draft.tabs.count - 1 {
                        Button { model.apply(.move(tab.legoScreen, toIndex: index + 1)) } label: { Image(systemName: "chevron.down") }
                            .accessibilityLabel("Move \(tab.title) down")
                    }
                }
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(Theme.secondary)
                .buttonStyle(.plain)
            }
        }
        .padding(12)
        .background(Theme.surfaceRaised.opacity(0.6), in: .rect(cornerRadius: Theme.smallRadius))

        if isEditing {
            Menu {
                Button("Rename", systemImage: "pencil") { newName = tab.title; renaming = tab }
                Button("Change emoji", systemImage: "face.smiling") { emojiFor = tab }
                if tab.legoScreen == .learn || tab.legoScreen == .fitness {
                    Menu("Leave out a topic") {
                        ForEach(tab.topicIDs, id: \.self) { id in
                            Button(data.topic(id)?.label ?? id) { model.apply(.leaveOut(topicID: id), echo: "Drop \(data.topic(id)?.label.lowercased() ?? id)") }
                        }
                    }
                }
                Button("Remove", systemImage: "trash", role: .destructive) {
                    model.apply(.remove(tab.legoScreen), echo: "Remove \(tab.title)")
                }
            } label: { row }
            .buttonStyle(.plain)
            .draggable(tab.id)
            .dropDestination(for: String.self) { items, _ in
                guard let id = items.first, let moving = model.draft.tabs.first(where: { $0.id == id }) else { return false }
                model.apply(.move(moving.legoScreen, toIndex: index))
                return true
            }
        } else {
            row
        }
    }

    private func emojiChoices(_ screen: LegoScreen?) -> [String] {
        switch screen {
        case .map: ["🗺️", "🍽️", "📍", "🌆", "✈️"]
        case .fitness: ["💪", "🧘", "🏃", "🤸", "🦴"]
        case .learn, .none: ["📚", "🧠", "🎸", "💡", "✏️"]
        }
    }
}

/// Three tiny previews per tab (thumbnails, or type pins for the Map).
private struct SamplesRow: View {
    let data: HindsightData
    let tab: TabConfig

    var body: some View {
        let samples = tab.topicIDs.compactMap { data.topic($0) }.flatMap(\.samplePostIds).prefix(3)
        HStack(spacing: 6) {
            ForEach(Array(samples), id: \.self) { id in
                PostThumbnail(post: data.post(id), emoji: data.topic(forPost: id)?.emoji, size: 34, cornerRadius: 8)
            }
        }
        .padding(.top, 4)
    }
}

extension HindsightData {
    /// No saves yet (the setup chat before its data arrives).
    static let empty = HindsightData(file: ContractFile(contractVersion: ContractFile.supportedVersion, generatedAt: nil,
                                                        user: ContractUser(handle: "", platforms: []), posts: [], topics: [], items: []))
}

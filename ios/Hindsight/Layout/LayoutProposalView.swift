import SwiftUI

/// "Here's your app" (layout-proposal.md): a short chat that ends in an approved
/// `LayoutConfig`. Rules only (no LLM in the MVP): fixed wording, chips, and a
/// rule-based parser for typed edits.
///
/// Integration point for Ariel's onboarding chat: `LayoutProposalView(app:)` for now;
/// when his chat lands it can call `LayoutProposalChat(data:onApprove:)` directly.
struct LayoutProposalView: View {
    let app: AppModel

    var body: some View {
        if let data = app.data {
            LayoutProposalChat(data: data, datasetID: app.dataset?.id ?? "default") { config in
                app.approve(config)
            }
        }
    }
}

/// The chat itself: data in, `LayoutConfig` out.
struct LayoutProposalChat: View {
    let data: HindsightData
    let datasetID: String
    let onApprove: (LayoutConfig) -> Void

    @State private var model: ProposalChatModel?

    var body: some View {
        Group {
            if let model {
                ChatContent(model: model, data: data, onApprove: onApprove)
            } else {
                Color.clear
            }
        }
        .onAppear {
            if model == nil { model = ProposalChatModel(data: data, datasetID: datasetID) }
        }
    }
}

// MARK: - Model

/// Chat state. Persisted so quitting mid-chat resumes at the last bot message.
@Observable
@MainActor
final class ProposalChatModel {
    enum Stage: String, Codable { case found, questions, proposal, editing, approved }

    struct Message: Identifiable, Codable, Equatable {
        enum Kind: String, Codable { case bot, user, topics, question, preview }
        var id = UUID()
        var kind: Kind
        var text: String = ""
        var topicID: String?
    }

    private(set) var messages: [Message] = []
    private(set) var stage: Stage = .found
    private(set) var draft: LayoutRules.Draft
    private(set) var questionIndex = 0
    private(set) var isTyping = false
    var lastTouched: LegoScreen?

    let data: HindsightData
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

    init(data: HindsightData, datasetID: String) {
        self.data = data
        let proposal = LayoutRules.propose(data)
        self.proposal = proposal
        draft = proposal.draft
        assignment = LayoutRules.naturalAssignment(data)
        file = JSONFile(name: "proposal-chat", directory: JSONFile<Saved>.directory(for: datasetID))
        if let saved = file.load(), !saved.messages.isEmpty, saved.stage != .approved {
            messages = saved.messages
            stage = saved.stage
            questionIndex = saved.questionIndex
            draft = LayoutRules.Draft(tabs: saved.tabs, excludedTopicIDs: saved.excluded)
            answers = saved.answers
            for (topic, screen) in saved.answers { assignment[topic] = .some(LegoScreen(rawValue: screen)) }
            self.proposal = LayoutRules.propose(data, assignment: assignment)
            self.proposal.questions = proposal.questions
        } else {
            Task { await start() }
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

    // B1
    private func start() async {
        let total = data.posts.count
        switch proposal.situation {
        case .nothingFits:
            await say("Okay, I went through your \(total) saves.")
            await say("", kind: .topics, delay: .milliseconds(300))
            await say("Your saves are mostly memes and news, which I can't organize yet. Here's the closest I've got:")
        default:
            await say("Okay, I went through your \(total) saves. Here's what's in there:")
            await say("", kind: .topics, delay: .milliseconds(400))
            let none = data.topics.filter { $0.legoScreen == nil }.reduce(0) { $0 + $1.postIds.count }
            if none > 0 { await say("The random stuff (\(none) memes, news and ads) I'll leave out for now. It's all still in Everything else.") }
            if proposal.situation == .fewSaves { await say("That's not a lot yet. The more you save, the smarter this gets.") }
        }
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
        file.delete()
        Task {
            await say("Building it… 🔨", delay: .milliseconds(350))
            try? await Task.sleep(for: .milliseconds(700))
            approvedConfig = draft.config()
        }
    }
}

// MARK: - Views

private struct ChatContent: View {
    let model: ProposalChatModel
    let data: HindsightData
    let onApprove: (LayoutConfig) -> Void

    @State private var typed = ""
    @FocusState private var typing: Bool

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Hindsight").font(Theme.title(20))
                Spacer()
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
            }
            replies
        }
        .onChange(of: model.approvedConfig) { _, config in
            if let config { onApprove(config) }
        }
    }

    @ViewBuilder private func row(_ message: ProposalChatModel.Message) -> some View {
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
                case .found, .approved:
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
    let model: ProposalChatModel
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

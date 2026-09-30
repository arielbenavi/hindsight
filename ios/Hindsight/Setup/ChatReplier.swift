import Foundation
import FoundationModels

/// Answers what the user types in the setup chat, with Apple's models (Private
/// Cloud Compute first, then on-device). The bot's own lines stay fixed; this
/// only handles the user's messages: questions about their saves, and layout
/// edits in their own words. Edits are limited to the ones the app preview card
/// already offers (LayoutEdit), so the model can't break anything. Without a
/// model, the chat falls back to `TypedEditParser`.
protocol ChatReplying: Sendable {
    func reply(to message: String, about summary: String) async -> ChatReply?
}

/// The model's answer, as plain values.
struct ChatReply: Sendable, Equatable {
    enum Intent: String, Sendable { case question, edit, approve, other }
    enum EditKind: String, Sendable { case none, rename, remove, add, move, leaveOut }

    var intent: Intent
    var edit: EditKind = .none
    /// "map", "learn" or "fitness".
    var tab: String = ""
    /// The new name (rename) or the topic's label (leaveOut).
    var value: String = ""
    /// 1 = first (move).
    var position: Int = 0
    /// What the bot says back.
    var text: String

    /// The edit to apply, if the model asked for one the card supports **and**
    /// the person's own words back it up. Small models misread requests ("drop the
    /// design stuff" → remove the whole Learn tab), so every edit is checked
    /// against the message: a tab edit needs the tab named, a rename needs the
    /// new name in the message, a leave-out needs a topic the words point to.
    func layoutEdit(draft: LayoutRules.Draft, data: HindsightData, message: String) -> LayoutEdit? {
        guard intent == .edit else { return nil }
        let said = TextMatch.fold(message)
        let screen = LegoScreen(rawValue: tab.lowercased()) ?? TypedEditParser.screen(named: tab, draft: draft)
        let named = screen.map { Self.mentions(said, screen: $0, draft: draft) } ?? false
        // Words that point at one of the person's topics ("the design stuff" → Design inspo).
        let topic = TypedEditParser.topic(named: value, draft: draft, data: data)
            ?? said.split(separator: " ").lazy.filter { $0.count > 3 }
                .compactMap { TypedEditParser.topic(named: String($0), draft: draft, data: data) }.first
        switch edit {
        case .rename:
            guard let screen, named, let name = value.nilIfEmpty, said.contains(TextMatch.fold(name)) else { return nil }
            return .rename(screen, name)
        case .remove:
            if let topic, !named { return .leaveOut(topicID: topic) }
            guard let screen, named else { return nil }
            return .remove(screen)
        case .add:
            guard let screen, named else { return nil }
            return .add(screen)
        case .move:
            guard let screen, named, position > 0 else { return nil }
            return .move(screen, toIndex: position - 1)
        case .leaveOut:
            return topic.map { .leaveOut(topicID: $0) }
        case .none:
            return nil
        }
    }

    /// An answer that says it changed something ("I've moved the Learn tab…") when
    /// nothing changed. Small models do this; such answers aren't shown.
    var claimsAChange: Bool {
        let t = TextMatch.fold(text)
        let verbs = ["moved", "added", "removed", "renamed", "dropped", "deleted", "changed", "updated", "put ", "made the"]
        let claims = ["i've ", "ive ", "i have ", "i just ", "i moved", "i added", "i removed", "i renamed", "done", "all set"]
        return claims.contains { t.contains($0) } && verbs.contains { t.contains($0) }
    }

    /// The message names this tab: its title, its screen, or a synonym ("places", "workouts").
    private static func mentions(_ said: String, screen: LegoScreen, draft: LayoutRules.Draft) -> Bool {
        let words = said.split { !$0.isLetter && !$0.isNumber }.map(String.init)
        if let title = draft.tab(for: screen)?.title, said.contains(TextMatch.fold(title)) { return true }
        return words.contains { TypedEditParser.screen(named: $0, draft: nil) == screen }
    }
}

// MARK: - What the model sees and answers

@Generable enum ChatReplyIntent: String { case question, edit, approve, other }
@Generable enum ChatReplyEdit: String { case none, rename, remove, add, move, leaveOut }

@Generable struct ChatReplyAnswer {
    @Guide(description: "question: they ask about their saves or the app. edit: they want to change the proposed app. approve: they're happy with it. other: anything else.")
    var intent: ChatReplyIntent
    @Guide(description: "Only for edit: rename a tab, remove a tab, add a tab, move a tab, or leaveOut a topic (a section inside a tab). none otherwise.")
    var edit: ChatReplyEdit
    @Guide(description: "The tab the edit is about: map, learn or fitness. Empty if none.")
    var tab: String
    @Guide(description: "rename: the new tab name. leaveOut: the topic's label exactly as in the summary. Empty otherwise.")
    var value: String
    @Guide(description: "move: the tab's new position, 1 = first. 0 otherwise.")
    var position: Int
    @Guide(description: "Your reply: 1-2 short sentences, warm and a little playful, in the person's language. Answer exactly what they asked, using only facts from the summary. Never say you changed, moved or removed anything.")
    var reply: String
}

enum ChatReplierPrompt {
    static let instructions = """
    You are the setup assistant inside Hindsight, an app that turns a person's saved Instagram, Facebook and X posts into tabs they'll use: a Map of places, Learn for tips and tutorials, Fitness for stretches and workouts. You just sorted their saves and proposed an app. Answer their message using only the summary. Keep it short. If they ask a question, answer it; don't change anything. Only use edit when they clearly ask for a change, and only one change: a tab (rename, remove, add, move) or leaving out a topic (a section inside a tab, like "Design inspo").

    What you can and can't do:
    - You can rename, remove, add or reorder the proposed tabs, and leave a topic out. Nothing else.
    - You can't import saves. More saves come from the Connect screen: Instagram and Facebook through Muse, Connect X, or Import a file (a data download).
    - Posts that fit no tab (memes, news, ads) stay in Everything else, reachable from every tab.
    """
}

/// Private Cloud Compute, falling back to the on-device model.
struct AppleChatReplier: ChatReplying {
    func reply(to message: String, about summary: String) async -> ChatReply? {
        let prompt = "\(summary)\n\nThe person says: \"\(message.prefix(500))\""
        if #available(iOS 27, *) {
            let cloud = PrivateCloudComputeLanguageModel()
            if cloud.isAvailable, let answer = await ask(LanguageModelSession(model: cloud, instructions: Instructions(ChatReplierPrompt.instructions)), prompt) {
                return answer
            }
        }
        guard SystemLanguageModel.default.isAvailable else { return nil }
        return await ask(LanguageModelSession(model: SystemLanguageModel.default, instructions: Instructions(ChatReplierPrompt.instructions)), prompt)
    }

    private func ask(_ session: LanguageModelSession, _ prompt: String) async -> ChatReply? {
        do {
            let a = try await session.respond(to: prompt, generating: ChatReplyAnswer.self).content
            DebugLog.write("chat reply: \(a.intent.rawValue)/\(a.edit.rawValue) tab=\(a.tab) value=\(a.value)")
            return ChatReply(intent: ChatReply.Intent(rawValue: a.intent.rawValue) ?? .other,
                             edit: ChatReply.EditKind(rawValue: a.edit.rawValue) ?? .none,
                             tab: a.tab, value: a.value, position: a.position, text: a.reply)
        } catch {
            DebugLog.write("chat reply failed: \(String(describing: error).prefix(100))")
            return nil
        }
    }
}

import Foundation
import Testing
@testable import Hindsight

@MainActor
struct ChatReplierTests {
    private func setup() throws -> (HindsightData, LayoutRules.Draft) {
        let data = try Fixtures.load("reut")
        return (data, LayoutRules.propose(data).draft)
    }

    @Test func editsMapOntoWhatTheCardAlreadyOffers() throws {
        let (data, draft) = try setup()
        #expect(ChatReply(intent: .edit, edit: .rename, tab: "map", value: "Eats", text: "")
            .layoutEdit(draft: draft, data: data, message: "call the map Eats") == .rename(.map, "Eats"))
        #expect(ChatReply(intent: .edit, edit: .move, tab: "Learn", position: 1, text: "")
            .layoutEdit(draft: draft, data: data, message: "put learn first") == .move(.learn, toIndex: 0))
        #expect(ChatReply(intent: .edit, edit: .remove, tab: "map", text: "")
            .layoutEdit(draft: draft, data: data, message: "remove the map") == .remove(.map))
        let guitar = try #require(data.topics.first { $0.label.localizedCaseInsensitiveContains("guitar") })
        #expect(ChatReply(intent: .edit, edit: .leaveOut, value: guitar.label, text: "")
            .layoutEdit(draft: draft, data: data, message: "leave out guitar") == .leaveOut(topicID: guitar.id))
    }

    /// What the Mac's model actually did: "drop the design stuff" → remove the Learn tab.
    @Test func editsMustBeBackedByWhatWasTyped() throws {
        let (data, draft) = try setup()
        let guitar = try #require(data.topics.first { $0.label.localizedCaseInsensitiveContains("guitar") })
        // A topic named, no tab named: leave the topic out instead of removing the tab.
        #expect(ChatReply(intent: .edit, edit: .remove, tab: "learn", text: "")
            .layoutEdit(draft: draft, data: data, message: "drop the guitar stuff") == .leaveOut(topicID: guitar.id))
        // A tab edit the message never asked for.
        #expect(ChatReply(intent: .edit, edit: .move, tab: "learn", position: 1, text: "")
            .layoutEdit(draft: draft, data: data, message: "what's in brooklyn?") == nil)
        // A rename to a name the person never typed.
        #expect(ChatReply(intent: .edit, edit: .rename, tab: "map", value: "Spots", text: "")
            .layoutEdit(draft: draft, data: data, message: "rename the map") == nil)
    }

    @Test func questionsAndNonsenseMakeNoEdits() throws {
        let (data, draft) = try setup()
        #expect(ChatReply(intent: .question, edit: .rename, tab: "map", value: "X", text: "").layoutEdit(draft: draft, data: data, message: "rename map to X") == nil)
        #expect(ChatReply(intent: .edit, edit: .rename, tab: "podcasts", value: "X", text: "").layoutEdit(draft: draft, data: data, message: "rename map to X") == nil)
        #expect(ChatReply(intent: .edit, edit: .move, tab: "map", position: 0, text: "").layoutEdit(draft: draft, data: data, message: "rename map to X") == nil)
    }

    @Test func summaryGivesTheModelTheFacts() throws {
        let (data, draft) = try setup()
        let summary = SetupChatModel.summary(posts: data.posts, sorted: data, draft: draft, offers: [])
        #expect(summary.contains("Saves: 324 (324 Instagram)"))
        #expect(summary.contains("1. map tab named \"Map\""))
        #expect(summary.contains("In Everything else:"))
        let few = SetupChatModel.summary(posts: Array(data.posts.prefix(4)), sorted: .empty, draft: .init(tabs: [], excludedTopicIDs: []), offers: [])
        #expect(few.contains("very few"))
        #expect(few.contains("(none yet)"))
    }
}

struct ChatClaimTests {
    @Test func spotsAnswersThatClaimChanges() {
        // Real answers from the Mac's on-device model to questions.
        #expect(ChatReply(intent: .question, text: "Sure thing! I've added the Brooklyn spots to your Map tab. It's all set! 🎉").claimsAChange)
        #expect(ChatReply(intent: .question, text: "Great! I've moved the Learn tab to the top, so it's the first thing you'll see.").claimsAChange)
        #expect(!ChatReply(intent: .question, text: "Your Brooklyn spots are 20 places in the Map tab.").claimsAChange)
        #expect(!ChatReply(intent: .question, text: "You have 4 saves so far. Bring in more from Muse or X!").claimsAChange)
    }
}

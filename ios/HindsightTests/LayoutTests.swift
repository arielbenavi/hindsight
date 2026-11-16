import Foundation
import Testing
@testable import Hindsight

@MainActor
struct LayoutTests {
    @Test func reutGetsMapAndLearn() throws {
        let data = try Fixtures.load("reut")
        let draft = LayoutRules.propose(data)
        #expect(draft.tabs.map(\.legoScreen) == [.map, .learn])
        // her 2 stretches live in Learn (under the Fitness threshold)
        #expect(draft.tab(for: .learn)?.topicIDs.contains("stretches") == true)
    }

    @Test func arielGetsLearnFitnessAndMap() throws {
        let data = try Fixtures.load("ariel")
        let draft = LayoutRules.propose(data)
        #expect(Set(draft.tabs.map(\.legoScreen)) == [.learn, .fitness, .map])
        #expect(draft.tabs.first?.legoScreen == .map)
    }

    /// Topics no view fits (memes, news) are real topics now, but never in a view.
    @Test func topicsWithoutAViewStayOutOfTheViews() throws {
        for id in ["reut", "ariel"] {
            let data = try Fixtures.load(id)
            let draft = LayoutRules.propose(data)
            let none = Set(data.topics.filter { $0.legoScreen == nil }.map(\.id))
            #expect(!none.isEmpty)
            #expect(none.isDisjoint(with: draft.tabs.flatMap(\.topicIDs)))
            #expect(none.isSubset(of: draft.excludedTopicIDs))
        }
    }
}

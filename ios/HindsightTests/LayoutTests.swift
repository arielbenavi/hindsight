import Foundation
import Testing
@testable import Hindsight

@MainActor
struct LayoutTests {
    @Test func reutGetsMapAndLearnWithTheCoffeeQuestion() throws {
        let data = try Fixtures.load("reut")
        let p = LayoutRules.propose(data)
        #expect(p.draft.tabs.map(\.legoScreen) == [.map, .learn])
        #expect(p.questions.map(\.id) == ["coffee-at-home"])
        #expect(p.questions[0].ambiguity?.question.contains("Aesthetic coffee") == true)
        // her 2 stretches live in Learn (under the Fitness threshold)
        #expect(p.draft.tab(for: .learn)?.topicIDs.contains("stretches") == true)
    }

    @Test func arielGetsLearnFitnessAndMap() throws {
        let data = try Fixtures.load("ariel")
        let p = LayoutRules.propose(data)
        #expect(Set(p.draft.tabs.map(\.legoScreen)) == [.learn, .fitness, .map])
        #expect(p.draft.tabs.first?.legoScreen == .map)
        #expect(p.questions.count <= LayoutRules.maxQuestions)
    }

    @Test func neverMoreThanTwoQuestions() throws {
        for id in ["reut", "ariel"] {
            #expect(LayoutRules.propose(try Fixtures.load(id)).questions.count <= 2)
        }
    }

    @Test func answeringMovesTheTopic() throws {
        let data = try Fixtures.load("reut")
        var assignment = LayoutRules.naturalAssignment(data)
        assignment["coffee-at-home"] = .some(nil)
        let p = LayoutRules.propose(data, assignment: assignment)
        #expect(p.draft.excludedTopicIDs.contains("coffee-at-home"))
        #expect(p.draft.tab(for: .learn)?.topicIDs.contains("coffee-at-home") == false)
        #expect(p.questions.isEmpty)
    }
}

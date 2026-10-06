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

    @Test func tapEditsReorderRenameRemoveAdd() throws {
        let data = try Fixtures.load("reut")
        var d = LayoutRules.propose(data).draft
        d = LayoutEdit.move(.learn, toIndex: 0).apply(to: d, data: data)
        #expect(d.tabs.map(\.legoScreen) == [.learn, .map])
        d = LayoutEdit.rename(.map, "Eats").apply(to: d, data: data)
        #expect(d.tab(for: .map)?.title == "Eats")
        d = LayoutEdit.remove(.learn).apply(to: d, data: data)
        #expect(d.tabs.map(\.legoScreen) == [.map])
        #expect(d.excludedTopicIDs.contains("cooking"))
        d = LayoutEdit.add(.learn).apply(to: d, data: data)
        #expect(d.tab(for: .learn) != nil)
        #expect(!d.excludedTopicIDs.contains("cooking"))
    }

    @Test func typedEdits() throws {
        let data = try Fixtures.load("reut")
        let d = LayoutRules.propose(data).draft
        func parse(_ s: String, last: LegoScreen? = nil) -> LayoutEdit? {
            TypedEditParser.parse(s, draft: d, data: data, lastTouched: last)
        }
        #expect(parse("call it Eats", last: .map) == .rename(.map, "Eats"))
        #expect(parse("rename learn to Skills") == .rename(.learn, "Skills"))
        #expect(parse("drop cooking") == .leaveOut(topicID: "cooking"))
        #expect(parse("remove the map") == .remove(.map))
        #expect(parse("put Learn first") == .move(.learn, toIndex: 0))
        #expect(parse("add fitness") == .add(.fitness))
        #expect(parse("make it purple") == nil)
    }

    @Test func approvedCardBecomesTheTabBar() throws {
        let data = try Fixtures.load("reut")
        let d = LayoutEdit.rename(.map, "Eats").apply(to: LayoutRules.propose(data).draft, data: data)
        let config = d.config()
        #expect(config.tabs == d.tabs)
        let app = AppModel(datasets: Dataset.bundled(), selected: "reut", persist: false)
        app.approve(config)
        #expect(app.layout?.tabs.map(\.title) == ["Eats", "Learn"])
    }
}

import Foundation
import Testing
@testable import Hindsight

@MainActor
struct ModelEvalTests {
    /// Same size and mix as the Mac run (docs/LESSONS.md), so the numbers compare.
    @Test func sampleMatchesTheMacRun() {
        let cases = EvalCase.sample(from: Dataset.bundled())
        #expect(cases.count == 115)
        #expect(cases.count { $0.dataset == "reut" && $0.gold == .map } == 25)
        #expect(cases.count { $0.dataset == "ariel" && $0.gold == .fitness } == 10)
        #expect(Set(cases.map(\.post.id)).count == cases.count)
    }

    @Test func summaryScoresBucketsAndPlaces() {
        let rows = [
            EvalRow(id: "1", dataset: "reut", gold: "map", hebrew: false, screen: "map", places: ["Salt Hank's NYC"], goldPlaces: ["Salt Hank's", "Joe's"], seconds: 1),
            EvalRow(id: "2", dataset: "reut", gold: "none", hebrew: true, screen: "learn", goldPlaces: [], seconds: 3),
            EvalRow(id: "3", dataset: "reut", gold: "learn", hebrew: true, goldPlaces: [], error: "unsupportedLanguageOrLocale", seconds: 0),
        ]
        let summary = EvalSummary(engine: .onDevice, rows: rows)
        #expect(summary.correct == 1 && summary.answered.count == 2)
        #expect(summary.placeRecall == (1, 2))
        #expect(summary.hebrew == (0, 1, 2))
        #expect(summary.errors == ["unsupportedLanguageOrLocale": 1])
    }
}

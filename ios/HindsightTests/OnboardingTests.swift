import Foundation
import Testing
@testable import Hindsight

@MainActor
struct OnboardingTests {
    @Test func stepsMoveForwardAndBackWithinBounds() {
        let model = OnboardingModel(posts: [], preferences: OnboardingPreferences())
        model.back()
        #expect(model.step == .welcome)
        for _ in 0..<10 { model.next() }
        #expect(model.step == .done)
        model.back()
        #expect(model.step == .preferences)
    }

    @Test func preferencesRoundTrip() throws {
        let defaults = try #require(UserDefaults(suiteName: "OnboardingTests-\(UUID())"))
        var prefs = OnboardingPreferences()
        prefs.grouping = .creator
        prefs.topics = ["music", "quant"]
        prefs.save(to: defaults)
        #expect(OnboardingPreferences.load(from: defaults) == prefs)
    }

    @Test func topicSuggestionsComeFromSeedCaptions() {
        let counts = TopicSuggester.counts(for: SeedData.posts())
        #expect(!counts.isEmpty)
        #expect(counts.map(\.count) == counts.map(\.count).sorted(by: >))
        #expect(counts.contains { $0.topic == "music" })
    }
}

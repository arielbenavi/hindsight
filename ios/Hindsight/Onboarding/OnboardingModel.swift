import Foundation
import Observation

@Observable
@MainActor
final class OnboardingModel {
    enum Step: Int, CaseIterable {
        case welcome, howItWorks, connect, preferences, done
    }

    static let completedKey = "hasCompletedOnboarding"

    private(set) var step: Step = .welcome
    private(set) var isMovingForward = true

    var preferences: OnboardingPreferences {
        didSet { preferences.save() }
    }

    /// Topic chips to offer, with how many saves match each.
    let topicSuggestions: [(topic: String, count: Int)]

    init(posts: [SavedPost], preferences: OnboardingPreferences? = OnboardingPreferences.load()) {
        let suggestions = TopicSuggester.counts(for: posts)
        topicSuggestions = suggestions
        var prefs = preferences ?? OnboardingPreferences()
        if prefs.topics.isEmpty {
            prefs.topics = Set(suggestions.prefix(3).map(\.topic))
        }
        self.preferences = prefs
    }

    var canGoBack: Bool { step != .welcome }

    func next() {
        guard let next = Step(rawValue: step.rawValue + 1) else { return }
        isMovingForward = true
        step = next
    }

    func back() {
        guard let previous = Step(rawValue: step.rawValue - 1) else { return }
        isMovingForward = false
        step = previous
    }

    func toggleTopic(_ topic: String) {
        if preferences.topics.contains(topic) {
            preferences.topics.remove(topic)
        } else {
            preferences.topics.insert(topic)
        }
    }
}

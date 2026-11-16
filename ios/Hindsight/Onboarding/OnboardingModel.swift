import Foundation
import Observation

/// How the user left Connect: with their own saves, or to look around with the sample.
enum OnboardingChoice: String, Sendable {
    case mySaves = "mine"
    case sample
}

@Observable
@MainActor
final class OnboardingModel {
    /// Welcome → How it works → Plug in your apps → You're in, then Home.
    enum Step: Int, CaseIterable {
        case welcome, howItWorks, connect, done
    }

    static let completedKey = "hasCompletedOnboarding"

    private(set) var step: Step = .welcome
    private(set) var isMovingForward = true
    /// Set on Connect: the user's own saves, or the sample.
    private(set) var choice: OnboardingChoice?
    /// What "You're in" shows: the saves the app opens with.
    private(set) var donePosts: [ContractPost] = []

    init() {}

    var canGoBack: Bool { step != Step.allCases.first }

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

    /// Leaving Connect: on to "You're in" with the saves the app will open with.
    func choose(_ choice: OnboardingChoice, posts: [ContractPost]) {
        self.choice = choice
        donePosts = posts
        while step != .done { next() }
    }

}

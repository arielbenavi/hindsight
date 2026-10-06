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
    /// The screens before the setup chat (docs/specs/onboarding-chat.md). The chat
    /// takes over after Connect and ends on `DoneStep`.
    enum Step: Int, CaseIterable {
        case welcome, howItWorks, connect
    }

    static let completedKey = "hasCompletedOnboarding"

    private(set) var step: Step = .welcome
    private(set) var isMovingForward = true

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

}

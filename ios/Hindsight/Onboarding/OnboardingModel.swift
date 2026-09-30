import Foundation
import Observation

@Observable
@MainActor
final class OnboardingModel {
    /// Onboarding ends once the user has connected their sources. How the saves
    /// are shown is decided next, by the layout proposal (docs/merge-plan.md).
    enum Step: Int, CaseIterable {
        case welcome, howItWorks, connect
    }

    static let completedKey = "hasCompletedOnboarding"

    private(set) var step: Step = .welcome
    private(set) var isMovingForward = true
    var isMuseSheetPresented = false

    init() {}

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

}

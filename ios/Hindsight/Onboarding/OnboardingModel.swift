import Foundation
import Observation

@Observable
@MainActor
final class OnboardingModel {
    /// Onboarding is one screen now: Connect. Everything after it happens in the
    /// setup chat (docs/specs/onboarding-chat.md). Kept as a step list so more
    /// screens can come back without touching the flow.
    enum Step: Int, CaseIterable {
        case connect
    }

    static let completedKey = "hasCompletedOnboarding"

    private(set) var step: Step = .connect
    private(set) var isMovingForward = true
    var isMuseSheetPresented = false

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

import Foundation
import Testing
@testable import Hindsight

@MainActor
struct OnboardingTests {
    /// Connect is the first and only onboarding screen; the setup chat takes it
    /// from there (docs/specs/onboarding-chat.md).
    @Test func connectIsTheOnlyStep() {
        #expect(OnboardingModel.Step.allCases == [.connect])
        let model = OnboardingModel()
        #expect(model.step == .connect)
        #expect(!model.canGoBack)
        model.next()
        model.back()
        #expect(model.step == .connect)
    }
}

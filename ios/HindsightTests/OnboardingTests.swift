import Foundation
import Testing
@testable import Hindsight

@MainActor
struct OnboardingTests {
    /// Welcome → How it works → Connect, then the setup chat takes it from there
    /// (docs/specs/onboarding-chat.md).
    @Test func threeStepsEndingAtConnect() {
        #expect(OnboardingModel.Step.allCases == [.welcome, .howItWorks, .connect])
        let model = OnboardingModel()
        #expect(model.step == .welcome)
        #expect(!model.canGoBack)
        model.next()
        model.next()
        #expect(model.step == .connect)
        model.next()
        #expect(model.step == .connect)
        model.back()
        #expect(model.step == .howItWorks)
    }
}

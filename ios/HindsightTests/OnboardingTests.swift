import Foundation
import Testing
@testable import Hindsight

@MainActor
struct OnboardingTests {
    @Test func stepsMoveForwardAndBackWithinBounds() {
        let model = OnboardingModel()
        model.back()
        #expect(model.step == .welcome)
        for _ in 0..<10 { model.next() }
        #expect(model.step == .connect)
        model.back()
        #expect(model.step == .howItWorks)
    }

    /// Onboarding ends at Connect; the layout proposal decides how saves are shown.
    @Test func endsAtConnect() {
        #expect(OnboardingModel.Step.allCases.last == .connect)
    }
}

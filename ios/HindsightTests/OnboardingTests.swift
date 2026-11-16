import Foundation
import Testing
@testable import Hindsight

@MainActor
struct OnboardingTests {
    /// Welcome → How it works → Plug in your apps → You're in, then Home.
    @Test func fourStepsEndingAtYoureIn() {
        #expect(OnboardingModel.Step.allCases == [.welcome, .howItWorks, .connect, .done])
        let model = OnboardingModel()
        #expect(model.step == .welcome)
        #expect(!model.canGoBack)
        model.next()
        model.next()
        #expect(model.step == .connect)
        model.back()
        #expect(model.step == .howItWorks)
    }

    @Test func choosingOnConnectGoesToYoureInWithThosePosts() {
        let model = OnboardingModel()
        let post = ContractPost(id: "instagram:A", url: URL(string: "https://www.instagram.com/p/A/")!, author: "a", caption: "hi")
        model.choose(.sample, posts: [post])
        #expect(model.step == .done)
        #expect(model.choice == .sample)
        #expect(model.donePosts.map(\.id) == ["instagram:A"])
    }
}

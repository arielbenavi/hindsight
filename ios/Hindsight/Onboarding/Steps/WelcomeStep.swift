import SwiftUI

struct WelcomeStep: View {
    let model: OnboardingModel
    @State private var appeared = false

    var body: some View {
        OnboardingPage {
            hero
                .frame(maxWidth: .infinity)
                .padding(.vertical, 28)

            Text("Your saves,\nin \(Text("hindsight.").foregroundStyle(OnboardingStyle.accent))")
                .font(OnboardingStyle.display())
                .minimumScaleFactor(0.7)

            Text("You've saved thousands of reels, posts and threads “for later”.\nThis is later. 👀")
                .font(OnboardingStyle.body)
                .foregroundStyle(OnboardingStyle.muted)
        } actions: {
            Button("Let's go", action: model.next)
                .buttonStyle(.onboardingPrimary)
        }
        .onAppear { appeared = true }
    }

    private var hero: some View {
        ZStack {
            ForEach(Array(Platform.allCases.enumerated()), id: \.element) { index, platform in
                let offset = CGFloat(index) - 1.5
                Text(platform.emoji)
                    .font(.system(size: 44))
                    .frame(width: 92, height: 116)
                    .background(OnboardingStyle.surface, in: .rect(cornerRadius: 20))
                    .overlay(RoundedRectangle(cornerRadius: 20).stroke(OnboardingStyle.stroke))
                    .rotationEffect(.degrees(appeared ? offset * 9 : 0))
                    .offset(x: appeared ? offset * 58 : 0, y: appeared ? abs(offset) * 10 : 0)
            }
        }
        .frame(height: 150)
        .animation(.spring(duration: 0.8, bounce: 0.35).delay(0.1), value: appeared)
        .accessibilityHidden(true)
    }
}

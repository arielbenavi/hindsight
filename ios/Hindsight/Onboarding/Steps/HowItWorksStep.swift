import SwiftUI

struct HowItWorksStep: View {
    let model: OnboardingModel

    private let rows: [(emoji: String, title: String, detail: String)] = [
        ("🔖", "You save stuff", "Everywhere. Instagram, X, TikTok, Facebook. Same as always."),
        ("🧲", "We pull it together", "One place for all of it. No more “where did I see that”."),
        ("🔁", "It comes back", "Grouped, searchable, and resurfaced when it's actually useful."),
    ]

    var body: some View {
        OnboardingPage {
            Text("Here's the\ndeal.")
                .font(OnboardingStyle.display())

            VStack(spacing: 12) {
                ForEach(rows, id: \.title) { row in
                    HStack(alignment: .top, spacing: 16) {
                        Text(row.emoji).font(.system(size: 34))
                        VStack(alignment: .leading, spacing: 4) {
                            Text(row.title).font(OnboardingStyle.title)
                            Text(row.detail)
                                .font(OnboardingStyle.body)
                                .foregroundStyle(OnboardingStyle.muted)
                        }
                    }
                    .onboardingCard()
                }
            }
        } actions: {
            Button("Nice", action: model.next)
                .buttonStyle(.onboardingPrimary)
        }
    }
}

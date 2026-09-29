import SwiftUI

struct HowItWorksStep: View {
    let model: OnboardingModel

    private let rows: [(symbol: String, title: String, detail: String)] = [
        ("bookmark.fill", "You save stuff", "Everywhere. Instagram, X, TikTok, Facebook. Same as always."),
        ("tray.and.arrow.down.fill", "We pull it together", "One place for all of it. No more “where did I see that”."),
        ("arrow.trianglehead.counterclockwise", "It comes back", "Grouped, searchable, and resurfaced when it's actually useful."),
    ]

    var body: some View {
        OnboardingPage {
            Text("Here's the\ndeal.")
                .font(OnboardingStyle.display())

            VStack(spacing: 12) {
                ForEach(rows, id: \.title) { row in
                    HStack(alignment: .top, spacing: 16) {
                        Image(systemName: row.symbol)
                            .font(.system(size: 24, weight: .bold))
                            .foregroundStyle(OnboardingStyle.accent)
                            .frame(width: 32)
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

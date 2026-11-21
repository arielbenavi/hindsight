import SwiftUI

/// Sources → "Viewing": whether saves play inside hindsight (`PlayerSheet`) or open
/// in their own app. On by default.
struct ViewingCard: View {
    @AppStorage(PlayerGate.playInAppKey) private var playsInApp = true

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("VIEWING")
                .font(.system(.caption, design: .rounded, weight: .bold)).tracking(0.8)
                .foregroundStyle(OnboardingStyle.muted)
            Toggle("Play saves inside hindsight", isOn: $playsInApp)
                .font(.system(.subheadline, design: .rounded, weight: .bold))
                .tint(OnboardingStyle.accent)
            Text(playsInApp
                 ? "Reels, posts and links play here. \"Open in…\" still takes you to the app."
                 : "Saves open in Instagram, TikTok, X or the browser.")
                .font(OnboardingStyle.caption)
                .foregroundStyle(OnboardingStyle.muted)
        }
        .onboardingCard()
    }
}

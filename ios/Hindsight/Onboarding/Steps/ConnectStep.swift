import SwiftUI

struct ConnectStep: View {
    @Bindable var model: OnboardingModel
    let store: SavedPostStore

    var body: some View {
        OnboardingPage {
            Text("Plug in\nyour apps.")
                .font(OnboardingStyle.display())

            museCard

            comingSoonRow(.x, detail: "Sign in with X. No developer account needed.")
            comingSoonRow(.tiktok, detail: "Waiting on TikTok's data API approval.")
        } actions: {
            Button("Continue", action: model.next)
                .buttonStyle(.onboardingPrimary)
            Text("You can connect more later.")
                .font(OnboardingStyle.caption)
                .foregroundStyle(OnboardingStyle.muted)
        }
        .sheet(isPresented: $model.isMuseSheetPresented) {
            Text("Muse sync goes here")
                .presentationDetents([.large])
        }
    }

    private var museCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("\(Platform.instagram.emoji) \(Platform.facebook.emoji)").font(.system(size: 28))
                Spacer()
                let count = store.count(for: .instagram) + store.count(for: .facebook)
                if count > 0 {
                    Label("\(count.formatted()) saves", systemImage: "checkmark.circle.fill")
                        .font(OnboardingStyle.caption)
                        .foregroundStyle(OnboardingStyle.accent)
                }
            }
            VStack(alignment: .leading, spacing: 4) {
                Text("Instagram + Facebook").font(OnboardingStyle.title)
                Text("Through Muse, Meta's AI. It can already see your saves. One tap, no passwords.")
                    .font(OnboardingStyle.body)
                    .foregroundStyle(OnboardingStyle.muted)
            }
            Button("Sync with Muse ✨") { model.isMuseSheetPresented = true }
                .buttonStyle(.onboardingSecondary)
        }
        .onboardingCard()
    }

    private func comingSoonRow(_ platform: Platform, detail: String) -> some View {
        HStack(spacing: 14) {
            Text(platform.emoji)
                .font(.system(size: 24, weight: .bold))
                .frame(width: 32)
            VStack(alignment: .leading, spacing: 2) {
                Text(platform.displayName).font(OnboardingStyle.title)
                Text(detail)
                    .font(OnboardingStyle.caption)
                    .foregroundStyle(OnboardingStyle.muted)
            }
            Spacer()
            Text("soon")
                .font(.system(.caption, design: .rounded, weight: .heavy))
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(OnboardingStyle.stroke, in: .capsule)
        }
        .onboardingCard(padding: 16)
        .opacity(0.7)
    }
}

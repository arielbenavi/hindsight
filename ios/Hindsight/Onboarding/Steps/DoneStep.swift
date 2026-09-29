import SwiftUI

struct DoneStep: View {
    let store: SavedPostStore
    let onFinish: () -> Void

    var body: some View {
        OnboardingPage {
            Text("You're in.")
                .font(OnboardingStyle.display())

            Text("\(Text(store.posts.count.formatted()).foregroundStyle(OnboardingStyle.accent)) saves, ready to resurface.")
                .font(.system(.title2, design: .rounded, weight: .heavy))

            HStack(spacing: 10) {
                ForEach(Platform.allCases) { platform in
                    VStack(spacing: 4) {
                        Image(systemName: platform.symbol).font(.system(size: 18, weight: .bold))
                        Text(store.count(for: platform).formatted())
                            .font(.system(.headline, design: .rounded, weight: .heavy))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(OnboardingStyle.surface, in: .rect(cornerRadius: 16))
                    .opacity(store.count(for: platform) > 0 ? 1 : 0.4)
                }
            }

            Text("A TASTE OF WHAT'S IN THERE")
                .font(.system(.caption, design: .rounded, weight: .heavy))
                .tracking(1.4)
                .foregroundStyle(OnboardingStyle.muted)
                .padding(.top, 4)

            ForEach(store.posts.prefix(4)) { post in
                SavedPostPreviewCard(post: post)
            }
        } actions: {
            Button("Open hindsight", action: onFinish)
                .buttonStyle(.onboardingPrimary)
        }
    }
}

/// Compact card for one saved post (used in onboarding previews).
struct SavedPostPreviewCard: View {
    let post: SavedPost

    var body: some View {
        Link(destination: post.url) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Image(systemName: post.platform.symbol)
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(OnboardingStyle.accent)
                    Text("@\(post.author)").font(.system(.subheadline, design: .rounded, weight: .bold))
                    Spacer()
                    Text(post.kind.rawValue)
                        .font(.system(.caption2, design: .rounded, weight: .heavy))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(OnboardingStyle.stroke, in: .capsule)
                    if let date = post.date {
                        Text(date, format: .dateTime.month(.abbreviated).day().year())
                            .font(OnboardingStyle.caption)
                            .foregroundStyle(OnboardingStyle.muted)
                    }
                }
                Text(post.caption ?? "No caption")
                    .font(OnboardingStyle.caption)
                    .foregroundStyle(post.caption == nil ? OnboardingStyle.muted : OnboardingStyle.text)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
            }
            .onboardingCard(padding: 14)
        }
        .buttonStyle(.plain)
    }
}

import SwiftUI

/// Opens a saved post in its own app (Instagram etc.), falling back to the browser.
/// ⚠️ In-app playback is the known gap (mvp-sprint.md → Video).
@MainActor
enum PostOpener {
    static func open(_ post: ContractPost, openURL: OpenURLAction) {
        openURL(post.url)
    }
}

/// A post's thumbnail, or a styled fallback tile (emoji / symbol on a dark tile).
/// Thumbnails aren't in the MVP data yet, so the fallback is what usually shows.
struct PostThumbnail: View {
    let post: ContractPost?
    var emoji: String?
    var symbol: String?
    var size: CGFloat = 56
    var cornerRadius: CGFloat = Theme.smallRadius

    var body: some View {
        ZStack {
            if let url = post?.thumbnailUrl {
                AsyncImage(url: url) { phase in
                    if let image = phase.image { image.resizable().scaledToFill() } else { fallback }
                }
            } else {
                fallback
            }
        }
        .frame(width: size, height: size)
        .clipShape(.rect(cornerRadius: cornerRadius))
        .overlay(RoundedRectangle(cornerRadius: cornerRadius).strokeBorder(Theme.stroke))
        .accessibilityHidden(true)
    }

    private var fallback: some View {
        ZStack {
            LinearGradient(colors: [Theme.surfaceRaised, Theme.surface], startPoint: .topLeading, endPoint: .bottomTrailing)
            if let emoji {
                Text(emoji).font(.system(size: size * 0.42))
            } else {
                Image(systemName: symbol ?? "play.rectangle.fill")
                    .font(.system(size: size * 0.34, weight: .semibold))
                    .foregroundStyle(Theme.secondary)
            }
        }
    }
}

/// A big hero tile that opens the post (detail sheets).
struct PostHero: View {
    let post: ContractPost
    var emoji: String?
    var symbol: String?
    var height: CGFloat = 190
    @Environment(\.openURL) private var openURL

    var body: some View {
        Button { PostOpener.open(post, openURL: openURL) } label: {
            ZStack(alignment: .bottomLeading) {
                LinearGradient(colors: [Theme.surfaceRaised, Theme.surface], startPoint: .topLeading, endPoint: .bottomTrailing)
                if let url = post.thumbnailUrl {
                    AsyncImage(url: url) { $0.resizable().scaledToFill() } placeholder: { Color.clear }
                } else if let emoji {
                    Text(emoji).font(.system(size: 64)).frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    Image(systemName: symbol ?? "play.rectangle.fill").font(.system(size: 48, weight: .semibold))
                        .foregroundStyle(Theme.secondary).frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                Label("Open in \(post.platform.displayName)", systemImage: "arrow.up.right")
                    .font(Theme.body(14, weight: .bold))
                    .foregroundStyle(Theme.text)
                    .padding(.horizontal, 12).padding(.vertical, 8)
                    .background(.black.opacity(0.55), in: Capsule())
                    .padding(12)
            }
            .frame(maxWidth: .infinity)
            .frame(height: height)
            .clipShape(.rect(cornerRadius: Theme.radius))
            .overlay(RoundedRectangle(cornerRadius: Theme.radius).strokeBorder(Theme.stroke))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Open the post in \(post.platform.displayName)")
    }
}

/// "@author · Instagram" byline.
struct PostByline: View {
    let post: ContractPost

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: post.platform.symbol).font(.system(size: 11, weight: .bold))
            Text(post.author.displayName ?? post.byline).lineLimit(1)
        }
        .font(Theme.body(13, weight: .semibold))
        .foregroundStyle(Theme.secondary)
    }
}

/// A collapsible original caption.
struct CaptionDisclosure: View {
    let caption: String?
    @State private var expanded = false

    var body: some View {
        if let caption {
            VStack(alignment: .leading, spacing: 8) {
                Button { withAnimation(.snappy) { expanded.toggle() } } label: {
                    HStack {
                        Text("Original caption").font(Theme.body(15, weight: .bold))
                        Spacer()
                        Image(systemName: expanded ? "chevron.up" : "chevron.down")
                    }
                    .foregroundStyle(Theme.secondary)
                }
                .buttonStyle(.plain)
                if expanded {
                    Text(caption).font(Theme.body(15)).foregroundStyle(Theme.secondary).textSelection(.enabled)
                }
            }
            .card(padding: 14)
        }
    }
}

/// Simple list row: thumbnail, first caption line, author (Everything else, search).
struct PostRow: View {
    let post: ContractPost
    var emoji: String?

    var body: some View {
        HStack(spacing: 12) {
            PostThumbnail(post: post, emoji: emoji, size: 52)
            VStack(alignment: .leading, spacing: 3) {
                Text(post.firstLine ?? "No caption").font(Theme.body(15, weight: .semibold)).lineLimit(2)
                PostByline(post: post)
            }
            Spacer(minLength: 0)
            Image(systemName: "arrow.up.right").foregroundStyle(Theme.muted)
        }
        .contentShape(.rect)
    }
}

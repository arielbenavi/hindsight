import SwiftUI

/// Search over saves: caption, author and hashtags (as Learn's search does).
enum SaveSearch {
    static func filter(_ posts: [ContractPost], query: String, platform: Platform? = nil) -> [ContractPost] {
        let terms = TextMatch.terms(query)
        return posts.filter { post in
            if let platform, post.platform != platform { return false }
            guard !terms.isEmpty else { return true }
            return TextMatch.score(terms: terms, fields: [(post.caption, 1), (post.author.username, 1), (post.author.displayName, 1),
                                                          (post.hashtags.joined(separator: " "), 1), (post.collections.joined(separator: " "), 1)]) > 0
        }
    }
}

/// Capsule search field used by Home, a topic and All saves.
struct SaveSearchField: View {
    @Binding var text: String
    var prompt = "Search your saves"
    var focused: FocusState<Bool>.Binding?

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass").foregroundStyle(Theme.muted)
            field
                .font(Theme.body(16))
                .autocorrectionDisabled()
                .submitLabel(.search)
            if !text.isEmpty {
                Button { text = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(Theme.muted) }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 13)
        .background(Theme.surface, in: Capsule())
        .overlay(Capsule().strokeBorder(Theme.stroke))
    }

    @ViewBuilder private var field: some View {
        if let focused {
            TextField(prompt, text: $text).focused(focused)
        } else {
            TextField(prompt, text: $text)
        }
    }
}

/// "All · Instagram 120 · X 40" chips. Hidden when the saves come from one platform.
struct PlatformFilterChips: View {
    let posts: [ContractPost]
    @Binding var selection: Platform?

    var body: some View {
        let counts = Dictionary(posts.map { ($0.platform, 1) }, uniquingKeysWith: +)
        let platforms = Platform.allCases.filter { counts[$0] != nil }
        if platforms.count > 1 {
            ScrollView(.horizontal) {
                HStack(spacing: 8) {
                    Chip(label: "All", isSelected: selection == nil) { withAnimation(.snappy) { selection = nil } }
                    ForEach(platforms) { platform in
                        Chip(label: platform.displayName, systemImage: platform.symbol, detail: counts[platform]?.formatted(),
                             isSelected: selection == platform) {
                            withAnimation(.snappy) { selection = selection == platform ? nil : platform }
                        }
                    }
                }
                .padding(.horizontal, Theme.padding)
            }
            .scrollIndicators(.hidden)
            .padding(.horizontal, -Theme.padding)
        }
    }
}

/// A save as a tappable card row that opens the post (All saves, a topic, Home).
struct SaveCardRow: View {
    let post: ContractPost
    @Environment(\.openURL) private var openURL

    var body: some View {
        Button { PostOpener.open(post, openURL: openURL) } label: {
            HStack(spacing: 14) {
                PostLinkThumbnail(post: post, size: 56)
                VStack(alignment: .leading, spacing: 5) {
                    Text(post.firstLine ?? "No caption")
                        .font(Theme.body(16, weight: .bold))
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    PostByline(post: post)
                }
                Spacer(minLength: 0)
            }
            .card(padding: 12)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }
}

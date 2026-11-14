import SwiftUI

/// The fallback when setup produced no tabs (nothing could be sorted, or reading
/// failed): every save in one searchable list, so the app never opens empty.
struct AllSavesScreen: View {
    let app: AppModel
    @State private var query = ""
    @Environment(\.openURL) private var openURL

    /// The sorted file if there is one, else the raw imports.
    private var posts: [ContractPost] { app.data?.posts ?? app.myPosts }

    var body: some View {
        let all = posts
        let terms = TextMatch.terms(query)
        let shown = terms.isEmpty ? all : all.filter { post in
            TextMatch.score(terms: terms, fields: [(post.caption, 1), (post.author.username, 1), (post.hashtags.joined(separator: " "), 1)]) > 0
        }
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 10) {
                ScreenHeader(title: "All saves", subtitle: "\(all.count.formatted()) saves. I couldn't sort these into tabs yet.") {
                    DevMenu(app: app)
                }
                .padding(.bottom, 6)
                searchField
                ForEach(shown) { post in
                    Button { PostOpener.open(post, openURL: openURL) } label: { row(post) }
                        .buttonStyle(.plain)
                }
                if shown.isEmpty {
                    Text(all.isEmpty ? "No saves yet." : "Nothing for \"\(query)\".")
                        .font(Theme.body(17, weight: .semibold))
                        .padding(.vertical, 8)
                }
            }
            .padding(Theme.padding)
        }
        .scrollIndicators(.hidden)
        .scrollDismissesKeyboard(.immediately)
    }

    private var searchField: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass").foregroundStyle(Theme.muted)
            TextField("Search your saves", text: $query)
                .font(Theme.body(16))
                .autocorrectionDisabled()
                .submitLabel(.search)
            if !query.isEmpty {
                Button { query = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(Theme.muted) }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 13)
        .background(Theme.surface, in: Capsule())
        .overlay(Capsule().strokeBorder(Theme.stroke))
    }

    /// Same shape as Learn's search rows.
    private func row(_ post: ContractPost) -> some View {
        HStack(spacing: 14) {
            PostLinkThumbnail(post: post, size: 60)
            VStack(alignment: .leading, spacing: 5) {
                Text(post.firstLine ?? "No caption")
                    .font(Theme.body(16, weight: .bold))
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                PostByline(post: post)
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right").font(.system(size: 13, weight: .bold)).foregroundStyle(Theme.muted)
        }
        .card(padding: 14)
        .contentShape(.rect)
    }
}

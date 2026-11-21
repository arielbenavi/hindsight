import SwiftUI

/// A save played inside hindsight: its own embed player on top, then who posted it,
/// our caption, and what to do with it (done, let go, the one useful destination).
/// "Open in <Platform>" stays in the top bar.
struct PlayerSheet: View {
    let app: AppModel
    let post: ContractPost
    let source: EmbedSource
    /// From Today: the answer goes to Today's set and the sheet closes. Elsewhere the
    /// buttons change the save's state, like the detail sheet.
    var onAnswer: ((TodayOutcome) -> Void)?
    @Environment(\.openURL) private var openURL
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let state = app.saves.state(post.id)
        let destination = Destinations.forToday(app.destinationInput(for: post, library: app.library()))
        NavigationStack {
            GeometryReader { geo in
                let size = PlayerLayout.playerSize(in: geo.size, tall: EmbedURL.isTall(post.url, platform: post.platform, kind: post.kind),
                                                   article: EmbedURL.isArticle(post.url, platform: post.platform))
                VStack(spacing: 0) {
                    EmbedPlayer(post: post, source: source)
                        .frame(width: size.width, height: size.height)
                        .clipShape(.rect(cornerRadius: Theme.smallRadius))
                        .frame(maxWidth: .infinity)
                    ScrollView {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("\(post.byline) · \(post.kind.rawValue)").font(Theme.body(16, weight: .heavy))
                            if let caption = post.caption?.nilIfEmpty {
                                Text(caption).font(Theme.body(15)).foregroundStyle(Theme.secondary).textSelection(.enabled)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, Theme.padding).padding(.vertical, 12)
                    }
                    .scrollIndicators(.automatic)
                    actions(state, destination: destination)
                        .padding(.horizontal, Theme.padding).padding(.vertical, 10)
                }
            }
            .themedScreen()
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close", systemImage: "xmark") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button { PostOpener.open(post, openURL: openURL) } label: {
                        Label("Open in \(post.platform.displayName)", systemImage: "arrow.up.right")
                            .labelStyle(.titleAndIcon)
                            .font(Theme.body(14, weight: .bold))
                    }
                    .accessibilityLabel("Open in \(post.platform.displayName)")
                }
            }
        }
        .tint(Theme.lime)
        .presentationDragIndicator(.visible)
        .onAppear { if onAnswer == nil { app.saves.recordOpen(post.id) } }
    }

    private func actions(_ state: SaveState, destination: Destination?) -> some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                Chip(label: "I did this", systemImage: "checkmark", isSelected: state.status == .done) {
                    if let onAnswer { onAnswer(.done); dismiss() } else { withAnimation(.snappy) { app.saves.toggleDone(post.id) } }
                }
                Chip(label: "Not interested", systemImage: "xmark", isSelected: state.status == .letGo) {
                    if let onAnswer { onAnswer(.letGo); dismiss() } else {
                        withAnimation(.snappy) { app.saves.setStatus(post.id, state.status == .letGo ? .new : .letGo) }
                    }
                }
                if let destination {
                    TodaySendAction(app: app, post: post, destination: destination) { _ in
                        if let onAnswer { onAnswer(.sent); dismiss() }
                    }
                }
            }
        }
        .scrollIndicators(.hidden)
        .scrollBounceBehavior(.basedOnSize, axes: .horizontal)
    }
}

/// How big the player is: reels and TikToks are 9:16, capped so the caption and
/// buttons still fit; posts and tweets get most of the sheet, articles a bit more.
enum PlayerLayout {
    static func playerSize(in space: CGSize, tall: Bool, article: Bool) -> CGSize {
        guard space.width > 0, space.height > 0 else { return .zero }
        if tall {
            let height = min(space.width * 16 / 9, space.height * 0.68)
            return CGSize(width: min(space.width, height * 9 / 16), height: height)
        }
        return CGSize(width: space.width, height: space.height * (article ? 0.74 : 0.62))
    }
}

/// Presents `PlayerSheet` for a save from anywhere that used to open it outside
/// (the Keep close shelf). `nil` source → the save opens in its own app.
extension View {
    func playerSheet(_ post: Binding<ContractPost?>, app: AppModel) -> some View {
        sheet(item: post) { post in
            if case .player(let source) = PlayerGate.choice(for: post, playInApp: true) {
                PlayerSheet(app: app, post: post, source: source)
            }
        }
    }
}

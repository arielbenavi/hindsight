import SwiftUI

/// A save's picture filling whatever frame it's given: its thumbnail, or a dark
/// tile with the platform's glyph (and, if asked, the caption's first words).
/// Thumbnails are rare in the data so far, so the tile is what usually shows.
struct SaveArt: View {
    let post: ContractPost
    var showsCaption = false
    var glyphSize: CGFloat = 52

    var body: some View {
        ZStack {
            tile
            if let url = post.thumbnailUrl {
                AsyncImage(url: url, transaction: Transaction(animation: .easeOut(duration: 0.2))) { phase in
                    if let image = phase.image { image.resizable().scaledToFill() } else { Color.clear }
                }
            }
        }
        .clipped()
        .accessibilityHidden(true)
    }

    private var tile: some View {
        ZStack(alignment: .bottomLeading) {
            LinearGradient(colors: [Theme.surfaceRaised, tint.opacity(0.35), Theme.surface],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
            PlatformGlyph(platform: post.platform, size: glyphSize)
                .clipShape(.rect(cornerRadius: glyphSize * 0.28))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            if showsCaption, let words = post.firstLine {
                Text(words)
                    .font(Theme.body(13, weight: .bold))
                    .foregroundStyle(Theme.text.opacity(0.85))
                    .lineLimit(3)
                    .padding(10)
            }
        }
    }

    /// A per-post hue, so a board of tiles isn't one flat color.
    private var tint: Color {
        let hues: [Color] = [Theme.violet, Color(hex: 0x2E7DFF), Color(hex: 0x1FB89A), Color(hex: 0xE0632E), Color(hex: 0xC94BC4)]
        return hues[Int(KeepClose.hash(post.id) % UInt64(hues.count))]
    }
}

// MARK: - Save detail, from anywhere in the Library

extension EnvironmentValues {
    /// Opens a save's detail sheet. Set by `saveDetailHost`; without it a row opens the post.
    @Entry var showSaveDetail: (@MainActor @Sendable (ContractPost) -> Void)? = nil
}

extension View {
    /// Rows below this show the save detail sheet when tapped.
    func saveDetailHost(app: AppModel) -> some View { modifier(SaveDetailHost(app: app)) }
}

private struct SaveDetailHost: ViewModifier {
    let app: AppModel
    @State private var post: ContractPost?

    func body(content: Content) -> some View {
        let binding = $post
        content
            .environment(\.showSaveDetail, { binding.wrappedValue = $0 })
            .sheet(item: $post) { SaveDetailSheet(app: app, post: $0) }
    }
}

/// Opens a save in its own app and counts the open.
@MainActor
enum SaveOpener {
    static func open(_ post: ContractPost, app: AppModel, openURL: OpenURLAction) {
        app.saves.recordOpen(post.id)
        PostOpener.open(post, openURL: openURL)
    }

    /// Plays it inside hindsight when it can (`PlayerGate`, Sources → Viewing), else
    /// opens it outside. `PlayerSheet` counts the open.
    static func playOrOpen(_ post: ContractPost, app: AppModel, openURL: OpenURLAction,
                           play: (ContractPost) -> Void) {
        if case .player = PlayerGate.choice(for: post) { play(post) } else { open(post, app: app, openURL: openURL) }
    }
}

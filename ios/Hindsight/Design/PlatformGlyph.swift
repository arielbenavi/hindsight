import SwiftUI

/// A drawn stand-in for a platform's logo, so a post tile reads as "this opens
/// Instagram" at a glance. Drawn, not bundled: we have no brand assets yet.
struct PlatformGlyph: View {
    let platform: Platform
    var size: CGFloat = 56

    var body: some View {
        ZStack {
            background
            mark
        }
        .frame(width: size, height: size)
        .accessibilityLabel(platform.displayName)
    }

    @ViewBuilder private var background: some View {
        switch platform {
        case .instagram:
            LinearGradient(colors: [Color(red: 0.99, green: 0.80, blue: 0.36), Color(red: 0.98, green: 0.24, blue: 0.40),
                                    Color(red: 0.74, green: 0.18, blue: 0.62), Color(red: 0.36, green: 0.29, blue: 0.85)],
                           startPoint: .bottomLeading, endPoint: .topTrailing)
        case .facebook: Color(red: 0.09, green: 0.47, blue: 0.95)
        case .x, .tiktok: Color.black
        }
    }

    @ViewBuilder private var mark: some View {
        let line = max(1.5, size * 0.06)
        switch platform {
        case .instagram:
            ZStack {
                RoundedRectangle(cornerRadius: size * 0.16).strokeBorder(.white, lineWidth: line)
                    .frame(width: size * 0.56, height: size * 0.56)
                Circle().strokeBorder(.white, lineWidth: line).frame(width: size * 0.25, height: size * 0.25)
                Circle().fill(.white).frame(width: line * 1.2, height: line * 1.2)
                    .offset(x: size * 0.15, y: -size * 0.15)
            }
        case .facebook:
            Text("f").font(.system(size: size * 0.62, weight: .heavy, design: .rounded)).foregroundStyle(.white)
                .offset(x: size * 0.04, y: size * 0.06)
        case .x:
            Text("𝕏").font(.system(size: size * 0.5, weight: .bold)).foregroundStyle(.white)
        case .tiktok:
            Image(systemName: "music.note").font(.system(size: size * 0.42, weight: .bold)).foregroundStyle(.white)
                .shadow(color: Color(red: 0.15, green: 0.96, blue: 0.93), radius: 0, x: -line * 0.6, y: -line * 0.4)
                .shadow(color: Color(red: 1.0, green: 0.17, blue: 0.33), radius: 0, x: line * 0.6, y: line * 0.4)
        }
    }
}

/// A tile that opens the original post: its thumbnail if we have one, else the
/// platform's glyph, with a small ↗ badge so it reads as a link.
struct PostLinkThumbnail: View {
    let post: ContractPost?
    var size: CGFloat = 64
    var cornerRadius: CGFloat = Theme.smallRadius

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            Group {
                if let url = post?.thumbnailUrl {
                    AsyncImage(url: url) { phase in
                        if let image = phase.image { image.resizable().scaledToFill() } else { glyph }
                    }
                } else {
                    glyph
                }
            }
            .frame(width: size, height: size)
            .clipShape(.rect(cornerRadius: cornerRadius))

            Image(systemName: "arrow.up.right")
                .font(.system(size: max(9, size * 0.16), weight: .heavy))
                .foregroundStyle(.white)
                .padding(max(3, size * 0.06))
                .background(.black.opacity(0.6), in: Circle())
                .padding(max(3, size * 0.05))
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Open in \(post?.platform.displayName ?? "the app")")
    }

    @ViewBuilder private var glyph: some View {
        if let post {
            PlatformGlyph(platform: post.platform, size: size)
        } else {
            Theme.surfaceRaised
        }
    }
}

#Preview {
    HStack {
        ForEach(Platform.allCases) { PlatformGlyph(platform: $0).clipShape(.rect(cornerRadius: 12)) }
    }
    .padding()
    .background(Theme.background)
}

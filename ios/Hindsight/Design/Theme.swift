import SwiftUI

/// The app's one design system: DailySpend's palette and type scale merged with
/// onboarding's cards, chips and spacing (`OnboardingStyle`, left untouched for now).
/// Dark, rounded, loud, after brrr.now.
enum Theme {
    static let background = Color(hex: 0x060A13)
    static let surface = Color(hex: 0x131729)
    static let surfaceRaised = Color(hex: 0x1C2038)
    static let stroke = Color.white.opacity(0.08)
    static let text = Color.white
    static let secondary = Color(hex: 0xB6B8C0)
    static let muted = Color(hex: 0x6E7385)
    static let lime = Color(hex: 0xA8F757)
    static let onLime = Color.black
    static let violet = Color(hex: 0x816DFF)
    static let red = Color(hex: 0xFF5C5C)

    static let padding: CGFloat = 20
    static let radius: CGFloat = 22
    static let smallRadius: CGFloat = 14

    /// Big numbers (rings, counts).
    static func number(_ size: CGFloat) -> Font {
        .system(size: size, weight: .black, design: .rounded)
    }

    /// Screen and card titles.
    static func title(_ size: CGFloat = 28) -> Font {
        .system(size: size, weight: .heavy, design: .rounded)
    }

    static func body(_ size: CGFloat = 17, weight: Font.Weight = .medium) -> Font {
        .system(size: size, weight: weight, design: .rounded)
    }

    static func label(_ size: CGFloat = 13) -> Font {
        .system(size: size, weight: .bold, design: .rounded)
    }
}

extension Color {
    init(hex: UInt32) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }
}

// MARK: - Buttons

/// Lime pill (primary), outlined pill (secondary) or a quiet text-only button.
struct PillButtonStyle: ButtonStyle {
    enum Kind { case primary, secondary, compact, compactPrimary }
    var kind: Kind = .primary

    func makeBody(configuration: Configuration) -> some View {
        let isPrimary = kind == .primary || kind == .compactPrimary
        let isCompact = kind == .compact || kind == .compactPrimary
        configuration.label
            .font(isCompact ? Theme.body(15, weight: .bold) : Theme.body(18, weight: .bold))
            .padding(.horizontal, isCompact ? 16 : 24)
            .padding(.vertical, isCompact ? 10 : 15)
            .frame(maxWidth: isCompact ? nil : .infinity)
            .foregroundStyle(isPrimary ? Theme.onLime : Theme.text)
            .background(isPrimary ? Theme.lime : Theme.surfaceRaised, in: Capsule())
            .overlay(Capsule().strokeBorder(isPrimary ? .clear : Theme.stroke, lineWidth: 1))
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(.spring(duration: 0.2), value: configuration.isPressed)
    }
}

extension ButtonStyle where Self == PillButtonStyle {
    static var pill: PillButtonStyle { PillButtonStyle() }
    static var pillSecondary: PillButtonStyle { PillButtonStyle(kind: .secondary) }
    static var pillCompact: PillButtonStyle { PillButtonStyle(kind: .compact) }
    static var pillCompactPrimary: PillButtonStyle { PillButtonStyle(kind: .compactPrimary) }
}

/// Round icon button (header actions, map floating buttons).
struct CircleIconButton: View {
    let systemImage: String
    var label: String
    var size: CGFloat = 44
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: size * 0.4, weight: .semibold))
                .foregroundStyle(Theme.text)
                .frame(width: size, height: size)
                .background(Theme.surface, in: Circle())
                .overlay(Circle().strokeBorder(Theme.stroke))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}

// MARK: - Cards and chips

extension View {
    /// Rounded dark card for rows, previews and practice cards.
    func card(padding: CGFloat = 18, background: Color = Theme.surface) -> some View {
        self.padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(background, in: .rect(cornerRadius: Theme.radius))
            .overlay(RoundedRectangle(cornerRadius: Theme.radius).strokeBorder(Theme.stroke))
    }

    /// Full-screen dark background used by every screen.
    func themedScreen() -> some View {
        self.background(Theme.background.ignoresSafeArea())
            .foregroundStyle(Theme.text)
            .preferredColorScheme(.dark)
    }
}

/// Selectable pill (filters, reply chips, setup choices).
struct Chip: View {
    let label: String
    var systemImage: String?
    var detail: String?
    var isSelected: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let systemImage { Image(systemName: systemImage) }
                Text(label)
                if let detail { Text(detail).opacity(0.6) }
            }
            .font(Theme.body(15, weight: .bold))
            .lineLimit(1)
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .foregroundStyle(isSelected ? Theme.onLime : Theme.text)
            .background(isSelected ? Theme.lime : Theme.surface, in: Capsule())
            .overlay(Capsule().strokeBorder(isSelected ? .clear : Theme.stroke))
        }
        .buttonStyle(.plain)
        .sensoryFeedback(.selection, trigger: isSelected)
    }
}

/// Small uppercase label, e.g. "SUGGESTED".
struct Tag: View {
    let text: String
    var color: Color = Theme.secondary

    var body: some View {
        Text(text.uppercased())
            .font(Theme.label(11))
            .tracking(0.6)
            .foregroundStyle(color)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(color.opacity(0.14), in: Capsule())
    }
}

/// Wrapping row of views (chip clouds).
struct WrapLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(width: proposal.width ?? .infinity, subviews: subviews)
        let height = rows.last.map { $0.y + $0.height } ?? 0
        let width = rows.map(\.width).max() ?? 0
        return CGSize(width: proposal.width ?? width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        for row in arrange(width: bounds.width, subviews: subviews) {
            var x = bounds.minX
            for index in row.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(at: CGPoint(x: x, y: bounds.minY + row.y), proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
        }
    }

    private struct Row { var indices: [Int] = []; var y: CGFloat = 0; var width: CGFloat = 0; var height: CGFloat = 0 }

    private func arrange(width: CGFloat, subviews: Subviews) -> [Row] {
        var rows: [Row] = [Row()]
        for (index, subview) in subviews.enumerated() {
            let size = subview.sizeThatFits(.unspecified)
            if !rows[rows.count - 1].indices.isEmpty, rows[rows.count - 1].width + spacing + size.width > width {
                let last = rows[rows.count - 1]
                rows.append(Row(y: last.y + last.height + spacing))
            }
            var row = rows[rows.count - 1]
            row.width += (row.indices.isEmpty ? 0 : spacing) + size.width
            row.height = max(row.height, size.height)
            row.indices.append(index)
            rows[rows.count - 1] = row
        }
        return rows
    }
}

// MARK: - Screen header

/// Big heavy screen title with trailing actions (every tab has the Everything else button).
struct ScreenHeader<Trailing: View>: View {
    let title: String
    var subtitle: String?
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(Theme.title(34))
                if let subtitle {
                    Text(subtitle).font(Theme.body(15)).foregroundStyle(Theme.secondary)
                }
            }
            Spacer()
            trailing
        }
    }
}

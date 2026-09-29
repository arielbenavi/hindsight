import SwiftUI

/// Every color, font and control style used by onboarding. brrr.now-ish:
/// black, huge heavy type, one loud accent. Reskin here, not in the steps.
enum OnboardingStyle {
    static let background = Color.black
    static let surface = Color(white: 0.1)
    static let raised = Color(white: 0.16)
    static let stroke = Color(white: 0.2)
    static let text = Color.white
    static let muted = Color(white: 0.6)
    static let accent = Color(red: 0.87, green: 1.0, blue: 0.3)
    static let onAccent = Color.black

    static func display(_ size: CGFloat = 46) -> Font {
        .system(size: size, weight: .black, design: .rounded)
    }
    static let title = Font.system(.title3, design: .rounded, weight: .bold)
    static let body = Font.system(.body, design: .rounded)
    static let caption = Font.system(.footnote, design: .rounded, weight: .medium)

    static let horizontalPadding: CGFloat = 24
    static let cornerRadius: CGFloat = 22
}

struct PrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(.headline, design: .rounded, weight: .heavy))
            .foregroundStyle(OnboardingStyle.onAccent)
            .frame(maxWidth: .infinity, minHeight: 56)
            .background(OnboardingStyle.accent, in: .capsule)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.snappy(duration: 0.15), value: configuration.isPressed)
    }
}

struct SecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(.subheadline, design: .rounded, weight: .bold))
            .foregroundStyle(OnboardingStyle.text)
            .frame(maxWidth: .infinity, minHeight: 48)
            .background(OnboardingStyle.raised, in: .capsule)
            .overlay(Capsule().stroke(OnboardingStyle.stroke))
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}

extension ButtonStyle where Self == PrimaryButtonStyle {
    static var onboardingPrimary: PrimaryButtonStyle { .init() }
}

extension ButtonStyle where Self == SecondaryButtonStyle {
    static var onboardingSecondary: SecondaryButtonStyle { .init() }
}

extension View {
    /// Rounded dark card used for rows and previews.
    func onboardingCard(padding: CGFloat = 18) -> some View {
        self.padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(OnboardingStyle.surface, in: .rect(cornerRadius: OnboardingStyle.cornerRadius))
            .overlay(RoundedRectangle(cornerRadius: OnboardingStyle.cornerRadius).stroke(OnboardingStyle.stroke))
    }
}

/// Selectable pill.
struct OnboardingChip: View {
    let label: String
    var detail: String?
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Text(label)
                if let detail {
                    Text(detail).opacity(0.6)
                }
            }
            .font(.system(.subheadline, design: .rounded, weight: .bold))
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .foregroundStyle(isSelected ? OnboardingStyle.onAccent : OnboardingStyle.text)
            .background(isSelected ? OnboardingStyle.accent : OnboardingStyle.surface, in: .capsule)
            .overlay(Capsule().stroke(isSelected ? .clear : OnboardingStyle.stroke))
        }
        .buttonStyle(.plain)
        .sensoryFeedback(.selection, trigger: isSelected)
    }
}

/// Shared layout for every step: scrolling content, CTA pinned to the bottom.
struct OnboardingPage<Content: View, Actions: View>: View {
    @ViewBuilder var content: Content
    @ViewBuilder var actions: Actions

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                content
            }
            .padding(.horizontal, OnboardingStyle.horizontalPadding)
            .padding(.top, 12)
            .padding(.bottom, 24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollBounceBehavior(.basedOnSize)
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 10) { actions }
                .padding(.horizontal, OnboardingStyle.horizontalPadding)
                .padding(.top, 12)
                .padding(.bottom, 8)
                .background(OnboardingStyle.background)
        }
    }
}

/// Round icon for a platform.
struct PlatformBadge: View {
    let platform: Platform

    var body: some View {
        Image(systemName: platform.symbol)
            .font(.system(size: 15, weight: .bold))
            .frame(width: 36, height: 36)
            .background(OnboardingStyle.stroke, in: .circle)
            .accessibilityLabel(platform.displayName)
    }
}

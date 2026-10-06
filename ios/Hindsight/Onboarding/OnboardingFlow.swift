import SwiftUI

/// First-run experience. Shown by `HindsightApp` until `onFinish` is called.
struct OnboardingFlow: View {
    let store: SavedPostStore
    let onFinish: (OnboardingChoice) -> Void
    @State private var model: OnboardingModel

    init(store: SavedPostStore, onFinish: @escaping (OnboardingChoice) -> Void) {
        self.store = store
        self.onFinish = onFinish
        _model = State(initialValue: OnboardingModel())
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Group {
                switch model.step {
                case .welcome: WelcomeStep(model: model)
                case .howItWorks: HowItWorksStep(model: model)
                case .connect: ConnectStep(model: model, store: store, onFinish: onFinish)
                }
            }
            .id(model.step)
            .transition(.asymmetric(
                insertion: .move(edge: model.isMovingForward ? .trailing : .leading).combined(with: .opacity),
                removal: .move(edge: model.isMovingForward ? .leading : .trailing).combined(with: .opacity)
            ))
            .frame(maxHeight: .infinity, alignment: .top)
        }
        .animation(.snappy(duration: 0.35), value: model.step)
        .foregroundStyle(OnboardingStyle.text)
        .background(OnboardingStyle.background.ignoresSafeArea())
        .preferredColorScheme(.dark)
        .tint(OnboardingStyle.accent)
    }

    @ViewBuilder private var header: some View {
        if OnboardingModel.Step.allCases.count > 1 { stepHeader } else { devSkip }
    }

    /// With a single screen there's no back button or step dots; just the dev Skip.
    private var devSkip: some View {
        HStack {
            Spacer()
            #if DEBUG
            Button("Skip") { onFinish(.sample) }
                .font(.system(.caption, design: .rounded, weight: .heavy))
                .foregroundStyle(OnboardingStyle.muted)
                .frame(minWidth: 36, minHeight: 36)
                .accessibilityLabel("Skip onboarding (dev)")
            #endif
        }
        .padding(.horizontal, OnboardingStyle.horizontalPadding - 8)
        .frame(minHeight: 8)
    }

    private var stepHeader: some View {
        HStack(spacing: 14) {
            Button(action: model.back) {
                Image(systemName: "chevron.left")
                    .font(.system(.headline, weight: .bold))
                    .frame(width: 36, height: 36)
                    .background(OnboardingStyle.surface, in: .circle)
            }
            .buttonStyle(.plain)
            .opacity(model.canGoBack ? 1 : 0)
            .disabled(!model.canGoBack)
            .accessibilityLabel("Back")

            HStack(spacing: 6) {
                ForEach(OnboardingModel.Step.allCases, id: \.self) { step in
                    Capsule()
                        .fill(step.rawValue <= model.step.rawValue ? OnboardingStyle.accent : OnboardingStyle.stroke)
                        .frame(height: 5)
                }
            }
            .accessibilityElement()
            .accessibilityLabel("Step \(model.step.rawValue + 1) of \(OnboardingModel.Step.allCases.count)")

            betaMenu
            #if DEBUG
            // Dev shortcut: straight to the app with the bundled seed data.
            Button("Skip") { onFinish(.sample) }
                .font(.system(.caption, design: .rounded, weight: .heavy))
                .foregroundStyle(OnboardingStyle.muted)
                .frame(minWidth: 36, minHeight: 36)
                .accessibilityLabel("Skip onboarding (dev)")
            #endif
        }
        .padding(.horizontal, OnboardingStyle.horizontalPadding - 8)
        .padding(.vertical, 8)
    }

    /// Beta menu, in every build while we're on TestFlight (temporary).
    private var betaMenu: some View {
        Menu {
            Button("Load seed saves", systemImage: "tray.and.arrow.down", action: loadSeed)
        } label: {
            Image(systemName: "ladybug").font(.system(size: 15, weight: .semibold))
                .foregroundStyle(OnboardingStyle.muted)
                .frame(width: 36, height: 36)
        }
        .accessibilityLabel("Beta menu")
    }

    /// Brings the bundled seed in as the user's own imports (the sort engine
    /// skips `.seedMD` records), then shows Connect with them counted.
    private func loadSeed() {
        let posts = SeedData.posts().map { post in
            var post = post
            post.source = .igExport
            return post
        }
        let added = store.merge(posts)
        DebugLog.write("beta menu: loaded seed → \(posts.count) posts, +\(added) new")
        while model.step != .connect { model.next() }
    }
}

#Preview {
    OnboardingFlow(store: SavedPostStore(fileURL: nil)) { _ in }
}

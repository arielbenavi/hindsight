import SwiftUI

/// The weekly ring, DailySpend style: lime fill, never red, never "broken".
struct WeeklyRing: View {
    let progress: WeeklyProgress
    var unit: String = "tries"
    var lineWidth: CGFloat = 14
    var size: CGFloat = 96

    var body: some View {
        HStack(spacing: 18) {
            ZStack {
                Circle().stroke(Theme.surfaceRaised, lineWidth: lineWidth)
                Circle()
                    .trim(from: 0, to: progress.fraction)
                    .stroke(Theme.lime, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .shadow(color: Theme.lime.opacity(0.4), radius: 10)
                Text("\(progress.filled)")
                    .font(Theme.number(34))
                    .contentTransition(.numericText(value: Double(progress.filled)))
            }
            .frame(width: size, height: size)
            VStack(alignment: .leading, spacing: 4) {
                Text("\(progress.filled) of \(progress.goal) \(unit) this week")
                    .font(Theme.title(20))
                Text(line).font(Theme.body(15)).foregroundStyle(Theme.secondary)
            }
            Spacer(minLength: 0)
        }
        .animation(.spring(duration: 0.6, bounce: 0.35), value: progress.filled)
        .accessibilityElement(children: .combine)
    }

    private var line: String {
        if progress.isComplete { return "Week done. Anything else is a bonus." }
        if progress.setupSegment && progress.done == 0 { return "Picked your saves ✓" }
        if progress.filled == 0 { return "Small is fine. One counts." }
        return "Nice. Keep it light."
    }
}

/// A small ring for history rows (L5).
struct MiniRing: View {
    let done: Int
    let goal: Int

    var body: some View {
        ZStack {
            Circle().stroke(Theme.surfaceRaised, lineWidth: 5)
            Circle().trim(from: 0, to: min(1, Double(done) / Double(max(goal, 1))))
                .stroke(Theme.lime, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .frame(width: 30, height: 30)
    }
}

/// "When?" chips: Tonight · Tomorrow · Weekend.
struct WhenChips: View {
    let onPick: (ReminderPolicy.When) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("When?").font(Theme.body(15, weight: .bold)).foregroundStyle(Theme.secondary)
            HStack(spacing: 8) {
                ForEach(ReminderPolicy.When.allCases) { when in
                    Chip(label: when.title) { onPick(when) }
                }
            }
        }
    }
}

/// Playful one-liners (DailySpend's voice). Never guilt.
enum PracticeQuip {
    static let tried = ["Look at you.", "That counts.", "Future you says thanks.", "Nice. Tiny steps."]
    static let doneForToday = ["Your future self says thanks.", "That's the day. Go live it.", "Done. No homework."]
    static let fitnessDone = ["Your spine sends its regards.", "Loose and happy.", "Body: thanked."]

    static func pick(_ list: [String], seed: String) -> String {
        var rng = SeededRandom(seed)
        return list[Int(rng.next() % UInt64(list.count))]
    }
}

/// The practice card (L2 / F2). Content-agnostic: Learn and Fitness fill the slots.
struct PracticeCardView<Details: View>: View {
    let title: String
    let post: ContractPost
    var emoji: String?
    var symbol: String?
    var subtitle: String?
    let prompt: String?
    /// "Suggested" label on AI-written prompts.
    var promptIsSuggested = true
    var primaryTitle: String
    var isReview = false
    var note: String?
    var openReelIsProminent = false
    @ViewBuilder var details: Details
    let onPrimary: () -> Void
    let onNotToday: (ReminderPolicy.When) -> Void
    let onNotForMe: () -> Void
    var onReviewYep: (() -> Void)?
    var onTap: (() -> Void)?

    @State private var askingWhen = false
    @Environment(\.openURL) private var openURL

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            if let prompt {
                VStack(alignment: .leading, spacing: 8) {
                    if promptIsSuggested && !isReview { Tag(text: "Suggested", color: Theme.lime) }
                    Text(prompt).font(Theme.title(22)).fixedSize(horizontal: false, vertical: true)
                }
            }
            details
            if let note {
                Label(note, systemImage: "heart.text.square").font(Theme.body(14)).foregroundStyle(Theme.secondary)
            }
            if askingWhen {
                WhenChips { when in
                    withAnimation(.snappy) { askingWhen = false }
                    onNotToday(when)
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
            } else {
                actions
            }
        }
        .card(padding: 20)
        .animation(.snappy, value: askingWhen)
    }

    private var header: some View {
        Button { onTap?() } label: {
            HStack(spacing: 14) {
                PostThumbnail(post: post, emoji: emoji, symbol: symbol, size: 64)
                VStack(alignment: .leading, spacing: 4) {
                    Text(title).font(Theme.title(19)).lineLimit(2).multilineTextAlignment(.leading)
                    if let subtitle { Text(subtitle).font(Theme.body(14)).foregroundStyle(Theme.secondary).lineLimit(1) }
                    PostByline(post: post)
                }
                Spacer(minLength: 0)
            }
        }
        .buttonStyle(.plain)
        .disabled(onTap == nil)
    }

    @ViewBuilder private var actions: some View {
        VStack(spacing: 10) {
            if isReview, let onReviewYep {
                HStack(spacing: 10) {
                    Button("Yep", action: onReviewYep).buttonStyle(.pill)
                    Button("Try again", action: onPrimary).buttonStyle(.pillSecondary)
                }
            } else {
                if openReelIsProminent {
                    Button { PostOpener.open(post, openURL: openURL) } label: {
                        Label("Open reel", systemImage: "arrow.up.right")
                    }
                    .buttonStyle(.pillSecondary)
                }
                Button(primaryTitle, action: onPrimary).buttonStyle(.pill)
                    .sensoryFeedback(.success, trigger: primaryTitle)
            }
            HStack {
                Button("Not today") { withAnimation(.snappy) { askingWhen = true } }
                Spacer()
                if !openReelIsProminent {
                    Button { PostOpener.open(post, openURL: openURL) } label: {
                        Label("Open the reel", systemImage: "arrow.up.right")
                    }
                    Spacer()
                }
                Button("Not for me", action: onNotForMe)
            }
            .font(Theme.body(14, weight: .semibold))
            .foregroundStyle(Theme.secondary)
            .buttonStyle(.plain)
            .padding(.horizontal, 4)
        }
    }
}

/// A handled card, collapsed ("✓ Box-shift trick", "Tonight ⏰").
struct HandledRow: View {
    let title: String
    let handling: Handling

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon).foregroundStyle(Theme.lime)
            Text(title).font(Theme.body(16, weight: .semibold)).lineLimit(1)
            Spacer()
            Text(label).font(Theme.body(14)).foregroundStyle(Theme.secondary)
        }
        .card(padding: 14)
    }

    private var icon: String {
        switch handling {
        case .tried, .reviewed: "checkmark.circle.fill"
        case .reminded: "alarm.fill"
        case .archived: "xmark.circle"
        }
    }

    private var label: String {
        switch handling {
        case .tried: "Done"
        case .reviewed: "Still got it"
        case .reminded(let date): Calendar.current.isDateInToday(date) ? "Tonight" : date.formatted(.dateTime.weekday(.wide))
        case .archived: "Not for me"
        }
    }
}

/// "Done for today." + a one-liner + a quiet "One more?".
struct DoneForToday: View {
    let quip: String
    var canDoMore: Bool
    let onOneMore: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Done for today.").font(Theme.title(24))
            Text(quip).font(Theme.body(16)).foregroundStyle(Theme.secondary)
            if canDoMore {
                Button("One more?", action: onOneMore)
                    .font(Theme.body(15, weight: .bold))
                    .foregroundStyle(Theme.lime)
                    .buttonStyle(.plain)
                    .padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 6)
    }
}

/// A card you can swipe right (yes) or left (no), with buttons as the equivalent.
/// Shared by Learn/Fitness setup and the place confirmation cards.
struct SwipeCard<Content: View>: View {
    let onRight: () -> Void
    let onLeft: () -> Void
    @ViewBuilder var content: Content

    @State private var offset: CGSize = .zero
    private let threshold: CGFloat = 110

    var body: some View {
        content
            .overlay(alignment: .topLeading) { stamp("YES", color: Theme.lime, visible: offset.width > 30).padding(20) }
            .overlay(alignment: .topTrailing) { stamp("NOPE", color: Theme.red, visible: offset.width < -30).padding(20) }
            .offset(x: offset.width, y: offset.height * 0.2)
            .rotationEffect(.degrees(Double(offset.width / 22)))
            .gesture(
                DragGesture()
                    .onChanged { offset = $0.translation }
                    .onEnded { value in
                        if value.translation.width > threshold {
                            fling(1, then: onRight)
                        } else if value.translation.width < -threshold {
                            fling(-1, then: onLeft)
                        } else {
                            withAnimation(.spring(duration: 0.35)) { offset = .zero }
                        }
                    }
            )
    }

    private func fling(_ direction: CGFloat, then action: @escaping () -> Void) {
        withAnimation(.easeIn(duration: 0.2)) { offset = CGSize(width: direction * 600, height: offset.height) }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(200))
            action()
            offset = .zero
        }
    }

    private func stamp(_ text: String, color: Color, visible: Bool) -> some View {
        Text(text).font(Theme.number(28)).foregroundStyle(color)
            .padding(.horizontal, 10).padding(.vertical, 4)
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(color, lineWidth: 3))
            .rotationEffect(.degrees(text == "YES" ? -12 : 12))
            .opacity(visible ? min(1, abs(offset.width) / threshold) : 0)
    }
}

/// Small undo toast, shown for 3 seconds after an action.
struct UndoToast: View {
    let message: String
    let onUndo: () -> Void

    var body: some View {
        HStack {
            Text(message).font(Theme.body(15, weight: .semibold))
            Spacer()
            Button("Undo", action: onUndo).font(Theme.body(15, weight: .heavy)).foregroundStyle(Theme.lime)
        }
        .padding(.horizontal, 18).padding(.vertical, 14)
        .background(Theme.surfaceRaised, in: Capsule())
        .overlay(Capsule().strokeBorder(Theme.stroke))
        .padding(.horizontal, Theme.padding)
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }
}

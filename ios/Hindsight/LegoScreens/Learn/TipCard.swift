import SwiftUI

/// The small tip card used in L1 section rows (`.tile`) and L3 / L6 lists (`.row`).
/// Thumbnail (fallback: the topic emoji on a dark tile), title, and the tip type or "Tried ✓".
struct TipCard: View {
    enum Style { case tile, row }

    let tip: Tip
    let emoji: String
    let state: PracticeState
    var style: Style = .tile
    /// Rows in search results also name the topic.
    var topicLabel: String?

    var body: some View {
        switch style {
        case .tile: tile
        case .row: row
        }
    }

    private var tile: some View {
        VStack(alignment: .leading, spacing: 10) {
            PostThumbnail(post: tip.post, emoji: emoji, size: 136, cornerRadius: Theme.smallRadius)
            Text(tip.title)
                .font(Theme.body(15, weight: .bold))
                .lineLimit(2, reservesSpace: true)
                .multilineTextAlignment(.leading)
            badge
        }
        .frame(width: 136, alignment: .leading)
        .padding(12)
        .background(Theme.surface, in: .rect(cornerRadius: Theme.radius))
        .overlay(RoundedRectangle(cornerRadius: Theme.radius).strokeBorder(Theme.stroke))
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
    }

    private var row: some View {
        HStack(spacing: 14) {
            PostThumbnail(post: tip.post, emoji: emoji, size: 60)
            VStack(alignment: .leading, spacing: 5) {
                Text(tip.title)
                    .font(Theme.body(16, weight: .bold))
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                HStack(spacing: 8) {
                    badge
                    if let topicLabel {
                        Text(topicLabel).font(Theme.body(13)).foregroundStyle(Theme.muted).lineLimit(1)
                    }
                }
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right").font(.system(size: 13, weight: .bold)).foregroundStyle(Theme.muted)
        }
        .card(padding: 12)
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder private var badge: some View {
        switch LearnStatus.kind(state) {
        case .tried: Tag(text: "Tried ✓", color: Theme.lime)
        case .archived: Tag(text: "Not for me", color: Theme.muted)
        case .notTried:
            if tip.isGated { Tag(text: "Behind a DM", color: Theme.violet) } else { Tag(text: tip.type.title, color: Theme.secondary) }
        }
    }
}

extension TipType {
    var title: String {
        switch self {
        case .tool: "Tool"
        case .technique: "Technique"
        case .tutorial: "Tutorial"
        case .list: "List"
        case .idea: "Idea"
        }
    }
}

/// Status wording and filters shared by the Learn screens. Pure.
enum LearnStatus {
    enum Kind { case notTried, tried, archived }

    static func kind(_ state: PracticeState) -> Kind {
        if state.status == .archived { return .archived }
        if state.status == .tried || !state.triedAt.isEmpty { return .tried }
        return .notTried
    }

    static func isTried(_ state: PracticeState) -> Bool { !state.triedAt.isEmpty }

    /// Passed at least one "Still got it?" review.
    static func stillGotIt(_ state: PracticeState) -> Bool { state.status == .tried && state.reviewStep >= 2 }

    static func times(_ n: Int) -> String {
        switch n {
        case 1: "once"
        case 2: "twice"
        default: "\(n) times"
        }
    }

    /// "Tried twice · next review in 8 days", "Not tried yet", "Reminder: Tomorrow".
    static func line(_ state: PracticeState, now: Date = .now, calendar: Calendar = .current) -> String {
        var parts: [String] = []
        if state.status == .archived {
            parts.append("Not for me")
        } else if state.triedAt.isEmpty {
            parts.append("Not tried yet")
        } else {
            parts.append("Tried \(times(state.triedAt.count))")
            if let next = state.nextReviewAt {
                let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: now),
                                                   to: calendar.startOfDay(for: next)).day ?? 0
                parts.append(days <= 0 ? "review due today" : days == 1 ? "next review tomorrow" : "next review in \(days) days")
            }
        }
        if state.status != .archived, let remind = state.remindAt, remind > now {
            parts.append("reminder \(reminderDay(remind, now: now, calendar: calendar))")
        }
        return parts.joined(separator: " · ")
    }

    /// "tonight", "tomorrow", "Saturday".
    static func reminderDay(_ date: Date, now: Date = .now, calendar: Calendar = .current) -> String {
        if calendar.isDate(date, inSameDayAs: now) { return "tonight" }
        if let tomorrow = calendar.date(byAdding: .day, value: 1, to: now), calendar.isDate(date, inSameDayAs: tomorrow) {
            return "tomorrow"
        }
        return date.formatted(.dateTime.weekday(.wide))
    }

    /// Newest saved first (undated last).
    static func newestFirst(_ tips: [Tip]) -> [Tip] {
        tips.enumerated().sorted { a, b in
            switch (a.element.post.savedDate, b.element.post.savedDate) {
            case let (x?, y?): x == y ? a.offset < b.offset : x > y
            case (_?, nil): true
            case (nil, _?): false
            case (nil, nil): a.offset < b.offset
            }
        }
        .map(\.element)
    }
}

#if DEBUG
/// Preview helper: Ariel's seed with the proposed layout approved, in memory.
@MainActor
enum LearnPreview {
    static func app(setupDone: Bool = true) -> AppModel {
        let app = AppModel(datasets: Dataset.bundled(), selected: "ariel", persist: false)
        if let data = app.data { app.approve(LayoutRules.propose(data).draft.config()) }
        if setupDone { app.practice.skipSetup(.learn) }
        return app
    }

    static func tab(_ app: AppModel) -> TabConfig {
        app.layout?.tab(for: .learn) ?? TabConfig(legoScreen: .learn, topicIDs: [])
    }
}

#Preview("Tip cards") {
    let app = LearnPreview.app()
    let section = app.learn?.sections.first
    ScrollView {
        VStack(alignment: .leading, spacing: 16) {
            ScrollView(.horizontal) {
                HStack {
                    ForEach(section?.tips.prefix(4) ?? []) { tip in
                        TipCard(tip: tip, emoji: section?.emoji ?? "📚", state: PracticeState())
                    }
                }
            }
            ForEach(section?.tips.prefix(3) ?? []) { tip in
                TipCard(tip: tip, emoji: section?.emoji ?? "📚", state: PracticeState(status: .tried, triedAt: [.now]), style: .row)
            }
        }
        .padding()
    }
    .themedScreen()
}
#endif

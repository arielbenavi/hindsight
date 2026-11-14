import SwiftUI

/// L3: one topic's tips, newest saved first, with filter chips.
struct LearnTopicView: View {
    let app: AppModel
    let section: LearnSection

    enum Filter: String, CaseIterable, Identifiable {
        case all = "All", notTried = "Not tried", tried = "Tried", notForMe = "Not for me"
        var id: String { rawValue }
    }

    @State private var filter: Filter = .all
    @State private var detail: Tip?

    private var practice: PracticeStore { app.practice }

    var body: some View {
        let states = section.tips.map { practice.state(.learn, $0.id) }
        let tried = states.count(where: LearnStatus.isTried)
        let shown = LearnStatus.newestFirst(section.tips).filter { matches(practice.state(.learn, $0.id)) }

        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(section.emoji) \(section.title)").font(Theme.title(32))
                    Text("\(tried) tried of \(section.tips.count)").font(Theme.body(16)).foregroundStyle(Theme.secondary)
                }
                ScrollView(.horizontal) {
                    HStack(spacing: 8) {
                        ForEach(Filter.allCases) { f in
                            Chip(label: f.rawValue, isSelected: filter == f) { withAnimation(.snappy) { filter = f } }
                        }
                    }
                }
                .scrollIndicators(.hidden)

                if shown.isEmpty {
                    Text(emptyLine)
                        .font(Theme.body(16)).foregroundStyle(Theme.secondary)
                        .padding(.vertical, 24)
                        .frame(maxWidth: .infinity)
                } else {
                    LazyVStack(spacing: 10) {
                        ForEach(shown) { tip in
                            Button { detail = tip } label: {
                                TipCard(tip: tip, emoji: section.emoji, state: practice.state(.learn, tip.id), style: .row)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .padding(Theme.padding)
        }
        .scrollIndicators(.hidden)
        .themedScreen()
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $detail) { TipDetailSheet(app: app, tip: $0) }
    }

    private func matches(_ state: PracticeState) -> Bool {
        switch filter {
        case .all: true
        case .notTried: LearnStatus.kind(state) == .notTried
        case .tried: LearnStatus.kind(state) == .tried
        case .notForMe: LearnStatus.kind(state) == .archived
        }
    }

    private var emptyLine: String {
        switch filter {
        case .all: "Nothing here yet."
        case .notTried: "You've tried every one. Look at you."
        case .tried: "Nothing tried here yet. One counts."
        case .notForMe: "Nothing set aside."
        }
    }
}

#if DEBUG
#Preview("Topic") {
    let app = LearnPreview.app()
    NavigationStack {
        if let section = app.learn?.sections.first { LearnTopicView(app: app, section: section) }
    }
}
#endif

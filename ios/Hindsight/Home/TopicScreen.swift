import SwiftUI

/// One topic's saves: search, platform filter, and the view that fits it
/// ("Open map") when there is one. Pushed from Home.
struct TopicScreen: View {
    let app: AppModel
    let topic: HomeTopic
    @State private var query = ""
    @State private var platform: Platform?

    var body: some View {
        let byID = Dictionary(app.allPosts.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let all = topic.postIDs.compactMap { byID[$0] }
        let shown = SaveSearch.filter(all, query: query, platform: platform)
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .center, spacing: 14) {
                    TopicIcon(topic: topic, size: 52)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(topic.label).font(Theme.title(30)).lineLimit(2).minimumScaleFactor(0.7)
                        Text(kindLine(all.count)).font(Theme.body(15)).foregroundStyle(Theme.secondary)
                    }
                    Spacer(minLength: 0)
                }
                .padding(.bottom, 6)
                if let screen = topic.legoScreen {
                    NavigationLink(value: HomeRoute.lego(screen, topicID: topic.topicID)) {
                        Label(screen.openTitle, systemImage: screen.symbol)
                    }
                    .buttonStyle(.pill)
                    .padding(.bottom, 4)
                }
                SaveSearchField(text: $query, prompt: "Search \(topic.label)")
                PlatformFilterChips(posts: all, selection: $platform)
                ForEach(shown) { SaveCardRow(post: $0) }
                if shown.isEmpty {
                    Text(query.isEmpty ? "Nothing here yet." : "Nothing for \"\(query)\".")
                        .font(Theme.body(17, weight: .semibold))
                        .padding(.vertical, 8)
                }
            }
            .padding(Theme.padding)
        }
        .scrollIndicators(.hidden)
        .scrollDismissesKeyboard(.immediately)
        .themedScreen()
        .navigationBarTitleDisplayMode(.inline)
    }

    private func kindLine(_ count: Int) -> String {
        let saves = "\(count.formatted()) \(count == 1 ? "save" : "saves")"
        switch topic.kind {
        case .ai: return saves
        case .collection: return "\(saves) · your collection"
        case .other: return "\(saves) · small topics and collections"
        }
    }
}

/// A topic's emoji on a device; its SF Symbol in the simulator, which can't draw emoji (LESSONS.md).
struct TopicIcon: View {
    let topic: HomeTopic
    var size: CGFloat = 36

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.3).fill(Theme.surfaceRaised)
            #if targetEnvironment(simulator)
            symbol
            #else
            if let emoji = topic.emoji { Text(emoji).font(.system(size: size * 0.5)) } else { symbol }
            #endif
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }

    private var symbol: some View {
        Image(systemName: topic.symbol)
            .font(.system(size: size * 0.4, weight: .bold))
            .foregroundStyle(topic.kind == .ai ? Theme.lime : Theme.secondary)
    }
}

extension LegoScreen {
    /// Home's names for the views: Places, Tips, Workouts.
    var homeTitle: String {
        switch self {
        case .map: "Places"
        case .learn: "Tips"
        case .fitness: "Workouts"
        }
    }

    var openTitle: String {
        switch self {
        case .map: "Open map"
        case .learn: "Open tips"
        case .fitness: "Open workouts"
        }
    }
}

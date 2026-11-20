import SwiftUI

/// Every save in one searchable list, newest first ("See all" on Home, and
/// "Search all saves" from Learn and Fitness).
struct AllSavesScreen: View {
    let app: AppModel
    var initialQuery = ""
    @State private var query = ""
    @State private var platform: Platform?

    var body: some View {
        // Let-go saves only come back through search.
        let all = query.isEmpty ? app.saves.visible(app.allPosts) : app.allPosts
        let shown = SaveSearch.filter(all, query: query, platform: platform)
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 10) {
                ScreenHeader(title: "All saves", subtitle: subtitle(all: all.count, shown: shown.count)) { EmptyView() }
                    .padding(.bottom, 6)
                SaveSearchField(text: $query)
                PlatformFilterChips(posts: all, selection: $platform)
                ForEach(shown) { SaveCardRow(post: $0, app: app) }
                if shown.isEmpty {
                    Text(all.isEmpty ? "No saves yet." : query.isEmpty ? "Nothing from there." : "Nothing for \"\(query)\".")
                        .font(Theme.body(17, weight: .semibold))
                        .padding(.vertical, 8)
                }
            }
            .padding(Theme.padding)
        }
        .scrollIndicators(.hidden)
        .scrollDismissesKeyboard(.immediately)
        .themedScreen()
        .pushedScreen()
        .onAppear { if query.isEmpty { query = initialQuery } }
    }

    private func subtitle(all: Int, shown: Int) -> String {
        shown == all ? "\(all.counted("save")), newest first." : "\(shown.formatted()) of \(all.counted("save"))."
    }
}

/// All saves in a sheet, already searched ("Search all saves" when Learn or
/// Fitness has nothing for a query).
struct AllSavesSheet: View {
    let app: AppModel
    var initialQuery = ""
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            AllSavesScreen(app: app, initialQuery: initialQuery)
                .saveDetailHost(app: app)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
        .presentationDragIndicator(.visible)
        .tint(Theme.lime)
    }
}

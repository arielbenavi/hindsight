import SwiftUI

/// The Ask tab, for now a focused search: "What were you looking for?", one big
/// field, results that say why they matched, and ready-made questions while the
/// field is empty. No AI calls.
struct AskScreen: View {
    let app: AppModel
    @State private var query = ""
    @State private var filter: AskFilter?

    var body: some View {
        let posts = app.allPosts
        let library = app.library()
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text("What were you looking for?")
                        .font(Theme.title(32))
                        .fixedSize(horizontal: false, vertical: true)
                    field
                    if query.isEmpty {
                        suggestions
                        if let filter { filtered(filter, posts: posts) }
                    } else {
                        results(posts, library: library)
                    }
                }
                .padding(Theme.padding)
                .padding(.bottom, 24)
            }
            .scrollIndicators(.hidden)
            .scrollDismissesKeyboard(.immediately) .statusBarStrip()
            .themedScreen()
            .toolbar(.hidden, for: .navigationBar)
        }
        .saveDetailHost(app: app)
    }

    private var field: some View {
        HStack(spacing: 12) {
            Image(systemName: "magnifyingglass").font(.system(size: 20, weight: .bold)).foregroundStyle(Theme.lime)
            TextField("A word, a person, a place…", text: $query)
                .font(Theme.body(19, weight: .semibold))
                .autocorrectionDisabled()
                .submitLabel(.search)
            if !query.isEmpty {
                Button { query = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(Theme.muted) }
                    .buttonStyle(.plain)
                    .frame(minWidth: 44, minHeight: 44)
                    .accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, 18)
        .frame(minHeight: 60)
        .background(Theme.surface, in: .rect(cornerRadius: Theme.radius))
        .overlay(RoundedRectangle(cornerRadius: Theme.radius).strokeBorder(Theme.lime.opacity(0.35), lineWidth: 1.5))
    }

    private var suggestions: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionLabel(text: "OR TRY")
            WrapLayout(spacing: 8) {
                ForEach(AskFilter.allCases) { item in
                    Chip(label: item.title, systemImage: item.symbol, isSelected: filter == item) {
                        withAnimation(.snappy) { filter = filter == item ? nil : item }
                    }
                }
            }
        }
    }

    @ViewBuilder private func filtered(_ filter: AskFilter, posts: [ContractPost]) -> some View {
        let shown = filter.apply(posts, states: app.saves.states, now: .now)
        VStack(alignment: .leading, spacing: 10) {
            SectionLabel(text: "\(filter.title.uppercased()) · \(shown.count.formatted())")
            if shown.isEmpty {
                Text("Nothing yet.").font(Theme.body(17, weight: .semibold)).foregroundStyle(Theme.secondary)
            }
            LazyVStack(spacing: 10) {
                ForEach(shown.prefix(200)) { SaveCardRow(post: $0, app: app) }
            }
        }
    }

    @ViewBuilder private func results(_ posts: [ContractPost], library: LibraryIndex) -> some View {
        let found = AskSearch.results(query, posts: posts, states: app.saves.states,
                                      topicLabel: { library.topicByPost[$0]?.label })
        VStack(alignment: .leading, spacing: 10) {
            SectionLabel(text: "\(found.count.formatted()) \(found.count == 1 ? "MATCH" : "MATCHES")")
            if found.isEmpty {
                Text("Nothing for \"\(query)\".").font(Theme.body(17, weight: .semibold))
            }
            LazyVStack(spacing: 10) {
                ForEach(found.prefix(200)) { result in
                    VStack(alignment: .leading, spacing: 6) {
                        if result.matchedTopic != nil || result.matchedNote {
                            HStack(spacing: 6) {
                                if let topic = result.matchedTopic { Tag(text: "Topic: \(topic)", color: Theme.lime) }
                                if result.matchedNote { Tag(text: "Your note", color: Theme.violet) }
                            }
                        }
                        SaveCardRow(post: result.post, app: app)
                    }
                }
            }
        }
    }
}

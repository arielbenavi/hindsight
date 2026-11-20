import SwiftUI

// MARK: - Do: a checklist

/// A Do topic: progress, To do / Done filter, rows with a round check, done ones
/// struck through at the bottom, and "Pick one for tonight".
struct DoListScreen: View {
    let app: AppModel
    let topic: HomeTopic
    @State private var filter: SaveStatus?
    @State private var pickRound = 0
    @Environment(\.showSaveDetail) private var showDetail

    var body: some View {
        let posts = app.posts(in: topic)
        let list = DoList.ordered(posts, states: app.saves.states)
        let progress = DoList.progress(posts, states: app.saves.states)
        let shown: [ContractPost] = switch filter {
        case .new?: list.todo
        case .done?: list.done
        default: list.todo + list.done
        }
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 12) {
                TopicTitle(topic: topic, line: "A list to work through")
                VStack(alignment: .leading, spacing: 8) {
                    Text("\(progress.done.formatted()) of \(progress.total.formatted()) done")
                        .font(Theme.body(15, weight: .bold)).foregroundStyle(Theme.secondary)
                        .contentTransition(.numericText(value: Double(progress.done)))
                    ProgressBar(value: progress.total == 0 ? 0 : Double(progress.done) / Double(progress.total))
                }
                .padding(.vertical, 4)
                HStack(spacing: 8) {
                    Chip(label: "To do", detail: list.todo.count.formatted(), isSelected: filter == .new) { toggle(.new) }
                    Chip(label: "Done", detail: list.done.count.formatted(), isSelected: filter == .done) { toggle(.done) }
                }
                ForEach(shown) { post in
                    DoRow(post: post, done: app.saves.status(post.id) == .done) {
                        withAnimation(.snappy) { app.saves.toggleDone(post.id) }
                    } open: { showDetail?(post) }
                }
                if shown.isEmpty {
                    Text(filter == .done ? "Nothing done yet." : "All done. Nice.")
                        .font(Theme.body(17, weight: .semibold)).padding(.vertical, 8)
                }
            }
            .padding(Theme.padding)
            .padding(.bottom, 80)
        }
        .scrollIndicators(.hidden)
        .safeAreaInset(edge: .bottom) {
            if !list.todo.isEmpty {
                Button {
                    pickRound += 1
                    let seed = "\(TodayPicker.dayKey(.now))|\(topic.id)|\(pickRound)"
                    if let pick = DoList.pickOne(list.todo, seed: seed) { showDetail?(pick) }
                } label: {
                    Label("Pick one for tonight", systemImage: "dice.fill")
                }
                .buttonStyle(.pill)
                .padding(.horizontal, Theme.padding)
                .padding(.bottom, 8)
            }
        }
        .sensoryFeedback(.success, trigger: progress.done)
        .themedScreen()
        .pushedScreen()
        .topicJobMenu(app: app, topic: topic)
    }

    private func toggle(_ status: SaveStatus) {
        withAnimation(.snappy) { filter = filter == status ? nil : status }
    }
}

private struct DoRow: View {
    let post: ContractPost
    let done: Bool
    let toggle: () -> Void
    let open: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Button(action: toggle) {
                Image(systemName: done ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundStyle(done ? Theme.lime : Theme.muted)
                    .frame(width: 44, height: 44)
                    .contentShape(.circle)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(done ? "Mark as not done" : "Mark as done")
            Button(action: open) {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(post.firstLine ?? "No caption")
                            .font(Theme.body(16, weight: .bold))
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                            .strikethrough(done, color: Theme.muted)
                            .foregroundStyle(done ? Theme.muted : Theme.text)
                        PostByline(post: post)
                    }
                    Spacer(minLength: 0)
                    SaveArt(post: post, glyphSize: 26)
                        .frame(width: 52, height: 52)
                        .clipShape(.rect(cornerRadius: Theme.smallRadius))
                        .opacity(done ? 0.5 : 1)
                }
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 8).padding(.leading, 4).padding(.trailing, 10)
        .background(Theme.surface, in: .rect(cornerRadius: Theme.radius))
        .overlay(RoundedRectangle(cornerRadius: Theme.radius).strokeBorder(Theme.stroke))
    }
}

/// A rounded progress bar.
struct ProgressBar: View {
    let value: Double
    var tint: Color = Theme.lime

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.surfaceRaised)
                Capsule().fill(tint).frame(width: max(value > 0 ? 8 : 0, geo.size.width * min(1, value)))
            }
        }
        .frame(height: 8)
        .animation(.snappy, value: value)
        .accessibilityElement()
        .accessibilityValue("\(Int(value * 100)) percent")
    }
}

// MARK: - Look: a picture board

/// A Look topic: two columns of tiles to browse; tap for the save.
struct LookBoardScreen: View {
    let app: AppModel
    let topic: HomeTopic
    @Environment(\.showSaveDetail) private var showDetail

    var body: some View {
        let posts = app.posts(in: topic)
        let columns = LookBoard.columns(posts)
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                TopicTitle(topic: topic, line: "\(posts.count.counted("save")) to browse")
                HStack(alignment: .top, spacing: 10) {
                    column(columns.left)
                    column(columns.right)
                }
            }
            .padding(Theme.padding)
        }
        .scrollIndicators(.hidden)
        .themedScreen()
        .pushedScreen()
        .topicJobMenu(app: app, topic: topic)
    }

    private func column(_ posts: [ContractPost]) -> some View {
        LazyVStack(spacing: 10) {
            ForEach(posts) { post in
                Button { showDetail?(post) } label: { LookTile(post: post) }
                    .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity)
    }
}

private struct LookTile: View {
    let post: ContractPost

    var body: some View {
        Color.clear
            .aspectRatio(1 / LookBoard.aspect(post), contentMode: .fit)
            .overlay { SaveArt(post: post, showsCaption: true, glyphSize: 36) }
            .overlay(alignment: .topLeading) {
                Text(post.byline)
                    .font(Theme.body(11, weight: .bold))
                    .lineLimit(1)
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(.black.opacity(0.55), in: Capsule())
                    .padding(8)
            }
            .clipShape(.rect(cornerRadius: Theme.smallRadius))
            .overlay(RoundedRectangle(cornerRadius: Theme.smallRadius).strokeBorder(Theme.stroke))
            .contentShape(.rect)
            .accessibilityElement()
            .accessibilityLabel("\(post.byline): \(post.firstLine ?? post.kind.rawValue)")
    }
}

// MARK: - Keep close: the quiet shelf

/// Keep close's own, calmer look: deeper background, lavender instead of lime.
enum ShelfStyle {
    static let background = Color(hex: 0x0A0D1C)
    static let card = Color(hex: 0x141A33)
    static let accent = Color(hex: 0xB9C2FF)
    static let text = Color(hex: 0xE8EAF6)
    static let muted = Color(hex: 0x8A90B0)
}

/// The shelf: "What do you need right now?", four needs, and up to three of the
/// user's saves for it from every Keep close topic. No counts, nothing to tick off.
struct KeepCloseScreen: View {
    let app: AppModel
    let topic: HomeTopic
    @State private var need: KeepCloseNeed?
    @State private var round = 0
    @State private var showsAll = false
    @Environment(\.openURL) private var openURL

    var body: some View {
        let library = app.library()
        let posts = shelfPosts(library)
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Label("Private · never in Today or notifications", systemImage: "lock.fill")
                    .font(Theme.body(13, weight: .semibold))
                    .foregroundStyle(ShelfStyle.muted)
                Text("What do you need right now?")
                    .font(Theme.title(32))
                    .foregroundStyle(ShelfStyle.text)
                    .fixedSize(horizontal: false, vertical: true)
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                    ForEach(KeepCloseNeed.allCases) { item in needButton(item) }
                }
                if let need {
                    picks(for: need, posts: posts)
                }
                Button { showsAll.toggle() } label: {
                    HStack {
                        Text(showsAll ? "Hide the list" : "All \(posts.count.formatted())")
                        Spacer()
                        Image(systemName: showsAll ? "chevron.up" : "chevron.down")
                    }
                    .font(Theme.body(16, weight: .bold))
                    .foregroundStyle(ShelfStyle.accent)
                    .frame(minHeight: 44)
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                if showsAll {
                    LazyVStack(spacing: 8) { ForEach(posts) { compactRow($0) } }
                }
            }
            .padding(Theme.padding)
            .animation(.easeInOut(duration: 0.3), value: need)
            .animation(.easeInOut(duration: 0.3), value: round)
        }
        .scrollIndicators(.hidden)
        .background(ShelfStyle.background.ignoresSafeArea())
        .foregroundStyle(ShelfStyle.text)
        .preferredColorScheme(.dark)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(ShelfStyle.background, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .tint(ShelfStyle.accent)
        .topicJobMenu(app: app, topic: topic)
    }

    /// Every Keep close topic's saves (the shelf is the job's, not one topic's).
    private func shelfPosts(_ library: LibraryIndex) -> [ContractPost] {
        var seen: Set<String> = []
        let topics = [topic] + library.topics(doing: .keepClose).filter { $0.id != topic.id }
        return topics.flatMap { app.posts(in: $0) }.filter { seen.insert($0.id).inserted }
    }

    private func needButton(_ item: KeepCloseNeed) -> some View {
        let selected = need == item
        return Button {
            if need == item { round += 1 } else { need = item; round = 0 }
        } label: {
            VStack(alignment: .leading, spacing: 10) {
                Image(systemName: item.symbol).font(.system(size: 18, weight: .semibold)).frame(height: 22)
                Text(item.title).font(Theme.body(16, weight: .bold)).multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .foregroundStyle(selected ? ShelfStyle.background : ShelfStyle.text)
            .frame(maxWidth: .infinity, minHeight: 58, alignment: .topLeading)
            .padding(14)
            .background(selected ? ShelfStyle.accent : ShelfStyle.card, in: .rect(cornerRadius: Theme.radius))
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    @ViewBuilder private func picks(for need: KeepCloseNeed, posts: [ContractPost]) -> some View {
        let notes = app.saves.states.compactMapValues(\.note)
        let result = KeepClose.picks(posts, notes: notes, need: need, seed: TodayPicker.dayKey(.now), round: round)
        VStack(alignment: .leading, spacing: 12) {
            Text(result.matched || need == .remind ? "YOU SAVED THESE FOR THIS" : "NOTHING SAID THIS EXACTLY, SO HERE'S WHAT YOU KEPT")
                .font(Theme.label(12)).tracking(1.2)
                .foregroundStyle(ShelfStyle.muted)
            if let first = result.posts.first {
                quoteCard(first).id("\(first.id)-\(round)")
            }
            ForEach(result.posts.dropFirst()) { compactRow($0) }
            if posts.count > 1 {
                Button { round += 1 } label: { Label("Show me another", systemImage: "arrow.triangle.2.circlepath") }
                    .font(Theme.body(16, weight: .bold))
                    .foregroundStyle(ShelfStyle.accent)
                    .frame(minHeight: 44)
            }
        }
        .transition(.opacity)
    }

    private func comeBackLine(_ id: String) -> String? {
        let opens = app.saves.state(id).opens
        return opens >= 2 ? "You've come back to this \(opens.formatted()) times" : nil
    }

    private func quoteCard(_ post: ContractPost) -> some View {
        Button { open(post) } label: {
            VStack(alignment: .leading, spacing: 14) {
                Image(systemName: "quote.opening").font(.system(size: 22, weight: .bold)).foregroundStyle(ShelfStyle.accent)
                Text(post.caption?.nilIfEmpty ?? "\(post.byline)'s \(post.kind.rawValue)")
                    .font(.system(size: 22, weight: .semibold, design: .serif))
                    .foregroundStyle(ShelfStyle.text)
                    .lineLimit(7)
                    .multilineTextAlignment(.leading)
                HStack(spacing: 6) {
                    Image(systemName: post.platform.symbol)
                    Text(post.byline).lineLimit(1)
                    Spacer()
                    Image(systemName: "arrow.up.right")
                }
                .font(Theme.body(13, weight: .semibold))
                .foregroundStyle(ShelfStyle.muted)
                if let line = comeBackLine(post.id) {
                    Text(line).font(Theme.body(13, weight: .semibold)).foregroundStyle(ShelfStyle.accent)
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(ShelfStyle.card, in: .rect(cornerRadius: 26))
            .overlay(RoundedRectangle(cornerRadius: 26).strokeBorder(ShelfStyle.accent.opacity(0.2)))
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }

    private func compactRow(_ post: ContractPost) -> some View {
        Button { open(post) } label: {
            HStack(spacing: 12) {
                Image(systemName: "leaf").foregroundStyle(ShelfStyle.accent).frame(width: 24)
                VStack(alignment: .leading, spacing: 2) {
                    Text(post.firstLine ?? "\(post.byline)'s \(post.kind.rawValue)")
                        .font(Theme.body(15, weight: .semibold)).lineLimit(2).multilineTextAlignment(.leading)
                    if let line = comeBackLine(post.id) {
                        Text(line).font(Theme.body(12, weight: .semibold)).foregroundStyle(ShelfStyle.accent)
                    } else {
                        Text(post.byline).font(Theme.body(12, weight: .semibold)).foregroundStyle(ShelfStyle.muted)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 14).padding(.vertical, 10)
            .frame(minHeight: 56)
            .background(ShelfStyle.card.opacity(0.7), in: .rect(cornerRadius: Theme.smallRadius))
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }

    private func open(_ post: ContractPost) {
        SaveOpener.open(post, app: app, openURL: openURL)
    }
}

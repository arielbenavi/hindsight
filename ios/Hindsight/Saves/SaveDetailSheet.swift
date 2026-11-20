import SwiftUI

/// One save, from the Library or Ask: picture, where it's from, caption, its topic
/// (and "Move"), "Open in <Platform>", and what the user can do with it: done,
/// a reminder, a note, let it go.
struct SaveDetailSheet: View {
    let app: AppModel
    let post: ContractPost
    @State private var note = ""
    @State private var editingNote = false
    @FocusState private var noteFocused: Bool
    @Environment(\.openURL) private var openURL
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let library = app.library()
        let topic = library.topicByPost[post.id]
        let job = library.job(forPost: post.id)
        let state = app.saves.state(post.id)
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    SaveArt(post: post, glyphSize: 72)
                        .frame(height: 230)
                        .frame(maxWidth: .infinity)
                        .clipShape(.rect(cornerRadius: Theme.radius))
                        .overlay(RoundedRectangle(cornerRadius: Theme.radius).strokeBorder(Theme.stroke))

                    VStack(alignment: .leading, spacing: 6) {
                        Text(metaLine.uppercased())
                            .font(Theme.label(12)).tracking(0.8)
                            .foregroundStyle(job == .keepClose ? ShelfStyle.accent : Theme.lime)
                        Text("\(post.byline) · \(post.kind.rawValue)").font(Theme.body(17, weight: .heavy))
                        if let caption = post.caption?.nilIfEmpty {
                            Text(caption).font(Theme.body(16)).foregroundStyle(Theme.secondary).textSelection(.enabled)
                        }
                    }

                    topicRow(topic, library: library)

                    Button { SaveOpener.open(post, app: app, openURL: openURL) } label: {
                        Label("Open in \(post.platform.displayName)", systemImage: "arrow.up.right")
                    }
                    .buttonStyle(.pill)

                    let destinations = Destinations.applicable(app.destinationInput(for: post, library: library))
                    if !destinations.isEmpty {
                        SendToGroup(app: app, post: post, destinations: destinations)
                    }

                    VStack(spacing: 0) {
                        doneRow(state)
                        divider
                        if job != .keepClose {
                            remindRow(state)
                            divider
                        }
                        noteRow(state)
                        divider
                        letGoRow(state)
                    }
                    .background(Theme.surface, in: .rect(cornerRadius: Theme.radius))
                    .overlay(RoundedRectangle(cornerRadius: Theme.radius).strokeBorder(Theme.stroke))

                    Text(footer(state))
                        .font(Theme.body(13, weight: .semibold))
                        .foregroundStyle(Theme.muted)
                        .frame(maxWidth: .infinity, alignment: .center)
                }
                .padding(Theme.padding)
            }
            .scrollDismissesKeyboard(.interactively)
            .themedScreen()
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
        .tint(Theme.lime)
        .presentationDragIndicator(.visible)
        .onAppear { note = state.note ?? "" }
        .onDisappear { saveNote() }
    }

    private var divider: some View { Rectangle().fill(Theme.stroke).frame(height: 1).padding(.leading, 56) }

    /// "SAVED 14 MARCH · INSTAGRAM · collection".
    private var metaLine: String {
        var parts: [String] = []
        if let date = post.savedDate {
            let sameYear = Calendar.current.isDate(date, equalTo: .now, toGranularity: .year)
            parts.append("Saved " + date.formatted(sameYear ? .dateTime.day().month(.wide) : .dateTime.day().month(.wide).year()))
        }
        parts.append(post.platform.displayName)
        if let collection = post.collections.first(where: { !TopicFallback.genericCollections.contains(TextMatch.fold($0)) }) {
            parts.append(collection)
        }
        return parts.joined(separator: " · ")
    }

    // MARK: - Topic + Move

    private func topicRow(_ topic: HomeTopic?, library: LibraryIndex) -> some View {
        HStack(spacing: 8) {
            if let topic {
                HStack(spacing: 6) {
                    Image(systemName: topic.symbol)
                    Text(topic.label).lineLimit(1)
                }
                .font(Theme.body(14, weight: .bold))
                .padding(.horizontal, 12).padding(.vertical, 8)
                .background(Theme.surfaceRaised, in: Capsule())
            }
            Menu {
                ForEach(library.topics.filter { $0.id != topic?.id }) { other in
                    Button(other.label, systemImage: other.symbol) { app.topicPrefs.move(post.id, to: other.id) }
                }
            } label: {
                Label("Move", systemImage: "arrow.left.arrow.right")
                    .font(Theme.body(14, weight: .bold))
                    .padding(.horizontal, 12).padding(.vertical, 8)
                    .frame(minHeight: 44)
            }
            .accessibilityLabel("Move to another topic")
            Spacer(minLength: 0)
        }
    }

    // MARK: - Rows

    private func row<Trailing: View>(_ title: String, symbol: String, tint: Color = Theme.text,
                                     @ViewBuilder trailing: () -> Trailing) -> some View {
        HStack(spacing: 14) {
            Image(systemName: symbol).font(.system(size: 18, weight: .semibold)).foregroundStyle(tint)
                .frame(width: 28)
            Text(title).font(Theme.body(16, weight: .bold)).foregroundStyle(tint)
            Spacer(minLength: 8)
            trailing()
        }
        .padding(.horizontal, 14)
        .frame(minHeight: 56)
        .contentShape(.rect)
    }

    private func doneRow(_ state: SaveState) -> some View {
        Button { withAnimation(.snappy) { app.saves.toggleDone(post.id) } } label: {
            row("I did this", symbol: state.status == .done ? "checkmark.circle.fill" : "circle",
                tint: state.status == .done ? Theme.lime : Theme.text) {
                if state.status == .done { Text("Done").font(Theme.body(14, weight: .bold)).foregroundStyle(Theme.lime) }
            }
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(state.status == .done ? .isSelected : [])
    }

    private func remindRow(_ state: SaveState) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            row("Remind me", symbol: "bell") {
                if let date = state.remindAt, date > .now {
                    Text(date.formatted(.dateTime.weekday(.abbreviated).hour().minute()))
                        .font(Theme.body(14, weight: .bold)).foregroundStyle(Theme.lime)
                }
            }
            HStack(spacing: 8) {
                Chip(label: "Tonight", systemImage: "moon.fill", isSelected: isSet(state, TodayNotifications.tonight(after: .now))) {
                    remind(TodayNotifications.tonight(after: .now))
                }
                Chip(label: "Weekend", systemImage: "sun.max.fill", isSelected: isSet(state, TodayNotifications.weekend(after: .now))) {
                    remind(TodayNotifications.weekend(after: .now))
                }
                if state.remindAt != nil {
                    Button("Clear") { remind(nil) }
                        .font(Theme.body(14, weight: .bold)).foregroundStyle(Theme.secondary)
                        .frame(minWidth: 44, minHeight: 44)
                }
            }
            .padding(.leading, 56).padding(.bottom, 12)
        }
    }

    private func isSet(_ state: SaveState, _ date: Date) -> Bool { state.remindAt == date }

    private func remind(_ date: Date?) {
        app.saves.setReminder(post.id, date)
        if let date {
            let post = post
            Task { await TodayNotifications.scheduleReminder(for: post, at: date) }
        } else {
            TodayNotifications.cancelReminder(for: post.id)
        }
    }

    private func noteRow(_ state: SaveState) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                editingNote = true
                noteFocused = true
            } label: {
                row(state.hasNote ? "Your note" : "Add a note", symbol: "note.text") { EmptyView() }
            }
            .buttonStyle(.plain)
            if editingNote || state.hasNote {
                TextField("A line for future you", text: $note, axis: .vertical)
                    .font(Theme.body(16))
                    .focused($noteFocused)
                    .lineLimit(1...6)
                    .submitLabel(.done)
                    .onSubmit(saveNote)
                    .onChange(of: noteFocused) { _, focused in if !focused { saveNote() } }
                    .padding(12)
                    .background(Theme.surfaceRaised, in: .rect(cornerRadius: Theme.smallRadius))
                    .padding(.leading, 56).padding(.trailing, 14).padding(.bottom, 12)
            }
        }
    }

    private func saveNote() {
        guard note != (app.saves.state(post.id).note ?? "") else { return }
        app.saves.setNote(post.id, note)
    }

    private func letGoRow(_ state: SaveState) -> some View {
        Button {
            withAnimation(.snappy) { app.saves.setStatus(post.id, state.status == .letGo ? .new : .letGo) }
        } label: {
            if state.status == .letGo {
                row("Let go", symbol: "xmark.circle.fill", tint: Theme.secondary) {
                    Text("Bring it back").font(Theme.body(14, weight: .heavy)).foregroundStyle(Theme.lime)
                }
            } else {
                row("Not interested anymore", symbol: "xmark.circle", tint: Theme.red) { EmptyView() }
            }
        }
        .buttonStyle(.plain)
    }

    private func footer(_ state: SaveState) -> String {
        let shown = "Shown in Today \(state.shownInToday.counted("time"))."
        guard let opened = state.lastOpened else { return shown + " Never opened." }
        return shown + " Opened \(opened.formatted(.relative(presentation: .named)))."
    }
}

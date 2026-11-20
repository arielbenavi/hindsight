import EventKit
import EventKitUI
import SwiftUI

/// What one tap on a destination does, and what to say after. Shared by the save
/// detail's "Send to" rows and Today's action under the card.
@Observable
@MainActor
final class SendToModel {
    struct Notice: Equatable {
        var text: String
        var ok: Bool
        /// Reminders access was refused: offer "Open Settings".
        var denied = false
    }

    struct CalendarDraft: Identifiable {
        let id = UUID()
        var postID: String
        var title: String
        var found: DateFinder.Found
        var location: String?
        var notes: String
        var url: URL
    }

    struct ShareFile: Identifiable {
        let id = UUID()
        var url: URL
    }

    var notice: Notice?
    var busy: String?
    var calendar: CalendarDraft?
    var share: ShareFile?

    /// `onSent` runs after it really got somewhere (Reminders added, Calendar saved,
    /// Maps opened) with the line to show.
    func perform(_ destination: Destination, post: ContractPost, app: AppModel, openURL: OpenURLAction,
                 onSent: ((String) -> Void)? = nil) async {
        switch destination {
        case .maps(let query):
            openURL(Destinations.appleMapsURL(query))
            onSent?("Opened in Maps")
        case .reminders(let list):
            busy = destination.id
            let result = await app.sender.send([post], to: list, saves: app.saves)
            busy = nil
            notice = Notice(text: result.message, ok: result.succeeded, denied: result == .denied)
            if result.succeeded { onSent?(result.message) }
        case .calendar(let found):
            pendingCalendarSent = onSent
            calendar = CalendarDraft(postID: post.id, title: Destinations.eventTitle(for: post, dateText: found.text), found: found,
                                     location: app.destinationInput(for: post, library: app.library()).placeQuery,
                                     notes: [post.caption?.nilIfBlank, post.url.absoluteString].compactMap { $0 }.joined(separator: "\n\n"),
                                     url: post.url)
        case .export:
            let entry = app.exportEntry(post)
            let markdown = MarkdownExporter.document(for: entry, topic: app.library().topicByPost[post.id]?.label, now: .now)
            if let url = MarkdownFile.write(markdown, title: Destinations.title(for: post)) { share = ShareFile(url: url) }
        }
    }

    @ObservationIgnored private var pendingCalendarSent: ((String) -> Void)?

    /// Apple's add-event sheet closed. Only a saved event counts.
    func calendarFinished(saved: Bool, app: AppModel) {
        guard let draft = calendar else { return }
        calendar = nil
        guard saved else { pendingCalendarSent = nil; return }
        app.saves.recordSent(draft.postID, to: Destination.calendarKey)
        notice = Notice(text: "Added to Calendar", ok: true)
        pendingCalendarSent?("Added to Calendar")
        pendingCalendarSent = nil
    }
}

enum MarkdownFile {
    /// Writes to a temporary file the share sheet can hand to Notes, Files, Obsidian…
    static func write(_ markdown: String, title: String) -> URL? {
        let folder = FileManager.default.temporaryDirectory.appending(path: "hindsight-export", directoryHint: .isDirectory)
        let url = folder.appending(path: MarkdownExporter.fileName(title))
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try markdown.write(to: url, atomically: true, encoding: .utf8)
            return url
        } catch {
            DebugLog.write("markdown export failed: \(error)")
            return nil
        }
    }
}

// MARK: - Save detail: "Send to"

/// The save detail's "Send to" rows: only the destinations that fit this save
/// (best first, at most three), one tap each. Once a save is in a list it says so
/// ("In Groceries") instead of offering the button again.
struct SendToGroup: View {
    let app: AppModel
    let post: ContractPost
    let destinations: [Destination]
    @State private var model = SendToModel()
    @Environment(\.openURL) private var openURL

    var body: some View {
        let state = app.saves.state(post.id)
        VStack(alignment: .leading, spacing: 8) {
            Text("SEND TO").font(Theme.label(12)).tracking(0.8).foregroundStyle(Theme.muted)
            VStack(spacing: 0) {
                ForEach(Array(destinations.enumerated()), id: \.element.id) { index, destination in
                    if index > 0 { Rectangle().fill(Theme.stroke).frame(height: 1).padding(.leading, 56) }
                    row(destination, sent: destination.sentKey.flatMap(state.sentDate))
                }
            }
            .background(Theme.surface, in: .rect(cornerRadius: Theme.radius))
            .overlay(RoundedRectangle(cornerRadius: Theme.radius).strokeBorder(Theme.stroke))
            if let notice = model.notice { NoticeLine(notice: notice) }
        }
        .sendToSheets(model, app: app)
        .animation(.snappy, value: model.notice)
    }

    @ViewBuilder private func row(_ destination: Destination, sent: Date?) -> some View {
        if let sent, let key = destination.sentKey {
            HStack(spacing: 14) {
                Image(systemName: "checkmark.circle.fill").font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(Theme.lime).frame(width: 28)
                Text("In \(key == Destination.calendarKey ? "Calendar" : ReminderList(rawValue: key)?.shortName ?? key)")
                    .font(Theme.body(16, weight: .bold))
                Spacer(minLength: 8)
                Text(sent.formatted(.dateTime.day().month(.abbreviated)))
                    .font(Theme.body(13, weight: .semibold)).foregroundStyle(Theme.muted)
            }
            .padding(.horizontal, 14)
            .frame(minHeight: 56)
            .accessibilityElement(children: .combine)
        } else {
            HStack(spacing: 0) {
                Button {
                    Task { await model.perform(destination, post: post, app: app, openURL: openURL) }
                } label: {
                    HStack(spacing: 14) {
                        Image(systemName: destination.symbol).font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(Theme.lime).frame(width: 28)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(title(destination)).font(Theme.body(16, weight: .bold))
                            if let detail = detail(destination) {
                                Text(detail).font(Theme.body(13)).foregroundStyle(Theme.secondary).lineLimit(1)
                            }
                        }
                        Spacer(minLength: 8)
                        if model.busy == destination.id { ProgressView().controlSize(.small) }
                    }
                    .padding(.horizontal, 14)
                    .frame(minHeight: 56)
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .disabled(model.busy != nil)
                if case .maps(let query) = destination {
                    // Google Maps opens through its universal link when it's installed.
                    Button("Google") { openURL(Destinations.googleMapsURL(query)) }
                        .font(Theme.body(13, weight: .bold))
                        .foregroundStyle(Theme.secondary)
                        .padding(.horizontal, 12).padding(.vertical, 7)
                        .background(Theme.surfaceRaised, in: Capsule())
                        .padding(.trailing, 12)
                        .accessibilityLabel("Open in Google Maps")
                }
            }
        }
    }

    /// "Add ingredients to Groceries" only when there's a list to add.
    private func title(_ destination: Destination) -> String {
        if destination == .reminders(.groceries), IngredientParser.parse(post.caption).isEmpty { return "Add to Groceries" }
        return destination.title
    }

    private func detail(_ destination: Destination) -> String? {
        switch destination {
        case .maps(let query): return query
        case .reminders(.groceries):
            let count = IngredientParser.parse(post.caption).count
            return count > 0 ? "\(count.counted("ingredient")) from the caption" : "No list in the caption: adds the recipe"
        case .reminders(let list): return "Reminders · \(list.name)"
        case .calendar(let found):
            return found.date.formatted(found.hasTime ? .dateTime.weekday(.abbreviated).day().month(.abbreviated).hour().minute()
                                                      : .dateTime.weekday(.abbreviated).day().month(.abbreviated))
        case .export: return "Notes, Files, Obsidian…"
        }
    }
}

/// "Added to Groceries · 7 items", or why not (with "Open Settings").
struct NoticeLine: View {
    let notice: SendToModel.Notice
    @Environment(\.openURL) private var openURL

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: notice.ok ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
            Text(notice.text).fixedSize(horizontal: false, vertical: true)
            if notice.denied {
                Spacer(minLength: 4)
                Button("Open Settings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                }
                .font(Theme.body(14, weight: .heavy))
            }
        }
        .font(Theme.body(14, weight: .semibold))
        .foregroundStyle(notice.ok ? Theme.lime : .orange)
        .transition(.opacity)
    }
}

// MARK: - Today: one small action under the card

/// Today's secondary action ("Add to Groceries", "Open in Maps", "Add to Calendar"):
/// one tap, and the card counts as handled for today.
struct TodaySendAction: View {
    let app: AppModel
    let post: ContractPost
    let destination: Destination
    let onSent: (String) -> Void
    @State private var model = SendToModel()
    @Environment(\.openURL) private var openURL

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let notice = model.notice, !notice.ok { NoticeLine(notice: notice) }
            Button {
                Task { await model.perform(destination, post: post, app: app, openURL: openURL, onSent: onSent) }
            } label: {
                HStack(spacing: 8) {
                    if model.busy != nil { ProgressView().controlSize(.mini) } else { Image(systemName: destination.symbol) }
                    Text(destination.shortTitle)
                }
                .font(Theme.body(15, weight: .bold))
                .foregroundStyle(Theme.lime)
                .padding(.horizontal, 16).frame(minHeight: 44)
                .background(Theme.lime.opacity(0.12), in: Capsule())
                .overlay(Capsule().strokeBorder(Theme.lime.opacity(0.35)))
            }
            .buttonStyle(.plain)
            .disabled(model.busy != nil)
            .accessibilityHint("Counts as handled for today")
        }
        .sendToSheets(model, app: app)
    }
}

// MARK: - Sheets: Apple's add-event sheet, the share sheet

extension View {
    func sendToSheets(_ model: SendToModel, app: AppModel) -> some View {
        modifier(SendToSheets(model: model, app: app))
    }
}

private struct SendToSheets: ViewModifier {
    @Bindable var model: SendToModel
    let app: AppModel

    func body(content: Content) -> some View {
        content
            .sheet(item: $model.calendar, onDismiss: { model.calendarFinished(saved: false, app: app) }) { draft in
                EventEditor(draft: draft) { saved in model.calendarFinished(saved: saved, app: app) }
                    .ignoresSafeArea()
            }
            .sheet(item: $model.share) { file in
                ShareSheet(items: [file.url]).presentationDetents([.medium, .large])
            }
    }
}

/// Apple's add-event sheet (EventKitUI), prefilled. The user confirms in it; on
/// iOS 17+ it needs no Calendar permission, and nothing is written without that tap.
struct EventEditor: UIViewControllerRepresentable {
    let draft: SendToModel.CalendarDraft
    let onDone: (Bool) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onDone: onDone) }

    func makeUIViewController(context: Context) -> EKEventEditViewController {
        let store = EKEventStore()
        let event = EKEvent(eventStore: store)
        event.title = draft.title
        event.location = draft.location
        event.notes = draft.notes
        event.url = draft.url
        event.isAllDay = !draft.found.hasTime
        event.startDate = draft.found.date
        event.endDate = draft.found.hasTime ? draft.found.date.addingTimeInterval(3600) : draft.found.date
        let controller = EKEventEditViewController()
        controller.eventStore = store
        controller.event = event
        controller.editViewDelegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ controller: EKEventEditViewController, context: Context) {}

    /// EventKitUI calls its delegate on the main thread, but the protocol isn't marked so.
    @MainActor
    final class Coordinator: NSObject, @preconcurrency EKEventEditViewDelegate {
        let onDone: (Bool) -> Void
        init(onDone: @escaping (Bool) -> Void) { self.onDone = onDone }

        func eventEditViewController(_ controller: EKEventEditViewController, didCompleteWith action: EKEventEditViewAction) {
            onDone(action == .saved)
        }
    }
}

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}

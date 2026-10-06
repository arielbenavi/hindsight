import SwiftUI
import UniformTypeIdentifiers
import UserNotifications

/// "Get your saves from Meta": guides the user through Meta's Download your
/// information (Instagram + Facebook), then imports the .zip. The dependable
/// path while Muse is unreliable. Only the saved-posts files are read
/// (DataExportParser); everything else in the download is ignored.
struct MetaImportSheet: View {
    let store: SavedPostStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @State private var isImporting = false
    @State private var result: Result?
    @State private var reminderSet = false

    enum Result: Equatable {
        case imported(added: Int, found: Int, inCollections: Int, partial: Bool)
        case failed(String)
    }

    /// Meta's "Download your information" page (signs in first if needed).
    static let downloadPage = URL(string: "https://accountscenter.instagram.com/info_and_permissions/dyi/")!

    var body: some View {
        NavigationStack {
            OnboardingPage {
                Text("Get your saves\nfrom Meta.")
                    .font(OnboardingStyle.display(40))
                Text("Instagram and Facebook can send you a file with everything you've saved. Asking takes about a minute; Meta emails you when it's ready, usually within an hour.")
                    .font(OnboardingStyle.body)
                    .foregroundStyle(OnboardingStyle.muted)

                VStack(spacing: 10) {
                    step(1, "Open Meta's download page",
                         "Accounts Center → Your information and permissions → Download your information.") {
                        Button("Open the download page") { openURL(Self.downloadPage) }
                            .buttonStyle(.onboardingSecondary)
                    }
                    step(2, "Ask for your saves only",
                         "Download or transfer information → your Instagram account → Some of your information → tick Saved. For Facebook, also tick Saved items and collections. Then Next.")
                    step(3, "Use these settings",
                         "Download to device · Date range: All time · Format: JSON (not HTML) · Media quality: Low. Then Create files.")
                    step(4, "Wait for Meta's email",
                         "You can close Hindsight. When it arrives, tap Download and save the .zip to Files.") {
                        Button(reminderSet ? "We'll remind you in an hour" : "Remind me in an hour", action: remind)
                            .buttonStyle(.onboardingSecondary)
                            .disabled(reminderSet)
                    }
                    step(5, "Import it here", "Choose the whole .zip. No need to unzip it.")
                }

                Label("Only your saved posts are read. Everything else in the file is ignored, and nothing leaves your phone.",
                      systemImage: "lock.fill")
                    .font(OnboardingStyle.caption)
                    .foregroundStyle(OnboardingStyle.muted)
            } actions: {
                // The result sits by the button, where it's always visible.
                statusBanner
                if case .imported(let added, _, _, _) = result, added > 0 {
                    Button("Done") { dismiss() }.buttonStyle(.onboardingPrimary)
                } else {
                    Button("Choose the .zip") { isImporting = true }.buttonStyle(.onboardingPrimary)
                }
                #if DEBUG
                // Testing without waiting on Meta: Reut's export from data/ig-reut-export (bundled).
                Button("Use Reut's export (dev)") { importBundledExport() }
                    .buttonStyle(.onboardingSecondary)
                #endif
            }
            .foregroundStyle(OnboardingStyle.text)
            .background(OnboardingStyle.background.ignoresSafeArea())
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { Button("Close") { dismiss() } }
            }
        }
        .preferredColorScheme(.dark)
        .tint(OnboardingStyle.accent)
        .fileImporter(isPresented: $isImporting, allowedContentTypes: [.zip, .json], allowsMultipleSelection: true) { picked in
            guard case .success(let urls) = picked else { return }
            importFiles(urls)
        }
    }

    // MARK: - Import

    private func importFiles(_ urls: [URL]) {
        var posts: [SavedPost] = []
        for url in urls {
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            posts += (try? DataExportParser.parse(fileAt: url)) ?? []
        }
        // Picking one .json instead of the .zip misses posts: saved_posts.json and
        // saved_collections.json each hold only part of them.
        let names = Set(urls.map { $0.lastPathComponent.lowercased() })
        let partial = !names.contains { $0.hasSuffix(".zip") } && !(names.contains("saved_posts.json") && names.contains("saved_collections.json"))
        finish(posts, partial: partial, from: urls.map(\.lastPathComponent).joined(separator: ", "))
    }

    #if DEBUG
    private func importBundledExport() {
        let urls = ["saved_posts", "saved_collections"].compactMap { Bundle.main.url(forResource: $0, withExtension: "json") }
        let posts = urls.flatMap { (try? DataExportParser.parse(fileAt: $0)) ?? [] }
        finish(posts, partial: false, from: "bundled export")
    }
    #endif

    private func finish(_ posts: [SavedPost], partial: Bool, from source: String) {
        guard !posts.isEmpty else {
            result = .failed("Couldn't find saved posts in that file. Make sure the format was JSON, and choose the whole .zip.")
            DebugLog.write("meta import: nothing in \(source)")
            return
        }
        let combined = DataExportParser.combined(posts)
        let added = store.merge(combined)
        result = .imported(added: added, found: combined.count, inCollections: combined.count { !$0.collections.isEmpty }, partial: partial)
        DebugLog.write("meta import: \(source) → \(combined.count) posts, +\(added) new, \(combined.count { !$0.collections.isEmpty }) in collections")
    }

    private func remind() {
        Task {
            let center = UNUserNotificationCenter.current()
            guard (try? await center.requestAuthorization(options: [.alert, .sound])) == true else { return }
            let content = UNMutableNotificationContent()
            content.title = "Is your Meta file ready?"
            content.body = "Check your email for Meta's download, save the .zip, then import it in Hindsight."
            let request = UNNotificationRequest(identifier: "meta-download-ready", content: content,
                                                trigger: UNTimeIntervalNotificationTrigger(timeInterval: 3600, repeats: false))
            try? await center.add(request)
            reminderSet = true
        }
    }

    // MARK: - Views

    @ViewBuilder private var statusBanner: some View {
        switch result {
        case .imported(let added, let found, let inCollections, let partial):
            VStack(alignment: .leading, spacing: 6) {
                Label(added > 0 ? "+\(added.formatted()) saves imported" : "Nothing new. All \(found.formatted()) were already here.",
                      systemImage: "checkmark.circle.fill")
                    .font(OnboardingStyle.title)
                    .foregroundStyle(OnboardingStyle.accent)
                if inCollections > 0 {
                    Text("\(inCollections.formatted()) of them are in your collections.")
                        .font(OnboardingStyle.caption).foregroundStyle(OnboardingStyle.muted)
                }
                if partial {
                    Text("Tip: choose the whole .zip to get everything. One file alone has only part of your saves.")
                        .font(OnboardingStyle.caption).foregroundStyle(.orange)
                }
            }
        case .failed(let message):
            Label(message, systemImage: "exclamationmark.triangle.fill")
                .font(OnboardingStyle.caption)
                .foregroundStyle(.orange)
        case nil:
            EmptyView()
        }
    }

    private func step(_ number: Int, _ title: String, _ detail: String) -> some View {
        step(number, title, detail) { EmptyView() }
    }

    private func step(_ number: Int, _ title: String, _ detail: String, @ViewBuilder action: () -> some View) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Text("\(number)")
                .font(.system(.headline, design: .rounded, weight: .black))
                .frame(width: 32, height: 32)
                .background(OnboardingStyle.stroke, in: .circle)
            VStack(alignment: .leading, spacing: 8) {
                Text(title).font(OnboardingStyle.title)
                Text(detail).font(OnboardingStyle.caption).foregroundStyle(OnboardingStyle.muted)
                action()
            }
            Spacer(minLength: 0)
        }
        .onboardingCard(padding: 14)
    }
}

#Preview {
    MetaImportSheet(store: SavedPostStore(fileURL: nil, seed: { [] }))
}

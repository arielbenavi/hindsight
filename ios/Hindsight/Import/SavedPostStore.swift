import Foundation
import Observation

/// All saved posts the app knows about, deduplicated by `SavedPost.id`.
/// Starts from the bundled seed; imports (e.g. from Muse) are merged on top
/// and persisted as JSON in Application Support.
@Observable
@MainActor
final class SavedPostStore {
    /// Newest saved first.
    private(set) var posts: [SavedPost] = []

    private let fileURL: URL?

    /// `fileURL: nil` keeps everything in memory (previews, tests).
    init(fileURL: URL? = SavedPostStore.defaultFileURL, seed: () -> [SavedPost] = SavedPostStore.seedPosts) {
        self.fileURL = fileURL
        if let fileURL, let data = try? Data(contentsOf: fileURL),
           let saved = try? JSONDecoder().decode([SavedPost].self, from: data) {
            posts = saved
        } else {
            posts = Self.deduplicated(seed())
            persist()
        }
    }

    /// Adds posts not already in the store, ahead of existing ones.
    /// Returns how many were new.
    @discardableResult
    func merge(_ incoming: [SavedPost]) -> Int {
        let known = Set(posts.map(\.id))
        let fresh = Self.deduplicated(incoming.filter { !known.contains($0.id) })
        guard !fresh.isEmpty else { return 0 }
        posts = fresh + posts
        persist()
        return fresh.count
    }

    func count(for platform: Platform) -> Int {
        posts.count { $0.platform == platform }
    }

    private func persist() {
        guard let fileURL else { return }
        do {
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(posts).write(to: fileURL, options: .atomic)
        } catch {
            print("SavedPostStore: failed to persist: \(error)")
        }
    }

    private static func deduplicated(_ posts: [SavedPost]) -> [SavedPost] {
        var seen = Set<String>()
        return posts.filter { seen.insert($0.id).inserted }
    }

    nonisolated static let defaultFileURL: URL? = URL.applicationSupportDirectory
        .appending(path: "saved-posts.json")

    nonisolated static func seedPosts() -> [SavedPost] {
        SeedData.markdown().map { SavedPostParser.parse($0).posts } ?? []
    }
}

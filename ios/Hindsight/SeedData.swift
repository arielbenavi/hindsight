import Foundation

/// Reads the bundled seed export (data/ig-saved-posts-seed.md in the repo).
enum SeedData {
    static func markdown(in bundle: Bundle = .main) -> String? {
        guard let url = bundle.url(forResource: "ig-saved-posts-seed", withExtension: "md") else {
            return nil
        }
        return try? String(contentsOf: url, encoding: .utf8)
    }

    static func posts(in bundle: Bundle = .main) -> [SavedPost] {
        markdown(in: bundle).map { SavedPostParser.parse($0, source: .seedMD).posts } ?? []
    }

    static func savedPostCount(in bundle: Bundle = .main) -> Int {
        posts(in: bundle).count
    }
}

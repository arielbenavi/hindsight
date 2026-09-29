import Foundation

/// Reads the bundled seed export (data/ig-saved-posts-seed.md in the repo).
enum SeedData {
    static func markdown(in bundle: Bundle = .main) -> String? {
        guard let url = bundle.url(forResource: "ig-saved-posts-seed", withExtension: "md") else {
            return nil
        }
        return try? String(contentsOf: url, encoding: .utf8)
    }

    /// Entries look like `12. **@username** · reel · 2026-09-16`.
    static func savedPostCount(in bundle: Bundle = .main) -> Int {
        guard let text = markdown(in: bundle) else { return 0 }
        return text.split(separator: "\n").count { line in
            line.firstMatch(of: /^\d+\. \*\*@/) != nil
        }
    }
}

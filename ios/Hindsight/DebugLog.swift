import Foundation

/// Append-only log of what happened on a test device (link attempts, imports,
/// parse failures). Debug builds only. Pull it off a connected phone with:
///   xcrun devicectl device copy from --device <id> --domain-type appDataContainer \
///     --domain-identifier <bundle id> --source Library/Application\ Support/debug-log.txt \
///     --destination debug-log.txt
enum DebugLog {
    static let fileURL = URL.applicationSupportDirectory.appending(path: "debug-log.txt")

    static func write(_ message: String) {
        #if DEBUG
        let line = "\(Date().formatted(.iso8601)) \(message)\n"
        print("[hindsight] \(message)")
        try? FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let handle = try? FileHandle(forWritingTo: fileURL) {
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: Data(line.utf8))
        } else {
            try? Data(line.utf8).write(to: fileURL)
        }
        #endif
    }
}

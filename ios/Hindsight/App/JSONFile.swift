import Foundation

/// A Codable value persisted as one JSON file in Application Support, namespaced
/// per dataset (`Hindsight/<dataset>/<name>.json`) so testers' states never mix.
/// `directory: nil` keeps it in memory only (previews, tests).
struct JSONFile<Value: Codable>: Sendable {
    let url: URL?

    init(name: String, directory: URL?) {
        url = directory?.appending(path: "\(name).json")
    }

    func load() -> Value? {
        guard let url, let data = try? Data(contentsOf: url) else { return nil }
        return try? Self.decoder.decode(Value.self, from: data)
    }

    func save(_ value: Value) {
        guard let url else { return }
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Self.encoder.encode(value).write(to: url, options: .atomic)
        } catch {
            DebugLog.write("JSONFile save failed \(url.lastPathComponent): \(error)")
        }
    }

    func delete() {
        guard let url else { return }
        try? FileManager.default.removeItem(at: url)
    }

    private static var encoder: JSONEncoder {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        return e
    }

    private static var decoder: JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }

    /// `Application Support/Hindsight/<datasetID>/`.
    static func directory(for datasetID: String) -> URL? {
        URL.applicationSupportDirectory.appending(path: "Hindsight/\(datasetID)", directoryHint: .isDirectory)
    }
}

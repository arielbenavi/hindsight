import Foundation

/// Reads the "download your data" exports from Instagram, Facebook and TikTok
/// (a .zip, or the JSON file inside it) into `SavedPost`s.
///
/// Formats, as of 2026 (keys vary between export versions, so matching is loose):
/// - Instagram, current (`your_instagram_activity/saved/`): `saved_posts.json` is a
///   top-level array of `{timestamp (saved, Unix s), label_values[]}` where
///   label_values holds `URL`, `Caption`, a "Hashtags" dict and an "Owner" dict
///   (`Username`, `Name`). `saved_collections.json` is an array of collections
///   (`Name` label + child post dicts, no per-post timestamp). See data/README.md.
/// - Instagram, older: `saved_saved_media[].title` (author) +
///   `string_map_data["Saved on"].{href, timestamp}`
/// - Facebook `saved_items_and_collections.json`: `saves_and_collections_v2[]`
///   with `timestamp`, `title`, and a URL somewhere under `attachments`
/// - TikTok `user_data_tiktok.json`: `Favorite Videos.FavoriteVideoList[]` and
///   `Like List.ItemFavoriteList[]`, each `{Date, Link}`
/// Ported from web/backend/scripts/import_{ig,fb}_export.py.
enum DataExportParser {
    enum ImportError: LocalizedError {
        case nothingFound
        var errorDescription: String? {
            "Couldn't find any saved posts in that file. Pick the .zip from Instagram, Facebook or TikTok, or the JSON inside it."
        }
    }

    /// Largest JSON file we'll pull out of an archive.
    private static let maxEntrySize: UInt64 = 200_000_000

    static func parse(fileAt url: URL) throws -> [SavedPost] {
        let posts: [SavedPost]
        if url.pathExtension.lowercased() == "zip" {
            let zip = try ZipReader(url: url)
            posts = try zip.entries
                .filter { isCandidate($0.name) && $0.uncompressedSize < maxEntrySize }
                .flatMap { parse(json: try zip.data(for: $0)) }
        } else {
            posts = parse(json: try Data(contentsOf: url))
        }
        guard !posts.isEmpty else { throw ImportError.nothingFound }
        return combined(posts)
    }

    /// One record per post: the same post shows up in `saved_posts.json` (with the
    /// saved time) and in `saved_collections.json` (with the collection name).
    static func combined(_ posts: [SavedPost]) -> [SavedPost] {
        var order: [String] = []
        var byID: [String: SavedPost] = [:]
        for post in posts {
            if let existing = byID[post.id] {
                byID[post.id] = existing.filling(from: post)
            } else {
                order.append(post.id)
                byID[post.id] = post
            }
        }
        return order.compactMap { byID[$0] }
    }

    /// Only the files that can hold saves; exports also carry messages, media, etc.
    static func isCandidate(_ path: String) -> Bool {
        let name = (path as NSString).lastPathComponent.lowercased()
        guard name.hasSuffix(".json"), !path.hasPrefix("__MACOSX") else { return false }
        return name.contains("saved") || name.hasPrefix("user_data")
    }

    static func parse(json data: Data) -> [SavedPost] {
        guard let object = try? JSONSerialization.jsonObject(with: data) else { return [] }
        return instagram(object) + facebook(object) + tiktok(object)
    }

    // MARK: - Instagram

    static func instagram(_ object: Any) -> [SavedPost] {
        if let entries = object as? [[String: Any]] {
            return entries.flatMap(instagramCurrent)
        }
        guard let root = object as? [String: Any] else { return [] }
        let items = root.filter { $0.key.hasPrefix("saved_saved_media") || $0.key == "saved_media" }
            .values.compactMap { $0 as? [[String: Any]] }.joined()
        return items.compactMap { item in
            guard let fields = (item["string_map_data"] as? [String: Any])?.values
                    .compactMap({ $0 as? [String: Any] })
                    .first(where: { $0["href"] is String }),
                  let url = (fields["href"] as? String).flatMap(URL.init(string:))
            else { return nil }
            return SavedPost(
                platform: .instagram,
                url: url,
                kind: kind(forPath: url.path()),
                author: fixMojibake(item["title"] as? String ?? ""),
                caption: nil,
                savedAt: date(fromTimestamp: fields["timestamp"]),
                source: .igExport
            )
        }
    }

    /// One entry of the current export: a saved post, or a collection of them.
    private static func instagramCurrent(_ entry: [String: Any]) -> [SavedPost] {
        guard let labels = entry["label_values"] as? [[String: Any]] else { return [] }
        if label("URL", in: labels) != nil {
            return instagramPost(labels, savedAt: date(fromTimestamp: entry["timestamp"]), collection: nil)
                .map { [$0] } ?? []
        }
        // A collection: its name, then its posts nested in `dict` groups.
        let name = label("Name", in: labels)?.trimmingCharacters(in: .whitespacesAndNewlines)
        return postLabelLists(in: labels).compactMap { instagramPost($0, savedAt: nil, collection: name) }
    }

    /// Every nested label list that describes a post (has a `URL` label).
    private static func postLabelLists(in labels: [[String: Any]]) -> [[[String: Any]]] {
        labels.flatMap { child -> [[[String: Any]]] in
            guard let nested = child["dict"] as? [[String: Any]] else { return [] }
            return label("URL", in: nested) != nil ? [nested] : postLabelLists(in: nested)
        }
    }

    private static func instagramPost(_ labels: [[String: Any]], savedAt: Date?, collection: String?) -> SavedPost? {
        guard let url = label("URL", in: labels).flatMap(URL.init(string:)) else { return nil }
        let owner = (group("Owner", in: labels).first).flatMap { $0["dict"] as? [[String: Any]] } ?? []
        let hashtags = group("Hashtags", in: labels)
            .compactMap { ($0["dict"] as? [[String: Any]]).flatMap { label("Name", in: $0) } }
            .map { $0.lowercased() }
        let caption = label("Caption", in: labels)
        return SavedPost(
            platform: .instagram,
            url: url,
            kind: kind(forPath: url.path()),
            author: label("Username", in: owner) ?? "",
            authorDisplayName: label("Name", in: owner),
            caption: caption,
            hashtags: hashtags.isEmpty ? nil : hashtags,
            collections: collection.map { [$0] } ?? [],
            savedAt: savedAt,
            source: .igExport
        )
    }

    /// Value of a `{label, value}` entry, decoded and non-empty.
    private static func label(_ name: String, in labels: [[String: Any]]) -> String? {
        guard let entry = labels.first(where: { $0["label"] as? String == name }),
              let raw = (entry["href"] as? String) ?? (entry["value"] as? String), !raw.isEmpty
        else { return nil }
        return fixMojibake(raw)
    }

    /// Children of a `{dict: [...], title: name}` group.
    private static func group(_ title: String, in labels: [[String: Any]]) -> [[String: Any]] {
        labels.first(where: { $0["title"] as? String == title && $0["dict"] != nil })?["dict"] as? [[String: Any]] ?? []
    }

    // MARK: - Facebook

    static func facebook(_ object: Any) -> [SavedPost] {
        guard let root = object as? [String: Any] else { return [] }
        let items = root.filter { $0.key.hasPrefix("saves_and_collections") || $0.key.hasPrefix("saved_items") }
            .values.compactMap { $0 as? [[String: Any]] }.joined()
        return items.compactMap { item in
            guard let url = firstURL(in: item["attachments"] ?? item).map(unwrapFacebookRedirect) else {
                return nil
            }
            let name = firstString(forKey: "name", in: item["attachments"] as Any)
            return SavedPost(
                platform: .facebook,
                url: url,
                kind: kind(forPath: url.path()),
                author: "",
                caption: fixMojibake(name ?? item["title"] as? String ?? ""),
                savedAt: date(fromTimestamp: item["timestamp"]),
                source: .fbExport
            )
        }
    }

    private static func unwrapFacebookRedirect(_ url: URL) -> URL {
        guard let host = url.host(), host == "l.facebook.com" || host == "lm.facebook.com",
              let target = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                .queryItems?.first(where: { $0.name == "u" })?.value,
              let unwrapped = URL(string: target)
        else { return url }
        return unwrapped
    }

    // MARK: - TikTok

    static func tiktok(_ object: Any) -> [SavedPost] {
        var posts: [SavedPost] = []
        func walk(_ value: Any, path: String) {
            if let dict = value as? [String: Any] {
                if let link = (dict["Link"] ?? dict["link"]) as? String,
                   path.contains("favorite video") || path.contains("favoritevideo") || path.contains("like list"),
                   let url = URL(string: link) {
                    posts.append(SavedPost(
                        platform: .tiktok,
                        url: url,
                        kind: .video,
                        author: tiktokAuthor(in: url) ?? "",
                        caption: nil,
                        savedAt: tiktokDate((dict["Date"] ?? dict["date"]) as? String),
                        source: .tiktokExport
                    ))
                    return
                }
                for (key, child) in dict { walk(child, path: path + "/" + key.lowercased()) }
            } else if let array = value as? [Any] {
                for child in array { walk(child, path: path) }
            }
        }
        walk(object, path: "")
        return posts
    }

    /// `tiktok.com/@user/video/123` → `user`. Share links (`tiktokv.com/share/video/123`) have none.
    private static func tiktokAuthor(in url: URL) -> String? {
        url.pathComponents.first { $0.hasPrefix("@") }.map { String($0.dropFirst()) }
    }

    /// TikTok writes `2024-05-01 10:00:00`, in UTC.
    private static func tiktokDate(_ raw: String?) -> Date? {
        guard let raw else { return nil }
        return try? Date(raw.replacingOccurrences(of: " ", with: "T") + "Z", strategy: .iso8601)
    }

    // MARK: - Helpers

    private static func kind(forPath path: String) -> SavedPost.Kind {
        let path = path.lowercased()
        if path.contains("/reel") { return .reel }
        if path.contains("/tv/") || path.contains("/video") || path.contains("/watch") { return .video }
        if path.contains("/p/") || path.contains("/posts/") || path.contains("/photo") { return .post }
        return .unknown
    }

    private static func date(fromTimestamp value: Any?) -> Date? {
        (value as? NSNumber).map { Date(timeIntervalSince1970: $0.doubleValue) }
    }

    private static func firstURL(in value: Any) -> URL? {
        if let dict = value as? [String: Any] {
            for key in ["url", "uri", "href", "link"] {
                if let string = dict[key] as? String, string.hasPrefix("http"), let url = URL(string: string) {
                    return url
                }
            }
            return dict.values.lazy.compactMap(firstURL).first
        }
        if let array = value as? [Any] {
            return array.lazy.compactMap(firstURL).first
        }
        return nil
    }

    private static func firstString(forKey key: String, in value: Any) -> String? {
        if let dict = value as? [String: Any] {
            if let string = dict[key] as? String { return string }
            return dict.values.lazy.compactMap { firstString(forKey: key, in: $0) }.first
        }
        if let array = value as? [Any] {
            return array.lazy.compactMap { firstString(forKey: key, in: $0) }.first
        }
        return nil
    }

    /// Meta exports write UTF-8 bytes as if each were a Latin-1 character
    /// ("cafÃ©"). Re-read those bytes as UTF-8 to get "café" back.
    static func fixMojibake(_ string: String) -> String {
        let scalars = string.unicodeScalars
        guard scalars.contains(where: { $0.value > 127 }), scalars.allSatisfy({ $0.value < 256 }) else {
            return string
        }
        let bytes = scalars.map { UInt8($0.value) }
        return String(bytes: bytes, encoding: .utf8) ?? string
    }
}

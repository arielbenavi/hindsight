import Foundation
import Testing
@testable import Hindsight

struct DataExportParserTests {
    static let instagramJSON = """
    {"saved_saved_media": [
      {"title": "evolving.ai", "string_map_data": {"Saved on": {"href": "https://www.instagram.com/p/DdwJgsNABze/", "timestamp": 1790000000}}},
      {"title": "caf\\u00c3\\u00a9.beats", "string_map_data": {"Saved on": {"href": "https://www.instagram.com/reel/ABC/", "timestamp": 1790000100}}},
      {"title": "no link", "string_map_data": {"Saved on": {"timestamp": 1}}}
    ]}
    """

    static let facebookJSON = """
    {"saves_and_collections_v2": [
      {"timestamp": 1790000000, "title": "Ariel saved a link.",
       "attachments": [{"data": [{"external_context": {"name": "Pasta night", "url": "https://l.facebook.com/l.php?u=https%3A%2F%2Fexample.com%2Frecipe&h=x"}}]}]},
      {"timestamp": 1790000200, "title": "Ariel saved a video.",
       "attachments": [{"data": [{"external_context": {"url": "https://www.facebook.com/reel/555/"}}]}]}
    ]}
    """

    static let tiktokJSON = """
    {"Activity": {
      "Favorite Videos": {"FavoriteVideoList": [{"Date": "2026-05-01 10:00:00", "Link": "https://www.tiktokv.com/share/video/7362000000000000001/"}]},
      "Like List": {"ItemFavoriteList": [{"date": "2026-05-02 11:00:00", "link": "https://www.tiktok.com/@chef/video/7362000000000000002"}]},
      "Favorite Sounds": {"FavoriteSoundList": [{"Date": "2026-05-03 12:00:00", "Link": "https://www.tiktok.com/music/x-1"}]}
    }}
    """

    @Test func instagramExport() {
        let posts = DataExportParser.parse(json: Data(Self.instagramJSON.utf8))
        #expect(posts.count == 2)
        #expect(posts[0].id == "instagram:DdwJgsNABze")
        #expect(posts[0].kind == .post)
        #expect(posts[0].date == Date(timeIntervalSince1970: 1790000000))
        #expect(posts[1].author == "café.beats")
        #expect(posts[1].kind == .reel)
    }

    @Test func facebookExportUnwrapsRedirects() {
        let posts = DataExportParser.parse(json: Data(Self.facebookJSON.utf8))
        #expect(posts.count == 2)
        #expect(posts.allSatisfy { $0.platform == .facebook })
        #expect(posts[0].url.absoluteString == "https://example.com/recipe")
        #expect(posts[0].id == "facebook:https://example.com/recipe")
        #expect(posts[0].caption == "Pasta night")
        #expect(posts[1].id == "facebook:555")
        #expect(posts[1].kind == .reel)
    }

    @Test func tiktokExportSkipsSounds() {
        let posts = DataExportParser.parse(json: Data(Self.tiktokJSON.utf8))
        #expect(posts.count == 2)
        #expect(posts.allSatisfy { $0.platform == .tiktok && $0.kind == .video })
        #expect(Set(posts.map(\.id)) == ["tiktok:7362000000000000001", "tiktok:7362000000000000002"])
        #expect(posts.first { $0.id.hasSuffix("2") }?.author == "chef")
    }

    @Test func zipWithStoredAndDeflatedEntries() throws {
        let deflated = try (Data(Self.tiktokJSON.utf8) as NSData).compressed(using: .zlib) as Data
        let zip = ZipFixture.make([
            ("your_instagram_activity/saved/saved_posts.json", Data(Self.instagramJSON.utf8), nil),
            ("TikTok/user_data_tiktok.json", deflated, Data(Self.tiktokJSON.utf8).count),
            ("media/photo.jpg", Data([0xFF, 0xD8]), nil),
        ])
        let file = URL.temporaryDirectory.appending(path: "export-\(UUID()).zip")
        try zip.write(to: file)
        defer { try? FileManager.default.removeItem(at: file) }

        let posts = try DataExportParser.parse(fileAt: file)
        #expect(posts.count { $0.platform == .instagram } == 2)
        #expect(posts.count { $0.platform == .tiktok } == 2)
    }

    @Test func emptyExportThrows() throws {
        let file = URL.temporaryDirectory.appending(path: "empty-\(UUID()).json")
        try Data("{}".utf8).write(to: file)
        defer { try? FileManager.default.removeItem(at: file) }
        #expect(throws: DataExportParser.ImportError.self) { try DataExportParser.parse(fileAt: file) }
    }

    @Test func candidateFiles() {
        #expect(DataExportParser.isCandidate("your_instagram_activity/saved/saved_posts.json"))
        #expect(DataExportParser.isCandidate("user_data_tiktok.json"))
        #expect(!DataExportParser.isCandidate("messages/inbox/a/message_1.json"))
        #expect(!DataExportParser.isCandidate("__MACOSX/saved_posts.json"))
    }
}

/// Builds a minimal ZIP in memory (CRCs left at 0; the reader doesn't check them).
enum ZipFixture {
    /// `uncompressedSize` non-nil means `data` is already raw-DEFLATE compressed.
    static func make(_ files: [(name: String, data: Data, uncompressedSize: Int?)]) -> Data {
        var archive = Data()
        var directory = Data()
        for file in files {
            let offset = UInt32(archive.count)
            let name = Data(file.name.utf8)
            let method: UInt16 = file.uncompressedSize == nil ? 0 : 8
            let size = UInt32(file.uncompressedSize ?? file.data.count)

            var local = le32(0x0403_4b50)
            local += le16(20) + le16(0) + le16(method)
            local += le32(0) + le32(0)
            local += le32(UInt32(file.data.count)) + le32(size)
            local += le16(UInt16(name.count)) + le16(0)
            archive.append(local)
            archive.append(name)
            archive.append(file.data)

            var central = le32(0x0201_4b50)
            central += le16(20) + le16(20) + le16(0) + le16(method)
            central += le32(0) + le32(0)
            central += le32(UInt32(file.data.count)) + le32(size)
            central += le16(UInt16(name.count)) + le16(0) + le16(0)
            central += le16(0) + le16(0) + le32(0) + le32(offset)
            directory.append(central)
            directory.append(name)
        }
        let directoryOffset = UInt32(archive.count)
        archive.append(directory)
        var end = le32(0x0605_4b50)
        end += le16(0) + le16(0) + le16(UInt16(files.count)) + le16(UInt16(files.count))
        end += le32(UInt32(directory.count)) + le32(directoryOffset) + le16(0)
        archive.append(end)
        return archive
    }

    private static func le16(_ value: UInt16) -> Data { withUnsafeBytes(of: value.littleEndian) { Data($0) } }
    private static func le32(_ value: UInt32) -> Data { withUnsafeBytes(of: value.littleEndian) { Data($0) } }
}

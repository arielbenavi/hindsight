import Foundation
import Testing
@testable import Hindsight

struct MetaImportTests {
    /// The dev button's data: Reut's Meta download (data/ig-reut-export), byte-identical
    /// to the saved files in the raw zip. Both files together give every save.
    @Test func reutsExportGivesAll324Saves() throws {
        let urls = ["saved_posts", "saved_collections"].compactMap { Bundle.main.url(forResource: $0, withExtension: "json") }
        #expect(urls.count == 2)
        let posts = DataExportParser.combined(try urls.flatMap { try DataExportParser.parse(fileAt: $0) })
        #expect(posts.count == 324)
        #expect(posts.count { !$0.collections.isEmpty } == 252)
        #expect(posts.allSatisfy { $0.source == .igExport })
        // One file alone is only part of it (why the sheet says "choose the whole .zip").
        #expect(try DataExportParser.parse(fileAt: urls[0]).count == 113)
    }
}

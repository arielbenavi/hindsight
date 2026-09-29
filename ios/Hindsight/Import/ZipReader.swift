import Foundation

/// Minimal read-only ZIP reader: lists entries and extracts the ones we ask for,
/// without loading the whole archive (platform exports with media run to GBs).
/// Handles stored and deflated entries, and ZIP64 archives.
struct ZipReader {
    struct Entry {
        let name: String
        let method: UInt16
        let compressedSize: UInt64
        let uncompressedSize: UInt64
        let localHeaderOffset: UInt64
    }

    enum ZipError: Error {
        case notAZip, unsupportedMethod(UInt16), corrupt
    }

    let entries: [Entry]
    private let handle: FileHandle

    init(url: URL) throws {
        handle = try FileHandle(forReadingFrom: url)
        entries = try Self.readCentralDirectory(handle)
    }

    func data(for entry: Entry) throws -> Data {
        try handle.seek(toOffset: entry.localHeaderOffset)
        guard let header = try handle.read(upToCount: 30), header.count == 30,
              header.uint32(at: 0) == 0x0403_4b50 else { throw ZipError.corrupt }
        let dataStart = entry.localHeaderOffset + 30
            + UInt64(header.uint16(at: 26)) + UInt64(header.uint16(at: 28))
        try handle.seek(toOffset: dataStart)
        let raw = try handle.read(upToCount: Int(entry.compressedSize)) ?? Data()
        switch entry.method {
        case 0:
            return raw
        case 8:
            // NSData's .zlib is raw DEFLATE, which is what ZIP stores.
            return try (raw as NSData).decompressed(using: .zlib) as Data
        default:
            throw ZipError.unsupportedMethod(entry.method)
        }
    }

    // MARK: - Central directory

    private static func readCentralDirectory(_ handle: FileHandle) throws -> [Entry] {
        let fileSize = try handle.seekToEnd()
        let tailLength = min(fileSize, 65_557)
        try handle.seek(toOffset: fileSize - tailLength)
        let tail = try handle.read(upToCount: Int(tailLength)) ?? Data()

        // End of central directory record, searched from the back.
        guard tail.count >= 22,
              let eocd = stride(from: tail.count - 22, through: 0, by: -1)
                .first(where: { tail.uint32(at: $0) == 0x0605_4b50 })
        else { throw ZipError.notAZip }

        var count = UInt64(tail.uint16(at: eocd + 10))
        var size = UInt64(tail.uint32(at: eocd + 12))
        var offset = UInt64(tail.uint32(at: eocd + 16))

        // ZIP64: a locator sits right before the EOCD and points at the real values.
        if eocd >= 20, tail.uint32(at: eocd - 20) == 0x0706_4b50 {
            try handle.seek(toOffset: tail.uint64(at: eocd - 20 + 8))
            guard let z = try handle.read(upToCount: 56), z.count == 56,
                  z.uint32(at: 0) == 0x0606_4b50 else { throw ZipError.corrupt }
            count = z.uint64(at: 32)
            size = z.uint64(at: 40)
            offset = z.uint64(at: 48)
        }

        try handle.seek(toOffset: offset)
        guard let directory = try handle.read(upToCount: Int(size)), directory.count == Int(size) else {
            throw ZipError.corrupt
        }

        var entries: [Entry] = []
        var cursor = 0
        for _ in 0..<count {
            guard cursor + 46 <= directory.count, directory.uint32(at: cursor) == 0x0201_4b50 else {
                throw ZipError.corrupt
            }
            let nameLength = Int(directory.uint16(at: cursor + 28))
            let extraLength = Int(directory.uint16(at: cursor + 30))
            let commentLength = Int(directory.uint16(at: cursor + 32))
            var compressed = UInt64(directory.uint32(at: cursor + 20))
            var uncompressed = UInt64(directory.uint32(at: cursor + 24))
            var localOffset = UInt64(directory.uint32(at: cursor + 42))
            let nameStart = cursor + 46
            let name = String(decoding: directory[nameStart..<nameStart + nameLength], as: UTF8.self)

            // ZIP64 extra field (0x0001) holds whichever values overflowed 32 bits, in order.
            var extra = nameStart + nameLength
            let extraEnd = extra + extraLength
            while extra + 4 <= extraEnd {
                let id = directory.uint16(at: extra)
                let length = Int(directory.uint16(at: extra + 2))
                if id == 0x0001 {
                    var field = extra + 4
                    if uncompressed == 0xFFFF_FFFF { uncompressed = directory.uint64(at: field); field += 8 }
                    if compressed == 0xFFFF_FFFF { compressed = directory.uint64(at: field); field += 8 }
                    if localOffset == 0xFFFF_FFFF { localOffset = directory.uint64(at: field) }
                }
                extra += 4 + length
            }

            entries.append(Entry(
                name: name,
                method: directory.uint16(at: cursor + 10),
                compressedSize: compressed,
                uncompressedSize: uncompressed,
                localHeaderOffset: localOffset
            ))
            cursor = extraEnd + commentLength
        }
        return entries
    }
}

private extension Data {
    func uint16(at offset: Int) -> UInt16 {
        UInt16(self[startIndex + offset]) | UInt16(self[startIndex + offset + 1]) << 8
    }

    func uint32(at offset: Int) -> UInt32 {
        (0..<4).reduce(0) { $0 | UInt32(self[startIndex + offset + $1]) << (8 * $1) }
    }

    func uint64(at offset: Int) -> UInt64 {
        (0..<8).reduce(0) { $0 | UInt64(self[startIndex + offset + $1]) << (8 * $1) }
    }
}

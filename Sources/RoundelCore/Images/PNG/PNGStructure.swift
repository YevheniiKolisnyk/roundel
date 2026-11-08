import Foundation

public enum PNGOptimizeError: Error, Equatable, Sendable {
    case notPNG
    /// A chunk runs past the end, a checksum is wrong, or the image data does not inflate to exactly the size the header promises.
    case damaged
    /// Adam7 interlacing: not optimized (yet).
    case interlaced
    /// APNG: recompressing would drop the animation.
    case animated
    /// A structure this optimizer does not handle (an unknown critical chunk, an impossible header).
    case unsupported
    /// The optimizer's own result did not decode back to the same pixels. Never expected; it is the safety net.
    case verificationFailed
}

/// The fields of IHDR that matter here.
struct PNGHeader: Equatable {
    var width: Int
    var height: Int
    var bitDepth: Int
    var colorType: Int
    var interlace: Int

    static let validDepths: [Int: [Int]] = [0: [1, 2, 4, 8, 16], 2: [8, 16], 3: [1, 2, 4, 8], 4: [8, 16], 6: [8, 16]]

    var isValid: Bool {
        width > 0 && height > 0 && width <= Int(Int32.max) && height <= Int(Int32.max)
            && (Self.validDepths[colorType]?.contains(bitDepth) ?? false) && (interlace == 0 || interlace == 1)
    }
    var channels: Int { [0: 1, 2: 3, 3: 1, 4: 2, 6: 4][colorType] ?? 1 }
    var bitsPerPixel: Int { channels * bitDepth }
    /// How far back the filters look: whole bytes, at least one.
    var filterStep: Int { max(1, bitsPerPixel / 8) }
    var rowBytes: Int { (width * bitsPerPixel + 7) / 8 }

    init(width: Int, height: Int, bitDepth: Int, colorType: Int, interlace: Int = 0) {
        self.width = width; self.height = height; self.bitDepth = bitDepth; self.colorType = colorType; self.interlace = interlace
    }

    init?(ihdr data: [UInt8]) {
        guard data.count == 13, data[10] == 0, data[11] == 0 else { return nil }   // compression and filter method 0
        func u32(_ i: Int) -> Int { Int(data[i]) << 24 | Int(data[i + 1]) << 16 | Int(data[i + 2]) << 8 | Int(data[i + 3]) }
        self.init(width: u32(0), height: u32(4), bitDepth: Int(data[8]), colorType: Int(data[9]), interlace: Int(data[12]))
        guard isValid else { return nil }
    }

    var ihdrData: [UInt8] {
        func be(_ v: Int) -> [UInt8] { [UInt8(v >> 24 & 255), UInt8(v >> 16 & 255), UInt8(v >> 8 & 255), UInt8(v & 255)] }
        return be(width) + be(height) + [UInt8(bitDepth), UInt8(colorType), 0, 0, UInt8(interlace)]
    }
}

struct PNGChunk: Equatable {
    let type: String
    let data: [UInt8]

    init(type: String, data: [UInt8]) { self.type = type; self.data = data }

    /// Length, type, data and CRC, as they go into a file.
    func serialized() -> [UInt8] {
        let typeBytes = Array(type.utf8)
        func be(_ v: UInt32) -> [UInt8] { [UInt8(v >> 24 & 255), UInt8(v >> 16 & 255), UInt8(v >> 8 & 255), UInt8(v & 255)] }
        return be(UInt32(data.count)) + typeBytes + data + be(Zlib.crc32(typeBytes + data))
    }

    /// Ancillary chunks have a lowercase first letter.
    var isAncillary: Bool { (type.utf8.first ?? 0) & 0x20 != 0 }
}

/// A PNG file taken apart: every chunk in order (IHDR first, IEND last) and the joined image data.
struct PNGFile {
    static let signature: [UInt8] = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]

    var header: PNGHeader
    /// All chunks in file order, IDAT chunks included (the optimizer replaces them).
    var chunks: [PNGChunk]
    /// The concatenated data of the IDAT chunks: one zlib stream.
    var imageData: [UInt8] { chunks.filter { $0.type == "IDAT" }.flatMap(\.data) }

    static func parse(_ data: Data) throws -> PNGFile {
        let bytes = [UInt8](data)
        guard bytes.count >= 8, Array(bytes[0..<8]) == signature else { throw PNGOptimizeError.notPNG }

        var chunks: [PNGChunk] = []
        var offset = 8
        var sawEnd = false
        while offset + 12 <= bytes.count {
            let length = Int(bytes[offset]) << 24 | Int(bytes[offset + 1]) << 16 | Int(bytes[offset + 2]) << 8 | Int(bytes[offset + 3])
            let end = offset + 12 + length
            guard length >= 0, length <= Int(Int32.max), end <= bytes.count else { throw PNGOptimizeError.damaged }
            let typeBytes = Array(bytes[offset + 4..<offset + 8])
            guard typeBytes.allSatisfy({ ($0 >= 65 && $0 <= 90) || ($0 >= 97 && $0 <= 122) }) else { throw PNGOptimizeError.damaged }
            let body = Array(bytes[offset + 8..<offset + 8 + length])
            let stored = UInt32(bytes[end - 4]) << 24 | UInt32(bytes[end - 3]) << 16 | UInt32(bytes[end - 2]) << 8 | UInt32(bytes[end - 1])
            guard Zlib.crc32(typeBytes + body) == stored else { throw PNGOptimizeError.damaged }
            let type = String(decoding: typeBytes, as: UTF8.self)
            chunks.append(PNGChunk(type: type, data: body))
            offset = end
            if type == "IEND" { sawEnd = true; break }
        }
        guard sawEnd, let first = chunks.first, first.type == "IHDR" else { throw PNGOptimizeError.damaged }
        guard let header = PNGHeader(ihdr: first.data) else { throw PNGOptimizeError.unsupported }
        guard chunks.contains(where: { $0.type == "IDAT" }) else { throw PNGOptimizeError.damaged }
        return PNGFile(header: header, chunks: chunks)
    }

    func serialized() -> Data {
        var out = Self.signature
        for chunk in chunks { out += chunk.serialized() }
        return Data(out)
    }
}

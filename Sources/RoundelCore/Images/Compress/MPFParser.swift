import Foundation

/// One image listed in a JPEG's Multi-Picture Format index (the "MPF" APP2 segment cameras write: a primary image, previews,
/// thumbnails, and sometimes a disparity map or, on iPhones, a gain map).
public struct MPFEntry: Equatable, Sendable {
    public let attributes: UInt32
    public let size: UInt32
    /// Where the image starts, from the start of the MPF header.
    public let offset: UInt32

    /// What the type bits of the attributes say it is.
    public var role: String {
        switch attributes & 0x00FF_FFFF {
        case 0x030000: "primary image"
        case 0x010001: "large thumbnail (VGA)"
        case 0x010002: "large thumbnail (full HD)"
        case 0x020001: "multi-frame panorama"
        case 0x020002: "disparity map"
        case 0x020003: "multi-angle image"
        case 0x000000: "undefined (0x000000)"
        default: "other (0x\(String(format: "%06X", attributes & 0x00FF_FFFF)))"
        }
    }
}

/// Reads the MPF index of a JPEG. Only reads; a missing or broken index gives an empty list.
public enum MPFParser {
    public static func entries(in data: Data) -> [MPFEntry] {
        let bytes = [UInt8](data.prefix(4 << 20))
        guard bytes.count > 4, bytes[0] == 0xFF, bytes[1] == 0xD8 else { return [] }
        var i = 2
        while i + 4 <= bytes.count {
            guard bytes[i] == 0xFF else { return [] }
            let marker = bytes[i + 1]
            if marker == 0xFF { i += 1; continue }
            if marker == 0xD8 || marker == 0x01 || (0xD0...0xD7).contains(marker) { i += 2; continue }
            if marker == 0xD9 || marker == 0xDA { return [] }
            let length = Int(bytes[i + 2]) << 8 | Int(bytes[i + 3])
            guard length >= 2, i + 2 + length <= bytes.count else { return [] }
            let start = i + 4, end = i + 2 + length
            if marker == 0xE2, end - start > 8, Array(bytes[start..<start + 4]) == Array("MPF\0".utf8) {
                return parseIndex(bytes, base: start + 4, end: end)
            }
            i += 2 + length
        }
        return []
    }

    private static func parseIndex(_ b: [UInt8], base: Int, end: Int) -> [MPFEntry] {
        guard base + 8 <= end else { return [] }
        let little: Bool
        switch (b[base], b[base + 1]) {
        case (0x49, 0x49): little = true
        case (0x4D, 0x4D): little = false
        default: return []
        }
        func u16(_ o: Int) -> Int? { o >= base && o + 2 <= end ? (little ? Int(b[o]) | Int(b[o + 1]) << 8 : Int(b[o]) << 8 | Int(b[o + 1])) : nil }
        func u32(_ o: Int) -> UInt32? {
            guard o >= base, o + 4 <= end else { return nil }
            let v = (0..<4).map { UInt32(b[o + $0]) }
            return little ? v[0] | v[1] << 8 | v[2] << 16 | v[3] << 24 : v[0] << 24 | v[1] << 16 | v[2] << 8 | v[3]
        }
        guard u16(base + 2) == 42, let ifd = u32(base + 4), let count = u16(base + Int(ifd)), count <= 64 else { return [] }
        for n in 0..<count {
            let entry = base + Int(ifd) + 2 + n * 12
            guard u16(entry) == 0xB002, let size = u32(entry + 4), let offset = u32(entry + 8), size % 16 == 0, size <= 16 * 64 else { continue }
            var result: [MPFEntry] = []
            for k in 0..<Int(size / 16) {
                let o = base + Int(offset) + k * 16
                guard let attributes = u32(o), let length = u32(o + 4), let start = u32(o + 8) else { return [] }
                result.append(MPFEntry(attributes: attributes, size: length, offset: start))
            }
            return result
        }
        return []
    }
}

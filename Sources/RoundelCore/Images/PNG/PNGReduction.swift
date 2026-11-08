import Foundation

/// One way the pixels could be stored: its header, the pixel rows for it and the chunks it needs (PLTE, tRNS).
struct PNGCandidate {
    var header: PNGHeader
    var pixels: [UInt8]
    var extraChunks: [PNGChunk] = []
}

/// Lossless changes of how 8-bit pixels are stored. Each candidate describes exactly the same picture:
/// a dropped alpha channel was 255 everywhere, a dropped color channel pair was equal to the first one everywhere,
/// and a palette holds every distinct color the picture has, with its alpha.
enum PNGReduction {
    /// The candidates for non-interlaced 8-bit gray, gray+alpha, RGB or RGBA pixels (empty for anything else).
    /// The original storage is not among them.
    static func candidates(header: PNGHeader, pixels: [UInt8]) -> [PNGCandidate] {
        guard header.bitDepth == 8, header.interlace == 0, [0, 2, 4, 6].contains(header.colorType) else { return [] }
        let n = header.channels
        let count = header.width * header.height
        guard pixels.count == count * n else { return [] }

        let hasAlpha = header.colorType == 4 || header.colorType == 6
        let isColor = header.colorType == 2 || header.colorType == 6
        var opaque = true
        var gray = true
        var seen: [UInt32: Int] = [:]
        var order: [UInt32] = []
        var overflow = false

        for i in 0..<count {
            let o = i * n
            let r: UInt8, g: UInt8, b: UInt8, a: UInt8
            switch header.colorType {
            case 0: r = pixels[o]; g = r; b = r; a = 255
            case 4: r = pixels[o]; g = r; b = r; a = pixels[o + 1]
            case 2: r = pixels[o]; g = pixels[o + 1]; b = pixels[o + 2]; a = 255
            default: r = pixels[o]; g = pixels[o + 1]; b = pixels[o + 2]; a = pixels[o + 3]
            }
            if a != 255 { opaque = false }
            if r != g || g != b { gray = false }
            if !overflow {
                let key = UInt32(r) << 24 | UInt32(g) << 16 | UInt32(b) << 8 | UInt32(a)
                if seen[key] == nil {
                    if seen.count == 256 { overflow = true } else { seen[key] = order.count; order.append(key) }
                }
            }
        }

        var result: [PNGCandidate] = []

        // Fewer channels.
        let keepAlpha = hasAlpha && !opaque
        let keepColor = isColor && !gray
        let targetType = keepColor ? (keepAlpha ? 6 : 2) : (keepAlpha ? 4 : 0)
        if targetType != header.colorType {
            var reduced = header
            reduced.colorType = targetType
            var out: [UInt8] = []
            out.reserveCapacity(count * reduced.channels)
            for i in 0..<count {
                let o = i * n
                if keepColor { out.append(contentsOf: pixels[o..<o + 3]) } else { out.append(pixels[o]) }
                if keepAlpha { out.append(pixels[o + n - 1]) }
            }
            result.append(PNGCandidate(header: reduced, pixels: out))
        }

        // A palette.
        if !overflow, !order.isEmpty {
            // Entries with transparency first, so that tRNS only has to list them.
            let transparent = order.filter { $0 & 255 != 255 }
            let solid = order.filter { $0 & 255 == 255 }
            let entries = transparent + solid
            var index: [UInt32: Int] = [:]
            for (i, key) in entries.enumerated() { index[key] = i }
            let depth = entries.count <= 2 ? 1 : entries.count <= 4 ? 2 : entries.count <= 16 ? 4 : 8

            var paletteHeader = header
            paletteHeader.colorType = 3
            paletteHeader.bitDepth = depth
            let rowBytes = paletteHeader.rowBytes
            var out = [UInt8](repeating: 0, count: rowBytes * header.height)
            for y in 0..<header.height {
                for x in 0..<header.width {
                    let o = (y * header.width + x) * n
                    let r: UInt8, g: UInt8, b: UInt8, a: UInt8
                    switch header.colorType {
                    case 0: r = pixels[o]; g = r; b = r; a = 255
                    case 4: r = pixels[o]; g = r; b = r; a = pixels[o + 1]
                    case 2: r = pixels[o]; g = pixels[o + 1]; b = pixels[o + 2]; a = 255
                    default: r = pixels[o]; g = pixels[o + 1]; b = pixels[o + 2]; a = pixels[o + 3]
                    }
                    let value = index[UInt32(r) << 24 | UInt32(g) << 16 | UInt32(b) << 8 | UInt32(a)] ?? 0
                    if depth == 8 {
                        out[y * rowBytes + x] = UInt8(value)
                    } else {
                        out[y * rowBytes + x * depth / 8] |= UInt8(value << (8 - depth - (x * depth) % 8))
                    }
                }
            }
            var chunks = [PNGChunk(type: "PLTE", data: entries.flatMap { [UInt8($0 >> 24), UInt8($0 >> 16 & 255), UInt8($0 >> 8 & 255)] })]
            if !transparent.isEmpty { chunks.append(PNGChunk(type: "tRNS", data: transparent.map { UInt8($0 & 255) })) }
            result.append(PNGCandidate(header: paletteHeader, pixels: out, extraChunks: chunks))
        }
        return result
    }
}

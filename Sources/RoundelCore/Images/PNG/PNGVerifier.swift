import Foundation

/// The safety net of the PNG optimizer. It looks at the finished file, the very bytes that are about to be written, and
/// checks them against the file that was read, with its own plainly written code (it shares nothing with the optimizer's
/// filters, so a bug there cannot hide itself here):
///
/// - the file parses (every checksum is right) and has the same size;
/// - its chunks are the source's, in the same order and unchanged, except for what the optimizer may add (a palette and
///   its transparency; if they are missing the pixel comparison below fails) and what the user asked to strip;
/// - and every pixel, expanded to 16-bit RGBA (through the palette and transparency, whatever the sample format), is the
///   same. Rows are compared one at a time, so memory use stays small.
enum PNGVerifier {
    static func verify(source: PNGFile, sourceRaw: [UInt8], result data: Data, stripMetadata: Bool, addedChunkTypes: Set<String>) -> Bool {
        guard let result = try? PNGFile.parse(data), result.header.interlace == 0,
              result.header.width == source.header.width, result.header.height == source.header.height else { return false }

        // Chunks.
        let core: Set<String> = ["IHDR", "IDAT", "IEND"]
        let sourceTypes = Set(source.chunks.map(\.type))
        let expected = source.chunks.filter { !core.contains($0.type) && !(stripMetadata && PNGOptimizer.isStrippable($0)) }
        let actual = result.chunks.filter { chunk in
            !core.contains(chunk.type) && !(addedChunkTypes.contains(chunk.type) && !sourceTypes.contains(chunk.type))
        }
        guard actual == expected else { return false }

        // Pixels.
        let a = source.header, b = result.header
        let resultSize = b.height * (b.rowBytes + 1)
        guard stream(result).count * 1100 >= resultSize, let resultRaw = Zlib.inflate(stream(result), limit: resultSize), resultRaw.count == resultSize,
              sourceRaw.count == a.height * (a.rowBytes + 1) else { return false }
        let pa = Palette(source), pb = Palette(result)

        var previousA = [UInt8](repeating: 0, count: a.rowBytes), currentA = previousA
        var previousB = [UInt8](repeating: 0, count: b.rowBytes), currentB = previousB
        var pixelsA = [UInt16](repeating: 0, count: a.width * 4), pixelsB = pixelsA
        for y in 0..<a.height {
            guard unfilterRow(sourceRaw, at: y * (a.rowBytes + 1), into: &currentA, previous: previousA, step: a.filterStep),
                  unfilterRow(resultRaw, at: y * (b.rowBytes + 1), into: &currentB, previous: previousB, step: b.filterStep) else { return false }
            expand(currentA, header: a, palette: pa, into: &pixelsA)
            expand(currentB, header: b, palette: pb, into: &pixelsB)
            if pixelsA != pixelsB { return false }
            swap(&previousA, &currentA)
            swap(&previousB, &currentB)
        }
        return true
    }

    private static func stream(_ file: PNGFile) -> [UInt8] { file.imageData }

    // MARK: Reference unfiltering (one row at a time)

    /// Undoes the filter of the row that starts at `offset` in `raw`; `false` for a filter type that does not exist.
    static func unfilterRow(_ raw: [UInt8], at offset: Int, into row: inout [UInt8], previous: [UInt8], step: Int) -> Bool {
        let type = raw[offset]
        guard type <= 4 else { return false }
        for i in 0..<row.count {
            let x = Int(raw[offset + 1 + i])
            let left = i >= step ? Int(row[i - step]) : 0
            let up = Int(previous[i])
            let upLeft = i >= step ? Int(previous[i - step]) : 0
            let predicted: Int
            switch type {
            case 0: predicted = 0
            case 1: predicted = left
            case 2: predicted = up
            case 3: predicted = (left + up) / 2
            default:
                let p = left + up - upLeft
                let pa = abs(p - left), pb = abs(p - up), pc = abs(p - upLeft)
                predicted = (pa <= pb && pa <= pc) ? left : (pb <= pc ? up : upLeft)
            }
            row[i] = UInt8((x + predicted) & 255)
        }
        return true
    }

    /// All rows unfiltered (for tests of the reference code itself).
    static func unfilterAll(_ filtered: [UInt8], rowBytes: Int, height: Int, step: Int) -> [UInt8] {
        var out: [UInt8] = []
        var previous = [UInt8](repeating: 0, count: rowBytes), row = previous
        for y in 0..<height {
            guard unfilterRow(filtered, at: y * (rowBytes + 1), into: &row, previous: previous, step: step) else { return [] }
            out += row
            swap(&previous, &row)
        }
        return out
    }

    // MARK: Expanding a row to 16-bit RGBA

    private struct Palette {
        var rgb: [UInt8]
        var trns: [UInt8]
        init(_ file: PNGFile) {
            rgb = file.chunks.first { $0.type == "PLTE" }?.data ?? []
            trns = file.chunks.first { $0.type == "tRNS" }?.data ?? []
        }
    }

    private static func expand(_ row: [UInt8], header h: PNGHeader, palette: Palette, into out: inout [UInt16]) {
        let depth = h.bitDepth
        let maxValue = (1 << depth) - 1
        func sample(_ index: Int) -> Int {
            switch depth {
            case 16: return Int(row[index * 2]) << 8 | Int(row[index * 2 + 1])
            case 8: return Int(row[index])
            default:
                let bit = index * depth
                return Int(row[bit / 8]) >> (8 - depth - bit % 8) & maxValue
            }
        }
        func scale(_ v: Int) -> UInt16 { UInt16(v * 65535 / maxValue) }
        func key(_ i: Int) -> Int? { palette.trns.count >= 2 * i + 2 ? Int(palette.trns[2 * i]) << 8 | Int(palette.trns[2 * i + 1]) : nil }
        let n = h.channels
        for x in 0..<h.width {
            let o = x * 4
            switch h.colorType {
            case 0:
                let v = sample(x), g = scale(v)
                out[o] = g; out[o + 1] = g; out[o + 2] = g; out[o + 3] = key(0) == v ? 0 : 65535
            case 2:
                let r = sample(x * n), g = sample(x * n + 1), b = sample(x * n + 2)
                out[o] = scale(r); out[o + 1] = scale(g); out[o + 2] = scale(b)
                out[o + 3] = (key(0) == r && key(1) == g && key(2) == b) ? 0 : 65535
            case 3:
                let i = sample(x)
                if palette.rgb.count >= 3 * i + 3 {
                    out[o] = UInt16(palette.rgb[3 * i]) * 257; out[o + 1] = UInt16(palette.rgb[3 * i + 1]) * 257; out[o + 2] = UInt16(palette.rgb[3 * i + 2]) * 257
                } else {
                    out[o] = 0xFFFF; out[o + 1] = 0; out[o + 2] = 0xFFFF   // an index outside the palette: matches nothing real
                }
                out[o + 3] = i < palette.trns.count ? UInt16(palette.trns[i]) * 257 : 65535
            case 4:
                let g = scale(sample(x * 2))
                out[o] = g; out[o + 1] = g; out[o + 2] = g; out[o + 3] = scale(sample(x * 2 + 1))
            default:
                out[o] = scale(sample(x * 4)); out[o + 1] = scale(sample(x * 4 + 1)); out[o + 2] = scale(sample(x * 4 + 2)); out[o + 3] = scale(sample(x * 4 + 3))
            }
        }
    }
}

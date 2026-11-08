import Foundation
@testable import RoundelCore

/// An independent PNG writer and reader for tests: an unoptimized file (filter "none", quick deflate) goes in, and what
/// comes out is compared pixel by pixel after expanding everything to 16-bit RGBA. It shares only zlib with the
/// optimizer, not its filters, reductions or chunk handling.
enum TestPNG {
    struct Spec {
        var width: Int
        var height: Int
        var colorType: Int
        var bitDepth: Int
        /// The sample of channel `channel` (0...channels-1) at (x, y), 0...(2^bitDepth - 1).
        var sample: (Int, Int, Int) -> Int
        var palette: [UInt8]? = nil
        /// Chunks written before the image data, after PLTE if there is one, in this order.
        var chunks: [(String, [UInt8])] = []
        var level: Int32 = 1
        var interlace = 0
    }

    static func channels(_ colorType: Int) -> Int { [0: 1, 2: 3, 3: 1, 4: 2, 6: 4][colorType]! }

    static func packedRows(_ spec: Spec) -> [UInt8] {
        let n = channels(spec.colorType)
        let rowBytes = (spec.width * n * spec.bitDepth + 7) / 8
        var out = [UInt8](repeating: 0, count: rowBytes * spec.height)
        for y in 0..<spec.height {
            var bitPosition = 0
            for x in 0..<spec.width {
                for c in 0..<n {
                    let v = spec.sample(x, y, c)
                    switch spec.bitDepth {
                    case 16:
                        out[y * rowBytes + bitPosition / 8] = UInt8(v >> 8 & 255)
                        out[y * rowBytes + bitPosition / 8 + 1] = UInt8(v & 255)
                    case 8:
                        out[y * rowBytes + bitPosition / 8] = UInt8(v & 255)
                    default:
                        out[y * rowBytes + bitPosition / 8] |= UInt8(v << (8 - spec.bitDepth - bitPosition % 8))
                    }
                    bitPosition += spec.bitDepth
                }
            }
        }
        return out
    }

    static func make(_ spec: Spec) -> Data {
        let rowBytes = (spec.width * channels(spec.colorType) * spec.bitDepth + 7) / 8
        let rows = packedRows(spec)
        var filtered: [UInt8] = []
        for y in 0..<spec.height { filtered.append(0); filtered += rows[(y * rowBytes)..<((y + 1) * rowBytes)] }
        let header = PNGHeader(width: spec.width, height: spec.height, bitDepth: spec.bitDepth, colorType: spec.colorType, interlace: spec.interlace)
        var chunks = [PNGChunk(type: "IHDR", data: header.ihdrData)]
        if let palette = spec.palette { chunks.append(PNGChunk(type: "PLTE", data: palette)) }
        for (type, data) in spec.chunks { chunks.append(PNGChunk(type: type, data: data)) }
        chunks.append(PNGChunk(type: "IDAT", data: Zlib.deflate(filtered, level: spec.level)!))
        chunks.append(PNGChunk(type: "IEND", data: []))
        return PNGFile(header: header, chunks: chunks).serialized()
    }

    // MARK: Reader

    struct Decoded: Equatable {
        var width: Int
        var height: Int
        /// R, G, B, A of every pixel, 16 bits each, rows top to bottom.
        var rgba16: [UInt16]
    }

    static func chunks(of data: Data) -> [PNGChunk] { (try? PNGFile.parse(data).chunks) ?? [] }

    /// Decodes any non-interlaced PNG (all colour types and depths, PLTE, tRNS) to 16-bit RGBA, or `nil`.
    static func decode(_ data: Data) -> Decoded? {
        guard let file = try? PNGFile.parse(data), file.header.interlace == 0 else { return nil }
        let h = file.header
        let rowBytes = h.rowBytes
        guard let raw = Zlib.inflate(file.imageData, limit: h.height * (rowBytes + 1) + 16), raw.count == h.height * (rowBytes + 1) else { return nil }

        // Undo the filters, written out plainly.
        let step = h.filterStep
        var pix = [UInt8](repeating: 0, count: h.height * rowBytes)
        for y in 0..<h.height {
            let type = raw[y * (rowBytes + 1)]
            for i in 0..<rowBytes {
                let x = Int(raw[y * (rowBytes + 1) + 1 + i])
                let a = i >= step ? Int(pix[y * rowBytes + i - step]) : 0
                let b = y > 0 ? Int(pix[(y - 1) * rowBytes + i]) : 0
                let c = (y > 0 && i >= step) ? Int(pix[(y - 1) * rowBytes + i - step]) : 0
                var p = 0
                switch type {
                case 1: p = a
                case 2: p = b
                case 3: p = (a + b) / 2
                case 4:
                    let q = a + b - c
                    let pa = abs(q - a), pb = abs(q - b), pc = abs(q - c)
                    p = (pa <= pb && pa <= pc) ? a : (pb <= pc ? b : c)
                default: break
                }
                pix[y * rowBytes + i] = UInt8((x + p) & 255)
            }
        }

        let palette = file.chunks.first { $0.type == "PLTE" }?.data ?? []
        let trns = file.chunks.first { $0.type == "tRNS" }?.data ?? []
        let maxValue = (1 << h.bitDepth) - 1
        func sample(_ y: Int, _ index: Int) -> Int {   // the index-th sample of row y
            switch h.bitDepth {
            case 16: return Int(pix[y * rowBytes + index * 2]) << 8 | Int(pix[y * rowBytes + index * 2 + 1])
            case 8: return Int(pix[y * rowBytes + index])
            default:
                let bit = index * h.bitDepth
                return Int(pix[y * rowBytes + bit / 8]) >> (8 - h.bitDepth - bit % 8) & maxValue
            }
        }
        func scale(_ v: Int) -> UInt16 { UInt16(v * 65535 / maxValue) }
        func colorKey(_ i: Int) -> Int? { trns.count >= 2 * i + 2 ? Int(trns[2 * i]) << 8 | Int(trns[2 * i + 1]) : nil }

        var out = [UInt16](repeating: 0, count: h.width * h.height * 4)
        for y in 0..<h.height {
            for x in 0..<h.width {
                let n = h.channels
                let s = (0..<n).map { sample(y, x * n + $0) }
                var px: [UInt16]
                switch h.colorType {
                case 0:
                    let v = scale(s[0]); px = [v, v, v, colorKey(0) == s[0] ? 0 : 65535]
                case 2:
                    px = [scale(s[0]), scale(s[1]), scale(s[2]), (colorKey(0) == s[0] && colorKey(1) == s[1] && colorKey(2) == s[2]) ? 0 : 65535]
                case 3:
                    let i = s[0]
                    guard palette.count >= 3 * i + 3 else { return nil }
                    px = [UInt16(palette[3 * i]) * 257, UInt16(palette[3 * i + 1]) * 257, UInt16(palette[3 * i + 2]) * 257, i < trns.count ? UInt16(trns[i]) * 257 : 65535]
                case 4:
                    let v = scale(s[0]); px = [v, v, v, scale(s[1])]
                default:
                    px = [scale(s[0]), scale(s[1]), scale(s[2]), scale(s[3])]
                }
                let o = (y * h.width + x) * 4
                for k in 0..<4 { out[o + k] = px[k] }
            }
        }
        return Decoded(width: h.width, height: h.height, rgba16: out)
    }
}

/// Deterministic pseudo-random numbers for generated pictures.
struct TestNoise {
    var state: UInt32
    mutating func next() -> Int { state = state &* 1_664_525 &+ 1_013_904_223; return Int(state >> 16) }
}

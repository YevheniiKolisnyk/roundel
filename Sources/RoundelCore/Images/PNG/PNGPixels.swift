import Foundation

/// A PNG's pixels as 8-bit straight RGBA, read with the reference code of `PNGVerifier` (every color type and bit depth,
/// palette and tRNS included; 16-bit samples are rounded to 8). For non-interlaced files only.
enum PNGPixels {
    static func rgba8(_ file: PNGFile) -> [UInt8]? {
        let h = file.header
        guard h.interlace == 0 else { return nil }
        let size = h.height * (h.rowBytes + 1)
        let stream = file.imageData
        guard stream.count * 1100 >= size, size <= PNGOptimizer.maxRawBytes, let raw = Zlib.inflate(stream, limit: size), raw.count == size else { return nil }
        let palette = PNGVerifier.Palette(file)
        var out = [UInt8](repeating: 0, count: h.width * h.height * 4)
        var previous = [UInt8](repeating: 0, count: h.rowBytes), row = previous
        var wide = [UInt16](repeating: 0, count: h.width * 4)
        for y in 0..<h.height {
            guard PNGVerifier.unfilterRow(raw, at: y * (h.rowBytes + 1), into: &row, previous: previous, step: h.filterStep) else { return nil }
            let base = y * h.width * 4
            if h.bitDepth == 8 {
                // The common case, straight from the bytes.
                switch h.colorType {
                case 6: for i in 0..<(h.width * 4) { out[base + i] = row[i] }
                case 2: for x in 0..<h.width { let o = base + x * 4, s = x * 3; out[o] = row[s]; out[o + 1] = row[s + 1]; out[o + 2] = row[s + 2]; out[o + 3] = 255 }
                case 0: for x in 0..<h.width { let o = base + x * 4; out[o] = row[x]; out[o + 1] = row[x]; out[o + 2] = row[x]; out[o + 3] = 255 }
                case 4: for x in 0..<h.width { let o = base + x * 4; out[o] = row[x * 2]; out[o + 1] = row[x * 2]; out[o + 2] = row[x * 2]; out[o + 3] = row[x * 2 + 1] }
                default: break
                }
                // Types 0, 2 and 3 can carry a transparency chunk and type 3 needs its palette: those go the general way.
                if [4, 6].contains(h.colorType) || (h.colorType != 3 && palette.trns.isEmpty) { swap(&previous, &row); continue }
            }
            PNGVerifier.expand(row, header: h, palette: palette, into: &wide)
            for i in 0..<(h.width * 4) { out[base + i] = UInt8((Int(wide[i]) + 128) / 257) }
            swap(&previous, &row)
        }
        return out
    }
}

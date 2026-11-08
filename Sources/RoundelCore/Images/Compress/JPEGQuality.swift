import Foundation

/// JPEG quality, on two scales: ImageIO's 0-1 `lossyCompressionQuality` and the classic IJG 1-100 scale that the
/// quantization tables inside a file reveal. The first is what we write with, the second is all a file can tell us
/// about its own quality, so the mapping between them was measured (files written by ImageIO, tables read back).
public enum JPEGQuality {
    /// A recompressed file should end up this many IJG points below its source, or it will hardly shrink.
    public static let safetyMargin = 4
    /// Below this (ImageIO 0.3) a JPEG is already so heavily compressed that recompressing only makes it ugly.
    public static let lowestWorthRecompressing = 46.0

    /// Measured: (ImageIO quality, IJG quality).
    private static let scale: [(Double, Double)] = [(0, 25), (0.1, 25), (0.2, 31), (0.3, 46), (0.4, 67), (0.5, 80), (0.6, 87), (0.7, 92), (0.8, 94), (0.9, 96), (1.0, 100)]

    public static func ijg(forImageIO quality: Double) -> Double {
        let q = min(max(quality.isFinite ? quality : 0, 0), 1)
        for (lower, upper) in zip(scale, scale.dropFirst()) where q <= upper.0 {
            let t = (q - lower.0) / (upper.0 - lower.0)
            return lower.1 + t * (upper.1 - lower.1)
        }
        return 100
    }

    /// The highest ImageIO quality whose IJG quality does not exceed `ijg`.
    public static func imageIO(forIJG ijg: Double) -> Double {
        var q = 1.0
        while q > 0 {
            if self.ijg(forImageIO: q) <= ijg { return q }
            q -= 0.005
        }
        return 0
    }

    /// The best ImageIO quality for recompressing a source of IJG quality `source`: `safetyMargin` below it. `nil` when
    /// that would be too low to be worth it (the file is already as small as is sensible).
    public static func cap(forSourceIJG source: Int) -> Double? {
        let target = Double(source - safetyMargin)
        return target < lowestWorthRecompressing ? nil : imageIO(forIJG: target)
    }

    // MARK: Reading a file's quality

    private static let standardLuminance: [Double] = [
        16, 11, 10, 16, 24, 40, 51, 61, 12, 12, 14, 19, 26, 58, 60, 55, 14, 13, 16, 24, 40, 57, 69, 56, 14, 17, 22, 29, 51, 87, 80, 62,
        18, 22, 37, 56, 68, 109, 103, 77, 24, 35, 55, 64, 81, 104, 113, 92, 49, 64, 78, 87, 103, 121, 120, 101, 72, 92, 95, 98, 112, 100, 103, 99,
    ]
    /// Position in the file (zigzag order) -> position in the table above (row by row).
    private static let zigzag: [Int] = [
        0, 1, 8, 16, 9, 2, 3, 10, 17, 24, 32, 25, 18, 11, 4, 5, 12, 19, 26, 33, 40, 48, 41, 34, 27, 20, 13, 6, 7, 14, 21, 28,
        35, 42, 49, 56, 57, 50, 43, 36, 29, 22, 15, 23, 30, 37, 44, 51, 58, 59, 52, 45, 38, 31, 39, 46, 53, 60, 61, 54, 47, 55, 62, 63,
    ]

    /// The IJG quality (1-100) whose scaled standard table is closest to the file's first (luminance) table; `nil` if the
    /// file has no 8-bit table, or ends inside it.
    public static func estimateIJG(from data: Data) -> Int? {
        let bytes = [UInt8](data.prefix(1 << 20))   // the tables are at the start
        guard bytes.count > 4, bytes[0] == 0xFF, bytes[1] == 0xD8 else { return nil }
        var i = 2
        while i + 4 <= bytes.count {
            guard bytes[i] == 0xFF else { return nil }
            let marker = bytes[i + 1]
            if marker == 0xFF { i += 1; continue }
            if marker == 0xD8 || marker == 0x01 || (0xD0...0xD7).contains(marker) { i += 2; continue }
            if marker == 0xD9 || marker == 0xDA { return nil }   // end of image / start of scan: no table came before
            let length = Int(bytes[i + 2]) << 8 | Int(bytes[i + 3])
            guard length >= 2, i + 2 + length <= bytes.count else { return nil }
            if marker == 0xDB {
                var p = i + 4
                let end = i + 2 + length
                while p < end {
                    let info = bytes[p]
                    let precision = info >> 4, id = info & 15
                    let size = precision == 0 ? 64 : 128
                    guard p + 1 + size <= end else { return nil }
                    if id == 0, precision == 0 {
                        var table = [Double](repeating: 0, count: 64)
                        for k in 0..<64 { table[zigzag[k]] = Double(bytes[p + 1 + k]) }
                        return bestQuality(for: table)
                    }
                    p += 1 + size
                }
            }
            i += 2 + length
        }
        return nil
    }

    private static func bestQuality(for table: [Double]) -> Int {
        var best = (error: Double.infinity, quality: 1)
        for quality in 1...100 {
            let scaling = quality < 50 ? 5000.0 / Double(quality) : 200.0 - 2.0 * Double(quality)
            var error = 0.0
            for k in 0..<64 {
                let value = min(255, max(1, ((standardLuminance[k] * scaling + 50) / 100).rounded(.down)))
                error += abs(value - table[k])
            }
            if error < best.error { best = (error, quality) }
        }
        return best.quality
    }
}

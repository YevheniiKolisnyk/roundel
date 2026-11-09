import Foundation

/// A picture reduced to a palette: RGBA entries (4 bytes each) and one palette index per pixel.
struct QuantizedImage: Equatable {
    var palette: [UInt8]
    var indices: [UInt8]
    var count: Int { palette.count / 4 }
}

/// Median-cut color quantization with optional Floyd-Steinberg dithering, written for flat graphics (screenshots, icons).
/// Deterministic: buckets are sorted, ties are broken by position, nothing depends on hashing order or threads.
///
/// - Fully transparent pixels get one dedicated (0, 0, 0, 0) entry and stay exactly transparent; opaque pixels are matched
///   to entries of their own opacity (alpha counts in the distance).
/// - The palette is chosen from a histogram of colors cut to 6 bits per channel and 5 bits of alpha, over at most about two
///   million pixels (every n-th one); every pixel is then mapped.
enum PNGQuantizer {
    private struct Bucket {
        var key: UInt32
        var count = 0
        var sum = (r: 0, g: 0, b: 0, a: 0)
        var mean: (r: Double, g: Double, b: Double, a: Double) {
            let n = Double(max(count, 1)); return (Double(sum.r) / n, Double(sum.g) / n, Double(sum.b) / n, Double(sum.a) / n)
        }
    }

    static func quantize(rgba: [UInt8], width: Int, height: Int, maxColors: Int, dither: Bool) -> QuantizedImage {
        let pixelCount = width * height
        guard pixelCount > 0, rgba.count == pixelCount * 4, maxColors > 0 else { return QuantizedImage(palette: [], indices: []) }

        // Histogram of (nearly) distinct colors.
        var table: [UInt32: Int] = [:]
        var buckets: [Bucket] = []
        var hasTransparent = false
        let stride = max(1, pixelCount / 2_000_000)
        var i = 0
        while i < pixelCount {
            let o = i * 4
            let a = Int(rgba[o + 3])
            if a == 0 { hasTransparent = true } else {
                let r = Int(rgba[o]), g = Int(rgba[o + 1]), b = Int(rgba[o + 2])
                let key = UInt32(r >> 2) << 17 | UInt32(g >> 2) << 11 | UInt32(b >> 2) << 5 | UInt32(a >> 3)
                let index: Int
                if let found = table[key] { index = found } else { index = buckets.count; table[key] = index; buckets.append(Bucket(key: key)) }
                buckets[index].count += 1
                buckets[index].sum.r += r; buckets[index].sum.g += g; buckets[index].sum.b += b; buckets[index].sum.a += a
            }
            i += stride
        }
        // The transparent pixels not in the sample still need their entry.
        if !hasTransparent { for j in 0..<pixelCount where rgba[j * 4 + 3] == 0 { hasTransparent = true; break } }
        buckets.sort { $0.key < $1.key }

        var palette = medianCut(buckets, limit: maxColors - (hasTransparent ? 1 : 0))
        var transparentIndex = -1
        if hasTransparent { transparentIndex = palette.count / 4; palette += [0, 0, 0, 0] }
        let entries = palette.count / 4
        guard entries > 0 else { return QuantizedImage(palette: [], indices: [UInt8](repeating: 0, count: pixelCount)) }

        // Nearest palette entry, remembered per exact color.
        var cache: [UInt32: UInt8] = [:]
        func nearest(_ r: Int, _ g: Int, _ b: Int, _ a: Int) -> UInt8 {
            let key = UInt32(r) << 24 | UInt32(g) << 16 | UInt32(b) << 8 | UInt32(a)
            if let hit = cache[key] { return hit }
            var best = 0, bestDistance = Int.max
            for e in 0..<entries where e != transparentIndex {
                let dr = r - Int(palette[e * 4]), dg = g - Int(palette[e * 4 + 1]), db = b - Int(palette[e * 4 + 2]), da = a - Int(palette[e * 4 + 3])
                let d = dr * dr + dg * dg + db * db + 3 * da * da
                if d < bestDistance { bestDistance = d; best = e }
            }
            cache[key] = UInt8(best)
            return UInt8(best)
        }

        var indices = [UInt8](repeating: 0, count: pixelCount)
        if !dither {
            for p in 0..<pixelCount {
                let o = p * 4
                indices[p] = rgba[o + 3] == 0 ? UInt8(transparentIndex) : nearest(Int(rgba[o]), Int(rgba[o + 1]), Int(rgba[o + 2]), Int(rgba[o + 3]))
            }
            return QuantizedImage(palette: palette, indices: indices)
        }

        // Floyd-Steinberg, left to right and back again on alternate rows; the error only travels over opaque-ish pixels.
        var current = [Float](repeating: 0, count: (width + 2) * 3), next = current
        for y in 0..<height {
            let forward = y % 2 == 0
            for step in 0..<width {
                let x = forward ? step : width - 1 - step
                let o = (y * width + x) * 4
                let slot = (x + 1) * 3
                if rgba[o + 3] == 0 { indices[y * width + x] = UInt8(transparentIndex); continue }
                let r = Int(max(0, min(255, (Float(rgba[o]) + current[slot]).rounded())))
                let g = Int(max(0, min(255, (Float(rgba[o + 1]) + current[slot + 1]).rounded())))
                let b = Int(max(0, min(255, (Float(rgba[o + 2]) + current[slot + 2]).rounded())))
                let chosen = nearest(r, g, b, Int(rgba[o + 3]))
                indices[y * width + x] = chosen
                let errors = [Float(r) - Float(palette[Int(chosen) * 4]), Float(g) - Float(palette[Int(chosen) * 4 + 1]), Float(b) - Float(palette[Int(chosen) * 4 + 2])]
                let ahead = forward ? 1 : -1
                for c in 0..<3 {
                    current[slot + ahead * 3 + c] += errors[c] * 7 / 16
                    next[slot - ahead * 3 + c] += errors[c] * 3 / 16
                    next[slot + c] += errors[c] * 5 / 16
                    next[slot + ahead * 3 + c] += errors[c] * 1 / 16
                }
            }
            swap(&current, &next)
            for k in 0..<next.count { next[k] = 0 }
        }
        return QuantizedImage(palette: palette, indices: indices)
    }

    /// The palette (RGBA, 4 bytes per entry) of at most `limit` colors for the buckets.
    private static func medianCut(_ buckets: [Bucket], limit: Int) -> [UInt8] {
        guard !buckets.isEmpty, limit > 0 else { return [] }
        let means = buckets.map(\.mean)
        var order = Array(buckets.indices)
        var boxes: [(start: Int, end: Int)] = [(0, buckets.count)]

        func range(_ box: (start: Int, end: Int)) -> (axis: Int, spread: Double) {
            var lo = [Double.infinity, .infinity, .infinity, .infinity], hi = [-Double.infinity, -.infinity, -.infinity, -.infinity]
            for k in box.start..<box.end {
                let m = means[order[k]]
                for (axis, v) in [m.r, m.g, m.b, m.a].enumerated() { lo[axis] = min(lo[axis], v); hi[axis] = max(hi[axis], v) }
            }
            var best = (axis: 0, spread: -1.0)
            for axis in 0..<4 { let spread = (hi[axis] - lo[axis]) * (axis == 3 ? 2 : 1); if spread > best.spread { best = (axis, spread) } }
            return best
        }

        while boxes.count < limit {
            // The box worth cutting most: many pixels over a wide spread of color.
            var chosen = -1
            var chosenScore = 0.0
            for (index, box) in boxes.enumerated() where box.end - box.start > 1 {
                let population = order[box.start..<box.end].reduce(0) { $0 + buckets[$1].count }
                let score = Double(population) * range(box).spread
                if score > chosenScore { chosenScore = score; chosen = index }
            }
            guard chosen >= 0 else { break }
            let box = boxes[chosen]
            let axis = range(box).axis
            func value(_ index: Int) -> Double { let m = means[index]; return [m.r, m.g, m.b, m.a][axis] }
            order[box.start..<box.end].sort { value($0) != value($1) ? value($0) < value($1) : buckets[$0].key < buckets[$1].key }
            let total = order[box.start..<box.end].reduce(0) { $0 + buckets[$1].count }
            var running = 0
            var cut = box.start + 1
            for k in box.start..<(box.end - 1) {
                running += buckets[order[k]].count
                cut = k + 1
                if running * 2 >= total { break }
            }
            boxes[chosen] = (box.start, cut)
            boxes.append((cut, box.end))
        }

        var palette: [UInt8] = []
        for box in boxes {
            var n = 0, r = 0, g = 0, b = 0, a = 0
            for k in box.start..<box.end { let bucket = buckets[order[k]]; n += bucket.count; r += bucket.sum.r; g += bucket.sum.g; b += bucket.sum.b; a += bucket.sum.a }
            let d = max(n, 1)
            palette += [UInt8((r + d / 2) / d), UInt8((g + d / 2) / d), UInt8((b + d / 2) / d), UInt8((a + d / 2) / d)]
        }
        return palette
    }
}

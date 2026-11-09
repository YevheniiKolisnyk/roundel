import Foundation

/// The rules that decide whether a reduced-color PNG may be used. A lossy result is accepted only if it is clearly smaller than
/// the lossless one AND, as it would be written, looks the same as the original.
enum PNGLossyGuard {
    struct Thresholds: Equatable {
        /// The lossy file must be at most this much smaller than the lossless one to be worth the loss (0.30: 30% smaller).
        var minShrink = 0.30
        /// Structural similarity of the luminance, and of each of R, G, B, after compositing over mid-gray.
        var lumaSSIM = 0.98
        var channelSSIM = 0.97
        /// Largest change of any pixel's alpha, out of 255.
        var maxAlphaChange = 8
        /// More distinct colors than this in a sample means a photograph, which a palette ruins.
        var maxSampledColors = 8192
        var maxPixels = 24_000_000
        /// Banding: at least this share of the picture must be smooth gradient for the check to apply, and the result is refused
        /// if at least `bandingCollapsed` of those blocks have collapsed to one or two colors.
        var bandingMinSmoothShare = 0.03
        var bandingCollapsed = 0.5

        static let standard = Thresholds()
    }

    enum Verdict: Equatable {
        case accepted
        case tooLarge
        case photographic
        case alphaChanged(Int)
        case lumaSimilarity(Double)
        case channelSimilarity(Int, Double)
        case banding
        case notSmallEnough
    }

    // MARK: Before quantizing

    /// Why not to try at all, or `nil`.
    static func precheck(width: Int, height: Int, sampledColors: Int, thresholds: Thresholds) -> Verdict? {
        if width * height > thresholds.maxPixels { return .tooLarge }
        if sampledColors > thresholds.maxSampledColors { return .photographic }
        return nil
    }

    /// Distinct RGBA values in every n-th pixel (n chosen to look at about a million), counting stops just past `limit`.
    static func sampledColors(_ rgba: [UInt8], width: Int, height: Int, limit: Int) -> Int {
        let pixels = width * height
        guard pixels > 0, rgba.count == pixels * 4 else { return 0 }
        let stride = max(1, pixels / 1_000_000)
        var seen = Set<UInt32>()
        var i = 0
        while i < pixels {
            let o = i * 4
            seen.insert(UInt32(rgba[o]) << 24 | UInt32(rgba[o + 1]) << 16 | UInt32(rgba[o + 2]) << 8 | UInt32(rgba[o + 3]))
            if seen.count > limit { return seen.count }
            i += stride
        }
        return seen.count
    }

    static func isSmallEnough(lossy: Int, lossless: Int, thresholds: Thresholds) -> Bool {
        lossless > 0 && Double(lossy) <= Double(lossless) * (1 - thresholds.minShrink)
    }

    // MARK: After quantizing

    /// Judges `result` (what would be written, decoded) against `original`: alpha first, then the similarity scores, then banding.
    static func evaluate(original: [UInt8], result: [UInt8], width: Int, height: Int, thresholds: Thresholds) -> Verdict {
        guard original.count == width * height * 4, result.count == original.count else { return .lumaSimilarity(0) }
        var worstAlpha = 0
        for i in 0..<(width * height) { worstAlpha = max(worstAlpha, abs(Int(original[i * 4 + 3]) - Int(result[i * 4 + 3]))) }
        if worstAlpha > thresholds.maxAlphaChange { return .alphaChanged(worstAlpha) }

        let a = composited(original), b = composited(result)
        let luma = ImageMetrics.lumaSSIM(a, b, width: width, height: height)
        if luma < thresholds.lumaSSIM { return .lumaSimilarity(luma) }
        for channel in 0..<3 {
            let score = ImageMetrics.channelSSIM(a, b, width: width, height: height, channel: channel)
            if score < thresholds.channelSSIM { return .channelSimilarity(channel, score) }
        }
        if bandingShare(original: a, result: b, width: width, height: height, thresholds: thresholds) >= thresholds.bandingCollapsed { return .banding }
        return .accepted
    }

    /// The picture as it looks over mid-gray: transparent pixels show the gray whatever color is stored under them.
    static func composited(_ rgba: [UInt8]) -> [UInt8] {
        var out = rgba
        for i in stride(from: 0, to: rgba.count, by: 4) {
            let a = Int(rgba[i + 3])
            if a == 255 { continue }
            for c in 0..<3 { out[i + c] = UInt8((Int(rgba[i + c]) * a + 128 * (255 - a) + 127) / 255) }
            out[i + 3] = 255
        }
        return out
    }

    /// Among the 8x8 blocks of the original that are smooth gradients (the colors vary by 2 to 40 levels, so not flat and not an
    /// edge, and there are at least three different ones: two flat colors meeting at a soft edge are not a gradient), the share that
    /// the result has flattened to at most two colors. 0 when smooth blocks are rare: flat graphics.
    static func bandingShare(original: [UInt8], result: [UInt8], width: Int, height: Int, thresholds: Thresholds = .standard) -> Double {
        guard width >= 8, height >= 8, original.count == width * height * 4, result.count == original.count else { return 0 }
        var blocks = 0, smooth = 0, collapsed = 0
        var by = 0
        while by + 8 <= height {
            var bx = 0
            while bx + 8 <= width {
                blocks += 1
                var lo = [255, 255, 255], hi = [0, 0, 0]
                var colors = Set<UInt32>(), originalColors = Set<UInt32>()
                for y in by..<(by + 8) { for x in bx..<(bx + 8) {
                    let o = (y * width + x) * 4
                    for c in 0..<3 { lo[c] = min(lo[c], Int(original[o + c])); hi[c] = max(hi[c], Int(original[o + c])) }
                    colors.insert(UInt32(result[o]) << 16 | UInt32(result[o + 1]) << 8 | UInt32(result[o + 2]))
                    originalColors.insert(UInt32(original[o]) << 16 | UInt32(original[o + 1]) << 8 | UInt32(original[o + 2]))
                } }
                let span = (0..<3).map { hi[$0] - lo[$0] }.max() ?? 0
                if span >= 2 && span <= 40 && originalColors.count >= 3 { smooth += 1; if colors.count <= 2 { collapsed += 1 } }
                bx += 8
            }
            by += 8
        }
        guard blocks > 0, Double(smooth) / Double(blocks) >= thresholds.bandingMinSmoothShare else { return 0 }
        return Double(collapsed) / Double(smooth)
    }
}

import Foundation

/// Strong's lossy PNG step. After the lossless optimizer has done its best, a palette of at most 256 colors is tried; it is used only
/// if what would be written passes every guard of `PNGLossyGuard` and is clearly smaller than the lossless file. Otherwise the caller
/// keeps the lossless result. Every attempt is recorded, so a refusal can be explained and measured.
enum PNGColorReducer {
    typealias Quantizer = ([UInt8], Int, Int, Int, Bool) -> QuantizedImage

    struct Result {
        var data: Data
        var colors: Int
    }

    struct Attempt: CustomStringConvertible {
        var colors: Int
        var dither: Bool
        var verdict: PNGLossyGuard.Verdict
        var size: Int?
        var description: String { "\(colors) colors\(dither ? " dithered" : ""): \(verdict)\(size.map { " (\($0) bytes)" } ?? "")" }
    }

    struct Outcome {
        var result: Result?
        var attempts: [Attempt]
    }

    /// Chunks that mean something only for the original pixel format; they are not carried into a palette image.
    private static let dropped: Set<String> = ["IHDR", "IDAT", "IEND", "PLTE", "tRNS", "bKGD", "sBIT", "hIST", "sPLT"]
    private static let defaultQuantizer: Quantizer = { PNGQuantizer.quantize(rgba: $0, width: $1, height: $2, maxColors: $3, dither: $4) }
    /// Palette sizes to try, from the best looking down; a smaller one is only tried while the bigger one passed.
    private static let colorCounts = [256, 64, 16]
    /// After this long no further palette size is tried (the best result so far, if any, is used). Only big pictures get near it.
    static let timeBudget = Duration.seconds(20)

    static func reduce(source: Data, lossless: Data, stripMetadata: Bool, thresholds: PNGLossyGuard.Thresholds = .standard,
                       quantizer: Quantizer = PNGColorReducer.defaultQuantizer, timeBudget: Duration = PNGColorReducer.timeBudget) -> Outcome {
        var attempts: [Attempt] = []
        guard let file = try? PNGFile.parse(source), file.header.interlace == 0, !file.chunks.contains(where: { $0.type == "acTL" }) else {
            return Outcome(result: nil, attempts: [])
        }
        let w = file.header.width, h = file.header.height
        guard w * h <= thresholds.maxPixels else { return Outcome(result: nil, attempts: [Attempt(colors: 0, dither: false, verdict: .tooLarge, size: nil)]) }
        guard let original = PNGPixels.rgba8(file) else { return Outcome(result: nil, attempts: []) }
        let sampled = PNGLossyGuard.sampledColors(original, width: w, height: h, limit: thresholds.maxSampledColors)
        if let refusal = PNGLossyGuard.precheck(width: w, height: h, sampledColors: sampled, thresholds: thresholds) {
            return Outcome(result: nil, attempts: [Attempt(colors: 0, dither: false, verdict: refusal, size: nil)])
        }

        let kept = file.chunks.filter { !dropped.contains($0.type) && !(stripMetadata && PNGOptimizer.isStrippable($0)) }
        let started = ContinuousClock.now
        var best: Result?
        for colors in colorCounts {
            if best != nil, ContinuousClock.now - started > timeBudget { break }
            var passedHere = false
            for dither in [false, true] {
                let quantized = quantizer(original, w, h, colors, dither)
                guard let written = write(quantized, width: w, height: h, chunks: kept), let pixels = PNGFile.parsed(written).flatMap(PNGPixels.rgba8) else { break }
                var verdict = PNGLossyGuard.evaluate(original: original, result: pixels, width: w, height: h, thresholds: thresholds)
                if verdict == .accepted, !PNGLossyGuard.isSmallEnough(lossy: written.count, lossless: lossless.count, thresholds: thresholds) { verdict = .notSmallEnough }
                attempts.append(Attempt(colors: colors, dither: dither, verdict: verdict, size: written.count))
                if verdict == .accepted {
                    passedHere = true
                    if best == nil || written.count < best!.data.count { best = Result(data: written, colors: quantized.count) }
                    break
                }
                if verdict == .notSmallEnough { passedHere = true; break }   // looks fine; dithering would only be bigger
            }
            if !passedHere { break }
        }
        // The candidates were compared with the quick optimizer; the one that won gets the thorough one.
        if var winner = best, let better = try? PNGOptimizer.optimize(winner.data, options: PNGOptimizer.Options(effort: .thorough)), better.count < winner.data.count {
            winner.data = better
            best = winner
        }
        return Outcome(result: best, attempts: attempts)
    }

    /// The palette PNG for `quantized`: the kept chunks, PLTE (entries with transparency first, so tRNS stays short), tRNS, the
    /// image data, optimized losslessly.
    private static func write(_ quantized: QuantizedImage, width: Int, height: Int, chunks: [PNGChunk]) -> Data? {
        let count = quantized.count
        guard count > 0, quantized.indices.count == width * height else { return nil }
        let order = (0..<count).sorted { (quantized.palette[$0 * 4 + 3] == 255 ? 1 : 0, $0) < (quantized.palette[$1 * 4 + 3] == 255 ? 1 : 0, $1) }
        var remap = [UInt8](repeating: 0, count: count)
        for (newIndex, old) in order.enumerated() { remap[old] = UInt8(newIndex) }
        let transparent = order.filter { quantized.palette[$0 * 4 + 3] != 255 }

        let depth = count <= 2 ? 1 : count <= 4 ? 2 : count <= 16 ? 4 : 8
        let header = PNGHeader(width: width, height: height, bitDepth: depth, colorType: 3)
        var rows = [UInt8](repeating: 0, count: header.rowBytes * height)
        for y in 0..<height { for x in 0..<width {
            let value = remap[Int(quantized.indices[y * width + x])]
            if depth == 8 { rows[y * header.rowBytes + x] = value } else { rows[y * header.rowBytes + x * depth / 8] |= value << UInt8(8 - depth - (x * depth) % 8) }
        } }
        let filtered = PNGFilter.filter(rows, rowBytes: header.rowBytes, height: height, step: header.filterStep, strategy: .adaptive)
        guard let stream = Zlib.deflate(filtered, level: 1) else { return nil }

        var out = [PNGChunk(type: "IHDR", data: header.ihdrData)] + chunks
        out.append(PNGChunk(type: "PLTE", data: order.flatMap { [quantized.palette[$0 * 4], quantized.palette[$0 * 4 + 1], quantized.palette[$0 * 4 + 2]] }))
        if !transparent.isEmpty { out.append(PNGChunk(type: "tRNS", data: transparent.map { quantized.palette[$0 * 4 + 3] })) }
        out.append(PNGChunk(type: "IDAT", data: stream))
        out.append(PNGChunk(type: "IEND", data: []))
        let built = PNGFile(header: header, chunks: out).serialized()
        // The quick optimizer is enough to compare candidates; palette data compresses about the same either way.
        return (try? PNGOptimizer.optimize(built, options: PNGOptimizer.Options(effort: .light))) ?? built
    }
}

extension PNGFile {
    static func parsed(_ data: Data) -> PNGFile? { try? PNGFile.parse(data) }
}

import Foundation

/// A lossless PNG optimizer that works on the file's own chunks: the image data is inflated, stored in the smallest
/// equivalent way (only when that is provably lossless, see `PNGReduction`), filtered with the best strategy and deflated
/// again. Every other chunk is kept as it is, in its place. It never decodes the picture with a graphics library, so
/// nothing about it (color management, gamma, premultiplied alpha) can change.
///
/// - The result is checked before it is returned: its image data is inflated and unfiltered and must equal the pixels
///   that went in.
/// - Reductions of the pixel format are skipped whenever the file has a chunk whose meaning depends on it
///   (iCCP, gAMA, cHRM, sRGB, tRNS, sBIT, bKGD, PLTE, hIST, sPLT, or any chunk this code does not know).
public enum PNGOptimizer {
    public enum Effort: Equatable, Sendable {
        /// The adaptive filter heuristic and a medium deflate level: quick.
        case light
        /// Every filter strategy and the strongest deflate level.
        case thorough
    }

    public struct Options: Equatable, Sendable {
        public var effort: Effort
        /// Drop text, time and EXIF chunks (XMP lives in iTXt). An EXIF block that carries a rotation stays, or the
        /// picture would come out turned.
        public var stripMetadata: Bool

        public init(effort: Effort = .thorough, stripMetadata: Bool = false) {
            self.effort = effort
            self.stripMetadata = stripMetadata
        }
    }

    /// Raw data bigger than this is not attempted: it would need gigabytes of memory.
    static let maxRawBytes = 1_200_000_000
    /// How much work the search may be. Measured in release: a strongest-level pass over noisy 8-bit RGB costs about 1.5 s per
    /// megapixel (and trying every strategy took 10 s for one megapixel, 35 s for twelve), but on flat pictures (screenshots,
    /// graphics: most of what is stored as PNG) the same pass is fast. So the thorough search is for small pictures and for
    /// pictures that compress well, and everything else gets a medium or quick one.
    static let smallBytes = 1 << 20
    static let rankedSearchBytes = 32 << 20
    /// A sample that deflates (quickly) to at most this share of its size is "flat": cheap to search hard.
    static let flatSampleRatio = 0.25

    enum SearchPlan: Equatable {
        /// The adaptive filter heuristic, one deflate at level 6.
        case quick
        /// The adaptive heuristic and the strategy that looked best on a sample of rows, each deflated once at level 6.
        case ranked
        /// Every filter strategy deflated at the strongest level, then the other zlib strategy on the best.
        case full
    }

    /// - Parameter sampleRatio: how well a quick deflate of a sample of the picture compresses (0-1; smaller is flatter).
    static func searchPlan(effort: Effort, rawBytes: Int, sampleRatio: Double) -> SearchPlan {
        guard effort == .thorough else { return .quick }
        if rawBytes <= smallBytes { return .full }
        if rawBytes > rankedSearchBytes { return .quick }
        return sampleRatio <= flatSampleRatio ? .full : .ranked
    }

    /// The chunks that may be present while the pixel format is changed.
    static let reductionSafeChunks: Set<String> = ["IHDR", "IDAT", "IEND", "pHYs", "tEXt", "zTXt", "iTXt", "eXIf", "tIME"]
    static let strippedChunks: Set<String> = ["tEXt", "zTXt", "iTXt", "tIME"]

    /// The two steps that produce the output, replaceable so that tests can break them and watch the safety net
    /// (`PNGVerifier`) catch it.
    struct Steps {
        /// The deflate stream of the filtered rows of a candidate.
        var compress: ([UInt8], PNGHeader, SearchPlan) -> [UInt8]?
        /// The finished file.
        var assemble: (PNGFile, PNGCandidate, [UInt8], Options) -> Data

        static let standard = Steps(compress: { PNGOptimizer.compress($0, header: $1, plan: $2) },
                                    assemble: { PNGOptimizer.assemble(file: $0, chosen: $1, stream: $2, options: $3) })
    }

    public static func optimize(_ data: Data, options: Options = Options()) throws -> Data {
        try optimize(data, options: options, steps: .standard)
    }

    static func optimize(_ data: Data, options: Options, steps: Steps) throws -> Data {
        let file = try PNGFile.parse(data)
        if file.chunks.contains(where: { $0.type == "acTL" }) { throw PNGOptimizeError.animated }
        if file.header.interlace != 0 { throw PNGOptimizeError.interlaced }
        for chunk in file.chunks where !chunk.isAncillary && !["IHDR", "PLTE", "IDAT", "IEND"].contains(chunk.type) { throw PNGOptimizeError.unsupported }
        if file.header.colorType == 3, !file.chunks.contains(where: { $0.type == "PLTE" }) { throw PNGOptimizeError.damaged }

        let header = file.header
        let expected = header.height * (header.rowBytes + 1)
        let stream = file.imageData
        // Deflate cannot expand more than about 1000 to 1: a header that promises far more than the data can hold is a lie.
        guard stream.count * 1100 >= expected else { throw PNGOptimizeError.damaged }
        guard expected <= maxRawBytes else { throw PNGOptimizeError.unsupported }
        guard let raw = Zlib.inflate(stream, limit: expected), raw.count == expected,
              let pixels = PNGFilter.unfilter(raw, rowBytes: header.rowBytes, height: header.height, step: header.filterStep) else { throw PNGOptimizeError.damaged }

        var candidates = [PNGCandidate(header: header, pixels: pixels)]
        if file.chunks.allSatisfy({ reductionSafeChunks.contains($0.type) }) {
            candidates += PNGReduction.candidates(header: header, pixels: pixels)
        }

        var best: (candidate: PNGCandidate, stream: [UInt8], size: Int)?
        for candidate in candidates {
            let plan = searchPlan(effort: options.effort, rawBytes: candidate.pixels.count, sampleRatio: options.effort == .thorough && candidate.pixels.count > smallBytes ? sampleRatio(of: candidate) : 1)
            guard let packed = steps.compress(candidate.pixels, candidate.header, plan) else { throw PNGOptimizeError.verificationFailed }
            let size = packed.count + candidate.extraChunks.reduce(0) { $0 + $1.data.count + 12 }
            if best == nil || size < best!.size { best = (candidate, packed, size) }
        }
        guard let chosen = best else { throw PNGOptimizeError.verificationFailed }

        // The safety net: the finished file must be the file we were given, pixel for pixel and chunk for chunk (see PNGVerifier).
        let written = steps.assemble(file, chosen.candidate, chosen.stream, options)
        guard PNGVerifier.verify(source: file, sourceRaw: raw, result: written, stripMetadata: options.stripMetadata,
                                 addedChunkTypes: Set(chosen.candidate.extraChunks.map(\.type))) else { throw PNGOptimizeError.verificationFailed }
        return written
    }

    // MARK: Compression

    /// The zlib stream of the filtered rows, searched for according to `plan`.
    static func compress(_ pixels: [UInt8], header: PNGHeader, plan: SearchPlan) -> [UInt8]? {
        let rowBytes = header.rowBytes, height = header.height, step = header.filterStep
        switch plan {
        case .quick:
            return Zlib.deflate(PNGFilter.filter(pixels, rowBytes: rowBytes, height: height, step: step, strategy: .adaptive), level: 6)

        case .ranked:
            let ranked = rank(pixels, rowBytes: rowBytes, height: height, step: step)
            let tried = Set([PNGFilter.Strategy.adaptive] + ranked.prefix(1))
            return smallest(of: tried, pixels: pixels, header: header, level: 6)

        case .full:
            guard let best = smallest(of: Set(PNGFilter.Strategy.allCases), pixels: pixels, header: header, level: 9, keepFiltered: true) else { return nil }
            // The other zlib strategy occasionally wins on the best filtering.
            if let alternative = Zlib.deflate(best.filtered, level: 9, strategy: best.strategy == .none ? .filtered : .standard), alternative.count < best.stream.count {
                return alternative
            }
            return best.stream
        }
    }

    /// How well a band of rows from the middle of the candidate compresses with a quick deflate (the adaptive filter first).
    static func sampleRatio(of candidate: PNGCandidate) -> Double {
        let h = candidate.header
        let rows = max(1, min(h.height, 1_000_000 / max(1, h.rowBytes)))
        let start = (h.height - rows) / 2
        let band = Array(candidate.pixels[(start * h.rowBytes)..<((start + rows) * h.rowBytes)])
        let filtered = PNGFilter.filter(band, rowBytes: h.rowBytes, height: rows, step: h.filterStep, strategy: .adaptive)
        guard let packed = Zlib.deflate(filtered, level: 1) else { return 1 }
        return Double(packed.count) / Double(max(1, band.count))
    }

    private static func smallest(of strategies: Set<PNGFilter.Strategy>, pixels: [UInt8], header: PNGHeader, level: Int32) -> [UInt8]? {
        smallest(of: strategies, pixels: pixels, header: header, level: level, keepFiltered: false)?.stream
    }

    private static func smallest(of strategies: Set<PNGFilter.Strategy>, pixels: [UInt8], header: PNGHeader, level: Int32, keepFiltered: Bool) -> (stream: [UInt8], filtered: [UInt8], strategy: PNGFilter.Strategy)? {
        var best: (stream: [UInt8], filtered: [UInt8], strategy: PNGFilter.Strategy)?
        for strategy in PNGFilter.Strategy.allCases where strategies.contains(strategy) {   // allCases: a fixed order, so results are reproducible
            let filtered = PNGFilter.filter(pixels, rowBytes: header.rowBytes, height: header.height, step: header.filterStep, strategy: strategy)
            guard let packed = Zlib.deflate(filtered, level: level, strategy: strategy == .none ? .standard : .filtered) else { continue }
            if best == nil || packed.count < best!.stream.count { best = (packed, keepFiltered ? filtered : [], strategy) }
        }
        return best
    }

    /// The strategies, best first, judged by a quick deflate of a band of rows from the middle of the picture.
    private static func rank(_ pixels: [UInt8], rowBytes: Int, height: Int, step: Int, sampleBytes: Int = 2_000_000) -> [PNGFilter.Strategy] {
        let rows = max(1, min(height, sampleBytes / max(1, rowBytes)))
        let start = (height - rows) / 2
        let band = Array(pixels[(start * rowBytes)..<((start + rows) * rowBytes)])
        return PNGFilter.Strategy.allCases.compactMap { strategy -> (PNGFilter.Strategy, Int)? in
            let sample = PNGFilter.filter(band, rowBytes: rowBytes, height: rows, step: step, strategy: strategy)
            return Zlib.deflate(sample, level: 1).map { (strategy, $0.count) }
        }.sorted { $0.1 < $1.1 }.map(\.0)
    }

    // MARK: Writing the file

    static func assemble(file: PNGFile, chosen: PNGCandidate, stream: [UInt8], options: Options) -> Data {
        var out: [PNGChunk] = []
        var wroteImageData = false
        for chunk in file.chunks {
            switch chunk.type {
            case "IHDR":
                out.append(PNGChunk(type: "IHDR", data: chosen.header.ihdrData))
            case "IDAT":
                guard !wroteImageData else { continue }
                wroteImageData = true
                out.append(contentsOf: chosen.extraChunks)
                var offset = 0
                while offset < stream.count {
                    let end = min(stream.count, offset + (1 << 20))
                    out.append(PNGChunk(type: "IDAT", data: Array(stream[offset..<end])))
                    offset = end
                }
            default:
                if options.stripMetadata, isStrippable(chunk) { continue }
                out.append(chunk)
            }
        }
        return PNGFile(header: chosen.header, chunks: out).serialized()
    }

    /// Metadata that may go when the user asks for it; an EXIF block that holds a rotation may not.
    static func isStrippable(_ chunk: PNGChunk) -> Bool {
        if strippedChunks.contains(chunk.type) { return true }
        if chunk.type == "eXIf" { return (exifOrientation(chunk.data) ?? 1) <= 1 }
        return false
    }

    /// The Orientation tag (0x0112) of the first IFD of a binary EXIF block, if there is one.
    static func exifOrientation(_ bytes: [UInt8]) -> Int? {
        guard bytes.count >= 8 else { return nil }
        let little: Bool
        switch (bytes[0], bytes[1]) {
        case (0x49, 0x49): little = true
        case (0x4D, 0x4D): little = false
        default: return nil
        }
        func u16(_ o: Int) -> Int? { o >= 0 && o + 2 <= bytes.count ? (little ? Int(bytes[o]) | Int(bytes[o + 1]) << 8 : Int(bytes[o]) << 8 | Int(bytes[o + 1])) : nil }
        func u32(_ o: Int) -> Int? { guard let a = u16(o), let b = u16(o + 2) else { return nil }; return little ? a | b << 16 : a << 16 | b }
        guard let ifd = u32(4), let count = u16(ifd), count <= 512 else { return nil }
        for index in 0..<count {
            let entry = ifd + 2 + index * 12
            if u16(entry) == 0x0112 { return u16(entry + 8) }
        }
        return nil
    }
}

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
    /// Raw data up to this size is tried with every filter strategy; bigger data is sampled first.
    static let fullSearchBytes = 4 << 20
    /// The chunks that may be present while the pixel format is changed.
    static let reductionSafeChunks: Set<String> = ["IHDR", "IDAT", "IEND", "pHYs", "tEXt", "zTXt", "iTXt", "eXIf", "tIME"]
    static let strippedChunks: Set<String> = ["tEXt", "zTXt", "iTXt", "tIME"]

    public static func optimize(_ data: Data, options: Options = Options()) throws -> Data {
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
            guard let packed = compress(candidate.pixels, header: candidate.header, effort: options.effort) else { throw PNGOptimizeError.verificationFailed }
            let size = packed.count + candidate.extraChunks.reduce(0) { $0 + $1.data.count + 12 }
            if best == nil || size < best!.size { best = (candidate, packed, size) }
        }
        guard let chosen = best else { throw PNGOptimizeError.verificationFailed }

        // The safety net: what is about to be written must decode to the pixels that were read.
        let h = chosen.candidate.header
        guard let again = Zlib.inflate(chosen.stream, limit: h.height * (h.rowBytes + 1)),
              PNGFilter.unfilter(again, rowBytes: h.rowBytes, height: h.height, step: h.filterStep) == chosen.candidate.pixels else { throw PNGOptimizeError.verificationFailed }

        return assemble(file: file, chosen: chosen.candidate, stream: chosen.stream, options: options)
    }

    // MARK: Compression

    /// The zlib stream of the filtered rows, with the strategy and level that `effort` calls for.
    static func compress(_ pixels: [UInt8], header: PNGHeader, effort: Effort) -> [UInt8]? {
        let rowBytes = header.rowBytes, height = header.height, step = header.filterStep
        switch effort {
        case .light:
            return Zlib.deflate(PNGFilter.filter(pixels, rowBytes: rowBytes, height: height, step: step, strategy: .adaptive), level: 6)
        case .thorough:
            var strategies = PNGFilter.Strategy.allCases
            if pixels.count > fullSearchBytes {
                // Rank the strategies on a band of rows from the middle; only the two best get the full treatment.
                let rows = max(1, min(height, 2_000_000 / max(1, rowBytes)))
                let start = (height - rows) / 2
                let band = Array(pixels[(start * rowBytes)..<((start + rows) * rowBytes)])
                let ranked = strategies.compactMap { strategy -> (PNGFilter.Strategy, Int)? in
                    let sample = PNGFilter.filter(band, rowBytes: rowBytes, height: rows, step: step, strategy: strategy)
                    return Zlib.deflate(sample, level: 1).map { (strategy, $0.count) }
                }.sorted { $0.1 < $1.1 }
                strategies = ranked.prefix(2).map(\.0)
            }
            var best: [UInt8]?
            var bestFiltered: [UInt8]?
            var bestStrategy = PNGFilter.Strategy.adaptive
            for strategy in strategies {
                let filtered = PNGFilter.filter(pixels, rowBytes: rowBytes, height: height, step: step, strategy: strategy)
                guard let packed = Zlib.deflate(filtered, level: 9, strategy: strategy == .none ? .standard : .filtered) else { continue }
                if best == nil || packed.count < best!.count { best = packed; bestFiltered = filtered; bestStrategy = strategy }
            }
            // The other zlib strategy occasionally wins on the best filtering.
            if let filtered = bestFiltered, let alternative = Zlib.deflate(filtered, level: 9, strategy: bestStrategy == .none ? .filtered : .standard),
               alternative.count < (best?.count ?? .max) {
                best = alternative
            }
            return best
        }
    }

    // MARK: Writing the file

    private static func assemble(file: PNGFile, chosen: PNGCandidate, stream: [UInt8], options: Options) -> Data {
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

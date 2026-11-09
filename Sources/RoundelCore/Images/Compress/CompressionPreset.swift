import Foundation

/// How hard to compress. The numbers are per format because the formats' quality scales are not alike (ImageIO's JPEG
/// quality 0.7 is about IJG 92; libwebp's 70 is much lower).
public enum CompressionPreset: String, CaseIterable, Sendable {
    case light, balanced, strong

    public var title: String { rawValue.prefix(1).uppercased() + rawValue.dropFirst() }

    /// ImageIO's `lossyCompressionQuality` for JPEG (0.55 is about IJG 83).
    public var jpegQuality: Double { [CompressionPreset.light: 0.70, .balanced: 0.55, .strong: 0.35][self] ?? 0.55 }
    public var heicQuality: Double { [CompressionPreset.light: 0.65, .balanced: 0.55, .strong: 0.25][self] ?? 0.55 }
    /// libwebp's quality divided by 100.
    public var webpQuality: Double { [CompressionPreset.light: 0.80, .balanced: 0.70, .strong: 0.60][self] ?? 0.70 }
    /// How hard the lossless PNG optimizer tries.
    public var pngEffort: PNGOptimizer.Effort { self == .light ? .light : .thorough }

    /// What Strong does beyond the numbers: it is the maximum, so it removes everything that does not change how the picture looks
    /// (metadata, HDR/depth/Live Photo data) and may reduce a PNG's colors. The user's own parameters override each of these.
    public var impliesRemovingExtras: Bool { self == .strong }
}

/// What the user asked for, from an action node's params.
public struct CompressionOptions: Equatable, Sendable {
    public var preset: CompressionPreset
    /// Explicit quality (0-1, the scale of `image.convert`); wins over the preset's number and over Strong's search. Ignored for PNG.
    public var quality: Double?
    public var maxDimension: Int?
    /// `nil` = the preset decides (Strong removes, the others keep); a value is the user's own choice and wins.
    public var stripMetadata: Bool?
    public var dropHDRData: Bool?
    public var reducePNGColors: Bool?

    public init(preset: CompressionPreset = .balanced, quality: Double? = nil, maxDimension: Int? = nil,
                stripMetadata: Bool? = nil, dropHDRData: Bool? = nil, reducePNGColors: Bool? = nil) {
        self.preset = preset
        self.quality = quality
        self.maxDimension = maxDimension
        self.stripMetadata = stripMetadata
        self.dropHDRData = dropHDRData
        self.reducePNGColors = reducePNGColors
    }

    public init(params: Params) {
        self.init(preset: params.string("preset").flatMap(CompressionPreset.init(rawValue:)) ?? .balanced,
                  quality: params.double("quality").map { min(max($0, 0), 1) },
                  maxDimension: params.int("maxDimension").flatMap { $0 > 0 ? $0 : nil },
                  stripMetadata: params.bool("stripMetadata"),
                  dropHDRData: params.bool("dropHDRData"),
                  reducePNGColors: params.bool("reducePNGColors"))
    }

    /// Remove EXIF, GPS, IPTC, XMP and the like (orientation and the color profile always stay).
    public var stripsMetadata: Bool { stripMetadata ?? preset.impliesRemovingExtras }
    /// Re-encode JPEG and HEIC files that carry an HDR gain map, depth data, mattes or a Live Photo link, dropping those.
    public var dropsHDRData: Bool { dropHDRData ?? preset.impliesRemovingExtras }
    /// Allow a PNG to be reduced to a palette of at most 256 colors (lossy, with guards).
    public var reducesPNGColors: Bool { reducePNGColors ?? preset.impliesRemovingExtras }
}

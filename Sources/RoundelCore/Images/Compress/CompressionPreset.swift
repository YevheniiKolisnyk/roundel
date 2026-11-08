import Foundation

/// How hard to compress. The numbers are per format because the formats' quality scales are not alike (ImageIO's JPEG
/// quality 0.7 is about IJG 92; libwebp's 70 is much lower).
public enum CompressionPreset: String, CaseIterable, Sendable {
    case light, balanced, strong

    public var title: String { rawValue.prefix(1).uppercased() + rawValue.dropFirst() }

    /// ImageIO's `lossyCompressionQuality` for JPEG (0.55 is about IJG 83).
    public var jpegQuality: Double { [CompressionPreset.light: 0.70, .balanced: 0.55, .strong: 0.40][self] ?? 0.55 }
    public var heicQuality: Double { [CompressionPreset.light: 0.65, .balanced: 0.55, .strong: 0.45][self] ?? 0.55 }
    /// libwebp's quality divided by 100.
    public var webpQuality: Double { [CompressionPreset.light: 0.80, .balanced: 0.70, .strong: 0.55][self] ?? 0.70 }
    /// PNG stays lossless, so the presets only differ in effort: Strong is Balanced.
    public var pngEffort: PNGOptimizer.Effort { self == .light ? .light : .thorough }
}

/// What the user asked for, from an action node's params.
public struct CompressionOptions: Equatable, Sendable {
    public var preset: CompressionPreset
    /// Explicit quality (0-1, the scale of `image.convert`); wins over the preset's number. Ignored for PNG.
    public var quality: Double?
    public var maxDimension: Int?
    public var stripMetadata: Bool

    public init(preset: CompressionPreset = .balanced, quality: Double? = nil, maxDimension: Int? = nil, stripMetadata: Bool = false) {
        self.preset = preset
        self.quality = quality
        self.maxDimension = maxDimension
        self.stripMetadata = stripMetadata
    }

    public init(params: Params) {
        self.init(preset: params.string("preset").flatMap(CompressionPreset.init(rawValue:)) ?? .balanced,
                  quality: params.double("quality").map { min(max($0, 0), 1) },
                  maxDimension: params.int("maxDimension").flatMap { $0 > 0 ? $0 : nil },
                  stripMetadata: params.bool("stripMetadata") ?? false)
    }
}

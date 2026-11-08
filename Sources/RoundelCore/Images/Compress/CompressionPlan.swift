import Foundation

/// What is known about a file before anything is done to it.
public struct ImageFacts: Equatable, Sendable {
    /// The type found in the file's content.
    public var detectedType: String
    public var isAnimated: Bool
    /// HDR gain map, depth, disparity, matte, or Live Photo data: things a plain re-encode would drop.
    public var hasAuxiliaryData: Bool
    /// For JPEG: the quality its quantization tables say it has (IJG scale), if readable.
    public var jpegQualityIJG: Int?
    /// For WebP: lossless or not, from the container; `nil` if unknown.
    public var webpIsLossless: Bool?

    public init(detectedType: String, isAnimated: Bool = false, hasAuxiliaryData: Bool = false, jpegQualityIJG: Int? = nil, webpIsLossless: Bool? = nil) {
        self.detectedType = detectedType
        self.isAnimated = isAnimated
        self.hasAuxiliaryData = hasAuxiliaryData
        self.jpegQualityIJG = jpegQualityIJG
        self.webpIsLossless = webpIsLossless
    }
}

public enum CompressionSkipReason: Equatable, Sendable {
    case animated
    /// A format that cannot be recompressed without changing it (GIF, BMP, TIFF, AVIF): say so and point to Convert.
    case useConvert(String)
    case hasAuxiliaryData
    case interlacedPNG
    case unsupported(String)

    /// One short phrase for after the file's name.
    public var message: String {
        switch self {
        case .animated: "animated, skipped (compressing would drop the animation)"
        case .useConvert(let name): "\(name) isn’t compressed; use Convert to WebP"
        case .hasAuxiliaryData: "has HDR, depth or Live Photo data, skipped (re-encoding would drop it)"
        case .interlacedPNG: "interlaced PNG, skipped"
        case .unsupported(let name): "\(name) isn’t supported"
        }
    }
}

public enum CompressionDecision: Equatable, Sendable {
    /// Encode again in the same format with these options.
    case reencode(format: ImageFormat, options: ImageEncodingOptions)
    case optimizePNG(PNGOptimizer.Options)
    case skip(CompressionSkipReason)
    /// Nothing worth doing: the file is already compressed as far as is sensible.
    case alreadyOptimal
}

/// The decision for one file. Pure.
public enum CompressionPlan {
    public static func decide(_ facts: ImageFacts, options: CompressionOptions) -> CompressionDecision {
        if facts.isAnimated { return .skip(.animated) }

        switch facts.detectedType {
        case "public.png":
            return .optimizePNG(PNGOptimizer.Options(effort: options.preset.pngEffort, stripMetadata: options.stripMetadata))

        case "public.jpeg":
            if facts.hasAuxiliaryData { return .skip(.hasAuxiliaryData) }
            var quality = options.quality ?? options.preset.jpegQuality
            if options.quality == nil, let source = facts.jpegQualityIJG {
                if let cap = JPEGQuality.cap(forSourceIJG: source) {
                    quality = min(quality, cap)
                } else if options.maxDimension == nil {
                    return .alreadyOptimal
                } else {
                    quality = JPEGQuality.imageIO(forIJG: Double(source))   // only the size changes
                }
            }
            return reencode("jpeg", options, quality: quality)

        case "public.heic":
            if facts.hasAuxiliaryData { return .skip(.hasAuxiliaryData) }
            return reencode("heic", options, quality: options.quality ?? options.preset.heicQuality)

        case "org.webmproject.webp":
            switch facts.webpIsLossless {
            case true?:
                // Stays lossless, whatever the preset: the same pixels, as small as the encoder can make them.
                return reencode("webp", options, quality: 1.0, lossless: true)
            case false?:
                return reencode("webp", options, quality: options.quality ?? options.preset.webpQuality)
            case nil:
                return .skip(.unsupported("WebP"))
            }

        case "com.compuserve.gif", "com.microsoft.bmp", "public.tiff", "public.avif":
            return .skip(.useConvert(ImageFormats.name(ofDetectedType: facts.detectedType)))

        default:
            return .skip(.unsupported(ImageFormats.name(ofDetectedType: facts.detectedType)))
        }
    }

    private static func reencode(_ key: String, _ options: CompressionOptions, quality: Double, lossless: Bool = false) -> CompressionDecision {
        guard let format = ImageFormats.format(forKey: key) else { return .skip(.unsupported(key)) }
        return .reencode(format: format, options: ImageEncodingOptions(quality: quality, lossless: lossless, maxDimension: options.maxDimension,
                                                                         stripMetadata: options.stripMetadata, thorough: true))
    }

    /// The file extension of the output: the source's own if it is right for the content, else the content's usual one.
    public static func outputExtension(detectedType: String, source: URL) -> String {
        let valid: [String: [String]] = [
            "public.jpeg": ["jpg", "jpeg", "jpe"], "public.png": ["png"], "public.heic": ["heic", "heif"], "org.webmproject.webp": ["webp"],
        ]
        let canonical: [String: String] = ["public.jpeg": "jpg", "public.png": "png", "public.heic": "heic", "org.webmproject.webp": "webp"]
        let own = source.pathExtension
        if let list = valid[detectedType], list.contains(own.lowercased()) { return own }
        return canonical[detectedType] ?? own
    }
}

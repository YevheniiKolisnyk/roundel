import Foundation

/// Something that lives next to the picture and that a plain re-encode would drop: visible when the image is viewed in the
/// right place (HDR), or used by Photos (depth effects, portraits, the Live Photo's video).
public enum AuxiliaryKind: Equatable, Sendable, CaseIterable {
    case hdrGainMap, depth, disparity, portraitMatte, semanticMatte, livePhoto

    /// For after "has ": "an HDR gain map", "depth data", ...
    public var name: String {
        switch self {
        case .hdrGainMap: "an HDR gain map"
        case .depth: "depth data"
        case .disparity: "disparity data"
        case .portraitMatte: "a portrait matte"
        case .semanticMatte: "segmentation mattes"
        case .livePhoto: "Live Photo pairing"
        }
    }

    /// "an HDR gain map", "an HDR gain map and depth data", "A, B and C".
    public static func naturalList(_ kinds: [AuxiliaryKind]) -> String {
        let names = kinds.map(\.name)
        switch names.count {
        case 0, 1: return names.first ?? ""
        case 2: return "\(names[0]) and \(names[1])"
        default: return names.dropLast().joined(separator: ", ") + " and " + names[names.count - 1]
        }
    }
}

/// What is known about a file before anything is done to it.
public struct ImageFacts: Equatable, Sendable {
    /// The type found in the file's content.
    public var detectedType: String
    public var isAnimated: Bool
    /// What a plain re-encode would drop, each kind once, in a fixed order. Empty for an ordinary picture.
    public var auxiliaryData: [AuxiliaryKind]
    /// For JPEG: the quality its quantization tables say it has (IJG scale), if readable.
    public var jpegQualityIJG: Int?
    public var hasAuxiliaryData: Bool { !auxiliaryData.isEmpty }
    /// For WebP: lossless or not, from the container; `nil` if unknown.
    public var webpIsLossless: Bool?

    public init(detectedType: String, isAnimated: Bool = false, auxiliaryData: [AuxiliaryKind] = [], jpegQualityIJG: Int? = nil, webpIsLossless: Bool? = nil) {
        self.detectedType = detectedType
        self.isAnimated = isAnimated
        self.auxiliaryData = auxiliaryData
        self.jpegQualityIJG = jpegQualityIJG
        self.webpIsLossless = webpIsLossless
    }
}

public enum CompressionSkipReason: Equatable, Sendable {
    case animated
    /// A format that cannot be recompressed without changing it (GIF, BMP, TIFF, AVIF): say so and point to Convert.
    case useConvert(String)
    /// Extras that a re-encode would drop; `dropHDRData` allows it anyway.
    case hasAuxiliaryData([AuxiliaryKind])
    case interlacedPNG
    case unsupported(String)

    /// One short phrase for after the file's name.
    public var message: String {
        switch self {
        case .animated: "animated, skipped (compressing would drop the animation)"
        case .useConvert(let name): "\(name) isn’t compressed; use Convert to WebP"
        case .hasAuxiliaryData(let kinds): "has \(AuxiliaryKind.naturalList(kinds)), skipped (set dropHDRData to compress anyway)"
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
            if facts.hasAuxiliaryData, !options.dropHDRData { return .skip(.hasAuxiliaryData(facts.auxiliaryData)) }
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
            if facts.hasAuxiliaryData, !options.dropHDRData { return .skip(.hasAuxiliaryData(facts.auxiliaryData)) }
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

import Foundation
import CoreGraphics
import ImageIO

/// Looks at a file without changing it, and tells what matters for deciding how to compress it.
public protocol ImageProbing: Sendable {
    func facts(of url: URL, detectedType: String) -> ImageFacts
    /// Width times height from the header (0 if unknown): what the memory budget is counted in.
    func pixelCount(of url: URL) -> Int
}

public struct ImageIOProbe: ImageProbing {
    public init() {}

    public func facts(of url: URL, detectedType: String) -> ImageFacts {
        var facts = ImageFacts(detectedType: detectedType)
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return facts }
        let frames = CGImageSourceGetCount(source)
        let index = CGImageSourceGetPrimaryImageIndex(source)
        let properties = CGImageSourceCopyPropertiesAtIndex(source, index, nil) as? [CFString: Any] ?? [:]

        facts.isAnimated = ImageIOSource.isAnimated(type: detectedType, frames: frames)
        if detectedType == "public.jpeg" || detectedType == "public.heic" {
            facts.hasAuxiliaryData = Self.hasAuxiliaryData(source, index: index) || Self.isLivePhoto(properties: properties)
        }
        if detectedType == "public.jpeg" || detectedType == "org.webmproject.webp",
           let data = try? Data(contentsOf: url, options: .mappedIfSafe) {
            if detectedType == "public.jpeg" { facts.jpegQualityIJG = JPEGQuality.estimateIJG(from: data) }
            if let kind = WebPContainer.kind(of: data) {
                facts.webpIsLossless = kind == .lossless
                if kind == .animated { facts.isAnimated = true }
            }
        }
        return facts
    }

    public func pixelCount(of url: URL) -> Int {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, CGImageSourceGetPrimaryImageIndex(source), nil) as? [CFString: Any],
              let width = (properties[kCGImagePropertyPixelWidth] as? NSNumber)?.intValue,
              let height = (properties[kCGImagePropertyPixelHeight] as? NSNumber)?.intValue else { return 0 }
        return max(0, width) * max(0, height)
    }

    // MARK: Pieces

    /// HDR gain map, depth, disparity or a matte: data that lives next to the picture and that a plain re-encode drops.
    static func hasAuxiliaryData(_ source: CGImageSource, index: Int) -> Bool {
        var types: [CFString] = [kCGImageAuxiliaryDataTypeHDRGainMap, kCGImageAuxiliaryDataTypeDepth, kCGImageAuxiliaryDataTypeDisparity,
                                 kCGImageAuxiliaryDataTypePortraitEffectsMatte, kCGImageAuxiliaryDataTypeSemanticSegmentationSkinMatte,
                                 kCGImageAuxiliaryDataTypeSemanticSegmentationHairMatte, kCGImageAuxiliaryDataTypeSemanticSegmentationTeethMatte,
                                 kCGImageAuxiliaryDataTypeSemanticSegmentationGlassesMatte, kCGImageAuxiliaryDataTypeSemanticSegmentationSkyMatte]
        if #available(macOS 15.0, *) { types.append(kCGImageAuxiliaryDataTypeISOGainMap) }
        return types.contains { CGImageSourceCopyAuxiliaryDataInfoAtIndex(source, index, $0) != nil }
    }

    /// A Live Photo's still carries Apple's content identifier (MakerApple tag 17), which ties it to its video.
    static func isLivePhoto(properties: [CFString: Any]) -> Bool {
        guard let apple = properties[kCGImagePropertyMakerAppleDictionary] as? [AnyHashable: Any] else { return false }
        return apple["17"] != nil || apple[17] != nil
    }
}

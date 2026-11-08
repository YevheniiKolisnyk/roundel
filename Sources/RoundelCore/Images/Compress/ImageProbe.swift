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
            var kinds = Self.auxiliaryKinds(source, index: index).map(\.kind)
            if Self.livePhotoIdentifier(in: properties) != nil { kinds.append(.livePhoto) }
            facts.auxiliaryData = AuxiliaryKind.allCases.filter { kinds.contains($0) }
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

    /// The auxiliary-data types ImageIO can hand over, with the kind each counts as and its name for reports.
    static let auxiliaryTypes: [(type: CFString, kind: AuxiliaryKind, label: String)] = {
        var list: [(CFString, AuxiliaryKind, String)] = [
            (kCGImageAuxiliaryDataTypeHDRGainMap, .hdrGainMap, "HDR gain map (kCGImageAuxiliaryDataTypeHDRGainMap)"),
            (kCGImageAuxiliaryDataTypeDepth, .depth, "Depth (kCGImageAuxiliaryDataTypeDepth)"),
            (kCGImageAuxiliaryDataTypeDisparity, .disparity, "Disparity (kCGImageAuxiliaryDataTypeDisparity)"),
            (kCGImageAuxiliaryDataTypePortraitEffectsMatte, .portraitMatte, "Portrait effects matte (kCGImageAuxiliaryDataTypePortraitEffectsMatte)"),
            (kCGImageAuxiliaryDataTypeSemanticSegmentationSkinMatte, .semanticMatte, "Skin matte (kCGImageAuxiliaryDataTypeSemanticSegmentationSkinMatte)"),
            (kCGImageAuxiliaryDataTypeSemanticSegmentationHairMatte, .semanticMatte, "Hair matte (kCGImageAuxiliaryDataTypeSemanticSegmentationHairMatte)"),
            (kCGImageAuxiliaryDataTypeSemanticSegmentationTeethMatte, .semanticMatte, "Teeth matte (kCGImageAuxiliaryDataTypeSemanticSegmentationTeethMatte)"),
            (kCGImageAuxiliaryDataTypeSemanticSegmentationGlassesMatte, .semanticMatte, "Glasses matte (kCGImageAuxiliaryDataTypeSemanticSegmentationGlassesMatte)"),
            (kCGImageAuxiliaryDataTypeSemanticSegmentationSkyMatte, .semanticMatte, "Sky matte (kCGImageAuxiliaryDataTypeSemanticSegmentationSkyMatte)"),
        ]
        if #available(macOS 15.0, *) { list.append((kCGImageAuxiliaryDataTypeISOGainMap, .hdrGainMap, "ISO gain map (kCGImageAuxiliaryDataTypeISOGainMap)")) }
        return list
    }()

    /// The kinds of extras image `index` carries, with the ImageIO type that revealed each (an MPF preview or thumbnail is
    /// not among them: it is not auxiliary data, and dropping it loses nothing).
    static func auxiliaryKinds(_ source: CGImageSource, index: Int) -> [(kind: AuxiliaryKind, label: String, info: [AnyHashable: Any])] {
        auxiliaryTypes.compactMap { entry in
            (CGImageSourceCopyAuxiliaryDataInfoAtIndex(source, index, entry.type) as? [AnyHashable: Any]).map { (entry.kind, entry.label, $0) }
        }
    }

    /// A Live Photo's still carries Apple's content identifier (MakerApple tag 17, a text UUID), which ties it to its video.
    /// Only a non-empty text identifier counts.
    static func livePhotoIdentifier(in properties: [CFString: Any]) -> String? {
        guard let apple = properties[kCGImagePropertyMakerAppleDictionary] as? [AnyHashable: Any] else { return nil }
        guard let identifier = (apple["17"] ?? apple[17]) as? String, !identifier.isEmpty else { return nil }
        return identifier
    }
}

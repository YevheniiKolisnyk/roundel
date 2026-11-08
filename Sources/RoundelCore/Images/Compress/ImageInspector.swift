import Foundation
import CoreGraphics
import ImageIO

/// What a file holds and what Compress makes of it. Only reads the file.
public struct ImageInspection: Sendable {
    public let text: String
    public let imageCount: Int
    /// Labels of the auxiliary-data types ImageIO found on the primary image.
    public let auxiliaryTypesFound: [String]
    public let mpfEntries: [MPFEntry]
    /// What Compress counts as "HDR/depth/Live Photo data" for this file (what makes it skip).
    public let treatedAsExtraData: [AuxiliaryKind]
    /// What Compress would do with default settings; `nil` for a file that is not an image.
    public let decision: CompressionDecision?
}

public enum ImageInspector {
    public static func inspect(_ url: URL) -> ImageInspection {
        var lines: [String] = []
        func empty(_ message: String) -> ImageInspection {
            ImageInspection(text: (lines + [message]).joined(separator: "\n"), imageCount: 0, auxiliaryTypesFound: [], mpfEntries: [], treatedAsExtraData: [], decision: nil)
        }

        let size = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? NSNumber)?.intValue
        lines.append("File: \(url.path)" + (size.map { " (\($0) bytes)" } ?? ""))
        guard FileManager.default.fileExists(atPath: url.path) else { return empty("Result: not found") }
        let encoder = ImageIOEncoder()
        guard let type = encoder.detectType(of: url), let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return empty("Result: not an image (ImageIO cannot read it)") }

        let count = CGImageSourceGetCount(source)
        let primary = CGImageSourceGetPrimaryImageIndex(source)
        let properties = CGImageSourceCopyPropertiesAtIndex(source, primary, nil) as? [CFString: Any] ?? [:]
        lines.append("Type (by content): \(type)")
        lines.append("Images in the file: \(count) (primary is #\(primary))")
        if let w = properties[kCGImagePropertyPixelWidth] as? Int, let h = properties[kCGImagePropertyPixelHeight] as? Int {
            lines.append("Size: \(w) x \(h) px, orientation \(properties[kCGImagePropertyOrientation] as? Int ?? 1)")
        }

        // Auxiliary data, image by image (only the primary one is looked at by Compress).
        lines.append("")
        lines.append("Auxiliary data (CGImageSourceCopyAuxiliaryDataInfoAtIndex):")
        var primaryFound: [(kind: AuxiliaryKind, label: String, info: [AnyHashable: Any])] = []
        var anyFound = false
        for index in 0..<max(count, 1) {
            let found = ImageIOProbe.auxiliaryKinds(source, index: index)
            if index == primary { primaryFound = found }
            for item in found {
                anyFound = true
                let d = item.info[kCGImageAuxiliaryDataInfoDataDescription as String] as? [AnyHashable: Any]
                let dims = (d?["Width"] as? Int).flatMap { w in (d?["Height"] as? Int).map { " \(w) x \($0)" } } ?? ""
                lines.append("  - \(item.label)\(dims), on image #\(index)\(index == primary ? "" : " (not examined by Compress)")")
            }
        }
        if !anyFound { lines.append("  none found") }

        // Apple's MakerNote and the Live Photo link.
        lines.append("")
        if let apple = properties[kCGImagePropertyMakerAppleDictionary] as? [AnyHashable: Any] {
            let keys = apple.keys.map { "\($0)" }.sorted()
            lines.append("Apple MakerNote (MakerApple) keys: \(keys.joined(separator: ", "))")
        } else {
            lines.append("Apple MakerNote (MakerApple): none")
        }
        let live = ImageIOProbe.livePhotoIdentifier(in: properties)
        lines.append("Live Photo content identifier (MakerApple 17): \(live ?? "none")")

        // MPF.
        lines.append("")
        let mpf = type == "public.jpeg" ? ((try? Data(contentsOf: url, options: .mappedIfSafe)).map { MPFParser.entries(in: $0) } ?? []) : []
        if mpf.isEmpty {
            lines.append("MPF: none")
        } else {
            lines.append("MPF: \(mpf.count) entries")
            for (i, e) in mpf.enumerated() { lines.append("  #\(i): \(e.role), \(e.size) bytes at offset \(e.offset)") }
            lines.append("  (MPF entries are not a reason to skip: previews and thumbnails are not dropped data. Gain maps and depth maps show up above as auxiliary data.)")
        }

        // What Compress makes of it.
        let facts = ImageIOProbe().facts(of: url, detectedType: type)
        let treated = facts.auxiliaryData
        lines.append("")
        lines.append("Treated as HDR/depth/Live Photo data: " + (treated.isEmpty ? "nothing" : AuxiliaryKind.naturalList(treated)))
        let decision = CompressionPlan.decide(facts, options: CompressionOptions())
        lines.append("Compress (Balanced, defaults) would: \(describe(decision))")
        if case .skip(.hasAuxiliaryData) = decision {
            lines.append("With dropHDRData: true it would: \(describe(CompressionPlan.decide(facts, options: CompressionOptions(dropHDRData: true)))) (the extras above are removed)")
        }
        return ImageInspection(text: lines.joined(separator: "\n"), imageCount: count, auxiliaryTypesFound: primaryFound.map(\.label), mpfEntries: mpf,
                               treatedAsExtraData: treated, decision: decision)
    }

    private static func describe(_ decision: CompressionDecision) -> String {
        switch decision {
        case .reencode(let format, let o): "re-encode (\(format.displayName)\(o.quality.map { ", quality \(String(format: "%.2f", $0))" } ?? "")\(o.lossless ? ", lossless" : ""))"
        case .optimizePNG: "optimize the PNG losslessly"
        case .skip(let reason): "SKIP: \(reason.message)"
        case .alreadyOptimal: "do nothing (already optimal)"
        }
    }
}

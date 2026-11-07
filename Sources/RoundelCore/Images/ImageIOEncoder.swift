import Foundation
import CoreGraphics
import ImageIO

/// The ImageIO backend: reads and writes whatever `CGImageSource` and `CGImageDestination` support on this system.
public struct ImageIOEncoder: ImageBackend {
    public let name = "ImageIO"
    private let capabilities: any ImageCapabilities

    /// - Parameter capabilities: what to report as writable; the system's own list by default.
    public init(capabilities: any ImageCapabilities = SystemImageCapabilities()) {
        self.capabilities = capabilities
    }

    public var writableTypeIdentifiers: [String] { capabilities.writableTypeIdentifiers }

    public func detectType(of url: URL) -> String? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil), CGImageSourceGetCount(source) > 0,
              let type = CGImageSourceGetType(source) else { return nil }
        return type as String
    }

    public func encode(source url: URL, to destination: URL, format: ImageFormat, options: ImageEncodingOptions) throws -> EncodeOutcome {
        // A format that cannot store the orientation tag gets the rotation applied to the pixels instead.
        let loaded = try ImageIOSource.load(url, upright: !format.storesOrientation)
        var image = loaded.image
        var settings = Self.metadata(from: loaded.properties)

        if !format.supportsAlpha, Self.hasAlpha(image) {
            guard let flat = Self.flattenedOnWhite(image) else { throw ImageConversionError.encodeFailed(format: format.displayName) }
            image = flat
        }

        if format.isLossy, let quality = options.quality { settings[kCGImageDestinationLossyCompressionQuality] = min(max(quality, 0), 1) }

        guard let sink = CGImageDestinationCreateWithURL(destination as CFURL, format.typeIdentifier as CFString, 1, nil) else {
            throw ImageConversionError.encodeFailed(format: format.displayName)
        }
        CGImageDestinationAddImage(sink, image, settings as CFDictionary)
        guard CGImageDestinationFinalize(sink) else { throw ImageConversionError.encodeFailed(format: format.displayName) }

        return EncodeOutcome(notes: loaded.isAnimated ? [.firstFrameOnly] : [])
    }

    // MARK: Helpers

    /// The parts of the source's properties worth carrying over: EXIF, TIFF, GPS, IPTC, orientation and resolution.
    /// Format-specific blocks (JFIF, PNG, GIF, HEIC) are left out; the color profile travels with the image itself.
    static func metadata(from properties: [CFString: Any]) -> [CFString: Any] {
        let keys: [CFString] = [kCGImagePropertyExifDictionary, kCGImagePropertyTIFFDictionary, kCGImagePropertyGPSDictionary,
                                kCGImagePropertyIPTCDictionary, kCGImagePropertyOrientation, kCGImagePropertyDPIWidth, kCGImagePropertyDPIHeight]
        return keys.reduce(into: [:]) { result, key in
            if let value = properties[key] { result[key] = value }
        }
    }

    private static func hasAlpha(_ image: CGImage) -> Bool {
        switch image.alphaInfo {
        case .none, .noneSkipFirst, .noneSkipLast: false
        default: true
        }
    }

    /// Draws the image over white in its own color space, so the profile survives the flattening.
    static func flattenedOnWhite(_ image: CGImage) -> CGImage? {
        let space = image.colorSpace.flatMap { $0.model == .rgb ? $0 : nil } ?? CGColorSpace(name: CGColorSpace.sRGB)
        guard let space, let context = CGContext(data: nil, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: 0,
                                                 space: space, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return nil }
        let rect = CGRect(x: 0, y: 0, width: image.width, height: image.height)
        context.setFillColor(red: 1, green: 1, blue: 1, alpha: 1)
        context.fill(rect)
        context.draw(image, in: rect)
        return context.makeImage()
    }

}

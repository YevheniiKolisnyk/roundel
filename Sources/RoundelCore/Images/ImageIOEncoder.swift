import Foundation
import CoreGraphics
import ImageIO

/// The ImageIO backend: reads and writes whatever `CGImageSource` and `CGImageDestination` support on this system.
public struct ImageIOEncoder: ImageBackend {
    public let name = "ImageIO"
    private let capabilities: any ImageCapabilities
    private let pngOptimizer: (@Sendable (Data) throws -> Data)?

    /// - Parameters:
    ///   - capabilities: what to report as writable; the system's own list by default.
    ///   - pngOptimizer: runs on every PNG this backend writes, because ImageIO's PNG writer makes files much bigger than
    ///     they need to be (a screenshot twice the size, an icon too). The result replaces the file only if it is smaller;
    ///     if the optimizer fails, ImageIO's own file stays. `nil` leaves PNGs as ImageIO wrote them.
    public init(capabilities: any ImageCapabilities = SystemImageCapabilities(), pngOptimizer: (@Sendable (Data) throws -> Data)? = ImageIOEncoder.optimizePNG) {
        self.capabilities = capabilities
        self.pngOptimizer = pngOptimizer
    }

    /// The lossless optimizer at full effort; it limits its own search by the size of the picture.
    public static let optimizePNG: @Sendable (Data) throws -> Data = { data in
        try PNGOptimizer.optimize(data, options: PNGOptimizer.Options(effort: .thorough))
    }

    public var writableTypeIdentifiers: [String] { capabilities.writableTypeIdentifiers }

    public func detectType(of url: URL) -> String? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil), CGImageSourceGetCount(source) > 0,
              let type = CGImageSourceGetType(source) else { return nil }
        return type as String
    }

    public func encode(source url: URL, to destination: URL, format: ImageFormat, options: ImageEncodingOptions) throws -> EncodeOutcome {
        // A format that cannot store the orientation tag gets the rotation applied to the pixels instead.
        let loaded = try ImageIOSource.load(url, upright: !format.storesOrientation, maxPixelSize: options.maxDimension)
        var image = loaded.image
        var settings = Self.metadata(from: loaded.properties, stripping: options.stripMetadata)

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
        if format.key == "png", let pngOptimizer { Self.replaceIfSmaller(destination, using: pngOptimizer) }

        return EncodeOutcome(notes: loaded.isAnimated ? [.firstFrameOnly] : [])
    }

    // MARK: Helpers

    /// Runs `optimizer` on the file at `url` and swaps in the result when it is smaller. Any failure leaves the file alone.
    private static func replaceIfSmaller(_ url: URL, using optimizer: @Sendable (Data) throws -> Data) {
        guard let original = try? Data(contentsOf: url), let better = try? optimizer(original), better.count < original.count, !better.isEmpty else { return }
        try? better.write(to: url, options: .atomic)
    }

    /// The parts of the source's properties worth carrying over: EXIF, TIFF, GPS, IPTC, orientation and resolution.
    /// Format-specific blocks (JFIF, PNG, GIF, HEIC) are left out; the color profile travels with the image itself.
    /// With `stripping`, only what changes how the picture looks or prints stays: orientation and resolution.
    static func metadata(from properties: [CFString: Any], stripping: Bool = false) -> [CFString: Any] {
        let always: [CFString] = [kCGImagePropertyOrientation, kCGImagePropertyDPIWidth, kCGImagePropertyDPIHeight]
        let keys: [CFString] = stripping ? always : [kCGImagePropertyExifDictionary, kCGImagePropertyTIFFDictionary, kCGImagePropertyGPSDictionary,
                                                    kCGImagePropertyIPTCDictionary] + always
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

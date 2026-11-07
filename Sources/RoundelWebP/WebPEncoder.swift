import Foundation
import CoreGraphics
import RoundelCore

/// Writes WebP with libwebp, which ImageIO cannot do. The source is read with ImageIO (so everything ImageIO can open,
/// including WebP itself, works), converted to 8-bit RGBA and encoded. This backend reads nothing on its own.
///
/// What is kept: transparency, the ICC profile of non-sRGB images, and EXIF/TIFF/GPS metadata. The orientation is
/// applied to the pixels (browsers do not agree on the EXIF orientation of WebP). What is not kept is reported in the
/// outcome: IPTC, resolution, bit depth beyond 8 and color spaces other than RGB.
public struct WebPEncoder: ImageBackend {
    public let name = "libwebp"
    public let writableTypeIdentifiers = ["org.webmproject.webp"]

    public init() {}

    /// Always `nil`: reading is ImageIO's job, so libwebp's decoder is never involved.
    public func detectType(of url: URL) -> String? { nil }

    public func encode(source: URL, to destination: URL, format: ImageFormat, options: ImageEncodingOptions) throws -> EncodeOutcome {
        let loaded = try ImageIOSource.load(source, upright: true)
        let image = loaded.image
        guard image.width <= WebPSettings.maxDimension, image.height <= WebPSettings.maxDimension else {
            throw ImageConversionError.tooLarge(format: format.displayName, limit: WebPSettings.maxDimension)
        }

        var profile = ImageIOSource.iccProfile(of: image)
        let rgba = try Self.straightRGBA(of: image, profile: &profile)
        let settings = WebPSettings.make(from: options)
        let bitstream = try WebPLibrary.encode(rgba: rgba, width: image.width, height: image.height, settings: settings)
        let file = try WebPLibrary.assemble(bitstream: bitstream, icc: profile, exif: ImageIOSource.exifBlob(from: loaded.properties, pixelSize: (image.width, image.height)))
        try file.write(to: destination)

        var notes: [ConversionNote] = []
        if loaded.isAnimated { notes.append(.firstFrameOnly) }
        let lost = ImageIOSource.droppedMetadata(properties: loaded.properties, image: image)
        if !lost.isEmpty { notes.append(.metadataNotKept(lost)) }
        return EncodeOutcome(notes: notes)
    }

    // MARK: Pixels

    /// 8-bit RGBA with straight (not premultiplied) alpha, which is what libwebp takes. Drawn in the image's own RGB
    /// color space when a profile is going to be embedded, so the numbers and the profile agree; otherwise in sRGB,
    /// which is what a WebP without a profile means. If the image's space cannot be drawn in, `profile` is dropped.
    static func straightRGBA(of image: CGImage, profile: inout Data?) throws -> [UInt8] {
        let width = image.width
        let height = image.height
        var pixels = [UInt8](repeating: 0, count: width * height * 4)

        let srgb = CGColorSpace(name: CGColorSpace.sRGB)
        let spaces: [CGColorSpace?] = profile != nil ? [image.colorSpace, srgb] : [srgb]
        var drawn = false
        for (attempt, space) in spaces.enumerated() {
            guard let space else { continue }
            let ok = pixels.withUnsafeMutableBytes { buffer -> Bool in
                guard let context = CGContext(data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                                              space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
                context.clear(CGRect(x: 0, y: 0, width: width, height: height))
                context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
                return true
            }
            if ok {
                drawn = true
                if profile != nil, attempt > 0 { profile = nil }   // fell back to sRGB: the profile would no longer match
                break
            }
        }
        guard drawn else { throw ImageConversionError.encodeFailed(format: "WebP") }

        // CoreGraphics only draws premultiplied; undo it, because libwebp wants the color as it is.
        for index in stride(from: 0, to: pixels.count, by: 4) {
            let alpha = Int(pixels[index + 3])
            guard alpha != 0, alpha != 255 else { continue }
            for channel in 0..<3 {
                pixels[index + channel] = UInt8(min(255, (Int(pixels[index + channel]) * 255 + alpha / 2) / alpha))
            }
        }
        return pixels
    }
}

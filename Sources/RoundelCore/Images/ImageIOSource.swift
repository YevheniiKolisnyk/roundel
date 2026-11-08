import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

/// A decoded image together with what ImageIO knows about it.
public struct SourceImage {
    /// The primary frame.
    public let image: CGImage
    public let properties: [CFString: Any]
    /// Uniform type identifier of the file's content.
    public let detectedType: String
    /// More than one frame (an animated GIF, APNG or HEIC sequence): only the first was decoded.
    public let isAnimated: Bool
}

/// Reading images and their metadata with ImageIO. Every backend reads through this, including the libwebp one:
/// libwebp is used only to write, never to decode.
public enum ImageIOSource {
    /// - Parameter upright: apply the EXIF orientation to the pixels and set the orientation tag to 1.
    public static func load(_ url: URL, upright: Bool) throws -> SourceImage {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil), let type = CGImageSourceGetType(source) as String? else {
            throw ImageConversionError.unreadable
        }
        // ImageIO decodes a truncated PNG or JPEG as a complete image, so the file's own structure has to be checked.
        if let data = try? Data(contentsOf: url, options: .mappedIfSafe), ImageIntegrity.isComplete(data, detectedType: type) == false {
            throw ImageConversionError.damaged
        }
        let index = CGImageSourceGetPrimaryImageIndex(source)
        guard var image = CGImageSourceCreateImageAtIndex(source, index, nil) else { throw ImageConversionError.unreadable }
        var properties = CGImageSourceCopyPropertiesAtIndex(source, index, nil) as? [CFString: Any] ?? [:]

        let orientation = (properties[kCGImagePropertyOrientation] as? Int) ?? 1
        if upright, orientation != 1 {
            if let rotated = uprightImage(from: source, index: index, like: image) { image = rotated }
            properties[kCGImagePropertyOrientation] = 1
            if var tiff = properties[kCGImagePropertyTIFFDictionary] as? [CFString: Any] {
                tiff[kCGImagePropertyTIFFOrientation] = 1
                properties[kCGImagePropertyTIFFDictionary] = tiff
            }
        }
        return SourceImage(image: image, properties: properties, detectedType: type, isAnimated: isAnimated(type: type, frames: CGImageSourceGetCount(source)))
    }

    static func isAnimated(type: String, frames: Int) -> Bool {
        frames > 1 && ["com.compuserve.gif", "public.heics", "public.png", "org.webmproject.webp"].contains(type)
    }

    /// The image with its EXIF orientation applied, at full size.
    static func uprightImage(from source: CGImageSource, index: Int, like image: CGImage) -> CGImage? {
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: max(image.width, image.height),
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, index, options as CFDictionary)
    }

    // MARK: EXIF

    /// The EXIF/TIFF/GPS metadata as the binary EXIF structure (a TIFF header and its directories, without the
    /// "Exif\0\0" prefix), for formats that keep it in a chunk of its own. ImageIO only exposes dictionaries, so it is
    /// asked to write them into a tiny JPEG, and the APP1 segment is cut out. The orientation is left out: callers
    /// apply it to the pixels. `nil` when there is nothing worth carrying: ImageIO reports a few structural fields for
    /// every image (pixel size, color space, compression), and those alone are not metadata.
    /// - Parameter pixelSize: the size of the image that gets the blob. ImageIO writes the size of its tiny helper image
    ///   into the blob, so the two EXIF size fields are overwritten with this.
    public static func exifBlob(from properties: [CFString: Any], pixelSize: (width: Int, height: Int)? = nil) -> Data? {
        let exif = properties[kCGImagePropertyExifDictionary] as? [CFString: Any] ?? [:]
        var tiff = properties[kCGImagePropertyTIFFDictionary] as? [CFString: Any] ?? [:]
        let gps = properties[kCGImagePropertyGPSDictionary] as? [CFString: Any] ?? [:]
        tiff.removeValue(forKey: kCGImagePropertyTIFFOrientation)

        let hasMetadata = !gps.isEmpty
            || exif.keys.contains { !structuralExifKeys.contains($0 as String) }
            || tiff.keys.contains { !structuralTIFFKeys.contains($0 as String) }
        guard hasMetadata else { return nil }

        var carried: [CFString: Any] = [:]
        if !exif.isEmpty { carried[kCGImagePropertyExifDictionary] = exif }
        if !tiff.isEmpty { carried[kCGImagePropertyTIFFDictionary] = tiff }
        if !gps.isEmpty { carried[kCGImagePropertyGPSDictionary] = gps }
        guard let jpeg = tinyJPEG(with: carried), var blob = exifSegment(inJPEG: jpeg) else { return nil }
        if let pixelSize { _ = patchPixelSize(in: &blob, width: pixelSize.width, height: pixelSize.height) }
        return blob
    }

    private static let structuralExifKeys: Set<String> = ["ColorSpace", "PixelXDimension", "PixelYDimension"]
    private static let structuralTIFFKeys: Set<String> = [
        "Compression", "Orientation", "PhotometricInterpretation", "ResolutionUnit", "XResolution", "YResolution",
        "TileLength", "TileWidth", "PlanarConfiguration", "SamplesPerPixel", "BitsPerSample", "RowsPerStrip",
    ]

    /// Overwrites PixelXDimension / PixelYDimension (EXIF tags 0xA002 / 0xA003) in a binary EXIF structure. A value that
    /// does not fit a SHORT turns the entry into a LONG. Returns `false`, leaving the blob as it was, if it is not a
    /// TIFF structure with an Exif directory holding both tags.
    @discardableResult
    static func patchPixelSize(in blob: inout Data, width: Int, height: Int) -> Bool {
        var bytes = [UInt8](blob)
        guard bytes.count >= 8 else { return false }
        let little: Bool
        switch (bytes[0], bytes[1]) {
        case (0x49, 0x49): little = true
        case (0x4D, 0x4D): little = false
        default: return false
        }

        func read16(_ offset: Int) -> Int? {
            guard offset >= 0, offset + 2 <= bytes.count else { return nil }
            return little ? Int(bytes[offset]) | Int(bytes[offset + 1]) << 8 : Int(bytes[offset]) << 8 | Int(bytes[offset + 1])
        }
        func read32(_ offset: Int) -> Int? {
            guard let low = read16(little ? offset : offset + 2), let high = read16(little ? offset + 2 : offset) else { return nil }
            return high << 16 | low
        }
        func write16(_ value: Int, at offset: Int) {
            bytes[offset] = UInt8(little ? value & 0xFF : value >> 8 & 0xFF)
            bytes[offset + 1] = UInt8(little ? value >> 8 & 0xFF : value & 0xFF)
        }
        func write32(_ value: Int, at offset: Int) {
            write16(little ? value & 0xFFFF : value >> 16 & 0xFFFF, at: offset)
            write16(little ? value >> 16 & 0xFFFF : value & 0xFFFF, at: offset + 2)
        }
        /// Offsets of the 12-byte entries of the directory at `directory`, with their tags.
        func entries(of directory: Int) -> [(tag: Int, offset: Int)] {
            guard let count = read16(directory), directory + 2 + count * 12 <= bytes.count else { return [] }
            return (0..<count).compactMap { index in
                let offset = directory + 2 + index * 12
                return read16(offset).map { ($0, offset) }
            }
        }

        guard read16(2) == 42, let first = read32(4),
              let pointer = entries(of: first).first(where: { $0.tag == 0x8769 }), let exifDirectory = read32(pointer.offset + 8) else { return false }
        let exifEntries = entries(of: exifDirectory)
        guard let widthEntry = exifEntries.first(where: { $0.tag == 0xA002 }), let heightEntry = exifEntries.first(where: { $0.tag == 0xA003 }) else { return false }

        for (entry, value) in [(widthEntry, width), (heightEntry, height)] {
            guard let type = read16(entry.offset + 2), type == 3 || type == 4, read32(entry.offset + 4) == 1 else { return false }
            if type == 3, value <= 0xFFFF {
                write16(value, at: entry.offset + 8)
                write16(0, at: entry.offset + 10)
            } else {
                write16(4, at: entry.offset + 2)
                write32(value, at: entry.offset + 8)
            }
        }
        blob = Data(bytes)
        return true
    }

    private static func tinyJPEG(with properties: [CFString: Any]) -> Data? {
        guard let context = CGContext(data: nil, width: 2, height: 2, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                      bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue),
              let image = context.makeImage(),
              let data = CFDataCreateMutable(nil, 0),
              let sink = CGImageDestinationCreateWithData(data, UTType.jpeg.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(sink, image, properties as CFDictionary)
        return CGImageDestinationFinalize(sink) ? data as Data : nil
    }

    /// The payload of the APP1 "Exif" segment of a JPEG, without the "Exif\0\0" prefix.
    static func exifSegment(inJPEG jpeg: Data) -> Data? {
        let bytes = [UInt8](jpeg)
        guard bytes.count > 4, bytes[0] == 0xFF, bytes[1] == 0xD8 else { return nil }
        let prefix: [UInt8] = [0x45, 0x78, 0x69, 0x66, 0x00, 0x00]   // "Exif\0\0"
        var offset = 2
        while offset + 4 <= bytes.count, bytes[offset] == 0xFF {
            let marker = bytes[offset + 1]
            if marker == 0xDA { break }   // start of scan: no more metadata segments
            let length = Int(bytes[offset + 2]) << 8 | Int(bytes[offset + 3])
            let start = offset + 4
            let end = offset + 2 + length
            guard length >= 2, end <= bytes.count else { return nil }
            if marker == 0xE1, end - start > prefix.count, Array(bytes[start..<start + prefix.count]) == prefix {
                return Data(bytes[(start + prefix.count)..<end])
            }
            offset = end
        }
        return nil
    }

    // MARK: Color

    /// The embedded profile of an RGB image, or `nil` for sRGB (the default everywhere, so nothing needs saying) and for
    /// spaces that cannot be written as an ICC profile.
    public static func iccProfile(of image: CGImage) -> Data? {
        guard let space = image.colorSpace, space.model == .rgb, !isSRGB(space) else { return nil }
        return space.copyICCData() as Data?
    }

    static func isSRGB(_ space: CGColorSpace) -> Bool {
        (space.name as String?) == (CGColorSpace.sRGB as String)
    }

    // MARK: What a format without room for it would lose

    /// Metadata a format that stores only EXIF/TIFF/GPS and an ICC profile at 8 bits would lose from this image.
    /// Names are for the user: "IPTC", "resolution", "16-bit color", "color profile".
    public static func droppedMetadata(properties: [CFString: Any], image: CGImage) -> [String] {
        var lost: [String] = []
        if properties[kCGImagePropertyIPTCDictionary] != nil { lost.append("IPTC") }

        let width = (properties[kCGImagePropertyDPIWidth] as? NSNumber)?.doubleValue
        let height = (properties[kCGImagePropertyDPIHeight] as? NSNumber)?.doubleValue
        if (width != nil && width != 72) || (height != nil && height != 72) { lost.append("resolution") }

        if image.bitsPerComponent > 8 { lost.append("16-bit color") }

        if let space = image.colorSpace {
            switch space.model {
            case .monochrome:
                break
            case .rgb:
                if !isSRGB(space), iccProfile(of: image) == nil { lost.append("color profile") }
            default:
                lost.append("color profile")
            }
        }
        return lost
    }
}

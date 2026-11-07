import Foundation

/// An image format Roundel can convert to.
public struct ImageFormat: Equatable, Hashable, Sendable {
    /// Name used in config params, e.g. "jpeg".
    public let key: String
    public let displayName: String
    public let typeIdentifier: String
    /// What the output file is called, e.g. "jpg".
    public let fileExtension: String
    /// Has a quality setting (0-1).
    public let isLossy: Bool
    /// Can store transparency. Formats that cannot get the image flattened onto white.
    public let supportsAlpha: Bool
    /// Can store the EXIF orientation tag. Formats that cannot get the rotation applied to the pixels instead.
    public let storesOrientation: Bool
}

public enum ImageFormats {
    /// The formats offered in the ring, in ring order. Only those the running system reports as writable are shown
    /// (`CGImageDestinationCopyTypeIdentifiers()`); other writable types (PDF, ICO, TGA, ...) are not conversion targets.
    public static let catalog: [ImageFormat] = [
        ImageFormat(key: "png", displayName: "PNG", typeIdentifier: "public.png", fileExtension: "png", isLossy: false, supportsAlpha: true, storesOrientation: true),
        ImageFormat(key: "jpeg", displayName: "JPEG", typeIdentifier: "public.jpeg", fileExtension: "jpg", isLossy: true, supportsAlpha: false, storesOrientation: true),
        ImageFormat(key: "heic", displayName: "HEIC", typeIdentifier: "public.heic", fileExtension: "heic", isLossy: true, supportsAlpha: true, storesOrientation: true),
        ImageFormat(key: "tiff", displayName: "TIFF", typeIdentifier: "public.tiff", fileExtension: "tiff", isLossy: false, supportsAlpha: true, storesOrientation: true),
        ImageFormat(key: "gif", displayName: "GIF", typeIdentifier: "com.compuserve.gif", fileExtension: "gif", isLossy: false, supportsAlpha: true, storesOrientation: false),
        ImageFormat(key: "bmp", displayName: "BMP", typeIdentifier: "com.microsoft.bmp", fileExtension: "bmp", isLossy: false, supportsAlpha: true, storesOrientation: false),
        ImageFormat(key: "avif", displayName: "AVIF", typeIdentifier: "public.avif", fileExtension: "avif", isLossy: true, supportsAlpha: true, storesOrientation: true),
    ]

    public static func format(forKey key: String) -> ImageFormat? {
        catalog.first { $0.key == key }
    }

    /// The catalog formats the system can write, in catalog order.
    public static func available(writable typeIdentifiers: [String]) -> [ImageFormat] {
        let writable = Set(typeIdentifiers)
        return catalog.filter { writable.contains($0.typeIdentifier) }
    }

    /// Whether a file whose content was detected as `detectedType` is already in `format`. Compares the type found in
    /// the file's content, not its extension, and only exact types: JPEG 2000 is not JPEG.
    public static func isSame(detectedType: String, as format: ImageFormat) -> Bool {
        detectedType == format.typeIdentifier
    }

    /// A readable name for a detected type, for messages.
    public static func name(ofDetectedType type: String) -> String {
        if let known = catalog.first(where: { $0.typeIdentifier == type }) { return known.displayName }
        let others = ["public.jpeg-2000": "JPEG 2000", "com.adobe.photoshop-image": "PSD", "com.apple.icns": "ICNS", "com.microsoft.ico": "ICO",
                      "com.truevision.tga-image": "TGA", "public.heif": "HEIF", "org.webmproject.webp": "WebP", "com.adobe.raw-image": "DNG"]
        return others[type] ?? type
    }
}

import Foundation
import ImageIO

/// What this system can write. Read at run time, never hard-coded.
public protocol ImageCapabilities: Sendable {
    /// Uniform type identifiers of the formats that can be written, e.g. "public.png".
    var writableTypeIdentifiers: [String] { get }
}

/// ImageIO's own list, `CGImageDestinationCopyTypeIdentifiers()`.
public struct SystemImageCapabilities: ImageCapabilities {
    public init() {}
    public var writableTypeIdentifiers: [String] { CGImageDestinationCopyTypeIdentifiers() as? [String] ?? [] }
}

public struct EncodeOutcome: Equatable, Sendable {
    public var notes: [ConversionNote]
    public init(notes: [ConversionNote] = []) { self.notes = notes }
}

/// What the user asked for beyond the format.
public struct ImageEncodingOptions: Equatable, Sendable {
    /// 0-1 for formats with a quality setting. For lossless WebP it means compression effort instead.
    public var quality: Double?
    /// Lossless output, for formats that have such a mode (WebP).
    public var lossless: Bool

    public init(quality: Double? = nil, lossless: Bool = false) {
        self.quality = quality
        self.lossless = lossless
    }
}

public enum ImageConversionError: Error, Equatable, Sendable {
    case notAnImage
    case unreadable
    case encodeFailed(format: String)
    case tooLarge(format: String, limit: Int)

    /// Safe to show to the user as is.
    public var message: String {
        switch self {
        case .notAnImage: "not an image"
        case .unreadable: "can’t be read"
        case .encodeFailed(let format): "the system couldn’t write \(format)"
        case .tooLarge(let format, let limit): "too large for \(format) (max \(limit) pixels per side)"
        }
    }
}

/// One way of reading and writing images. ImageIO today; libwebp and libavif backends can be added next to it.
public protocol ImageEncoder: Sendable {
    /// The uniform type identifier of the file's *content*, or `nil` if it is not an image this backend can read.
    func detectType(of url: URL) -> String?
    /// Converts `source` and writes the result to exactly `destination`.
    func encode(source: URL, to destination: URL, format: ImageFormat, options: ImageEncodingOptions) throws -> EncodeOutcome
}

/// An encoder that can say which formats it writes, so several can be combined (see `ImageBackends`).
public protocol ImageBackend: ImageEncoder {
    /// Short name for logs and tests, e.g. "ImageIO".
    var name: String { get }
    /// Uniform type identifiers this backend can write.
    var writableTypeIdentifiers: [String] { get }
}

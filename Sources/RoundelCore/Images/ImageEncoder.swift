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
    public var note: ConversionNote?
    public init(note: ConversionNote? = nil) { self.note = note }
}

public enum ImageConversionError: Error, Equatable, Sendable {
    case notAnImage
    case unreadable
    case encodeFailed(format: String)

    /// Safe to show to the user as is.
    public var message: String {
        switch self {
        case .notAnImage: "not an image"
        case .unreadable: "can’t be read"
        case .encodeFailed(let format): "the system couldn’t write \(format)"
        }
    }
}

/// One way of reading and writing images. ImageIO today; libwebp and libavif backends can be added next to it.
public protocol ImageEncoder: Sendable {
    /// The uniform type identifier of the file's *content*, or `nil` if it is not an image this backend can read.
    func detectType(of url: URL) -> String?
    /// Converts `source` and writes the result to exactly `destination`.
    func encode(source: URL, to destination: URL, format: ImageFormat, quality: Double?) throws -> EncodeOutcome
}

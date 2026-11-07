import Foundation

/// Several image backends used as one, in priority order. A format is written by the first backend that can write it,
/// so ImageIO (listed first) keeps every format it can already write, and libwebp only adds what ImageIO lacks.
/// Reading is the same: the first backend that recognizes a file by its content.
public struct ImageBackends: ImageEncoder, ImageCapabilities, Sendable {
    private let backends: [any ImageBackend]

    public init(_ backends: [any ImageBackend]) {
        self.backends = backends
    }

    public func backend(for format: ImageFormat) -> (any ImageBackend)? {
        backends.first { $0.writableTypeIdentifiers.contains(format.typeIdentifier) }
    }

    /// The formats any backend can write, in priority order, each once.
    public var writableTypeIdentifiers: [String] {
        var seen: Set<String> = []
        return backends.flatMap(\.writableTypeIdentifiers).filter { seen.insert($0).inserted }
    }

    public func detectType(of url: URL) -> String? {
        for backend in backends {
            if let type = backend.detectType(of: url) { return type }
        }
        return nil
    }

    public func encode(source: URL, to destination: URL, format: ImageFormat, options: ImageEncodingOptions) throws -> EncodeOutcome {
        guard let backend = backend(for: format) else { throw ImageConversionError.encodeFailed(format: format.displayName) }
        return try backend.encode(source: source, to: destination, format: format, options: options)
    }
}

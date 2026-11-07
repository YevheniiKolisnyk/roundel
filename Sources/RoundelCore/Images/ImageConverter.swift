import Foundation

/// Converts a batch of files.
public protocol ImageConverting: Sendable {
    /// - Parameter progress: called once per finished file with `(done, total)`, from any thread.
    /// - Returns: one result per input file, in the same order.
    func convert(files: [URL], to format: ImageFormat, quality: Double?, progress: @escaping @Sendable (Int, Int) -> Void) async -> [ConversionItemResult]
}

/// Runs conversions with limited concurrency. For every file: detect the source type by content, skip files already
/// in the target format, pick an output name that is free (reserved up front so parallel files never choose the same
/// one), encode into a temporary file next to the source, and move it into place without ever replacing anything.
/// Originals are never modified or deleted.
public final class ImageConverter: ImageConverting, Sendable {
    private let encoder: any ImageEncoder
    private let maxConcurrent: Int
    private let fileExists: @Sendable (URL) -> Bool

    public init(encoder: any ImageEncoder, maxConcurrent: Int = 3,
                fileExists: @escaping @Sendable (URL) -> Bool = { FileManager.default.fileExists(atPath: $0.path) }) {
        self.encoder = encoder
        self.maxConcurrent = max(1, maxConcurrent)
        self.fileExists = fileExists
    }

    public func convert(files: [URL], to format: ImageFormat, quality: Double?, progress: @escaping @Sendable (Int, Int) -> Void) async -> [ConversionItemResult] {
        let total = files.count
        guard total > 0 else { return [] }

        let names = NameReservations(fileExists: fileExists)
        var results = [ConversionItemResult?](repeating: nil, count: total)
        var done = 0

        await withTaskGroup(of: (Int, ConversionItemResult).self) { group in
            var next = 0
            func startNext() {
                guard next < total else { return }
                let index = next
                next += 1
                group.addTask { (index, await self.convertOne(files[index], to: format, quality: quality, names: names)) }
            }
            for _ in 0..<min(maxConcurrent, total) { startNext() }
            while let (index, result) = await group.next() {
                results[index] = result
                done += 1
                progress(done, total)
                startNext()
            }
        }
        return results.enumerated().map { $0.element ?? .failed(source: files[$0.offset], message: "cancelled") }
    }

    // MARK: One file

    private func convertOne(_ source: URL, to format: ImageFormat, quality: Double?, names: NameReservations) async -> ConversionItemResult {
        if Task.isCancelled { return .failed(source: source, message: "cancelled") }
        guard FileManager.default.fileExists(atPath: source.path) else { return .failed(source: source, message: "file not found") }
        guard let type = encoder.detectType(of: source) else { return .failed(source: source, message: ImageConversionError.notAnImage.message) }
        if ImageFormats.isSame(detectedType: type, as: format) { return .skipped(source: source, reason: .alreadyInFormat) }

        let first = await names.reserve(for: source, fileExtension: format.fileExtension)
        let temporary = first.deletingLastPathComponent()
            .appendingPathComponent(".\(first.lastPathComponent).roundel-\(UUID().uuidString.prefix(8)).tmp")

        let outcome: EncodeOutcome
        do {
            outcome = try encoder.encode(source: source, to: temporary, format: format, quality: quality)
        } catch {
            try? FileManager.default.removeItem(at: temporary)
            return .failed(source: source, message: Self.message(for: error))
        }

        // Move into place. If the name was taken in the meantime, move on to the next free one: a file is never replaced.
        var destination = first
        for _ in 0..<50 {
            do {
                try FileManager.default.moveItem(at: temporary, to: destination)
                return .converted(source: source, output: destination, note: outcome.note)
            } catch {
                guard FileManager.default.fileExists(atPath: destination.path) else {
                    try? FileManager.default.removeItem(at: temporary)
                    return .failed(source: source, message: Self.message(for: error))
                }
                destination = await names.reserve(for: source, fileExtension: format.fileExtension)
            }
        }
        try? FileManager.default.removeItem(at: temporary)
        return .failed(source: source, message: "no free file name")
    }

    private static func message(for error: Error) -> String {
        (error as? ImageConversionError)?.message ?? error.localizedDescription
    }
}

/// Hands out output names one at a time, so files converted in parallel never pick the same one.
private actor NameReservations {
    private let fileExists: @Sendable (URL) -> Bool
    private var reserved: Set<URL> = []

    init(fileExists: @escaping @Sendable (URL) -> Bool) {
        self.fileExists = fileExists
    }

    func reserve(for source: URL, fileExtension: String) -> URL {
        let url = OutputNaming.destination(for: source, fileExtension: fileExtension, exists: fileExists, reserved: reserved)
        reserved.insert(url)
        return url
    }
}

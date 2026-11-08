import Foundation

/// Gives each output file its place: a free name next to the source (reserved up front, so files processed in parallel
/// never pick the same one), a hidden temporary file to write into, and a move into place that never replaces anything.
/// Shared by every action that writes a new file beside an original.
final class OutputPlacer: Sendable {
    struct Slot {
        let target: URL
        let temporary: URL
    }

    private let names: NameReservations
    private let suffix: String

    init(suffix: String = "", fileExists: @escaping @Sendable (URL) -> Bool = { FileManager.default.fileExists(atPath: $0.path) }) {
        self.names = NameReservations(fileExists: fileExists)
        self.suffix = suffix
    }

    func reserve(for source: URL, fileExtension: String) async -> Slot {
        let target = await names.reserve(for: source, suffix: suffix, fileExtension: fileExtension)
        return Slot(target: target, temporary: Self.temporaryURL(beside: target))
    }

    /// Moves a finished temporary file to its name; if that name was taken meanwhile, takes the next free one. The
    /// temporary file is gone afterwards whatever happens. Returns the final URL, or the message to show.
    func moveIntoPlace(_ slot: Slot, source: URL, fileExtension: String) async -> Result<URL, PlacementFailure> {
        var destination = slot.target
        for _ in 0..<50 {
            do {
                try FileManager.default.moveItem(at: slot.temporary, to: destination)
                return .success(destination)
            } catch {
                guard FileManager.default.fileExists(atPath: destination.path) else {
                    try? FileManager.default.removeItem(at: slot.temporary)
                    return .failure(PlacementFailure(message: FailureText.describe(error)))
                }
                destination = await names.reserve(for: source, suffix: suffix, fileExtension: fileExtension)
            }
        }
        try? FileManager.default.removeItem(at: slot.temporary)
        return .failure(PlacementFailure(message: "no free file name"))
    }

    static func temporaryURL(beside target: URL) -> URL {
        target.deletingLastPathComponent().appendingPathComponent(".\(target.lastPathComponent).roundel-\(UUID().uuidString.prefix(8)).tmp")
    }
}

struct PlacementFailure: Error, Equatable {
    let message: String
}

/// Hands out output names one at a time.
actor NameReservations {
    private let fileExists: @Sendable (URL) -> Bool
    private var reserved: Set<URL> = []

    init(fileExists: @escaping @Sendable (URL) -> Bool) {
        self.fileExists = fileExists
    }

    func reserve(for source: URL, suffix: String, fileExtension: String) -> URL {
        let url = OutputNaming.destination(for: source, suffix: suffix, fileExtension: fileExtension, exists: fileExists, reserved: reserved)
        reserved.insert(url)
        return url
    }
}

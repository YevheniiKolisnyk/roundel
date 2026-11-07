import Foundation

/// Where a converted file goes: next to the source, with the new extension, never on top of an existing file.
public enum OutputNaming {
    /// `photo.png` -> `photo.jpg`; if that is taken, `photo 2.jpg`, `photo 3.jpg`, ... like Finder.
    /// - Parameters:
    ///   - exists: whether a file is already there.
    ///   - reserved: names already promised to other files of the same batch. Compared ignoring case, because most
    ///     volumes do.
    public static func destination(for source: URL, fileExtension: String, exists: (URL) -> Bool, reserved: Set<URL> = []) -> URL {
        let directory = source.deletingLastPathComponent()
        let stem = source.deletingPathExtension().lastPathComponent
        let taken = Set(reserved.map { $0.path.lowercased() })

        var number = 1
        while true {
            let name = number == 1 ? "\(stem).\(fileExtension)" : "\(stem) \(number).\(fileExtension)"
            let candidate = directory.appendingPathComponent(name)
            if !exists(candidate) && !taken.contains(candidate.path.lowercased()) { return candidate }
            number += 1
        }
    }
}

import Foundation

enum ConfigLocation {
    /// `~/Library/Application Support/Roundel`. For development and tests, `ROUNDEL_CONFIG_DIR` overrides it.
    static var directory: URL {
        if let override = ProcessInfo.processInfo.environment["ROUNDEL_CONFIG_DIR"], !override.isEmpty {
            return URL(fileURLWithPath: (override as NSString).expandingTildeInPath, isDirectory: true)
        }
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support")
        return support.appendingPathComponent("Roundel", isDirectory: true)
    }

    static var file: URL { directory.appendingPathComponent("config.json") }
}

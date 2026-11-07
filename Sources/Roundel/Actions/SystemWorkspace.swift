import AppKit
import RoundelCore

@MainActor
struct SystemWorkspace: WorkspaceOpening {
    func applicationURL(forBundleID id: String) -> URL? {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: id)
    }

    func fileExists(at url: URL) -> Bool {
        FileManager.default.fileExists(atPath: url.path)
    }

    func openApplication(at url: URL) async throws {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true   // the user asked for this app: bringing it forward is the point
        do {
            _ = try await NSWorkspace.shared.openApplication(at: url, configuration: configuration)
        } catch {
            throw ActionError.failed("could not open \(url.deletingPathExtension().lastPathComponent): \(error.localizedDescription)")
        }
    }

    func open(_ urls: [URL], withApplicationAt appURL: URL) async throws {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true   // the user asked for this app: bringing it forward is the point
        do {
            _ = try await NSWorkspace.shared.open(urls, withApplicationAt: appURL, configuration: configuration)
        } catch {
            throw ActionError.failed("could not open the files with \(appURL.deletingPathExtension().lastPathComponent): \(error.localizedDescription)")
        }
    }

    func open(_ url: URL) async throws {
        guard NSWorkspace.shared.open(url) else {
            throw ActionError.failed("nothing could open \(url.isFileURL ? url.path : url.absoluteString)")
        }
    }
}

import Foundation

/// Fires `onChange` (debounced) when the config file or its folder changes.
///
/// Both are watched: editors that save by writing a temp file and renaming it change the folder entry
/// (the old file's descriptor goes stale), while editors that write in place only touch the file.
/// After every event both watches are re-created, so a replaced file keeps being tracked.
@MainActor
final class ConfigWatcher {
    private let directory: URL
    private let file: URL
    private let debounce: TimeInterval
    private let onChange: () -> Void

    private var directorySource: DispatchSourceFileSystemObject?
    private var fileSource: DispatchSourceFileSystemObject?
    private var pending: DispatchWorkItem?

    init(directory: URL, file: URL, debounce: TimeInterval = 0.25, onChange: @escaping () -> Void) {
        self.directory = directory
        self.file = file
        self.debounce = debounce
        self.onChange = onChange
    }

    func start() {
        arm()
    }

    func stop() {
        pending?.cancel()
        directorySource?.cancel()
        fileSource?.cancel()
        directorySource = nil
        fileSource = nil
    }

    /// Re-creates both watches. Safe to call any time (e.g. after the folder was recreated).
    func arm() {
        directorySource?.cancel()
        fileSource?.cancel()
        directorySource = makeSource(path: directory.path, mask: [.write, .rename, .delete, .link])
        fileSource = makeSource(path: file.path, mask: [.write, .extend, .rename, .delete, .attrib])
    }

    private func makeSource(path: String, mask: DispatchSource.FileSystemEvent) -> DispatchSourceFileSystemObject? {
        let descriptor = open(path, O_EVTONLY)
        guard descriptor >= 0 else { return nil }
        let source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: descriptor, eventMask: mask, queue: .main)
        source.setEventHandler { [weak self] in
            MainActor.assumeIsolated { self?.schedule() }
        }
        source.setCancelHandler { close(descriptor) }
        source.resume()
        return source
    }

    private func schedule() {
        pending?.cancel()
        let item = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.arm()
                self.onChange()
            }
        }
        pending = item
        DispatchQueue.main.asyncAfter(deadline: .now() + debounce, execute: item)
    }
}

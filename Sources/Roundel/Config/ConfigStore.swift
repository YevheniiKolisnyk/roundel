import Foundation
import RoundelCore

/// Owns the active config: creates the default on first launch, loads the file, watches it, keeps the last good
/// config when the file is invalid, and reports problems (log + toast). Never crashes on bad input.
@MainActor
final class ConfigStore {
    let directory: URL
    let file: URL

    /// Called with the active config after the initial load and after every successful change.
    var onChange: ((RoundelConfig) -> Void)?

    private let toast: ToastPresenter
    private var state = ConfigState(initial: DefaultConfig.config)
    private var watcher: ConfigWatcher?

    var config: RoundelConfig { state.config }
    var lastFailure: ConfigLoadFailure? { state.lastFailure }

    init(directory: URL = ConfigLocation.directory, file: URL = ConfigLocation.file, toast: ToastPresenter) {
        self.directory = directory
        self.file = file
        self.toast = toast
    }

    func start() {
        do {
            if try DefaultConfig.writeIfMissing(at: file) {
                Log.info("Created default config at \(file.path)")
            }
        } catch {
            Log.warning("Could not create the default config at \(file.path): \(error.localizedDescription)")
        }

        // Make sure the ring gets the initial config exactly once, even when the file equals the built-in default.
        if !reload(userInitiated: false) { onChange?(state.config) }

        let watcher = ConfigWatcher(directory: directory, file: file) { [weak self] in
            self?.reload(userInitiated: false)
        }
        watcher.start()
        self.watcher = watcher
    }

    /// Returns whether `onChange` was called.
    @discardableResult
    func reload(userInitiated: Bool) -> Bool {
        // One read of the whole file. A half-written file fails to parse and is retried on the next change event.
        let data: Data
        do {
            data = try Data(contentsOf: file)
        } catch {
            let reason = error.localizedDescription.trimmingCharacters(in: CharacterSet(charactersIn: "."))
            Log.warning("Cannot read \(file.lastPathComponent): \(reason). Keeping the previous config.")
            if userInitiated { toast.show("Cannot read config.json. Keeping the previous config.", isError: true) }
            watcher?.arm()
            return false
        }

        switch state.apply(data) {
        case .updated:
            Log.info("Config loaded: \(describe(state.config))")
            onChange?(state.config)
            if userInitiated { toast.show("Config reloaded") }
            return true
        case .recovered:
            Log.info("Config is valid again: \(describe(state.config))")
            if userInitiated { toast.show("Config reloaded") }
        case .unchanged:
            if let failure = state.lastFailure {
                if userInitiated { toast.show("Config still has errors: \(failure.summary)", isError: true) }
            } else if userInitiated {
                toast.show("Config is up to date")
            }
        case .rejected(let failure):
            for issue in failure.issues {
                Log.warning("config.json: \(issue). Keeping the previous config.")
            }
            toast.show("Config error: \(failure.summary)\nKeeping the previous config.", isError: true)
        }
        return false
    }

    private func describe(_ config: RoundelConfig) -> String {
        let (nodes, groups) = count(config.ring)
        return "\(config.ring.count) root sections, \(nodes) nodes, \(groups) groups, mode \(config.settings.openMode.rawValue)"
    }

    private func count(_ nodes: [Node]) -> (nodes: Int, groups: Int) {
        var total = 0, groups = 0
        for node in nodes {
            total += 1
            if let children = node.children {
                groups += 1
                let inner = count(children)
                total += inner.nodes
                groups += inner.groups
            }
        }
        return (total, groups)
    }
}

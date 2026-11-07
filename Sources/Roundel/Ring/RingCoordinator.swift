import AppKit
import KeyboardShortcuts
import SwiftUI
import RoundelCore

/// Glue: hotkey and pointer events go into `RingInteraction`; its outcomes drive the panel and the view model.
/// Holds no navigation logic of its own beyond translating screen coordinates to ring offsets.
@MainActor
final class RingCoordinator {
    private let iconStore: IconStore
    private let registry: ActionRegistry
    private let executor: ActionExecutor
    private let model = RingModel()
    private let panel: RingPanel
    private var interaction = RingInteraction()

    /// Config for the ring that is open right now. A reload while the ring is open waits until it closes.
    private var activeConfig = DefaultConfig.config
    private var pendingConfig: RoundelConfig?

    private var metrics = RingMetrics.make(sectionCount: 1)
    private var maxOuterRadius = RingMetrics.defaultMaxOuterRadius
    private var pollTimer: Timer?
    private var clickMonitors: [Any] = []

    init(iconStore: IconStore, registry: ActionRegistry, executor: ActionExecutor) {
        self.iconStore = iconStore
        self.registry = registry
        self.executor = executor
        self.panel = RingPanel(rootView: RingView(model: model), side: RingMetrics.make(sectionCount: 1).panelSide)
    }

    func start() {
        KeyboardShortcuts.onKeyDown(for: .openRing) { [weak self] in
            MainActor.assumeIsolated { self?.hotkeyDown() }
        }
        KeyboardShortcuts.onKeyUp(for: .openRing) { [weak self] in
            MainActor.assumeIsolated { self?.hotkeyUp() }
        }
        KeyboardShortcuts.onKeyDown(for: .dismissRing) { [weak self] in
            MainActor.assumeIsolated { self?.escape() }
        }
        // Registering a handler enables the shortcut immediately; Esc must only be live while the ring is open.
        KeyboardShortcuts.disable(.dismissRing)
    }

    // MARK: Config

    func applyConfig(_ config: RoundelConfig) {
        if interaction.isOpen {
            pendingConfig = config
        } else {
            activate(config)
        }
    }

    private func activate(_ config: RoundelConfig) {
        activeConfig = config
        pendingConfig = nil
        iconStore.reload(for: config)

        for level in RingMetrics.crowdedLevels(in: config) {
            let where_ = level.path.isEmpty ? "the top ring" : "group '\(level.path.joined(separator: " > "))'"
            Log.warning("\(where_) has \(level.count) sections, more than fit comfortably on screen. Consider grouping some of them.")
        }
    }

    // MARK: Hotkey

    private func hotkeyDown() {
        apply(interaction.hotkeyDown(config: activeConfig))
    }

    private func hotkeyUp() {
        apply(interaction.hotkeyUp())
    }

    private func escape() {
        apply(interaction.escape())
    }

    // MARK: Outcomes

    private func apply(_ outcome: RingOutcome) {
        switch outcome {
        case .none:
            break
        case .opened:
            open()
        case .levelChanged:
            withAnimation(.easeOut(duration: 0.1)) { showCurrentLevel() }
            // The ring under the cursor is new: tell the state machine where the cursor sits in it.
            pollPointer()
        case .select(let id):
            run(actionWithID: id)
            close()
        case .dismiss:
            close()
        }
    }

    private func open() {
        let started = DispatchTime.now()
        let frontmostBefore = NSWorkspace.shared.frontmostApplication?.bundleIdentifier

        let mouse = NSEvent.mouseLocation
        maxOuterRadius = Self.maxOuterRadius(at: mouse)
        showCurrentLevel()
        panel.show(centeredOn: mouse, side: metrics.panelSide)
        pollPointer()
        startTracking()
        KeyboardShortcuts.enable(.dismissRing)

        let millis = Double(DispatchTime.now().uptimeNanoseconds - started.uptimeNanoseconds) / 1_000_000
        Log.info("Ring opened in \(String(format: "%.1f", millis)) ms (\(interaction.mode.rawValue), \(interaction.currentNodes.count) sections)")

        // Focus check: the frontmost app must be the same one after we show the panel.
        let after = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        if after != frontmostBefore {
            Log.warning("Frontmost app changed on open: \(frontmostBefore ?? "nil") -> \(after ?? "nil")")
        }
    }

    private func close() {
        stopTracking()
        KeyboardShortcuts.disable(.dismissRing)
        panel.hide()
        model.highlighted = nil
        model.dwellProgress = nil
        if let pendingConfig { activate(pendingConfig) }
    }

    /// Rebuilds the view model and panel size for the level the state machine is on.
    private func showCurrentLevel() {
        let nodes = interaction.currentNodes
        metrics = RingMetrics.make(sectionCount: nodes.count, maxOuterRadius: maxOuterRadius)

        model.items = RingItem.items(
            for: nodes,
            isAvailable: { [registry] in registry.isAvailable($0) },
            isActive: { [registry] in registry.isActive($0) },
            defaultIcon: { [registry] in registry.defaultIcon(for: $0) }
        ).map {
            DisplayItem(item: $0, icon: iconStore.resolve($0))
        }
        model.metrics = metrics
        model.depth = interaction.depth
        model.highlighted = nil
        model.dwellProgress = nil
        model.levelToken += 1

        if panel.isVisible { panel.resize(side: metrics.panelSide) }
    }

    // MARK: Running actions

    private func run(actionWithID id: String) {
        guard case .action(let action)? = activeConfig.node(withID: id) else {
            Log.warning("Selected '\(id)' but it is not an action node")
            return
        }
        // The ring is already closing; the action runs on its own so a slow one never holds the UI.
        Task { await executor.execute(action) }
    }

    // MARK: Pointer tracking

    private func startTracking() {
        stopTracking()

        // Polling NSEvent.mouseLocation is independent of window event routing: a non-key panel does not reliably
        // receive mouseMoved, and global monitors do not fire for events over our own windows.
        let timer = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.pollPointer() }
        }
        RunLoop.main.add(timer, forMode: .common)
        pollTimer = timer

        let buttons: NSEvent.EventTypeMask = [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        if let global = NSEvent.addGlobalMonitorForEvents(matching: buttons, handler: { [weak self] _ in
            MainActor.assumeIsolated { self?.pointerClicked() }
        }) {
            clickMonitors.append(global)
        }
        if let local = NSEvent.addLocalMonitorForEvents(matching: buttons, handler: { [weak self] event in
            MainActor.assumeIsolated { self?.pointerClicked() }
            return event
        }) {
            clickMonitors.append(local)
        }
    }

    private func stopTracking() {
        pollTimer?.invalidate()
        pollTimer = nil
        clickMonitors.forEach(NSEvent.removeMonitor)
        clickMonitors.removeAll()
    }

    private func pollPointer() {
        guard interaction.isOpen else { return }
        let now = ProcessInfo.processInfo.systemUptime
        let offset = pointerOffset()
        let section = metrics.geometry.sectionIndex(dx: offset.dx, dy: offset.dy)

        let outcome = interaction.update(section: section, now: now)
        if outcome != .none {
            apply(outcome)
            return
        }

        if model.highlighted != interaction.highlighted { model.highlighted = interaction.highlighted }
        let progress = interaction.dwellProgress(at: now)
        if model.dwellProgress != progress { model.dwellProgress = progress }
    }

    private func pointerClicked() {
        let offset = pointerOffset()
        let geometry = metrics.geometry
        let distance = hypot(offset.dx, offset.dy)

        let target: ClickTarget
        if distance < metrics.deadZoneRadius {
            target = .center
        } else if geometry.isWithinRing(dx: offset.dx, dy: offset.dy), let section = geometry.sectionIndex(dx: offset.dx, dy: offset.dy) {
            target = .section(section)
        } else {
            target = .outside   // beyond the drawn ring, the transparent panel corners, or another app
        }
        apply(interaction.click(target))
    }

    /// Cursor offset from the ring center, y-up, in screen points.
    private func pointerOffset() -> (dx: Double, dy: Double) {
        let mouse = NSEvent.mouseLocation
        let center = panel.ringCenter
        return (Double(mouse.x - center.x), Double(mouse.y - center.y))
    }

    /// Keeps the largest ring inside the screen the cursor is on.
    private static func maxOuterRadius(at point: CGPoint) -> Double {
        let screen = NSScreen.screens.first { $0.frame.contains(point) } ?? NSScreen.main
        guard let frame = screen?.visibleFrame else { return RingMetrics.defaultMaxOuterRadius }
        let fits = (Double(min(frame.width, frame.height)) / 2).rounded(.down) - RingMetrics.panelPadding - 8
        return min(RingMetrics.defaultMaxOuterRadius, max(RingMetrics.minOuterRadius, fits))
    }
}

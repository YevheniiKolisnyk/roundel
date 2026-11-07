import AppKit
import KeyboardShortcuts
import RoundelCore

/// Glue: hotkey events and pointer events go into `RingInteraction`; its outcomes drive the panel.
/// Holds no ring logic of its own beyond translating screen coordinates to ring offsets.
@MainActor
final class RingCoordinator {
    private let settings: RingSettings
    private let model = RingModel()
    private let panel: RingPanel
    private var interaction = RingInteraction()
    private var geometry = RingLayout.geometry(sectionCount: PlaceholderRing.defaultCount)

    private var pollTimer: Timer?
    private var clickMonitors: [Any] = []

    init(settings: RingSettings) {
        self.settings = settings
        self.panel = RingPanel(rootView: RingView(model: model))
    }

    func start() {
        KeyboardShortcuts.onKeyDown(for: .openRing) { [weak self] in
            MainActor.assumeIsolated { self?.hotkeyDown() }
        }
        KeyboardShortcuts.onKeyUp(for: .openRing) { [weak self] in
            MainActor.assumeIsolated { self?.hotkeyUp() }
        }
        KeyboardShortcuts.onKeyDown(for: .dismissRing) { [weak self] in
            MainActor.assumeIsolated { self?.apply(self?.interaction.escape() ?? .none) }
        }
        // Registering a handler enables the shortcut immediately; Esc must only be live while the ring is open.
        KeyboardShortcuts.disable(.dismissRing)
    }

    // MARK: Hotkey

    private func hotkeyDown() {
        apply(interaction.hotkeyDown(mode: settings.openMode))
    }

    private func hotkeyUp() {
        apply(interaction.hotkeyUp())
    }

    // MARK: Outcomes

    private func apply(_ outcome: RingOutcome) {
        switch outcome {
        case .none:
            break
        case .opened:
            open()
        case .select(let index):
            // Milestone 1 has no actions: report the selection and close.
            Log.info("Selected section \(index + 1) of \(model.sections.count)")
            close()
        case .dismiss:
            close()
        }
    }

    private func open() {
        let started = DispatchTime.now()
        let frontmostBefore = NSWorkspace.shared.frontmostApplication?.bundleIdentifier

        let sections = PlaceholderRing.sections(count: settings.sectionCount)
        geometry = RingLayout.geometry(sectionCount: sections.count)
        model.sections = sections
        model.highlighted = nil

        panel.show(centeredOn: NSEvent.mouseLocation)
        pollPointer()
        startTracking()
        KeyboardShortcuts.enable(.dismissRing)

        let millis = Double(DispatchTime.now().uptimeNanoseconds - started.uptimeNanoseconds) / 1_000_000
        Log.info("Ring opened in \(String(format: "%.1f", millis)) ms (\(settings.openMode.rawValue), \(sections.count) sections)")

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
        let section = hoveredSection()
        guard section != interaction.highlighted else { return }
        interaction.pointerMoved(section: section)
        model.highlighted = section
    }

    private func pointerClicked() {
        // Clicks only count on the drawn ring; the dead zone, the transparent panel corners and everything
        // outside are "nothing", which dismisses a click-required ring.
        let offset = pointerOffset()
        let section = geometry.isWithinRing(dx: offset.dx, dy: offset.dy)
            ? geometry.sectionIndex(dx: offset.dx, dy: offset.dy)
            : nil
        apply(interaction.click(section: section))
    }

    private func hoveredSection() -> Int? {
        let offset = pointerOffset()
        return geometry.sectionIndex(dx: offset.dx, dy: offset.dy)
    }

    /// Cursor offset from the ring center, y-up, in screen points.
    private func pointerOffset() -> (dx: Double, dy: Double) {
        let mouse = NSEvent.mouseLocation
        let center = panel.ringCenter
        return (Double(mouse.x - center.x), Double(mouse.y - center.y))
    }
}

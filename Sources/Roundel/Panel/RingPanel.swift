import AppKit
import SwiftUI

/// Borderless floating panel that can show above other apps (including fullscreen ones) without ever taking focus.
final class RingPanel: NSPanel {
    private let side = RingLayout.panelSide

    init(rootView: some View) {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: RingLayout.panelSide, height: RingLayout.panelSide),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: true
        )

        isFloatingPanel = true
        level = .popUpMenu
        // Visible on every Space, including over fullscreen apps; hidden from Mission Control / window cycling.
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        hidesOnDeactivate = false
        becomesKeyOnlyIfNeeded = true
        isReleasedWhenClosed = false
        animationBehavior = .none
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false

        let hosting = NSHostingView(rootView: rootView)
        hosting.sizingOptions = []   // never let SwiftUI resize or re-center the panel
        hosting.frame = NSRect(x: 0, y: 0, width: side, height: side)
        contentView = hosting
        hosting.layoutSubtreeIfNeeded()   // pre-warm so the first open is not the first layout
    }

    // Never key, never main: this is what keeps the frontmost app's focus (text caret, selection) intact.
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    /// Screen-space center of the ring (y-up). Use this, not the raw cursor position, as the geometry origin.
    var ringCenter: CGPoint { CGPoint(x: frame.midX, y: frame.midY) }

    func show(centeredOn point: CGPoint) {
        let origin = CGPoint(x: (point.x - side / 2).rounded(), y: (point.y - side / 2).rounded())
        setFrame(NSRect(origin: origin, size: CGSize(width: side, height: side)), display: false)
        // orderFrontRegardless: does not activate the app and does not make the panel key.
        orderFrontRegardless()
    }

    func hide() {
        orderOut(nil)
    }
}

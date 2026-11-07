import AppKit
import SwiftUI

/// Borderless floating panel that can show above other apps (including fullscreen ones) without ever taking focus.
/// Square, and resizable around a fixed center because the ring grows with its number of sections.
final class RingPanel: NSPanel {
    private let dropView: DropHostingView

    /// Receives the file drags that land on the panel.
    weak var dropDelegate: RingDropDelegate? {
        didSet { dropView.dropDelegate = dropDelegate }
    }

    init(rootView: RingView, side: Double) {
        dropView = DropHostingView(rootView: rootView)
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: side, height: side),
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

        let hosting = dropView
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

    func show(centeredOn point: CGPoint, side: Double) {
        let origin = CGPoint(x: (point.x - side / 2).rounded(), y: (point.y - side / 2).rounded())
        setFrame(NSRect(origin: origin, size: CGSize(width: side, height: side)), display: false)
        // orderFrontRegardless: does not activate the app and does not make the panel key.
        orderFrontRegardless()
    }

    /// Changes the size while keeping the ring center fixed (`side` must be an even whole number of points).
    func resize(side: Double) {
        let center = ringCenter
        let origin = CGPoint(x: center.x - side / 2, y: center.y - side / 2)
        setFrame(NSRect(origin: origin, size: CGSize(width: side, height: side)), display: true)
    }

    /// Do not touch `ignoresMouseEvents` here or in `show()`: assigning it (even to `false`) was verified to make the
    /// window swallow clicks on its transparent pixels, which breaks the click-through outside the ring's footprint.
    /// The coordinator empties the footprint before calling this, which is what makes a closing panel inert.
    func hide() {
        orderOut(nil)
    }
}

import AppKit
import SwiftUI
import RoundelCore

/// How big the toast stack is and where it goes. Kept apart from the window so it can be measured without showing
/// anything.
///
/// A card is measured by SwiftUI for its real width, so a long message wraps instead of being cut off. Sizes must never
/// be empty: a window with no area is "on screen" and invisible, which is what every toast was once (reading
/// `fittingSize` of a hosting view with empty `sizingOptions` gives 0 x 0).
enum ToastLayout {
    private static let metrics = DesignMetrics.standard
    private static let fallbackSize = NSSize(width: metrics.toastWidth, height: 48)

    /// Room around the stack for the shadow. The top equals the margin, so the window starts exactly at the bottom of the
    /// menu bar and the first card sits one margin below it; the shadow above a card fits inside that margin.
    static var insets: NSEdgeInsets {
        NSEdgeInsets(top: metrics.toastMargin, left: metrics.shadowRadius, bottom: metrics.shadowRadius + metrics.shadowYOffset, right: metrics.shadowRadius)
    }

    /// The size of one card: the agreed width and the height its text needs.
    @MainActor
    static func cardSize(for message: ToastMessage) -> NSSize {
        let measured = NSHostingController(rootView: ToastCard(message: message))
            .sizeThatFits(in: CGSize(width: metrics.toastWidth, height: .greatestFiniteMagnitude))
        return usable(NSSize(width: metrics.toastWidth, height: ceil(measured.height)))
    }

    /// A size the window can really have; anything else (zero, NaN, infinite) becomes a visible default.
    static func usable(_ size: NSSize) -> NSSize {
        guard size.width.isFinite, size.height.isFinite, size.width >= 1, size.height >= 1 else { return fallbackSize }
        return size
    }

    /// The window for a stack of cards (and the "+N more" chip), shadow room included. Empty stack: no size.
    static func stackSize(cardHeights: [Double], hasMore: Bool) -> NSSize {
        guard !cardHeights.isEmpty else { return .zero }
        var height = insets.top + cardHeights.reduce(0, +) + metrics.toastSpacing * Double(cardHeights.count - 1) + insets.bottom
        if hasMore { height += metrics.toastSpacing + metrics.toastMoreChipHeight }
        return NSSize(width: metrics.toastWidth + insets.left + insets.right, height: height)
    }

    /// Top-right of the screen's usable area (below the menu bar): the first card's top edge one margin below the area's
    /// top, its right edge one margin in from the area's right. The window itself never rises above the area.
    static func panelFrame(size: NSSize, in area: NSRect) -> NSRect {
        let maxX = area.maxX - metrics.toastMargin + insets.right
        return NSRect(x: maxX - size.width, y: area.maxY - size.height, width: size.width, height: size.height)
    }
}

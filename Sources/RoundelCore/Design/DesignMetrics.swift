import Foundation

/// How an animation moves. Springs are short and subtle; with Reduce Motion everything becomes a quick cross-fade.
public enum MotionSpec: Equatable, Sendable {
    case spring(response: Double, dampingFraction: Double)
    case fade(duration: Double)
    /// A plain ease-out of a fixed length: it settles without overshoot.
    case easeOut(duration: Double)
}

/// The design language in numbers, in one place, like `RingMetrics` is for geometry: spacing, type scale, radii,
/// toast layout, borders and motion. Views take every value from here; none has a magic number of its own.
public struct DesignMetrics: Equatable, Sendable {
    public static let standard = DesignMetrics()

    // Spacing, on a 4 pt grid
    public var space1 = 4.0
    public var space2 = 8.0
    public var space3 = 12.0
    public var space4 = 16.0
    public var space5 = 24.0

    // Type scale (SF Pro, points): titles, secondary lines, small captions
    public var titleSize = 13.0
    public var bodySize = 12.0
    public var captionSize = 11.0

    // Toasts
    public var toastWidth = 360.0
    /// Distance from the screen edge and the menu bar.
    public var toastMargin = 12.0
    public var toastSpacing = 8.0
    public var toastCornerRadius = 18.0
    public var toastIconSize = 20.0
    public var toastMaxVisible = 3
    public var toastMaxCharacters = 600
    /// Inside the card; equal to `space3`.
    public var toastPadding: Double { space3 }
    /// Corner radius of anything inside the card that has its own corners: concentric with the card.
    public var toastIconRadius: Double { concentricRadius(outer: toastCornerRadius, inset: toastPadding) }

    /// Height of the "+N more" chip under the stack.
    public var toastMoreChipHeight = 24.0

    // Depth
    public var shadowRadius = 16.0
    public var shadowYOffset = 6.0
    public var shadowOpacity = 0.22

    // Edges
    public var borderWidth = 0.5
    public var borderWidthIncreasedContrast = 1.0

    // Motion
    public var appearMotion = MotionSpec.spring(response: 0.32, dampingFraction: 0.84)
    public var selectionMotion = MotionSpec.spring(response: 0.2, dampingFraction: 0.88)
    public var reducedMotionFade = MotionSpec.fade(duration: 0.12)
    /// The ring and its arcs coming in: opacity and a small scale only, nothing that moves or overshoots.
    public var ringAppearMotion = MotionSpec.easeOut(duration: 0.15)
    /// The highlight changing from one cell to the next: a quick cross-fade.
    public var ringHighlightMotion = MotionSpec.fade(duration: 0.1)

    public init() {}

    /// The radius of a shape inset by `inset` inside a shape of radius `outer`, so their corners share a center.
    public func concentricRadius(outer: Double, inset: Double) -> Double {
        max(0, outer - inset)
    }

    /// `motion`, or the short cross-fade when the user asked for less motion.
    public func resolve(_ motion: MotionSpec, reduceMotion: Bool) -> MotionSpec {
        reduceMotion ? reducedMotionFade : motion
    }
}

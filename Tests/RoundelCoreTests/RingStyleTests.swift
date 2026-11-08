import XCTest
@testable import RoundelCore

/// The look of the ring in numbers and small pure rules. Geometry (sizes, hit-testing) is RingMetrics' and is not touched.
final class RingStyleTests: XCTestCase {
    private let style = RingStyle.standard

    // MARK: Emphasis

    func testEmphasisFollowsHoverAndOpenParentAndDisabled() {
        XCTAssertEqual(style.emphasis(isHovered: false, isOpenParent: false, isDisabled: false), .none)
        XCTAssertEqual(style.emphasis(isHovered: true, isOpenParent: false, isDisabled: false), .hovered)
        XCTAssertEqual(style.emphasis(isHovered: false, isOpenParent: true, isDisabled: false), .openParent)
        XCTAssertEqual(style.emphasis(isHovered: true, isOpenParent: true, isDisabled: false), .hovered, "pointing at the open group itself")
    }

    func testADisabledItemIsNeverHighlightedHoveredOrNot() {
        for hovered in [true, false] {
            for parent in [true, false] {
                XCTAssertEqual(style.emphasis(isHovered: hovered, isOpenParent: parent, isDisabled: true), .disabled)
            }
        }
    }

    func testTheSelectedSectorIsUnmistakableInEveryCondition() {
        for dark in [true, false] {
            for contrast in [true, false] {
                let t = style.traits(for: .hovered, increaseContrast: contrast, isDark: dark)
                XCTAssertTrue(t.showsHighlight)
                XCTAssertGreaterThanOrEqual(t.fillOpacity, 0.7, "dark \(dark) contrast \(contrast): visible at a glance")
                XCTAssertGreaterThanOrEqual(t.edgeOpacity, 0.4, "a light edge as well, not only a fill")
                XCTAssertGreaterThan(t.glowOpacity, 0)
                XCTAssertGreaterThan(t.iconScale, 1, "the icon grows a little")
            }
        }
    }

    func testIncreasedContrastMakesTheSelectionStrongerStill() {
        for dark in [true, false] {
            let normal = style.traits(for: .hovered, increaseContrast: false, isDark: dark)
            let strong = style.traits(for: .hovered, increaseContrast: true, isDark: dark)
            XCTAssertGreaterThan(strong.fillOpacity, normal.fillOpacity)
            XCTAssertGreaterThan(strong.edgeWidth, normal.edgeWidth)
            XCTAssertGreaterThanOrEqual(strong.edgeOpacity, normal.edgeOpacity)
        }
    }

    func testTheOpenParentIsSofterThanTheCurrentItemButStillThere() {
        for dark in [true, false] {
            for contrast in [true, false] {
                let hovered = style.traits(for: .hovered, increaseContrast: contrast, isDark: dark)
                let parent = style.traits(for: .openParent, increaseContrast: contrast, isDark: dark)
                XCTAssertTrue(parent.showsHighlight)
                XCTAssertLessThan(parent.fillOpacity, hovered.fillOpacity)
                XCTAssertLessThan(parent.edgeOpacity, hovered.edgeOpacity)
                XCTAssertGreaterThanOrEqual(parent.fillOpacity, 0.2, "still visible")
                XCTAssertEqual(parent.iconScale, 1)
            }
        }
    }

    func testNoEmphasisAndDisabledDrawNoHighlight() {
        let none = style.traits(for: .none, increaseContrast: false, isDark: true)
        XCTAssertFalse(none.showsHighlight)
        XCTAssertEqual(none.iconOpacity, 1)
        let disabled = style.traits(for: .disabled, increaseContrast: false, isDark: true)
        XCTAssertFalse(disabled.showsHighlight)
        XCTAssertEqual(disabled.iconOpacity, style.dimmedOpacity)
        XCTAssertEqual(disabled.iconScale, 1, "no hover feedback at all")
    }

    func testTheDimmedOpacityStillReadsAndIsClearlyDifferent() {
        XCTAssertGreaterThanOrEqual(style.dimmedOpacity, 0.35)
        XCTAssertLessThanOrEqual(style.dimmedOpacity, 0.5)
    }

    // MARK: Concentric rounding

    func testTheHighlightIsConcentricWithTheBand() {
        XCTAssertEqual(style.highlightCornerRadius, style.bandCornerRadius - style.highlightInset)
        XCTAssertGreaterThan(style.highlightCornerRadius, 0)
    }

    func testCornerRadiusNeverExceedsWhatTheShapeCanTake() {
        XCTAssertEqual(style.cornerRadius(thickness: 64, arcLength: 200, preferred: 14), 14)
        XCTAssertLessThan(style.cornerRadius(thickness: 20, arcLength: 200, preferred: 14), 10, "half the thickness at most")
        XCTAssertLessThan(style.cornerRadius(thickness: 64, arcLength: 12, preferred: 14), 6, "half the length at most")
        XCTAssertEqual(style.cornerRadius(thickness: 0, arcLength: 50, preferred: 14), 0)
        XCTAssertGreaterThanOrEqual(style.cornerRadius(thickness: 3, arcLength: 3, preferred: 14), 0)
    }

    // MARK: Seams

    func testASeamKeepsTheSameWidthInPointsAtAnyRadius() {
        let near = style.seamAngle(width: 1, atRadius: 100)
        let far = style.seamAngle(width: 1, atRadius: 200)
        XCTAssertEqual(near, 2 * far, accuracy: 1e-4)
        XCTAssertEqual(near * 100, 1, accuracy: 1e-3, "angle times radius is the width")
        XCTAssertEqual(style.seamAngle(width: 1, atRadius: 0), 0, "no radius, no angle, no crash")
    }

    // MARK: Where the highlight of an item goes

    private func band(count: Int, thickness: Double = 64, itemWidth: Double = 0.5, startAngle: Double = -0.5 * 2.5, inner: Double = 150) -> RingBand {
        RingBand(level: 1, innerRadius: inner, outerRadius: inner + thickness, startAngle: startAngle, itemWidth: itemWidth, count: count,
                 iconRadius: inner + thickness / 2, iconSize: 20, isCrowded: false)
    }

    func testTheHighlightSitsInsideItsItemAndInsideTheBandRim() {
        let b = band(count: 5)
        for index in 0..<5 {
            let g = style.highlightGeometry(for: b, index: index)
            XCTAssertEqual(g.innerRadius, b.innerRadius + style.highlightInset)
            XCTAssertEqual(g.outerRadius, b.outerRadius - style.highlightInset)
            XCTAssertGreaterThan(g.startAngle, b.startAngle + Double(index) * b.itemWidth - 1e-12)
            XCTAssertLessThan(g.endAngle, b.startAngle + Double(index + 1) * b.itemWidth + 1e-12)
            XCTAssertGreaterThan(g.endAngle, g.startAngle)
        }
    }

    func testNeighboursKeepAGapBetweenTheirHighlights() {
        let b = band(count: 5)
        let mid = b.innerRadius + b.outerRadius / 2
        for index in 0..<4 {
            let left = style.highlightGeometry(for: b, index: index)
            let right = style.highlightGeometry(for: b, index: index + 1)
            let gapPoints = (right.startAngle - left.endAngle) * ((left.innerRadius + left.outerRadius) / 2)
            XCTAssertEqual(gapPoints, style.itemGap, accuracy: 0.01, "\(index) \(mid)")
        }
    }

    func testTheEndsOfAnArcAreInsetFromItsRim() {
        let b = band(count: 4)
        let first = style.highlightGeometry(for: b, index: 0)
        let last = style.highlightGeometry(for: b, index: 3)
        let mid = (first.innerRadius + first.outerRadius) / 2
        XCTAssertEqual((first.startAngle - b.startAngle) * mid, style.highlightInset, accuracy: 0.01)
        XCTAssertEqual(((b.startAngle + 4 * b.itemWidth) - last.endAngle) * mid, style.highlightInset, accuracy: 0.01)
    }

    func testInAFullCircleEveryEdgeIsAnInteriorSeam() {
        let full = RingBand(level: 0, innerRadius: 30, outerRadius: 130, startAngle: -.pi / 3, itemWidth: 2 * .pi / 6, count: 6, iconRadius: 80, iconSize: 20, isCrowded: false)
        let a = style.highlightGeometry(for: full, index: 0)
        let b = style.highlightGeometry(for: full, index: 5)
        // The last item's end and the first item's start are neighbours across the wrap: the same gap as anywhere else.
        let gap = (a.startAngle + 2 * .pi - b.endAngle) * ((a.innerRadius + a.outerRadius) / 2)
        XCTAssertEqual(gap, style.itemGap, accuracy: 0.01)
    }

    func testTheHighlightCornerRadiusFitsATinyItem() {
        let tiny = band(count: 40, thickness: 30, itemWidth: 0.02)
        let g = style.highlightGeometry(for: tiny, index: 3)
        XCTAssertGreaterThanOrEqual(g.cornerRadius, 0)
        XCTAssertLessThan(g.cornerRadius, (g.outerRadius - g.innerRadius) / 2)
    }

    // MARK: Labels that must fit

    func testHorizontalRoomInACellDependsOnWhereItIs() {
        // Straight up or down the room is the cell's tangential length; at 3 or 9 o'clock it is its radial thickness.
        XCTAssertEqual(style.availableTextWidth(thickness: 64, tangential: 120, angle: 0, padding: 0), 120, accuracy: 1e-6)
        XCTAssertEqual(style.availableTextWidth(thickness: 64, tangential: 120, angle: .pi / 2, padding: 0), 64, accuracy: 1e-6)
        let diagonal = style.availableTextWidth(thickness: 64, tangential: 120, angle: .pi / 4, padding: 0)
        XCTAssertLessThan(diagonal, 120)
        XCTAssertGreaterThan(diagonal, 64)
    }

    func testPaddingIsTakenOffBothSides() {
        XCTAssertEqual(style.availableTextWidth(thickness: 64, tangential: 120, angle: 0, padding: 5), 110, accuracy: 1e-6)
    }

    func testTheRoomIsNeverNegative() {
        XCTAssertEqual(style.availableTextWidth(thickness: 4, tangential: 4, angle: 1, padding: 10), 0)
    }

    func testALabelThatFitsKeepsItsSize() {
        XCTAssertEqual(style.fittedFontSize(textWidthAtBaseSize: 30, available: 60), style.labelBaseSize)
    }

    func testALabelThatIsTooWideIsScaledToFit() {
        let size = style.fittedFontSize(textWidthAtBaseSize: 60, available: 48)
        XCTAssertEqual(size, style.labelBaseSize * 0.8, accuracy: 1e-9)
        XCTAssertGreaterThan(size, style.labelMinSize)
    }

    func testALabelNeverShrinksBelowTheMinimumAndTheRestIsLeftToTruncation() {
        XCTAssertEqual(style.fittedFontSize(textWidthAtBaseSize: 200, available: 20), style.labelMinSize)
        XCTAssertEqual(style.fittedFontSize(textWidthAtBaseSize: 10, available: 0), style.labelMinSize)
    }

    func testNonsenseMeasurementsFallBackToTheBaseSize() {
        XCTAssertEqual(style.fittedFontSize(textWidthAtBaseSize: 0, available: 50), style.labelBaseSize)
        XCTAssertEqual(style.fittedFontSize(textWidthAtBaseSize: .nan, available: 50), style.labelBaseSize)
    }

    // MARK: Appearing

    func testTheRingAppearsFromJustBelowFullSize() {
        XCTAssertGreaterThanOrEqual(style.appearScale, 0.9)
        XCTAssertLessThan(style.appearScale, 1)
        XCTAssertLessThan(style.arcAppearScale, 1)
    }
}

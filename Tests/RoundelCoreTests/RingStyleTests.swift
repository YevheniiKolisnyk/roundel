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

    // MARK: Content must stay inside its cell

    /// A typical arc cell (44 pt wide, 64 pt thick) and the root ring's cells.
    private func rootBand(count: Int) -> RingBand {
        let layout = RingLayout.make(root: (0..<count).map { .action(ActionNode(id: "n\($0)", title: "N", action: "log", params: .object([:]))) }, path: [])
        return layout.bands[0]
    }

    private func arcBand(count: Int) -> RingBand {
        let group = Node.group(GroupNode(id: "g", title: "G", icon: nil, children: (0..<count).map { .action(ActionNode(id: "c\($0)", title: "C", action: "log", params: .object([:]))) }))
        let layout = RingLayout.make(root: [group, .action(ActionNode(id: "x", title: "X", action: "log", params: .object([:])))], path: ["g"])
        return layout.bands[1]
    }

    func testTheRoomIsAHalfBoxAroundTheIconPointAndLeavesTheCellPadding() {
        let b = arcBand(count: 5)
        let room = style.cellRoom(for: b, hasChevron: false)
        XCTAssertLessThan(room.halfRadial, (b.outerRadius - b.innerRadius) / 2 - style.contentInset + 1e-9)
        XCTAssertLessThan(room.halfTangential, b.itemWidth * b.iconRadius / 2 - style.contentInset + 1e-9)
        XCTAssertGreaterThan(room.halfRadial, 0)
        XCTAssertGreaterThan(room.halfTangential, 0)
    }

    func testAGroupCellReservesTheChevronsSlotSoContentCannotCollideWithIt() {
        let b = arcBand(count: 5)
        let plain = style.cellRoom(for: b, hasChevron: false)
        let group = style.cellRoom(for: b, hasChevron: true)
        XCTAssertLessThan(group.halfRadial, plain.halfRadial)
        XCTAssertEqual(group.halfTangential, plain.halfTangential, "only the radial extent is taken")
        // The content's outer edge stays clear of the chevron's inner edge by at least the label padding.
        let chevronInnerEdge = b.outerRadius - style.chevronInset - style.chevronSize / 2
        XCTAssertLessThanOrEqual(b.iconRadius + group.halfRadial, chevronInnerEdge - style.labelPadding + 1e-9)
    }

    func testTheRoomIsNeverNegativeEvenForATinyCell() {
        let tiny = RingBand(level: 1, innerRadius: 100, outerRadius: 106, startAngle: 0, itemWidth: 0.02, count: 3, iconRadius: 103, iconSize: 12, isCrowded: true)
        let room = style.cellRoom(for: tiny, hasChevron: true)
        XCTAssertEqual(room.halfRadial, 0)
        XCTAssertEqual(room.halfTangential, 0)
    }

    func testABoxFitsWhenItsRotatedCornersStayInsideTheCell() {
        let room = RingStyle.CellRoom(halfRadial: 20, halfTangential: 15)
        // Straight up the cell's width is tangential and its height radial; at 3 o'clock they swap.
        XCTAssertTrue(style.fits(width: 30, height: 40, angle: 0, in: room))
        XCTAssertFalse(style.fits(width: 30.5, height: 40, angle: 0, in: room))
        XCTAssertFalse(style.fits(width: 30, height: 40.5, angle: 0, in: room))
        XCTAssertTrue(style.fits(width: 40, height: 30, angle: .pi / 2, in: room))
        XCTAssertFalse(style.fits(width: 41, height: 30, angle: .pi / 2, in: room))
        // Diagonal: the corner of an upright box sticks out of a rotated cell sooner than its sides would suggest.
        XCTAssertFalse(style.fits(width: 30, height: 40, angle: .pi / 4, in: room))
    }

    func testTheWidestBoxOfAGivenHeight() {
        let room = RingStyle.CellRoom(halfRadial: 20, halfTangential: 15)
        XCTAssertEqual(style.maxWidth(forHeight: 14, angle: 0, in: room), 30, accuracy: 1e-9)
        XCTAssertEqual(style.maxWidth(forHeight: 14, angle: .pi / 2, in: room), 40, accuracy: 1e-9)
        XCTAssertEqual(style.maxWidth(forHeight: 50, angle: 0, in: room), 0, "too tall for the cell at all")
        for angle in stride(from: 0.0, to: 2 * Double.pi, by: 0.17) {
            let w = style.maxWidth(forHeight: 14, angle: angle, in: room)
            XCTAssertTrue(style.fits(width: w, height: 14, angle: angle, in: room), "\(angle)")
            XCTAssertFalse(style.fits(width: w + 0.5, height: 14, angle: angle, in: room), "\(angle) is the widest")
        }
    }

    func testFitScaleIsTheLargestScaleThatStillFits() {
        let room = RingStyle.CellRoom(halfRadial: 20, halfTangential: 15)
        for angle in stride(from: 0.0, to: 2 * Double.pi, by: 0.23) {
            let k = style.fitScale(width: 60, height: 20, angle: angle, in: room, scale: 1.1)
            XCTAssertTrue(style.fits(width: 60 * k * 1.1, height: 20 * k * 1.1, angle: angle, in: room), "\(angle)")
            XCTAssertFalse(style.fits(width: 60 * k * 1.1 * 1.01, height: 20 * k * 1.1 * 1.01, angle: angle, in: room), "\(angle): not smaller than needed")
        }
        XCTAssertEqual(style.fitScale(width: 0, height: 0, angle: 0, in: room, scale: 1), 1, "an empty box needs no shrinking")
    }

    func testALabelThatFitsKeepsTheBaseSize() {
        let room = RingStyle.CellRoom(halfRadial: 25, halfTangential: 30)
        let fit = style.labelFit(widthAtBaseSize: 20, heightAtBaseSize: 14, angle: 0, in: room, scale: 1)
        XCTAssertEqual(fit?.fontSize, style.labelBaseSize)
        XCTAssertEqual(fit?.maxWidth ?? 0, 20, accuracy: 1e-9)
    }

    func testALabelThatIsTooWideIsScaledDownToFit() throws {
        let room = RingStyle.CellRoom(halfRadial: 25, halfTangential: 15)
        let fit = try XCTUnwrap(style.labelFit(widthAtBaseSize: 36, heightAtBaseSize: 14, angle: 0, in: room, scale: 1))
        XCTAssertEqual(fit.fontSize, style.labelBaseSize * 30 / 36, accuracy: 1e-9)
        XCTAssertGreaterThanOrEqual(fit.fontSize, style.labelMinSize)
    }

    func testALabelNeverShrinksBelowTheMinimumAndTheRestIsTruncatedInsideTheBox() throws {
        let room = RingStyle.CellRoom(halfRadial: 25, halfTangential: 15)
        let fit = try XCTUnwrap(style.labelFit(widthAtBaseSize: 300, heightAtBaseSize: 14, angle: 0, in: room, scale: 1))
        XCTAssertEqual(fit.fontSize, style.labelMinSize)
        XCTAssertEqual(fit.maxWidth, 30, accuracy: 1e-9, "truncated to what the cell can take")
    }

    func testNoLabelIsDrawnWhenThereIsNoRoomForEvenOneLine() {
        let room = RingStyle.CellRoom(halfRadial: 3, halfTangential: 3)
        XCTAssertNil(style.labelFit(widthAtBaseSize: 30, heightAtBaseSize: 14, angle: 0, in: room, scale: 1))
        XCTAssertNil(style.labelFit(widthAtBaseSize: 30, heightAtBaseSize: 14, angle: 0, in: .init(halfRadial: 0, halfTangential: 0), scale: 1))
    }

    func testNonsenseMeasurementsAreSafe() {
        let room = RingStyle.CellRoom(halfRadial: 25, halfTangential: 30)
        XCTAssertNil(style.labelFit(widthAtBaseSize: .nan, heightAtBaseSize: 14, angle: 0, in: room, scale: 1))
        XCTAssertNil(style.labelFit(widthAtBaseSize: 0, heightAtBaseSize: 14, angle: 0, in: room, scale: 1))
        XCTAssertNil(style.labelFit(widthAtBaseSize: 30, heightAtBaseSize: -1, angle: 0, in: room, scale: 1))
    }

    /// The property that matters: whatever the label, the angle, the band or the hover scale, what gets drawn (the text,
    /// truncated to `maxWidth`, at the fitted size, scaled up for hover) is inside the cell's safe box.
    func testFittedLabelsNeverLeaveTheSafeBoxInAnyCellAtAnyAngleAndScale() {
        // Text widths at the base size for labels from 1 to 24 characters (about 7 pt per character, 15 pt tall).
        let labelWidths = [1, 3, 4, 5, 8, 14, 24].map { Double($0) * 7 }
        var bands = [rootBand(count: 3), rootBand(count: 6), rootBand(count: 12), rootBand(count: 20)]
        for count in [1, 2, 3, 5, 8, 12] { bands.append(arcBand(count: count)) }
        for b in bands {
            for chevron in [false, true] {
                let room = style.cellRoom(for: b, hasChevron: chevron)
                for index in 0..<b.count {
                    let angle = b.centerAngle(ofItem: index)
                    for width in labelWidths {
                        for scale in [1.0, style.hoverIconScale] {
                            guard let fit = style.labelFit(widthAtBaseSize: width, heightAtBaseSize: 15, angle: angle, in: room, scale: scale) else { continue }
                            XCTAssertLessThanOrEqual(fit.fontSize, style.labelBaseSize + 1e-9)
                            XCTAssertGreaterThanOrEqual(fit.fontSize, style.labelMinSize - 1e-9)
                            let drawnHeight = 15 * fit.fontSize / style.labelBaseSize * scale
                            XCTAssertTrue(style.fits(width: fit.maxWidth * scale, height: drawnHeight, angle: angle, in: room),
                                          "level \(b.level) count \(b.count) item \(index) chevron \(chevron) width \(width) scale \(scale)")
                            XCTAssertLessThanOrEqual(fit.maxWidth, width * fit.fontSize / style.labelBaseSize + 1e-9, "never wider than the text itself")
                        }
                    }
                }
            }
        }
    }

    func testShortFormatNamesStayReadableInEveryCellOfEveryRealisticBand() {
        // 3 to 4 letters ("PNG", "WebP"): about 28 pt wide at the base size. They must never be hidden or squeezed to nothing
        // in a leaf cell of a band with the usual number of items.
        for count in 3...12 {
            let b = arcBand(count: count)
            let room = style.cellRoom(for: b, hasChevron: false)
            for index in 0..<b.count {
                let fit = style.labelFit(widthAtBaseSize: 28, heightAtBaseSize: 15, angle: b.centerAngle(ofItem: index), in: room, scale: style.hoverIconScale)
                XCTAssertNotNil(fit, "count \(count) item \(index)")
                XCTAssertGreaterThanOrEqual(fit?.fontSize ?? 0, style.labelMinSize)
            }
        }
    }

    func testIconsShrinkToTheirSafeBoxToo() {
        let b = arcBand(count: 6)
        for chevron in [false, true] {
            let room = style.cellRoom(for: b, hasChevron: chevron)
            for index in 0..<b.count {
                let angle = b.centerAngle(ofItem: index)
                let k = min(1, style.fitScale(width: b.iconSize, height: b.iconSize, angle: angle, in: room, scale: style.hoverIconScale))
                let drawn = b.iconSize * k * style.hoverIconScale
                XCTAssertTrue(style.fits(width: drawn, height: drawn, angle: angle, in: room), "item \(index) chevron \(chevron)")
            }
        }
    }

    // MARK: The label in the middle

    private func insideCircle(width: Double, height: Double, radius: Double) -> Bool {
        (width / 2) * (width / 2) + (height / 2) * (height / 2) <= radius * radius + 1e-9
    }

    func testAShortCenterLabelKeepsItsSize() {
        let fit = style.centerLabelFit(widthAtBaseSize: 30, heightAtBaseSize: 13, radius: 30)
        XCTAssertEqual(fit?.fontSize, style.centerLabelBaseSize)
        XCTAssertEqual(fit?.maxWidth ?? 0, 30, accuracy: 1e-9)
    }

    func testALongerCenterLabelIsScaledDownUntilItsBoxFitsTheCircle() throws {
        let fit = try XCTUnwrap(style.centerLabelFit(widthAtBaseSize: 52, heightAtBaseSize: 13, radius: 30))
        XCTAssertLessThan(fit.fontSize, style.centerLabelBaseSize)
        XCTAssertGreaterThanOrEqual(fit.fontSize, style.labelMinSize)
        let k = fit.fontSize / style.centerLabelBaseSize
        XCTAssertTrue(insideCircle(width: 52 * k, height: 13 * k, radius: 30 - style.centerLabelPadding))
    }

    func testAVeryLongCenterLabelIsTruncatedAtTheMinimumSizeInsideTheCircle() throws {
        let fit = try XCTUnwrap(style.centerLabelFit(widthAtBaseSize: 400, heightAtBaseSize: 13, radius: 30))
        XCTAssertEqual(fit.fontSize, style.labelMinSize)
        let h = 13 * style.labelMinSize / style.centerLabelBaseSize
        XCTAssertTrue(insideCircle(width: fit.maxWidth, height: h, radius: 30 - style.centerLabelPadding))
        XCTAssertGreaterThan(fit.maxWidth, 30, "still a useful amount of text")
    }

    func testNoCenterLabelWhenTheCircleIsTooSmallOrTheInputIsNonsense() {
        XCTAssertNil(style.centerLabelFit(widthAtBaseSize: 30, heightAtBaseSize: 13, radius: 5))
        XCTAssertNil(style.centerLabelFit(widthAtBaseSize: 0, heightAtBaseSize: 13, radius: 30))
        XCTAssertNil(style.centerLabelFit(widthAtBaseSize: .nan, heightAtBaseSize: 13, radius: 30))
        XCTAssertNil(style.centerLabelFit(widthAtBaseSize: 30, heightAtBaseSize: 13, radius: -Double.infinity))
    }

    func testACenterLabelNeverLeavesTheCircleWhateverItsLengthOrTheCirclesSize() {
        for radius in [16.0, 22, 30, 40, 60] {
            for width in stride(from: 4.0, through: 600, by: 17) {
                for height in [10.0, 13, 16] {
                    guard let fit = style.centerLabelFit(widthAtBaseSize: width, heightAtBaseSize: height, radius: radius) else { continue }
                    let k = fit.fontSize / style.centerLabelBaseSize
                    let drawnWidth = min(width * k, fit.maxWidth)
                    XCTAssertTrue(insideCircle(width: drawnWidth, height: height * k, radius: radius - style.centerLabelPadding), "radius \(radius) width \(width) height \(height)")
                    XCTAssertLessThanOrEqual(fit.fontSize, style.centerLabelBaseSize + 1e-9)
                    XCTAssertGreaterThanOrEqual(fit.fontSize, style.labelMinSize - 1e-9)
                }
            }
        }
    }

    // MARK: Appearing

    func testTheRingAppearsFromJustBelowFullSize() {
        XCTAssertGreaterThanOrEqual(style.appearScale, 0.95)
        XCTAssertLessThan(style.appearScale, 1)
        XCTAssertGreaterThanOrEqual(style.arcAppearScale, 0.95)
        XCTAssertLessThan(style.arcAppearScale, 1)
    }
}

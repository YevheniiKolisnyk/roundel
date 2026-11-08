import XCTest
import SwiftUI
import RoundelCore
@testable import Roundel

/// Where things end up on the panel, and that content stays inside its cell.
@MainActor
final class RingLayoutFitTests: XCTestCase {
    private let style = RingStyle.standard

    func testEveryBandsRoundedOutlineStaysClearOfThePanelEdge() {
        // Glass draws a little beyond its shape (rim, refraction): the panel must leave room, including for an arc that
        // has been slid along its band to stay on screen.
        let screen = CGRect(x: 0, y: 0, width: 1440, height: 900)
        let spots = [CGPoint(x: 720, y: 450), CGPoint(x: 30, y: 450), CGPoint(x: 1410, y: 880), CGPoint(x: 700, y: 20)]
        for center in spots {
            for path in [[], ["launch"], ["launch", "launch.links"], ["files", "files.convert"]] {
                let placement = ArcPlacement.Context(ringCenter: center, bounds: screen)
                let model = RingFixture.model(path: path, placement: placement)
                let rect = CGRect(x: 0, y: 0, width: model.panelSide, height: model.panelSide)
                for bandModel in model.bands {
                    let outline = RingBandShape.of(bandModel.band, style: style).path(in: rect).boundingRect
                    XCTAssertGreaterThanOrEqual(outline.minX, 8, "\(center) \(path)")
                    XCTAssertGreaterThanOrEqual(outline.minY, 8, "\(center) \(path)")
                    XCTAssertLessThanOrEqual(outline.maxX, rect.maxX - 8, "\(center) \(path)")
                    XCTAssertLessThanOrEqual(outline.maxY, rect.maxY - 8, "\(center) \(path)")
                }
            }
        }
    }

    func testTheEndCapsOfAnArcAreRoundedAtBothEnds() {
        let model = RingFixture.model(path: ["launch"])
        let arc = model.bands[1].band
        let rect = CGRect(x: 0, y: 0, width: model.panelSide, height: model.panelSide)
        let path = RingBandShape.of(arc, style: style).path(in: rect)
        let mid = model.panelSide / 2
        let start = arc.startAngle, end = arc.startAngle + arc.itemWidth * Double(arc.count)
        for angle in [start, end] {
            let inwards = angle == start ? 0.5 : -0.5
            // The outer corner of a sharp sector is not part of the rounded one, but a few points in it is.
            func point(_ r: Double, _ a: Double) -> CGPoint { CGPoint(x: mid + r * sin(a), y: mid - r * cos(a)) }
            XCTAssertFalse(path.contains(point(arc.outerRadius - 0.5, angle + inwards / arc.outerRadius)), "outer corner at \(angle)")
            XCTAssertFalse(path.contains(point(arc.innerRadius + 0.5, angle + inwards / arc.innerRadius)), "inner corner at \(angle)")
            XCTAssertTrue(path.contains(point((arc.innerRadius + arc.outerRadius) / 2, angle + (angle == start ? 6 : -6) / arc.iconRadius)), "the cap itself is solid")
        }
    }

    // MARK: Content inside its cell

    private let labels = ["PNG", "WebP", "AVIF", "HEIC", "JPEG", "TIFF", "BMP", "GIF", "Абв", "Aa", "Привіт", "Вимкнути екран",
                          "Конвертувати у формат", "A rather long English label", "Wi", "Дуже довга українська назва пункту меню"]

    private func bands() -> [RingBand] {
        var result: [RingBand] = []
        for count in [3, 4, 6, 8, 12, 16] {
            let nodes = (0..<count).map { Node.action(ActionNode(id: "n\($0)", title: "N", action: "log", params: .object([:]))) }
            result.append(RingLayout.make(root: nodes, path: []).bands[0])
        }
        for count in [2, 3, 5, 8, 12] {
            let group = Node.group(GroupNode(id: "g", title: "G", icon: nil, children: (0..<count).map { .action(ActionNode(id: "c\($0)", title: "C", action: "log", params: .object([:]))) }))
            result.append(RingLayout.make(root: [group, .action(ActionNode(id: "x", title: "X", action: "log", params: .object([:])))], path: ["g"]).bands[1])
        }
        return result
    }

    func testEveryLabelStaysInsideItsCellAtEveryAngleAtDefaultAndHoverScale() {
        for band in bands() {
            for hasChevron in [false, true] {
                let room = style.cellRoom(for: band, hasChevron: hasChevron)
                for index in 0..<band.count {
                    let angle = band.centerAngle(ofItem: index)
                    for text in labels {
                        for scale in [1.0, style.hoverIconScale] {
                            guard let fit = ContentFit.label(text, band: band, index: index, hasChevron: hasChevron, scale: scale, style: style) else { continue }
                            let measured = ContentFit.measure(text, size: fit.fontSize)
                            let drawnWidth = min(measured.width, fit.maxWidth)
                            XCTAssertTrue(style.fits(width: drawnWidth * scale, height: measured.height * scale, angle: angle, in: room),
                                          "'\(text)' level \(band.level) count \(band.count) item \(index) chevron \(hasChevron) scale \(scale) size \(fit.fontSize)")
                        }
                    }
                }
            }
        }
    }

    func testShortFormatNamesAreAlwaysShownInLeafCellsOfAnyArc() {
        for band in bands() where band.level == 1 && band.count >= 3 {
            for index in 0..<band.count {
                for text in ["PNG", "WebP", "AVIF", "Абв", "HEIC"] {
                    XCTAssertNotNil(ContentFit.label(text, band: band, index: index, hasChevron: false, scale: style.hoverIconScale, style: style), "'\(text)' count \(band.count) item \(index)")
                }
            }
        }
    }

    func testIconsShrinkToTheirSafeBoxAndNeverGrow() {
        for band in bands() {
            for hasChevron in [false, true] {
                let room = style.cellRoom(for: band, hasChevron: hasChevron)
                for index in 0..<band.count {
                    let size = ContentFit.iconSize(band: band, index: index, hasChevron: hasChevron, scale: style.hoverIconScale, style: style)
                    XCTAssertLessThanOrEqual(size, band.iconSize + 1e-9)
                    XCTAssertGreaterThan(size, 0)
                    let drawn = size * style.hoverIconScale
                    XCTAssertTrue(style.fits(width: drawn, height: drawn, angle: band.centerAngle(ofItem: index), in: room), "level \(band.level) count \(band.count) item \(index) chevron \(hasChevron)")
                }
            }
        }
    }

    func testAGroupCellsChevronNeverOverlapsItsContentBox() {
        for band in bands() {
            for index in 0..<band.count {
                let angle = band.centerAngle(ofItem: index)
                let room = style.cellRoom(for: band, hasChevron: true)
                // Radial extent of the content (a box fitted to the room, at the hover scale) against the chevron's slot.
                let size = ContentFit.iconSize(band: band, index: index, hasChevron: true, scale: style.hoverIconScale, style: style) * style.hoverIconScale
                let radialReach = (size * abs(sin(angle)) + size * abs(cos(angle))) / 2
                let contentOuter = band.iconRadius + radialReach
                let chevronInner = band.outerRadius - style.chevronInset - style.chevronSize / 2
                XCTAssertLessThanOrEqual(contentOuter, chevronInner - style.labelPadding + 1e-9, "level \(band.level) item \(index) \(room)")
            }
        }
    }
}

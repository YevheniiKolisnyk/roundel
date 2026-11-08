import XCTest
@testable import RoundelCore

/// The design language lives in numbers in one place; these keep it coherent.
final class DesignMetricsTests: XCTestCase {
    private let m = DesignMetrics.standard

    func testSpacingIsOnAFourPointGridAndGrows() {
        let steps = [m.space1, m.space2, m.space3, m.space4, m.space5]
        for step in steps { XCTAssertEqual(step.truncatingRemainder(dividingBy: 4), 0, "\(step)") }
        XCTAssertEqual(steps, steps.sorted())
        XCTAssertEqual(Set(steps).count, steps.count, "every step is different")
    }

    func testTheTypeScaleHasClearSteps() {
        XCTAssertGreaterThan(m.titleSize, m.bodySize)
        XCTAssertGreaterThan(m.bodySize, m.captionSize)
        XCTAssertGreaterThanOrEqual(m.captionSize, 10, "nothing smaller than the system's smallest")
    }

    func testConcentricRadiiShrinkByTheInset() {
        XCTAssertEqual(m.concentricRadius(outer: 18, inset: 12), 6)
        XCTAssertEqual(m.concentricRadius(outer: 18, inset: 0), 18)
        XCTAssertEqual(m.concentricRadius(outer: 6, inset: 12), 0, "never negative")
    }

    func testTheToastCardAndItsContentAreConcentric() {
        XCTAssertEqual(m.toastIconRadius, m.concentricRadius(outer: m.toastCornerRadius, inset: m.toastPadding))
        XCTAssertLessThan(m.toastIconRadius, m.toastCornerRadius)
    }

    func testToastMetricsMatchTheAgreedDesign() {
        XCTAssertEqual(m.toastWidth, 360)
        XCTAssertEqual(m.toastMargin, 12)
        XCTAssertEqual(m.toastMaxVisible, 3)
        XCTAssertEqual(m.toastPadding, m.space3)
    }

    func testTheShadowAboveACardFitsInsideTheMargin() {
        // The toast window starts at the bottom of the menu bar; the shadow above the first card must not need more room
        // than the margin, or the window would reach into the menu bar.
        XCTAssertLessThanOrEqual(m.shadowRadius - m.shadowYOffset, m.toastMargin)
    }

    func testBordersGetThickerWithIncreasedContrast() {
        XCTAssertGreaterThan(m.borderWidthIncreasedContrast, m.borderWidth)
    }

    // MARK: Motion

    func testMotionIsShortAndSubtle() {
        for case .spring(let response, let damping) in [m.appearMotion, m.selectionMotion] {
            XCTAssertLessThanOrEqual(response, 0.4)
            XCTAssertGreaterThanOrEqual(damping, 0.75, "hardly any overshoot")
            XCTAssertLessThanOrEqual(damping, 1)
        }
        if case .fade(let duration) = m.reducedMotionFade { XCTAssertLessThanOrEqual(duration, 0.2) } else { XCTFail("reduced motion is a fade") }
    }

    func testReduceMotionTurnsASpringIntoAShortFade() {
        XCTAssertEqual(m.resolve(m.appearMotion, reduceMotion: false), m.appearMotion)
        XCTAssertEqual(m.resolve(m.appearMotion, reduceMotion: true), m.reducedMotionFade)
        XCTAssertEqual(m.resolve(m.selectionMotion, reduceMotion: true), m.reducedMotionFade)
    }
}

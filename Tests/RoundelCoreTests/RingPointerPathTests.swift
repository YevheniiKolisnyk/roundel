import XCTest
@testable import RoundelCore

/// Layout + state machine together, driven by simulated pointer movement at 60 Hz.
/// These are the situations that are easy to get wrong with hand-picked hits: diagonals and deep chains.
final class RingPointerPathTests: XCTestCase {
    private let metrics = RingMetrics.standard

    private func action(_ id: String) -> Node { .action(ActionNode(id: id, title: id, action: "log")) }
    private func group(_ id: String, _ children: [Node]) -> Node { .group(GroupNode(id: id, title: id, children: children)) }

    // root (6 items): 0:a 1:g[ c0 c1 c2 c3 c4 ] 2:b 3:c 4:d 5:e      g sits at 60°
    private var ring: [Node] {
        [action("a"), group("g", (0..<5).map { action("c\($0)") }), action("b"), action("c"), action("d"), action("e")]
    }

    /// Drives the state machine like the app does.
    private struct Driver {
        var nav = RingInteraction()
        var layout: RingLayout
        var time = 0.0
        let root: [Node]
        var position = CGPoint.zero
        var selected: String?

        let metrics: RingMetrics

        init(root: [Node], mode: OpenMode = .holdRelease, metrics: RingMetrics = .standard) {
            self.root = root
            self.metrics = metrics
            nav = RingInteraction(metrics: metrics)
            var config = RoundelConfig(ring: root)
            config.settings = ConfigSettings(openMode: mode)
            _ = nav.hotkeyDown(config: config)
            layout = RingLayout.make(root: root, path: [], metrics: metrics)
        }

        mutating func step() {
            for _ in 0..<4 {
                let hit = layout.hit(dx: Double(position.x), dy: Double(position.y))
                let outcome = nav.update(hit: hit, now: time)
                guard outcome == .layoutChanged else { break }
                layout = RingLayout.make(root: root, path: nav.path, metrics: metrics)
            }
        }

        /// Straight line to `target` over `duration` seconds.
        mutating func move(to target: CGPoint, over duration: Double) {
            let start = position
            let steps = max(1, Int(duration * 60))
            for i in 1...steps {
                let t = Double(i) / Double(steps)
                position = CGPoint(x: start.x + (target.x - start.x) * t, y: start.y + (target.y - start.y) * t)
                time += 1.0 / 60
                step()
            }
        }

        mutating func rest(_ duration: Double) {
            for _ in 0..<max(1, Int(duration * 60)) { time += 1.0 / 60; step() }
        }
    }

    private func point(_ degrees: Double, _ radius: Double) -> CGPoint {
        let r = degrees * .pi / 180
        return CGPoint(x: radius * sin(r), y: radius * cos(r))
    }

    private func midRadius(_ band: RingBand) -> Double { (band.innerRadius + band.outerRadius) / 2 }

    private func itemPoint(_ band: RingBand, _ item: Int) -> CGPoint {
        point(band.centerAngle(ofItem: item) * 180 / .pi, midRadius(band))
    }

    /// Opens "g" by resting on its section.
    private func driverWithArcOpen(mode: OpenMode = .holdRelease, metrics: RingMetrics = .standard) -> Driver {
        var driver = Driver(root: ring, mode: mode, metrics: metrics)
        driver.position = itemPoint(driver.layout.bands[0], 1)
        driver.rest(0.3)
        XCTAssertEqual(driver.nav.path, ["g"], "precondition: the arc is open")
        return driver
    }

    // MARK: Diagonals

    func testStraightDiagonalFromTheParentToTheFarEndsOfTheArcKeepsTheArcOpen() {
        for farItem in [0, 4] {
            var driver = driverWithArcOpen()
            let target = itemPoint(driver.layout.bands[1], farItem)
            driver.move(to: target, over: 0.25)
            driver.rest(0.05)
            XCTAssertEqual(driver.nav.path, ["g"], "far item \(farItem): the arc must survive the diagonal")
            XCTAssertEqual(driver.nav.hovered, RingItemRef(level: 1, index: farItem))
            XCTAssertEqual(driver.nav.hotkeyUp(), .select("c\(farItem)"))
        }
    }

    func testSlowDiagonalsSurviveCrossingTheGap() {
        // Down to about 80 pt/s the pointer is in the gap for less than the hysteresis.
        for duration in [0.5, 1.0, 1.5] {
            var driver = driverWithArcOpen()
            driver.move(to: itemPoint(driver.layout.bands[1], 4), over: duration)
            driver.rest(0.05)
            XCTAssertEqual(driver.nav.path, ["g"], "\(duration) s diagonal")
        }
    }

    func testTheHysteresisIsWhatKeepsASlowDiagonalAlive() {
        var none = RingMetrics.standard
        none.closeHysteresis = 0
        var driver = driverWithArcOpen(metrics: none)
        driver.move(to: itemPoint(driver.layout.bands[1], 4), over: 1.0)
        XCTAssertEqual(driver.nav.path, [], "without the hysteresis the same move collapses the arc")
    }

    func testAnExtremelySlowCrawlThroughTheGapDoesCollapseTheArc() {
        // About 40 pt/s: the 8 pt gap takes 0.2 s, longer than the 0.15 s hysteresis. A known limit, tune `closeHysteresis`.
        var driver = driverWithArcOpen()
        driver.move(to: itemPoint(driver.layout.bands[1], 4), over: 2.5)
        XCTAssertEqual(driver.nav.path, [])
    }

    func testFastFlickAlongTheDiagonalAlsoWorks() {
        var driver = driverWithArcOpen()
        driver.move(to: itemPoint(driver.layout.bands[1], 4), over: 0.08)
        driver.rest(0.02)
        XCTAssertEqual(driver.nav.path, ["g"])
        XCTAssertEqual(driver.nav.hotkeyUp(), .select("c4"))
    }

    func testStraightRadialMoveToTheMiddleChild() {
        var driver = driverWithArcOpen()
        driver.move(to: itemPoint(driver.layout.bands[1], 2), over: 0.2)
        driver.rest(0.05)
        XCTAssertEqual(driver.nav.hotkeyUp(), .select("c2"))
    }

    // MARK: Leaving and switching

    func testMovingBackToTheCenterAndWaitingClosesTheArc() {
        var driver = driverWithArcOpen()
        driver.move(to: .zero, over: 0.2)
        driver.rest(0.3)
        XCTAssertEqual(driver.nav.path, [])
        XCTAssertEqual(driver.nav.hotkeyUp(), .dismiss)
    }

    func testSlidingAlongTheRootRingToAnotherSectionSwitchesOrClosesAfterTheDelay() {
        var driver = driverWithArcOpen()
        driver.move(to: itemPoint(driver.layout.bands[0], 2), over: 0.15)   // next section clockwise: a leaf
        driver.rest(0.3)
        XCTAssertEqual(driver.nav.path, [])
    }

    func testSlowlyTracingTheRootRingPastAGroupDoesNotLeaveArcsBehind() {
        var driver = Driver(root: ring)
        let start = point(0, 77), end = point(180, 77)
        driver.position = start
        driver.rest(0.05)
        // Around the clockwise side, through the group's section, at a gentle pace (the arc may open on the way).
        for degrees in stride(from: 0.0, through: 180, by: 6) { driver.move(to: point(degrees, 77), over: 0.04) }
        driver.rest(0.4)
        XCTAssertEqual(driver.nav.path, [], "ended on a leaf, so nothing stays open")
        _ = end
    }

    // MARK: Deep chains

    private var deepRing: [Node] {
        [action("a"), group("g1", [action("c0"), group("g2", [action("d0"), group("g3", [action("e0"), action("e1"), action("e2")]), action("d2")]), action("c2")]),
         action("b"), action("c")]
    }

    func testWalkingOutwardThroughThreeLevelsAndSelectingALeaf() {
        var driver = Driver(root: deepRing)
        driver.position = point(90, 77)   // root has 4 items: g1 is item 1, at 90°
        for level in 1...3 {
            let parentBand = driver.layout.bands[level - 1]
            let parentItem = level == 1 ? 1 : 1
            driver.move(to: itemPoint(parentBand, parentItem), over: 0.15)
            driver.rest(0.25)
            XCTAssertEqual(driver.nav.path.count, level, "level \(level) opened")
        }
        let leafBand = driver.layout.bands[3]
        driver.move(to: itemPoint(leafBand, 2), over: 0.2)
        driver.rest(0.05)
        XCTAssertEqual(driver.nav.path, ["g1", "g2", "g3"])
        XCTAssertEqual(driver.nav.hotkeyUp(), .select("e2"))
    }

    func testWalkingBackInwardKeepsTheChainWhileOnItAndClosesWhenLeaving() {
        var driver = Driver(root: deepRing)
        driver.position = point(90, 77)
        for level in 1...2 {
            driver.move(to: itemPoint(driver.layout.bands[level - 1], 1), over: 0.15)
            driver.rest(0.25)
        }
        XCTAssertEqual(driver.nav.path, ["g1", "g2"])
        driver.move(to: point(90, 77), over: 0.2)   // straight back to the root section of g1
        driver.rest(0.5)
        XCTAssertEqual(driver.nav.path, ["g1", "g2"], "still on the chain")
        driver.move(to: .zero, over: 0.1)
        driver.rest(0.3)
        XCTAssertEqual(driver.nav.path, [], "left everything for longer than the hysteresis")
    }

    // MARK: Click mode on the same geometry

    func testClickModeClickingAChildAfterHoverOpenedTheArc() {
        var driver = driverWithArcOpen(mode: .clickRequired)
        driver.move(to: itemPoint(driver.layout.bands[1], 3), over: 0.2)
        let hit = driver.layout.hit(dx: Double(driver.position.x), dy: Double(driver.position.y))
        XCTAssertEqual(hit, .item(level: 1, index: 3))
        XCTAssertEqual(driver.nav.click(hit), .select("c3"))
    }
}

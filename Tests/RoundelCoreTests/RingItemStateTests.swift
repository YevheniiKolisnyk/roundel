import XCTest
@testable import RoundelCore

final class RingItemStateTests: XCTestCase {
    private func action(_ id: String, icon: Icon? = nil, action: String = "x") -> Node {
        .action(ActionNode(id: id, title: id, icon: icon, action: action))
    }

    func testActiveStateComesFromTheProvider() {
        let items = RingItem.items(
            for: [action("on", action: "t.on"), action("off", action: "t.off"), action("none", action: "t.none")],
            isActive: { node in ["t.on": true, "t.off": false][node.action] }
        )
        XCTAssertEqual(items.map(\.isActive), [true, false, nil])
    }

    func testGroupsHaveNoActiveState() {
        let group = Node.group(GroupNode(id: "g", title: "G", children: [action("c")]))
        XCTAssertNil(RingItem.items(for: [group], isActive: { _ in true })[0].isActive)
    }

    func testDefaultIconFillsInOnlyWhenTheNodeHasNone() {
        let items = RingItem.items(
            for: [action("plain"), action("custom", icon: .emoji("🚀"))],
            defaultIcon: { _ in .symbol("bolt.fill") }
        )
        XCTAssertEqual(items[0].icon, .symbol("bolt.fill"))
        XCTAssertEqual(items[1].icon, .emoji("🚀"))
    }

    func testUnknownActionWithoutIconKeepsNilSoTheFirstLetterShows() {
        let items = RingItem.items(for: [action("ghost", action: "ghost")], isAvailable: { _ in false }, defaultIcon: { _ in nil })
        XCTAssertNil(items[0].icon)
        XCTAssertTrue(items[0].isDimmed)
    }

    func testDefaultsKeepOldCallsWorking() {
        let items = RingItem.items(for: [action("a")])
        XCTAssertNil(items[0].isActive)
        XCTAssertFalse(items[0].isDimmed)
        XCTAssertNil(items[0].icon)
    }
}

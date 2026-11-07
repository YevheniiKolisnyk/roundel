import XCTest
@testable import RoundelCore

@MainActor
final class ActionRegistryTests: XCTestCase {
    private var rules: ParamRules { ParamRules(specs: [.string("url", required: true)]) }

    private func registry(_ actions: [any Action] = []) -> ActionRegistry {
        ActionRegistry(actions.isEmpty ? [StubAction(id: "known", paramRules: rules)] : actions)
    }

    private func config(_ nodes: [Node]) -> RoundelConfig { RoundelConfig(ring: nodes) }

    // MARK: Lookup

    func testLookupById() {
        let registry = registry([StubAction(id: "a"), StubAction(id: "b")])
        XCTAssertEqual(registry.action(for: "a")?.id, "a")
        XCTAssertEqual(registry.action(for: "b")?.id, "b")
        XCTAssertNil(registry.action(for: "c"))
        XCTAssertEqual(registry.ids, ["a", "b"], "registration order is kept")
    }

    func testDuplicateIdKeepsFirstAndIsReported() {
        let registry = registry([StubAction(id: "a", title: "First"), StubAction(id: "a", title: "Second")])
        XCTAssertEqual(registry.action(for: "a")?.title, "First")
        XCTAssertEqual(registry.duplicateIDs, ["a"])
        XCTAssertEqual(registry.ids, ["a"])
    }

    // MARK: Availability (feeds the dimmed state)

    func testAvailability() {
        let registry = registry()
        XCTAssertTrue(registry.isAvailable(node("x", action: "known")))
        XCTAssertFalse(registry.isAvailable(node("x", action: "nope")))
    }

    func testDefaultIconComesFromTheAction() {
        let registry = registry([StubAction(id: "a", defaultIcon: .symbol("bolt"))])
        XCTAssertEqual(registry.defaultIcon(for: node("x", action: "a")), .symbol("bolt"))
        XCTAssertNil(registry.defaultIcon(for: node("x", action: "unknown")))
    }

    func testActiveStateIsNilForStatelessAndUnknown() {
        let registry = registry()
        XCTAssertNil(registry.isActive(node("x", action: "known")))
        XCTAssertNil(registry.isActive(node("x", action: "unknown")))
    }

    // MARK: Load-time warnings (never config failures)

    func testUnknownActionProducesWarning() {
        let warnings = registry().warnings(for: config([.action(node("n1", action: "ghost"))]))
        XCTAssertEqual(warnings.count, 1)
        XCTAssertEqual(warnings[0].nodeID, "n1")
        XCTAssertTrue(warnings[0].message.contains("unknown action 'ghost'"), warnings[0].message)
    }

    func testBadParamsProduceWarningsEvenInNestedGroups() {
        let nested = Node.group(GroupNode(id: "g", title: "G", children: [
            .group(GroupNode(id: "h", title: "H", children: [.action(node("deep", action: "known"))])),
        ]))
        let warnings = registry().warnings(for: config([nested]))
        XCTAssertEqual(warnings.map(\.nodeID), ["deep"])
        XCTAssertTrue(warnings[0].message.contains("\"url\" is required"), warnings[0].message)
        XCTAssertTrue(warnings[0].message.contains("known"), "mentions the action id")
    }

    func testValidNodesProduceNoWarnings() {
        let good = node("ok", action: "known", params: .object(["url": .string("https://x.y")]))
        XCTAssertTrue(registry().warnings(for: config([.action(good)])).isEmpty)
    }

    func testUnknownParamKeysAreWarnings() {
        let n = node("n", action: "known", params: .object(["url": .string("u"), "oops": .bool(true)]))
        XCTAssertEqual(registry().warnings(for: config([.action(n)])).count, 1)
    }

    func testUnknownActionStillParsesAsValidConfig() throws {
        // An unknown action id must never be a config error (M2 rule kept in M3).
        let json = #"{"version":1,"ring":[{"type":"action","id":"a","title":"A","action":"does.not.exist"}]}"#
        XCTAssertNoThrow(try ConfigLoader.parse(Data(json.utf8)).get())
    }

    // MARK: Toast only when the set of warnings changes

    func testWarningTrackerFiresOnlyWhenSetChanges() {
        var tracker = WarningTracker()
        let a = ActionWarning(nodeID: "a", message: "m1")
        let b = ActionWarning(nodeID: "b", message: "m2")

        XCTAssertFalse(tracker.update([]), "nothing to say")
        XCTAssertTrue(tracker.update([a]), "first appearance")
        XCTAssertFalse(tracker.update([a]), "same reload again")
        XCTAssertTrue(tracker.update([a, b]), "a warning was added")
        XCTAssertFalse(tracker.update([b, a]), "order does not matter")
        XCTAssertFalse(tracker.update([a, b, a]), "duplicates do not matter")
        XCTAssertTrue(tracker.update([b]), "a warning went away and the set differs")
        XCTAssertFalse(tracker.update([]), "all cleared: no toast")
        XCTAssertTrue(tracker.update([b]), "comes back after being cleared: tell again")
    }

    // MARK: The real registry

    func testStandardRegistryHasEveryPlannedActionOnce() {
        let registry = ActionRegistry.standard(services: Fakes().services)
        XCTAssertEqual(Set(registry.ids), [
            "log", "app.open", "url.open", "path.open", "shell.run", "shortcut.run",
            "caffeinate.toggle", "screen.lock", "appearance.toggle", "dnd.toggle",
            "media.playPause", "media.next", "media.previous", "volume.muteToggle",
            "text.case", "text.pastePlain", "text.swapLayout",
        ])
        XCTAssertTrue(registry.duplicateIDs.isEmpty)
        XCTAssertEqual(registry.ids.count, Set(registry.ids).count)
    }

    func testEveryStandardActionHasTitleAndTheRightInputRequirement() {
        let registry = ActionRegistry.standard(services: Fakes().services)
        for id in registry.ids {
            guard let action = registry.action(for: id) else { return XCTFail(id) }
            XCTAssertFalse(action.title.isEmpty, id)
            // The selected-text actions take text; everything else needs no input.
            XCTAssertEqual(action.acceptedInputs, id.hasPrefix("text.") ? [.text] : [.none], id)
            XCTAssertEqual(action.id, id)
        }
    }
}

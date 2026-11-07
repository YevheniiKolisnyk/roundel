import XCTest
@testable import RoundelCore

final class ConfigValidationTests: XCTestCase {
    private func parse(_ json: String) -> Result<RoundelConfig, ConfigLoadFailure> {
        ConfigLoader.parse(Data(json.utf8))
    }

    private func issues(_ json: String, file: StaticString = #filePath, line: UInt = #line) -> [ConfigIssue] {
        if case .failure(let failure) = parse(json) { return failure.issues }
        XCTFail("expected failure", file: file, line: line)
        return []
    }

    private func action(_ id: String, title: String = "T") -> String {
        #"{"type":"action","id":"\#(id)","title":"\#(title)","action":"log"}"#
    }

    private func group(_ id: String, _ children: String) -> String {
        #"{"type":"group","id":"\#(id)","title":"G","children":[\#(children)]}"#
    }

    private func config(_ ring: String, version: String = "1") -> String {
        #"{"version":\#(version),"ring":[\#(ring)]}"#
    }

    // MARK: Version

    func testMissingVersionFails() {
        let found = issues(#"{"ring":[\#(action("a"))]}"#)
        XCTAssertEqual(found.first?.path, "version")
    }

    func testVersionZeroAndNegativeFail() {
        for version in ["0", "-1"] {
            XCTAssertEqual(issues(config(action("a"), version: version)).first?.path, "version", version)
        }
    }

    func testNewerVersionIsRejectedWithClearMessage() {
        let found = issues(config(action("a"), version: "2"))
        XCTAssertEqual(found.count, 1)
        XCTAssertEqual(found.first?.path, "version")
        XCTAssertTrue(found.first?.message.contains("newer") == true, found.first?.message ?? "")
    }

    func testNewerVersionWithIncompatibleSchemaStillReportsVersionOnly() {
        let found = issues(#"{"version":2,"ring":"not an array"}"#)
        XCTAssertEqual(found.count, 1)
        XCTAssertTrue(found.first?.message.contains("newer") == true)
    }

    func testVersionOneIsAccepted() {
        XCTAssertNoThrow(try parse(config(action("a"))).get())
    }

    // MARK: Ring shape

    func testEmptyRootRingFails() {
        XCTAssertEqual(issues(config("")).first?.path, "ring")
    }

    func testEmptyGroupFails() {
        let found = issues(config(action("a") + "," + group("g", "")))
        XCTAssertEqual(found.first?.path, "ring[1].children")
    }

    func testEmptyIdAndTitleFail() {
        let paths = issues(config(#"{"type":"action","id":"  ","title":"","action":"x"}"#)).compactMap(\.path)
        XCTAssertTrue(paths.contains("ring[0].id"))
        XCTAssertTrue(paths.contains("ring[0].title"))
    }

    func testEmptyActionStringFails() {
        let found = issues(config(#"{"type":"action","id":"a","title":"A","action":""}"#))
        XCTAssertEqual(found.first?.path, "ring[0].action")
    }

    // MARK: Duplicate ids

    func testDuplicateIdAtRoot() {
        let found = issues(config(action("a") + "," + action("a")))
        XCTAssertEqual(found.count, 1)
        XCTAssertEqual(found.first?.path, "ring[1].id")
        XCTAssertTrue(found.first?.message.contains("duplicate") == true)
        XCTAssertTrue(found.first?.message.contains("ring[0].id") == true, "message points at the first use")
    }

    func testDuplicateIdAcrossNestingLevels() {
        let found = issues(config(action("x") + "," + group("g", action("y") + "," + action("x"))))
        XCTAssertEqual(found.map(\.path), ["ring[1].children[1].id"])
    }

    func testGroupAndActionCannotShareAnId() {
        let found = issues(config(action("same") + "," + group("same", action("y"))))
        XCTAssertEqual(found.map(\.path), ["ring[1].id"])
    }

    func testSameIdInSiblingGroupsIsStillDuplicate() {
        let found = issues(config(group("g1", action("x")) + "," + group("g2", action("x"))))
        XCTAssertEqual(found.map(\.path), ["ring[1].children[0].id"])
    }

    func testAllProblemsAreReportedTogether() {
        let found = issues(config(action("a") + "," + action("a") + "," + #"{"type":"action","id":"b","title":"","action":"x"}"#))
        XCTAssertEqual(Set(found.compactMap(\.path)), ["ring[1].id", "ring[2].title"])
    }

    // MARK: Future-proofing (M3): action ids are free-form strings, never a config error

    func testUnknownActionIdIsNotAConfigError() {
        XCTAssertNoThrow(try parse(config(#"{"type":"action","id":"a","title":"A","action":"definitely.not.registered"}"#)).get())
    }
}

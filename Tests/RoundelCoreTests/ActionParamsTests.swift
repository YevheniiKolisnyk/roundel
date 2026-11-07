import XCTest
@testable import RoundelCore

final class ActionParamsTests: XCTestCase {
    private let rules = ParamRules(
        specs: [
            .string("url", required: true),
            .string("mode", allowed: ["display", "system"]),
            .int("minutes", range: 1...1440),
            .bool("login"),
            .stringList("args"),
        ]
    )

    private func issues(_ json: JSONValue) -> [ParamIssue] { rules.validate(json, actionID: "test.action") }
    private func blocking(_ json: JSONValue) -> [String] { issues(json).filter(\.blocksRun).map(\.message) }

    func testValidParamsHaveNoIssues() {
        let json: JSONValue = .object([
            "url": .string("https://x.y"), "mode": .string("system"), "minutes": .number(30),
            "login": .bool(true), "args": .array([.string("a"), .string("b")]),
        ])
        XCTAssertTrue(issues(json).isEmpty)
    }

    func testRequiredMissingOrNull() {
        XCTAssertEqual(blocking(.object([:])), ["\"url\" is required"])
        XCTAssertEqual(blocking(.object(["url": .null])), ["\"url\" is required"])
        XCTAssertEqual(blocking(.null), ["\"url\" is required"], "no params at all behaves like an empty object")
    }

    func testWrongTypes() {
        XCTAssertEqual(blocking(.object(["url": .number(1)])), ["\"url\" must be a string"])
        XCTAssertEqual(blocking(.object(["url": .string("u"), "login": .string("yes")])), ["\"login\" must be true or false"])
        XCTAssertEqual(blocking(.object(["url": .string("u"), "minutes": .string("5")])), ["\"minutes\" must be a whole number"])
        XCTAssertEqual(blocking(.object(["url": .string("u"), "args": .string("a")])), ["\"args\" must be a list of strings"])
        XCTAssertEqual(blocking(.object(["url": .string("u"), "args": .array([.string("a"), .number(2)])])), ["\"args\" must be a list of strings"])
    }

    func testEmptyStringIsRejected() {
        XCTAssertEqual(blocking(.object(["url": .string("   ")])), ["\"url\" must not be empty"])
    }

    func testAllowedValues() {
        XCTAssertEqual(blocking(.object(["url": .string("u"), "mode": .string("both")])),
                       ["\"mode\" must be one of: display, system"])
    }

    func testIntegerRangeAndFractions() {
        XCTAssertEqual(blocking(.object(["url": .string("u"), "minutes": .number(0)])), ["\"minutes\" must be between 1 and 1440"])
        XCTAssertEqual(blocking(.object(["url": .string("u"), "minutes": .number(1441)])), ["\"minutes\" must be between 1 and 1440"])
        XCTAssertEqual(blocking(.object(["url": .string("u"), "minutes": .number(2.5)])), ["\"minutes\" must be a whole number"])
        XCTAssertTrue(blocking(.object(["url": .string("u"), "minutes": .number(1440)])).isEmpty)
    }

    func testParamsMustBeAnObject() {
        XCTAssertEqual(blocking(.array([])), ["params must be a JSON object"])
        XCTAssertEqual(blocking(.string("x")), ["params must be a JSON object"])
    }

    func testUnknownKeysAreNonBlockingWarnings() {
        let found = issues(.object(["url": .string("u"), "colour": .string("red")]))
        XCTAssertEqual(found.count, 1)
        XCTAssertFalse(found[0].blocksRun)
        XCTAssertEqual(found[0].message, "\"colour\" is not a parameter of test.action (ignored)")
    }

    func testUnderscoreKeysAreComments() {
        XCTAssertTrue(issues(.object(["url": .string("u"), "_comment": .string("hi")])).isEmpty)
    }

    func testExactlyOneOf() {
        let rules = ParamRules(specs: [.string("name"), .string("bundleId")], exactlyOneOf: [["name", "bundleId"]])
        func found(_ json: JSONValue) -> [String] { rules.validate(json, actionID: "a").filter(\.blocksRun).map(\.message) }
        XCTAssertEqual(found(.object([:])), ["exactly one of \"name\" or \"bundleId\" is required"])
        XCTAssertEqual(found(.object(["name": .string("a"), "bundleId": .string("b")])), ["use only one of \"name\" or \"bundleId\""])
        XCTAssertTrue(found(.object(["name": .string("a")])).isEmpty)
        XCTAssertTrue(found(.object(["bundleId": .string("b")])).isEmpty)
    }

    func testMultipleProblemsAreAllReported() {
        let found = blocking(.object(["mode": .string("zzz"), "minutes": .number(0)]))
        XCTAssertEqual(found.count, 3)
    }

    // MARK: Accessors

    func testParamsAccessors() {
        let params = Params(.object([
            "s": .string("x"), "i": .number(7), "f": .number(1.5), "b": .bool(true),
            "l": .array([.string("a"), .string("b")]), "n": .null,
        ]))
        XCTAssertEqual(params.string("s"), "x")
        XCTAssertEqual(params.int("i"), 7)
        XCTAssertNil(params.int("f"))
        XCTAssertEqual(params.bool("b"), true)
        XCTAssertEqual(params.stringList("l"), ["a", "b"])
        XCTAssertNil(params.string("n"))
        XCTAssertNil(params.string("missing"))
        XCTAssertNil(params.bool("s"))
    }

    func testParamsFromNonObjectIsEmpty() {
        XCTAssertNil(Params(.array([.string("a")])).string("a"))
        XCTAssertNil(Params(.null).string("a"))
    }
}

import Foundation

public struct ParamIssue: Equatable, Sendable {
    public var message: String
    /// True when the action cannot run with these params. False for notes such as an ignored unknown key.
    public var blocksRun: Bool

    public init(message: String, blocksRun: Bool) {
        self.message = message
        self.blocksRun = blocksRun
    }
}

/// Typed read access to a node's `params` object.
public struct Params: Equatable, Sendable {
    public let values: [String: JSONValue]

    public init(_ value: JSONValue) {
        if case .object(let object) = value { values = object } else { values = [:] }
    }

    public func string(_ key: String) -> String? {
        if case .string(let value)? = values[key] { return value }
        return nil
    }

    public func int(_ key: String) -> Int? {
        guard case .number(let value)? = values[key], let int = Self.wholeNumber(value) else { return nil }
        return int
    }

    public func bool(_ key: String) -> Bool? {
        if case .bool(let value)? = values[key] { return value }
        return nil
    }

    public func stringList(_ key: String) -> [String]? {
        guard case .array(let items)? = values[key] else { return nil }
        let strings = items.compactMap(\.stringValue)
        return strings.count == items.count ? strings : nil
    }

    static func wholeNumber(_ value: Double) -> Int? {
        guard value.isFinite, value == value.rounded(), abs(value) < 1e15 else { return nil }
        return Int(value)
    }
}

public struct ParamSpec: Sendable {
    public enum Kind: Sendable { case string, int, bool, stringList }

    public let name: String
    public let kind: Kind
    public let isRequired: Bool
    public let allowed: [String]?
    public let range: ClosedRange<Int>?

    public static func string(_ name: String, required: Bool = false, allowed: [String]? = nil) -> ParamSpec {
        ParamSpec(name: name, kind: .string, isRequired: required, allowed: allowed, range: nil)
    }

    public static func int(_ name: String, required: Bool = false, range: ClosedRange<Int>? = nil) -> ParamSpec {
        ParamSpec(name: name, kind: .int, isRequired: required, allowed: nil, range: range)
    }

    public static func bool(_ name: String, required: Bool = false) -> ParamSpec {
        ParamSpec(name: name, kind: .bool, isRequired: required, allowed: nil, range: nil)
    }

    public static func stringList(_ name: String, required: Bool = false) -> ParamSpec {
        ParamSpec(name: name, kind: .stringList, isRequired: required, allowed: nil, range: nil)
    }
}

/// Declarative description of an action's params, validated the same way for every action.
public struct ParamRules: Sendable {
    public var specs: [ParamSpec]
    /// Groups of param names of which exactly one must be present.
    public var exactlyOneOf: [[String]]

    public init(specs: [ParamSpec], exactlyOneOf: [[String]] = []) {
        self.specs = specs
        self.exactlyOneOf = exactlyOneOf
    }

    public func validate(_ value: JSONValue, actionID: String) -> [ParamIssue] {
        let object: [String: JSONValue]
        switch value {
        case .object(let found): object = found
        case .null: object = [:]
        default: return [ParamIssue(message: "params must be a JSON object", blocksRun: true)]
        }

        var issues: [ParamIssue] = []
        func block(_ message: String) { issues.append(ParamIssue(message: message, blocksRun: true)) }

        for spec in specs {
            guard let found = object[spec.name], found != .null else {
                if spec.isRequired { block("\"\(spec.name)\" is required") }
                continue
            }
            check(found, against: spec, report: block)
        }

        for group in exactlyOneOf {
            let present = group.filter { object[$0] != nil && object[$0] != .null }
            let names = group.map { "\"\($0)\"" }.joined(separator: " or ")
            if present.isEmpty { block("exactly one of \(names) is required") }
            if present.count > 1 { block("use only one of \(names)") }
        }

        let known = Set(specs.map(\.name))
        for key in object.keys.sorted() where !known.contains(key) && !key.hasPrefix("_") {
            issues.append(ParamIssue(message: "\"\(key)\" is not a parameter of \(actionID) (ignored)", blocksRun: false))
        }
        return issues
    }

    private func check(_ value: JSONValue, against spec: ParamSpec, report: (String) -> Void) {
        let name = spec.name
        switch spec.kind {
        case .string:
            guard case .string(let text) = value else { return report("\"\(name)\" must be a string") }
            if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return report("\"\(name)\" must not be empty") }
            if let allowed = spec.allowed, !allowed.contains(text) {
                report("\"\(name)\" must be one of: \(allowed.joined(separator: ", "))")
            }
        case .int:
            guard case .number(let number) = value, let int = Params.wholeNumber(number) else {
                return report("\"\(name)\" must be a whole number")
            }
            if let range = spec.range, !range.contains(int) {
                report("\"\(name)\" must be between \(range.lowerBound) and \(range.upperBound)")
            }
        case .bool:
            guard case .bool = value else { return report("\"\(name)\" must be true or false") }
        case .stringList:
            guard case .array(let items) = value, items.allSatisfy({ $0.stringValue != nil }) else {
                return report("\"\(name)\" must be a list of strings")
            }
        }
    }
}

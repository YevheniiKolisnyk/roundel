import Foundation

/// One problem found in a config file. Syntax errors carry a line/column; schema errors carry the JSON path
/// (Codable does not expose source positions for those).
public struct ConfigIssue: Equatable, Sendable, CustomStringConvertible {
    public var path: String?
    public var line: Int?
    public var column: Int?
    public var message: String

    public init(path: String? = nil, line: Int? = nil, column: Int? = nil, message: String) {
        self.path = path
        self.line = line
        self.column = column
        self.message = message
    }

    public var description: String {
        if let line {
            let position = column.map { "line \(line), column \($0)" } ?? "line \(line)"
            return "\(position): \(message)"
        }
        if let path, !path.isEmpty { return "\(path): \(message)" }
        return message
    }
}

public struct ConfigLoadFailure: Error, Equatable, Sendable, CustomStringConvertible {
    public var issues: [ConfigIssue]

    public init(issues: [ConfigIssue]) {
        self.issues = issues
    }

    public init(_ issue: ConfigIssue) {
        self.issues = [issue]
    }

    public var description: String {
        issues.map(\.description).joined(separator: "\n")
    }

    /// First problem only, for the small toast.
    public var summary: String {
        guard let first = issues.first else { return "invalid config" }
        let more = issues.count > 1 ? " (+\(issues.count - 1) more)" : ""
        return first.description + more
    }
}

enum ConfigPathFormatter {
    /// `[ring, 2, children, 0, icon]` -> `ring[2].children[0].icon`
    static func format(_ codingPath: [CodingKey]) -> String {
        var result = ""
        for key in codingPath {
            if let index = key.intValue {
                result += "[\(index)]"
            } else {
                result += result.isEmpty ? key.stringValue : ".\(key.stringValue)"
            }
        }
        return result
    }
}

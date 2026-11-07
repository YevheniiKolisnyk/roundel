import Foundation

public enum ConfigLoader {
    // MARK: Parse

    public static func parse(_ data: Data) -> Result<RoundelConfig, ConfigLoadFailure> {
        if data.allSatisfy({ $0 == 0x20 || $0 == 0x0A || $0 == 0x0D || $0 == 0x09 }) {
            return .failure(ConfigLoadFailure(ConfigIssue(message: "config file is empty")))
        }

        // 1. Syntax, with line/column.
        do {
            _ = try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
        } catch {
            return .failure(ConfigLoadFailure(syntaxIssue(from: error, data: data)))
        }

        // 2. Version first, so a file written for a newer Roundel gets one clear message instead of field errors.
        struct VersionProbe: Decodable { var version: Int }
        let probe: VersionProbe
        do {
            probe = try JSONDecoder().decode(VersionProbe.self, from: data)
        } catch let error as DecodingError {
            return .failure(ConfigLoadFailure(issue(from: error, versionProbe: true)))
        } catch {
            return .failure(ConfigLoadFailure(ConfigIssue(message: error.localizedDescription)))
        }
        guard probe.version >= 1 else {
            return .failure(ConfigLoadFailure(ConfigIssue(path: "version", message: "version must be 1 or higher, got \(probe.version)")))
        }
        guard probe.version <= RoundelConfig.supportedVersion else {
            return .failure(ConfigLoadFailure(ConfigIssue(
                path: "version",
                message: "config version \(probe.version) is newer than this Roundel supports (\(RoundelConfig.supportedVersion)); update Roundel"
            )))
        }

        // 3. Schema.
        let config: RoundelConfig
        do {
            config = try JSONDecoder().decode(RoundelConfig.self, from: data)
        } catch let error as DecodingError {
            return .failure(ConfigLoadFailure(issue(from: error, versionProbe: false)))
        } catch {
            return .failure(ConfigLoadFailure(ConfigIssue(message: error.localizedDescription)))
        }

        // 4. Semantics.
        let problems = ConfigValidator.validate(config)
        return problems.isEmpty ? .success(config) : .failure(ConfigLoadFailure(issues: problems))
    }

    public static func load(from url: URL) -> Result<RoundelConfig, ConfigLoadFailure> {
        do {
            return parse(try Data(contentsOf: url))
        } catch {
            return .failure(ConfigLoadFailure(ConfigIssue(message: "cannot read \(url.lastPathComponent): \(error.localizedDescription)")))
        }
    }

    /// Non-fatal remarks about a file that loaded fine, e.g. settings that no longer do anything. The host logs them.
    public static func notes(for data: Data) -> [String] {
        guard let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let settings = object["settings"] as? [String: Any] else { return [] }
        var notes: [String] = []
        if settings["dwellMs"] != nil {
            notes.append("settings.dwellMs is no longer used; settings.expandDelayMs (default \(ConfigSettings.defaultExpandDelayMs)) replaces it")
        }
        if settings["centerDwellMs"] != nil {
            notes.append("settings.centerDwellMs is no longer used: the center does not go back any more, arcs close when the pointer moves away")
        }
        return notes
    }

    public static func encode(_ config: RoundelConfig) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(config)
    }

    // MARK: Error mapping

    private static func syntaxIssue(from error: Error, data: Data) -> ConfigIssue {
        let nsError = error as NSError
        let debug = (nsError.userInfo[NSDebugDescriptionErrorKey] as? String) ?? nsError.localizedDescription

        if let match = debug.range(of: #"line (\d+), column (\d+)"#, options: .regularExpression) {
            let numbers = debug[match].split(whereSeparator: { !$0.isNumber }).compactMap { Int($0) }
            if numbers.count == 2 {
                let message = debug[..<match.lowerBound]
                    .trimmingCharacters(in: CharacterSet(charactersIn: " ,.").union(.whitespaces))
                    .replacingOccurrences(of: " around", with: "")
                return ConfigIssue(line: numbers[0], column: numbers[1],
                                   message: "invalid JSON: " + (message.isEmpty ? "syntax error" : message))
            }
        }
        if let index = nsError.userInfo["NSJSONSerializationErrorIndex"] as? Int {
            let prefix = data.prefix(index)
            let line = prefix.filter { $0 == 0x0A }.count + 1
            return ConfigIssue(line: line, message: "invalid JSON: \(debug)")
        }
        return ConfigIssue(message: "invalid JSON: \(debug.lowercasedFirst) (is the file complete?)")
    }

    private static func issue(from error: DecodingError, versionProbe: Bool) -> ConfigIssue {
        switch error {
        case .keyNotFound(let key, let context):
            return ConfigIssue(path: ConfigPathFormatter.format(context.codingPath + [key]), message: "missing required field")
        case .typeMismatch(let type, let context), .valueNotFound(let type, let context):
            let path = ConfigPathFormatter.format(context.codingPath)
            if path.isEmpty { return ConfigIssue(message: "top level of the config must be a JSON object") }
            return ConfigIssue(path: path, message: "wrong type, expected \(describe(type))")
        case .dataCorrupted(let context):
            return ConfigIssue(path: ConfigPathFormatter.format(context.codingPath), message: context.debugDescription)
        @unknown default:
            return ConfigIssue(message: "\(error)")
        }
    }

    private static func describe(_ type: Any.Type) -> String {
        switch "\(type)" {
        case "Int": "an integer"
        case "String": "a string"
        case "Bool": "true or false"
        case let name where name.hasPrefix("Array"): "an array"
        case let name where name.hasPrefix("Dictionary"): "an object"
        case let name: name
        }
    }
}

private extension String {
    var lowercasedFirst: String { prefix(1).lowercased() + dropFirst() }
}

import Foundation

/// A node icon: exactly one of an SF Symbol name, an emoji, or an image file relative to the config folder.
public enum Icon: Equatable, Sendable, Codable {
    case symbol(String)
    case emoji(String)
    case image(String)

    private struct Key: CodingKey {
        var stringValue: String
        var intValue: Int? { nil }
        init(_ string: String) { stringValue = string }
        init?(stringValue: String) { self.stringValue = stringValue }
        init?(intValue: Int) { nil }
    }

    private static let kinds = ["symbol", "emoji", "image"]

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: Key.self)
        let present = Self.kinds.filter { container.contains(Key($0)) }

        func fail(_ message: String) -> DecodingError {
            // Reported at the icon itself so the path reads `ring[2].icon`.
            .dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: message))
        }

        guard present.count == 1, let kind = present.first else {
            throw fail(present.isEmpty
                ? "icon needs exactly one of \"symbol\", \"emoji\" or \"image\""
                : "icon has more than one of \"symbol\", \"emoji\", \"image\" (use exactly one)")
        }

        let value = try container.decode(String.self, forKey: Key(kind))
        switch kind {
        case "symbol":
            guard !value.trimmingCharacters(in: .whitespaces).isEmpty else { throw fail("icon symbol name is empty") }
            self = .symbol(value)
        case "emoji":
            guard value.count == 1, let character = value.first, character.looksLikeEmoji else {
                throw fail("icon emoji must be exactly one emoji, got \"\(value)\"")
            }
            self = .emoji(value)
        default:
            guard ConfigPaths.isSafeRelative(value) else {
                throw fail("icon image must be a relative path inside the config folder, got \"\(value)\"")
            }
            self = .image(value)
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: Key.self)
        switch self {
        case .symbol(let name): try container.encode(name, forKey: Key("symbol"))
        case .emoji(let value): try container.encode(value, forKey: Key("emoji"))
        case .image(let path): try container.encode(path, forKey: Key("image"))
        }
    }
}

extension Character {
    /// True for emoji (including flags, ZWJ sequences, keycaps) but not for plain ASCII letters or digits.
    var looksLikeEmoji: Bool {
        guard let first = unicodeScalars.first else { return false }
        return first.properties.isEmojiPresentation || (first.properties.isEmoji && unicodeScalars.count > 1)
    }
}

public enum ConfigPaths {
    /// Lexical check: relative, no home shortcut, no backslashes, and `..` never climbs out of the config folder.
    public static func isSafeRelative(_ path: String) -> Bool {
        guard !path.isEmpty, !path.hasPrefix("/"), !path.hasPrefix("~"),
              !path.contains("\\"), !path.contains("\0") else { return false }
        var depth = 0
        for component in path.split(separator: "/", omittingEmptySubsequences: true) {
            switch component {
            case ".": continue
            case "..":
                depth -= 1
                if depth < 0 { return false }
            default: depth += 1
            }
        }
        return true
    }
}

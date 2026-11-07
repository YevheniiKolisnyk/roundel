import Foundation

/// One physical key seen from both layouts: the character it types on the Latin (U.S.) layout and on the other one.
/// Shifted variants are separate pairs, which is what preserves case.
public struct LayoutPair: Equatable, Sendable {
    public let latin: Character
    public let native: Character

    public init(latin: Character, native: Character) {
        self.latin = latin
        self.native = native
    }
}

public enum SwapDirection: Equatable, Sendable {
    case latinToNative, nativeToLatin
}

/// A keyboard layout described as data: which Latin character each key's character corresponds to. A new layout
/// is a new table in `LayoutTables`, with no new logic.
public struct LayoutTable: Sendable {
    /// Config name of the language, e.g. "uk".
    public let language: String
    public let name: String
    /// Input source to switch to after Latin -> native, e.g. "com.apple.keylayout.Ukrainian-PC".
    public let nativeInputSourceID: String
    /// Input source to switch to after native -> Latin.
    public let latinInputSourceID: String
    public let pairs: [LayoutPair]
    /// Characters accepted only when converting Latin -> native (e.g. the ISO `§` key).
    public let latinExtras: [LayoutPair]
    /// Characters accepted only when converting native -> Latin (e.g. the typographic apostrophe).
    public let nativeAliases: [LayoutPair]

    private let toNative: [Character: Character]
    private let toLatin: [Character: Character]

    public init(language: String, name: String, nativeInputSourceID: String, latinInputSourceID: String,
                pairs: [LayoutPair], latinExtras: [LayoutPair] = [], nativeAliases: [LayoutPair] = []) {
        self.language = language
        self.name = name
        self.nativeInputSourceID = nativeInputSourceID
        self.latinInputSourceID = latinInputSourceID
        self.pairs = pairs
        self.latinExtras = latinExtras
        self.nativeAliases = nativeAliases
        // Real pairs win over extras and aliases.
        toNative = Dictionary((latinExtras + pairs).map { ($0.latin, $0.native) }, uniquingKeysWith: { _, last in last })
        toLatin = Dictionary((nativeAliases + pairs).map { ($0.native, $0.latin) }, uniquingKeysWith: { _, last in last })
    }

    public func nativeCharacter(forLatin character: Character) -> Character? { toNative[character] }
    public func latinCharacter(forNative character: Character) -> Character? { toLatin[character] }

    public func inputSourceID(for direction: SwapDirection) -> String {
        direction == .latinToNative ? nativeInputSourceID : latinInputSourceID
    }
}

public struct LayoutSwapResult: Equatable, Sendable {
    public let text: String
    public let direction: SwapDirection
    public let convertedCount: Int
}

/// Fixes text typed in the wrong layout. Every character is mapped by key position, so it is predictable:
/// a "." typed on the English layout is the Ю key. Characters of the other side are left as they are.
public enum LayoutSwapper {
    /// Which way to convert, by counting letters that belong to each side of the table. A tie goes Latin -> native.
    /// `nil` when the text has no letter the table knows.
    public static func detectDirection(_ text: String, using table: LayoutTable) -> SwapDirection? {
        var latin = 0
        var native = 0
        for character in text where character.isLetter {
            if table.nativeCharacter(forLatin: character) != nil && character.isASCII { latin += 1 }
            else if table.latinCharacter(forNative: character) != nil { native += 1 }
        }
        if latin == 0 && native == 0 { return nil }
        return latin >= native ? .latinToNative : .nativeToLatin
    }

    public static func swap(_ text: String, using table: LayoutTable) -> LayoutSwapResult? {
        guard let direction = detectDirection(text, using: table) else { return nil }
        var result = ""
        var converted = 0
        for character in text {
            let mapped = direction == .latinToNative ? table.nativeCharacter(forLatin: character) : table.latinCharacter(forNative: character)
            if let mapped {
                result.append(mapped)
                converted += 1
            } else {
                result.append(character)
            }
        }
        return LayoutSwapResult(text: result, direction: direction, convertedCount: converted)
    }
}

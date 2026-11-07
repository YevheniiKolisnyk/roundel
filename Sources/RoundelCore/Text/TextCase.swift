import Foundation

/// Case transforms for `text.case`. All of them work per Unicode letter, so Cyrillic and other scripts behave.
public enum TextCase: String, CaseIterable, Sendable {
    case upper, lower, title, sentence, toggle

    public func apply(_ text: String) -> String {
        switch self {
        case .upper: text.uppercased()
        case .lower: text.lowercased()
        case .title: Self.title(text)
        case .sentence: Self.sentence(text)
        case .toggle: Self.toggle(text)
        }
    }

    // MARK: Title

    /// First letter of every word upper case, the rest lower case. Apostrophes inside a word do not start a new
    /// word ("don't" -> "Don't"); hyphens do ("well-known" -> "Well-Known"). Digits count as part of a word.
    private static func title(_ text: String) -> String {
        var result = ""
        var atWordStart = true
        let characters = Array(text)
        for (index, character) in characters.enumerated() {
            if character.isLetter {
                result += atWordStart ? String(character).uppercased() : String(character).lowercased()
                atWordStart = false
            } else if character.isNumber {
                result.append(character)
                atWordStart = false
            } else if apostrophes.contains(character), !atWordStart,
                      index + 1 < characters.count, characters[index + 1].isLetter {
                result.append(character)
            } else {
                result.append(character)
                atWordStart = true
            }
        }
        return result
    }

    // MARK: Sentence

    /// Everything lower case, then a capital at the start, after `. ! ? …` followed by whitespace, and at every line.
    private static func sentence(_ text: String) -> String {
        var result = ""
        var capitalizeNext = true
        var afterTerminator = false
        for character in text {
            if character.isLetter {
                result += capitalizeNext ? String(character).uppercased() : String(character).lowercased()
                capitalizeNext = false
                afterTerminator = false
            } else if character.isNumber {
                result.append(character)
                capitalizeNext = false
                afterTerminator = false
            } else if character.isNewline {
                result.append(character)
                capitalizeNext = true
                afterTerminator = false
            } else if character.isWhitespace {
                result.append(character)
                if afterTerminator { capitalizeNext = true }
            } else if terminators.contains(character) {
                result.append(character)
                afterTerminator = true
            } else if closers.contains(character) && afterTerminator {
                result.append(character)   // `. "` keeps the pending capital
            } else if openers.contains(character) && capitalizeNext {
                result.append(character)   // the capital goes after an opening quote or bracket
            } else {
                result.append(character)
                afterTerminator = false
            }
        }
        return result
    }

    // MARK: Toggle

    private static func toggle(_ text: String) -> String {
        var result = ""
        for character in text {
            let single = String(character)
            if character.isUppercase { result += single.lowercased() }
            else if character.isLowercase { result += single.uppercased() }
            else { result += single }
        }
        return result
    }

    private static let apostrophes: Set<Character> = ["'", "’", "\u{02BC}"]
    private static let terminators: Set<Character> = [".", "!", "?", "…"]
    private static let closers: Set<Character> = ["\"", "”", "’", "'", ")", "]", "»"]
    private static let openers: Set<Character> = ["\"", "“", "‘", "'", "(", "[", "«", "¿", "¡"]
}

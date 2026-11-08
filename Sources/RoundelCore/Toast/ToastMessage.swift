import Foundation

public enum ToastKind: String, Equatable, Sendable {
    case success, warning, error, progress

    public init(isError: Bool) {
        self = isError ? .error : .success
    }

    /// Drawn in the attention style (the old `isError`).
    public var isErrorStyle: Bool { self == .error || self == .warning }
}

/// What a toast says: a title and, when there is more, a secondary line.
public struct ToastMessage: Equatable, Sendable {
    public let kind: ToastKind
    public let title: String
    public let detail: String?

    public init(kind: ToastKind, title: String, detail: String? = nil) {
        self.kind = kind
        self.title = title
        self.detail = detail
    }

    /// Splits a one-line message into title and detail, so everything that produces messages keeps producing plain text.
    /// In order: the action-name prefix ("Convert Image: ") is dropped; then the first of: a new line, " · ", a sentence
    /// end, a colon, a trailing parenthetical decides where the title ends.
    public static func parse(_ text: String, kind: ToastKind) -> ToastMessage {
        let limit = DesignMetrics.standard.toastMaxCharacters
        var body = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !body.isEmpty else {
            return ToastMessage(kind: kind, title: kind == .success ? "Done" : "Something went wrong")
        }

        var strippedPrefix = false
        if let rest = withoutActionPrefix(body) {
            body = rest
            strippedPrefix = true
        }

        var (title, detail) = split(body)
        if strippedPrefix, let first = title.first { title = first.uppercased() + title.dropFirst() }
        return ToastMessage(kind: kind, title: shortened(title, limit), detail: detail.map { shortened($0, limit) })
    }

    // MARK: Private

    private static func shortened(_ text: String, _ limit: Int) -> String {
        text.count > limit ? String(text.prefix(limit)) + "…" : text
    }

    /// "Convert Image: Couldn’t …" -> "Couldn’t …". The prefix is the action's name as the executor puts it: one to three
    /// capitalized words, nothing else, so a sentence that merely contains a colon is left alone.
    private static func withoutActionPrefix(_ text: String) -> String? {
        guard let range = text.range(of: ": ") else { return nil }
        let prefix = String(text[..<range.lowerBound])
        let rest = String(text[range.upperBound...]).trimmingCharacters(in: .whitespaces)
        let words = prefix.split(separator: " ")
        guard !rest.isEmpty, (1...3).contains(words.count), prefix.count <= 28,
              words.allSatisfy({ $0.first?.isUppercase == true && $0.allSatisfy { $0.isLetter || $0 == "&" } }) else { return nil }
        return rest
    }

    private static func split(_ body: String) -> (title: String, detail: String?) {
        if let newline = body.firstIndex(where: \.isNewline) {
            let detail = body[body.index(after: newline)...].trimmingCharacters(in: .whitespacesAndNewlines)
            return (String(body[..<newline]), detail.isEmpty ? nil : detail)
        }

        let facts = body.components(separatedBy: " · ").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        if facts.count > 1 { return (facts[0], facts.dropFirst().joined(separator: "\n")) }

        if let end = sentenceEnd(in: body) {
            let title = String(body[..<end])
            let detail = body[body.index(end, offsetBy: 2)...].trimmingCharacters(in: .whitespaces)
            if !title.isEmpty, !detail.isEmpty { return (title, detail) }
        }

        if let colon = body.range(of: ": ") {
            let title = String(body[..<colon.lowerBound])
            let detail = String(body[colon.upperBound...]).trimmingCharacters(in: .whitespaces)
            if !title.isEmpty, title.count <= 48, !detail.isEmpty { return (title, detail) }
        }

        if body.hasSuffix(")"), let open = body.range(of: " (") {
            let title = String(body[..<open.lowerBound])
            let inner = String(body[open.upperBound...].dropLast())
            if !title.isEmpty, !inner.isEmpty, isBalanced(inner) { return (title, inner) }
        }
        return (body, nil)
    }

    /// The index of the "." that ends the first sentence: followed by a space and a capital letter.
    private static func sentenceEnd(in text: String) -> String.Index? {
        var index = text.startIndex
        while let dot = text[index...].firstIndex(of: ".") {
            let afterDot = text.index(after: dot)
            if afterDot < text.endIndex, text[afterDot] == " ", dot > text.startIndex {
                let next = text.index(after: afterDot)
                if next < text.endIndex, text[next].isUppercase { return dot }
            }
            index = afterDot
            if index >= text.endIndex { break }
        }
        return nil
    }

    private static func isBalanced(_ text: String) -> Bool {
        var depth = 0
        for character in text {
            if character == "(" { depth += 1 }
            if character == ")" { depth -= 1 }
            if depth < 0 { return false }
        }
        return depth == 0
    }
}

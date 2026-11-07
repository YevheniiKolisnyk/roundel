import XCTest
@testable import RoundelCore

final class TextCaseTests: XCTestCase {
    func testUpperAndLowerHandleCyrillicAndSpecialLetters() {
        XCTAssertEqual(TextCase.upper.apply("привіт ї ґ"), "ПРИВІТ Ї Ґ")
        XCTAssertEqual(TextCase.lower.apply("ПРИВІТ Ї Ґ"), "привіт ї ґ")
        XCTAssertEqual(TextCase.upper.apply("straße"), "STRASSE")
    }

    // MARK: title

    func testTitleCapitalizesEachWordAndLowercasesTheRest() {
        XCTAssertEqual(TextCase.title.apply("hello wORLD"), "Hello World")
        XCTAssertEqual(TextCase.title.apply("NASA launch"), "Nasa Launch")
        XCTAssertEqual(TextCase.title.apply("привіт СВІТЕ"), "Привіт Світе")
    }

    func testTitleKeepsApostropheInsideAWordAndSplitsOnHyphen() {
        XCTAssertEqual(TextCase.title.apply("don't stop"), "Don't Stop")
        XCTAssertEqual(TextCase.title.apply("it’s well-known"), "It’s Well-Known")
        XCTAssertEqual(TextCase.title.apply("п'ять"), "П'ять")
    }

    func testTitleLeavesNumbersAndWhitespaceAlone() {
        XCTAssertEqual(TextCase.title.apply("3rd place"), "3rd Place")
        XCTAssertEqual(TextCase.title.apply("  two  spaces\tand\nlines "), "  Two  Spaces\tAnd\nLines ")
    }

    // MARK: sentence

    func testSentenceCapitalizesTheStartAndAfterTerminators() {
        XCTAssertEqual(TextCase.sentence.apply("hELLO. how ARE you? FINE! ok"), "Hello. How are you? Fine! Ok")
        XCTAssertEqual(TextCase.sentence.apply("привіт. ЯК справи?"), "Привіт. Як справи?")
    }

    func testSentenceStartsANewSentenceOnEveryLine() {
        XCTAssertEqual(TextCase.sentence.apply("line ONE\nline two"), "Line one\nLine two")
    }

    func testSentenceDoesNotBreakOnDecimalPointsOrAbbreviationsWithoutSpace() {
        XCTAssertEqual(TextCase.sentence.apply("3.14 is PI. yes"), "3.14 is pi. Yes")
        XCTAssertEqual(TextCase.sentence.apply("see file.TXT now"), "See file.txt now")
    }

    func testSentenceSkipsOpeningQuotesAndBracketsBeforeTheCapital() {
        XCTAssertEqual(TextCase.sentence.apply("he said. \"hi THERE\" (ok)"), "He said. \"Hi there\" (ok)")
        XCTAssertEqual(TextCase.sentence.apply("(first) second"), "(First) second")
    }

    func testSentenceDoesNotCapitalizeAfterANumberAtTheStart() {
        XCTAssertEqual(TextCase.sentence.apply("2 DOGS"), "2 dogs")
    }

    // MARK: toggle

    func testToggleInvertsEveryLetter() {
        XCTAssertEqual(TextCase.toggle.apply("Hello World"), "hELLO wORLD")
        XCTAssertEqual(TextCase.toggle.apply("Привіт 123!"), "пРИВІТ 123!")
    }

    func testEmptyAndSymbolOnlyTextIsUnchangedByEveryMode() {
        for mode in TextCase.allCases {
            XCTAssertEqual(mode.apply(""), "")
            XCTAssertEqual(mode.apply("123 !?"), "123 !?", "\(mode)")
        }
    }

    func testRawValuesMatchTheConfigNames() {
        XCTAssertEqual(TextCase.allCases.map(\.rawValue), ["upper", "lower", "title", "sentence", "toggle"])
    }
}

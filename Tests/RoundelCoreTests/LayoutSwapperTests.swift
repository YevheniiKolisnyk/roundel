import XCTest
@testable import RoundelCore

final class LayoutSwapperTests: XCTestCase {
    private let uk = LayoutTables.ukrainianPC
    private let ru = LayoutTables.russianWin

    private func swap(_ text: String, _ table: LayoutTable) -> String? { LayoutSwapper.swap(text, using: table)?.text }

    // MARK: Latin -> native

    func testRussianWordsTypedInTheEnglishLayout() {
        XCTAssertEqual(swap("ghbdtn", ru), "привет")
        XCTAssertEqual(swap("Ghbdtn vbh", ru), "Привет мир")
    }

    func testUkrainianWordsTypedInTheEnglishLayout() {
        XCTAssertEqual(swap("Ghbdsn", uk), "Привіт")
        XCTAssertEqual(swap("ghbdsn? cdsnt", uk), "привіт, світе", "the Ukrainian comma is Shift+/")
    }

    func testTheLettersOnlyUkrainianHas() {
        XCTAssertEqual(swap("]'s`", uk), "їєіґ")
        XCTAssertEqual(swap("}\"S~", uk), "ЇЄІҐ")
    }

    func testTheLettersOnlyRussianHas() {
        XCTAssertEqual(swap("]'s`", ru), "ъэыё")
        XCTAssertEqual(swap("}\"S~", ru), "ЪЭЫЁ")
    }

    func testDigitRowSymbolsFollowTheSystemLayout() {
        XCTAssertEqual(swap("a@#$^&", uk), "ф\"№;:?")
        XCTAssertEqual(swap("a@#$^&", ru), "ф\"№;:?")
    }

    // MARK: native -> Latin

    func testNativeTextTypedInTheEnglishLayoutGoesBack() {
        XCTAssertEqual(swap("руддщ", ru), "hello")
        XCTAssertEqual(swap("Руддщ цщкдв", uk), "Hello world")
        XCTAssertEqual(swap("привіт", uk), "ghbdsn")
        XCTAssertEqual(swap("їєіґ ЇЄІҐ", uk), "]'s` }\"S~")
    }

    func testTypographicAndModifierApostropheBothMapToTheApostropheKey() {
        XCTAssertEqual(swap("п’ять", uk), "g\\znm")
        XCTAssertEqual(swap("п\u{02BC}ять", uk), "g\\znm")
    }

    // MARK: Case, mixed text, punctuation

    func testCaseOfEveryLetterIsPreserved() {
        XCTAssertEqual(swap("hElLo", ru), "рУдДщ")
        XCTAssertEqual(swap("GHBDTN", ru), "ПРИВЕТ")
    }

    func testTextThatIsAlreadyInTheTargetScriptIsLeftAlone() {
        XCTAssertEqual(swap("hello приві", uk), "руддщ приві", "5 vs 5 is a tie: Latin -> native; Cyrillic stays")
        XCTAssertEqual(swap("привіт ab", uk), "ghbdsn ab", "native -> Latin; the Latin part stays")
    }

    func testDigitsSpacesAndLineBreaksSurvive() {
        XCTAssertEqual(swap("ghbdsn 123\n\tcdsnt", uk), "привіт 123\n\tсвіте")
        XCTAssertEqual(swap("ab\ncd", ru), "фи\nсв")
    }

    func testPunctuationIsMappedByKeyPosition() {
        XCTAssertEqual(swap("ghbdtn/", ru), "привет.")
        XCTAssertEqual(swap("ghbdtn.", ru), "приветю", "a '.' typed on the English layout is the Ю key")
        XCTAssertEqual(swap("привет.", ru), "ghbdtn/")
    }

    func testIsoSectionKeyIsAOneWayExtra() {
        XCTAssertEqual(swap("§g", ru), "ёп")
        XCTAssertEqual(swap("±g", ru), "Ёп")
        XCTAssertEqual(swap("§g", uk), "\\п")
    }

    // MARK: Direction

    func testDirectionCountsLettersOnly() {
        XCTAssertEqual(LayoutSwapper.detectDirection("hello", using: ru), .latinToNative)
        XCTAssertEqual(LayoutSwapper.detectDirection("привет", using: ru), .nativeToLatin)
        XCTAssertEqual(LayoutSwapper.detectDirection("привет hi", using: ru), .nativeToLatin)
        XCTAssertEqual(LayoutSwapper.detectDirection("hello мир", using: ru), .latinToNative, "5 Latin letters beat 3 Cyrillic")
        XCTAssertEqual(LayoutSwapper.detectDirection("hi привет", using: ru), .nativeToLatin)
        XCTAssertEqual(LayoutSwapper.detectDirection("hello приві", using: uk), .latinToNative, "a tie goes to Latin -> native")
        XCTAssertEqual(LayoutSwapper.detectDirection("ґї", using: uk), .nativeToLatin)
    }

    func testPunctuationAndDigitsDoNotCountForDirection() {
        XCTAssertEqual(LayoutSwapper.detectDirection(",.;'[] 123 привет", using: ru), .nativeToLatin)
    }

    func testLettersTheTableDoesNotKnowDoNotCount() {
        XCTAssertNil(LayoutSwapper.detectDirection("éüñ", using: ru))
        XCTAssertNil(LayoutSwapper.detectDirection("ґ", using: ru), "ґ is not on the Russian layout")
    }

    func testTextWithoutLettersCannotBeSwapped() {
        XCTAssertNil(LayoutSwapper.detectDirection("123 !?;", using: uk))
        XCTAssertNil(LayoutSwapper.swap("", using: uk))
        XCTAssertNil(LayoutSwapper.swap("123 ,./", using: uk))
    }

    func testResultReportsDirectionAndTheInputSourceToSwitchTo() throws {
        let toNative = try XCTUnwrap(LayoutSwapper.swap("ghbdsn", using: uk))
        XCTAssertEqual(toNative.direction, .latinToNative)
        XCTAssertEqual(uk.inputSourceID(for: toNative.direction), "com.apple.keylayout.Ukrainian-PC")
        let toLatin = try XCTUnwrap(LayoutSwapper.swap("привіт", using: uk))
        XCTAssertEqual(toLatin.direction, .nativeToLatin)
        XCTAssertEqual(uk.inputSourceID(for: toLatin.direction), "com.apple.keylayout.US")
        XCTAssertEqual(ru.inputSourceID(for: .latinToNative), "com.apple.keylayout.RussianWin")
    }

    // MARK: Tables as data

    func testEveryPairRoundTripsThroughBothMaps() {
        for table in LayoutTables.all {
            for pair in table.pairs {
                XCTAssertEqual(table.nativeCharacter(forLatin: pair.latin), pair.native, "\(table.language) \(pair.latin)")
                XCTAssertEqual(table.latinCharacter(forNative: pair.native), pair.latin, "\(table.language) \(pair.native)")
            }
        }
    }

    func testTablesAreOneToOne() {
        for table in LayoutTables.all {
            XCTAssertEqual(Set(table.pairs.map(\.latin)).count, table.pairs.count, "\(table.language): a Latin key appears twice")
            XCTAssertEqual(Set(table.pairs.map(\.native)).count, table.pairs.count, "\(table.language): a native character appears twice")
        }
    }

    func testEveryLetterOfTheAlphabetIsReachable() {
        for table in LayoutTables.all {
            for scalar in "abcdefghijklmnopqrstuvwxyz".unicodeScalars {
                let letter = Character(scalar)
                XCTAssertNotNil(table.nativeCharacter(forLatin: letter), "\(table.language) lower \(letter)")
                XCTAssertNotNil(table.nativeCharacter(forLatin: Character(letter.uppercased())), "\(table.language) upper \(letter)")
            }
        }
    }

    func testLanguageLookup() {
        XCTAssertEqual(LayoutTables.table(forLanguage: "uk")?.name, uk.name)
        XCTAssertEqual(LayoutTables.table(forLanguage: "ru")?.name, ru.name)
        XCTAssertNil(LayoutTables.table(forLanguage: "de"))
        XCTAssertEqual(LayoutTables.all.map(\.language), ["uk", "ru"])
    }

    func testAnExtraLayoutIsJustAnotherTable() {
        // Data-driven: a new layout needs only a table, no new logic.
        let toy = LayoutTable(language: "xx", name: "Toy", nativeInputSourceID: "toy.native", latinInputSourceID: "toy.latin",
                              pairs: [LayoutPair(latin: "a", native: "α"), LayoutPair(latin: "A", native: "Α")])
        XCTAssertEqual(LayoutSwapper.swap("aA", using: toy)?.text, "αΑ")
        XCTAssertEqual(LayoutSwapper.swap("αΑ", using: toy)?.text, "aA")
    }
}

import Foundation

/// The layouts Roundel can fix, taken from the key tables macOS itself reports for the layouts installed on the
/// author's Mac (`UCKeyTranslate`, ANSI key positions):
/// - Ukrainian: "Ukrainian - PC" (`com.apple.keylayout.Ukrainian-PC`), not Apple's own "Ukrainian".
/// - Russian: "Russian - PC" (`com.apple.keylayout.RussianWin`), not Apple's own "Russian".
/// - Latin side: "U.S." (`com.apple.keylayout.US`).
/// Each line is one physical key: the U.S. character and what the same key types on the other layout, unshifted then
/// shifted; keys that type the same character on both layouts (letters aside, e.g. most digits) are left out.
/// To support another layout, add a table here and list it in `all`; no other code changes.
public enum LayoutTables {
    private static let usInputSourceID = "com.apple.keylayout.US"

    private static func p(_ latin: Character, _ native: Character) -> LayoutPair { LayoutPair(latin: latin, native: native) }

    /// Ukrainian - PC. Has the letters ї є і ґ; the apostrophe key types U+02BC (ʼ).
    public static let ukrainianPC = LayoutTable(
        language: "uk",
        name: "Ukrainian - PC",
        nativeInputSourceID: "com.apple.keylayout.Ukrainian-PC",
        latinInputSourceID: usInputSourceID,
        pairs: [
            p("a", "ф"), p("A", "Ф"),   //kc0
            p("s", "і"), p("S", "І"),   //kc1
            p("d", "в"), p("D", "В"),   //kc2
            p("f", "а"), p("F", "А"),   //kc3
            p("h", "р"), p("H", "Р"),   //kc4
            p("g", "п"), p("G", "П"),   //kc5
            p("z", "я"), p("Z", "Я"),   //kc6
            p("x", "ч"), p("X", "Ч"),   //kc7
            p("c", "с"), p("C", "С"),   //kc8
            p("v", "м"), p("V", "М"),   //kc9
            p("b", "и"), p("B", "И"),   //kc11
            p("q", "й"), p("Q", "Й"),   //kc12
            p("w", "ц"), p("W", "Ц"),   //kc13
            p("e", "у"), p("E", "У"),   //kc14
            p("r", "к"), p("R", "К"),   //kc15
            p("y", "н"), p("Y", "Н"),   //kc16
            p("t", "е"), p("T", "Е"),   //kc17
            p("@", "\""),   //kc19
            p("#", "№"),   //kc20
            p("$", ";"),   //kc21
            p("^", ":"),   //kc22
            p("&", "?"),   //kc26
            p("]", "ї"), p("}", "Ї"),   //kc30
            p("o", "щ"), p("O", "Щ"),   //kc31
            p("u", "г"), p("U", "Г"),   //kc32
            p("[", "х"), p("{", "Х"),   //kc33
            p("i", "ш"), p("I", "Ш"),   //kc34
            p("p", "з"), p("P", "З"),   //kc35
            p("l", "д"), p("L", "Д"),   //kc37
            p("j", "о"), p("J", "О"),   //kc38
            p("'", "є"), p("\"", "Є"),   //kc39
            p("k", "л"), p("K", "Л"),   //kc40
            p(";", "ж"), p(":", "Ж"),   //kc41
            p("\\", "ʼ"), p("|", "₴"),   //kc42
            p(",", "б"), p("<", "Б"),   //kc43
            p("/", "."), p("?", ","),   //kc44
            p("n", "т"), p("N", "Т"),   //kc45
            p("m", "ь"), p("M", "Ь"),   //kc46
            p(".", "ю"), p(">", "Ю"),   //kc47
            p("`", "ґ"), p("~", "Ґ"),   //kc50
        ],
        // The ISO `§`/`±` key (left of 1 on ISO keyboards) types `\` and `/` here.
        latinExtras: [p("§", "\\"), p("±", "/")],
        // The typographic apostrophe is what people usually type or paste; it is the same key as ʼ.
        nativeAliases: [p("\\", "\u{2019}")]
    )

    /// Russian - PC (RussianWin). Has ё ъ ы э. Apple's table gives Ë (U+00CB) for Shift+` ; Ё is clearly what is meant.
    public static let russianWin = LayoutTable(
        language: "ru",
        name: "Russian - PC",
        nativeInputSourceID: "com.apple.keylayout.RussianWin",
        latinInputSourceID: usInputSourceID,
        pairs: [
            p("a", "ф"), p("A", "Ф"),   //kc0
            p("s", "ы"), p("S", "Ы"),   //kc1
            p("d", "в"), p("D", "В"),   //kc2
            p("f", "а"), p("F", "А"),   //kc3
            p("h", "р"), p("H", "Р"),   //kc4
            p("g", "п"), p("G", "П"),   //kc5
            p("z", "я"), p("Z", "Я"),   //kc6
            p("x", "ч"), p("X", "Ч"),   //kc7
            p("c", "с"), p("C", "С"),   //kc8
            p("v", "м"), p("V", "М"),   //kc9
            p("b", "и"), p("B", "И"),   //kc11
            p("q", "й"), p("Q", "Й"),   //kc12
            p("w", "ц"), p("W", "Ц"),   //kc13
            p("e", "у"), p("E", "У"),   //kc14
            p("r", "к"), p("R", "К"),   //kc15
            p("y", "н"), p("Y", "Н"),   //kc16
            p("t", "е"), p("T", "Е"),   //kc17
            p("@", "\""),   //kc19
            p("#", "№"),   //kc20
            p("$", ";"),   //kc21
            p("^", ":"),   //kc22
            p("&", "?"),   //kc26
            p("]", "ъ"), p("}", "Ъ"),   //kc30
            p("o", "щ"), p("O", "Щ"),   //kc31
            p("u", "г"), p("U", "Г"),   //kc32
            p("[", "х"), p("{", "Х"),   //kc33
            p("i", "ш"), p("I", "Ш"),   //kc34
            p("p", "з"), p("P", "З"),   //kc35
            p("l", "д"), p("L", "Д"),   //kc37
            p("j", "о"), p("J", "О"),   //kc38
            p("'", "э"), p("\"", "Э"),   //kc39
            p("k", "л"), p("K", "Л"),   //kc40
            p(";", "ж"), p(":", "Ж"),   //kc41
            p("|", "/"),   //kc42
            p(",", "б"), p("<", "Б"),   //kc43
            p("/", "."), p("?", ","),   //kc44
            p("n", "т"), p("N", "Т"),   //kc45
            p("m", "ь"), p("M", "Ь"),   //kc46
            p(".", "ю"), p(">", "Ю"),   //kc47
            p("`", "ё"), p("~", "Ё"),   //kc50
        ],
        // On ISO keyboards the `§`/`±` key types ё/Ё.
        latinExtras: [p("§", "ё"), p("±", "Ё")]
    )

    public static let all: [LayoutTable] = [ukrainianPC, russianWin]

    public static func table(forLanguage language: String) -> LayoutTable? {
        all.first { $0.language == language }
    }
}

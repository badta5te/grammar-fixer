import XCTest
@testable import GrammarFixerCore

/// Sanitizing is not decoration. An expensive model returns clean text without
/// it, while a cheap one adds a preamble and quotes. The model that breaks is
/// precisely the one the freedom to choose was built for.
final class ResponseSanitizerTests: XCTestCase {
    private func clean(_ output: String, original: String = "исходный текст") -> String {
        ResponseSanitizer.clean(output, original: original)
    }

    func testWhitespaceAroundTheAnswerIsTrimmed() {
        XCTAssertEqual(clean("\n  Привет, как дела?  \n"), "Привет, как дела?")
    }

    func testLeadingPreambleLineIsDropped() {
        XCTAssertEqual(
            clean("Here is the corrected text:\nПривет, как дела?"),
            "Привет, как дела?"
        )
    }

    func testRussianPreambleLineIsDropped() {
        XCTAssertEqual(
            clean("Вот исправленный текст:\nПривет, как дела?"),
            "Привет, как дела?"
        )
    }

    /// The model repeats the prompt's anchor, the very thing holding it back.
    func testRepeatedAnchorIsDroppedEvenOnTheSameLine() {
        XCTAssertEqual(clean("Rewritten text: Привет, как дела?"), "Привет, как дела?")
    }

    /// A line with a colon is sometimes real text. If it was in the input then
    /// it belongs to the person, not to the model's chatter.
    func testColonLineThatCameFromTheOriginalSurvives() {
        let original = "Задачи:\nкупить хлеб"
        XCTAssertEqual(clean("Задачи:\nкупить хлеб", original: original), "Задачи:\nкупить хлеб")
    }

    /// The model's job is to fix the text, so its answer differs from the
    /// input by design. A heading of the person's own with a space or a typo
    /// corrected must not become a preamble because it no longer matches.
    func testCorrectedColonLineFromTheOriginalSurvives() {
        XCTAssertEqual(
            clean("Задачи:\nкупить хлеб", original: "задчи :\nкупить хлеб"),
            "Задачи:\nкупить хлеб"
        )
    }

    func testLongFirstLineWithColonIsNotMistakenForPreamble() {
        let text = "Слушай, я тут подумал и решил, что нам всё-таки стоит перенести встречу: "
            + "в пятницу у меня самолёт, и я точно не успею подготовиться."
        XCTAssertEqual(clean(text), text)
    }

    func testSurroundingQuotesAreRemoved() {
        XCTAssertEqual(clean("\"Привет, как дела?\""), "Привет, как дела?")
    }

    func testTypographicAndRussianQuotesAreRemoved() {
        XCTAssertEqual(clean("«Привет, как дела?»"), "Привет, как дела?")
        XCTAssertEqual(clean("“Привет, как дела?”"), "Привет, как дела?")
        XCTAssertEqual(clean("„Привет, как дела?“"), "Привет, как дела?")
    }

    /// The person's own quotes are not to be touched: they are their text, not
    /// the model's wrapping.
    func testQuotesThatWereInTheOriginalSurvive() {
        XCTAssertEqual(
            clean("«Привет, как дела?»", original: "«привет как дела»"),
            "«Привет, как дела?»"
        )
    }

    func testUnbalancedQuoteIsNotTouched() {
        XCTAssertEqual(clean("\"Привет, как дела?"), "\"Привет, как дела?")
    }

    func testInnerQuotesSurvive() {
        let original = "он сказал \"привет\" и ушёл"
        XCTAssertEqual(
            clean("Он сказал \"привет\" и ушёл.", original: original),
            "Он сказал \"привет\" и ушёл."
        )
    }

    func testCodeFencesAreRemoved() {
        XCTAssertEqual(clean("```\nПривет, как дела?\n```"), "Привет, как дела?")
    }

    func testCodeFenceWithLanguageIsRemoved() {
        XCTAssertEqual(clean("```text\nПривет, как дела?\n```"), "Привет, как дела?")
    }

    /// A fence inside the text is the person's code and stays.
    func testFenceInsideTheTextSurvives() {
        let text = "Смотри пример:\n```\nlet a = 1\n```\nвот так"
        XCTAssertEqual(clean(text, original: text.lowercased()), text)
    }

    func testPreambleAndQuotesTogether() {
        XCTAssertEqual(
            clean("Вот исправленный текст:\n\n\"Привет, как дела?\""),
            "Привет, как дела?"
        )
    }

    func testUrlsAndEmojiSurviveUntouched() {
        let text = "Посмотри https://example.com/a_b?c=1 😀 и скажи"
        XCTAssertEqual(clean(text, original: text), text)
    }

    func testEmptyAnswerStaysEmpty() {
        XCTAssertEqual(clean("   \n  "), "")
    }
}

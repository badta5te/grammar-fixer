import XCTest
@testable import GrammarFixerCore

/// Санитизация существует не для красоты. Дорогая модель возвращает чистый
/// текст и без неё, а дешёвая добавляет преамбулу и кавычки — то есть ломается
/// ровно та модель, ради возможности выбрать которую всё и затевалось.
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

    /// Модель повторяет якорь промпта — тот самый, который её же и сдерживает.
    func testRepeatedAnchorIsDroppedEvenOnTheSameLine() {
        XCTAssertEqual(clean("Rewritten text: Привет, как дела?"), "Привет, как дела?")
    }

    /// Строка с двоеточием бывает и настоящим текстом. Если она была во входе,
    /// значит это текст пользователя, а не болтовня модели.
    func testColonLineThatCameFromTheOriginalSurvives() {
        let original = "Задачи:\nкупить хлеб"
        XCTAssertEqual(clean("Задачи:\nкупить хлеб", original: original), "Задачи:\nкупить хлеб")
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

    /// Кавычки пользователя трогать нельзя: это его текст, а не обёртка модели.
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

    /// Ограждение внутри текста — это код пользователя, и он остаётся.
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

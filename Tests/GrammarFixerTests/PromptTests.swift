import XCTest
@testable import GrammarFixerCore

/// Шаблон промпта хранится целиком и не разрезается на системную и
/// пользовательскую части. Разрезание теряет завершающий якорь, а якорь делает
/// настоящую работу: именно он подавляет «Here is the corrected text:» у
/// слабых моделей.
final class PromptTests: XCTestCase {
    func testSelectionIsSubstituted() {
        let rendered = Prompt.default.render(selection: "привет как дела")
        XCTAssertTrue(rendered.contains("привет как дела"))
        XCTAssertFalse(rendered.contains("{selection}"))
    }

    func testAnchorClosesThePrompt() {
        XCTAssertTrue(Prompt.default.render(selection: "текст").hasSuffix("Rewritten text:"))
    }

    func testRulesThatTheTicketNamesAreStated() {
        let text = Prompt.default.render(selection: "текст")
        XCTAssertTrue(text.contains("original language"))
        XCTAssertTrue(text.contains("quotes"))
        XCTAssertTrue(text.contains("emojis"))
    }

    /// Фигурные скобки в тексте пользователя не должны обращаться в подстановку.
    func testBracesInTheSelectionAreNotTreatedAsPlaceholders() {
        let rendered = Prompt.default.render(selection: "код {selection} внутри")
        XCTAssertTrue(rendered.contains("код {selection} внутри"))
    }
}

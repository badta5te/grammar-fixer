import XCTest
@testable import GrammarFixerCore

/// The prompt template is kept whole and never split into a system and a user
/// half. Splitting loses the closing anchor, and the anchor does real work: it
/// is what suppresses "Here is the corrected text:" in weaker models.
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

    /// Braces in the person's own text must not turn into a substitution.
    func testBracesInTheSelectionAreNotTreatedAsPlaceholders() {
        let rendered = Prompt.default.render(selection: "код {selection} внутри")
        XCTAssertTrue(rendered.contains("код {selection} внутри"))
    }
}

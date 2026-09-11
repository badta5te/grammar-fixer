import XCTest
@testable import GrammarFixerCore

/// Разбор строки потока вынесен в чистую функцию ровно затем, чтобы все формы,
/// в которых OpenAI-совместимые серверы расходятся, проверялись таблицей, а не
/// живым запросом к провайдеру.
final class StreamChunkTests: XCTestCase {
    private func event(_ line: String) throws -> StreamEvent? {
        try StreamChunk.event(from: line)
    }

    func testContentDeltaIsRead() throws {
        let line = #"data: {"choices":[{"delta":{"content":"Привет"},"index":0}]}"#
        XCTAssertEqual(try event(line), .delta("Привет"))
    }

    /// Пробел после двоеточия ставят не все.
    func testDataWithoutSpaceIsRead() throws {
        let line = #"data:{"choices":[{"delta":{"content":"а"}}]}"#
        XCTAssertEqual(try event(line), .delta("а"))
    }

    func testDoneMarkerEndsTheStream() throws {
        XCTAssertEqual(try event("data: [DONE]"), .done)
    }

    func testBlankLinesAndCommentsAreIgnored() throws {
        XCTAssertNil(try event(""))
        XCTAssertNil(try event("   "))
        XCTAssertNil(try event(": keep-alive"))
        XCTAssertNil(try event("event: message"))
        XCTAssertNil(try event("id: 42"))
    }

    /// Последний кусок с расходом токенов приходит с пустым списком choices.
    /// Обращение к choices[0] здесь уронило бы приложение на ровном месте.
    func testUsageChunkHasNoChoices() throws {
        let line = #"data: {"choices":[],"usage":{"prompt_tokens":10,"completion_tokens":5,"total_tokens":15}}"#
        XCTAssertEqual(try event(line), .usage(TokenUsage(promptTokens: 10, completionTokens: 5)))
    }

    func testChunkWithEmptyDeltaIsIgnored() throws {
        XCTAssertNil(try event(#"data: {"choices":[{"delta":{},"finish_reason":"stop"}]}"#))
    }

    /// Рассуждающие модели шлют отдельное поле, которое в текст не идёт.
    func testReasoningContentIsNotMistakenForTheAnswer() throws {
        let line = #"data: {"choices":[{"delta":{"reasoning_content":"думаю"}}]}"#
        XCTAssertNil(try event(line))
    }

    func testErrorInTheMiddleOfTheStreamIsThrown() {
        let line = #"data: {"error":{"message":"Rate limit reached","type":"rate_limit_error"}}"#
        XCTAssertThrowsError(try event(line)) { error in
            guard case LLMError.providerRejected(let detail) = error else {
                return XCTFail("ожидалась ошибка провайдера, получено \(error)")
            }
            XCTAssertEqual(detail, "Rate limit reached")
        }
    }

    func testUnreadableChunkIsIgnoredRatherThanFatal() throws {
        XCTAssertNil(try event("data: {не json"))
    }
}

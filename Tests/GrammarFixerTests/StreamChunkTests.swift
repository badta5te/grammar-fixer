import XCTest
@testable import GrammarFixerCore

/// Parsing a stream line is a pure function for exactly one reason: so that
/// every shape OpenAI-compatible servers diverge in can be checked by a table
/// rather than by a live request to a provider.
final class StreamChunkTests: XCTestCase {
    private func event(_ line: String) throws -> StreamEvent? {
        try StreamChunk.event(from: line)
    }

    func testContentDeltaIsRead() throws {
        let line = #"data: {"choices":[{"delta":{"content":"Привет"},"index":0}]}"#
        XCTAssertEqual(try event(line), .delta("Привет"))
    }

    /// Not everyone puts a space after the colon.
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

    /// The final chunk carrying token usage arrives with an empty list of
    /// choices. Reaching for choices[0] here would crash the app for nothing.
    func testUsageChunkHasNoChoices() throws {
        let line = #"data: {"choices":[],"usage":{"prompt_tokens":10,"completion_tokens":5,"total_tokens":15}}"#
        XCTAssertEqual(try event(line), .usage(TokenUsage(promptTokens: 10, completionTokens: 5)))
    }

    func testChunkWithEmptyDeltaIsIgnored() throws {
        XCTAssertNil(try event(#"data: {"choices":[{"delta":{},"finish_reason":"stop"}]}"#))
    }

    /// Reasoning models send a separate field that does not belong in the
    /// text.
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

    /// The same danger on the other adapter. No ceiling is asked for here, but
    /// a provider has one of its own, and a half-written correction pasted over
    /// somebody's text is just as destructive whoever cut it short.
    func testAnAnswerCutShortByTheProviderIsRaisedRatherThanPassedOn() {
        let line = #"data: {"choices":[{"delta":{},"finish_reason":"length"}]}"#

        XCTAssertThrowsError(try StreamChunk.event(from: line)) { error in
            XCTAssertEqual(error as? LLMError, .answerTruncated)
        }
    }

    func testAnOrdinaryEndingIsNotMistakenForTruncation() throws {
        let line = #"data: {"choices":[{"delta":{},"finish_reason":"stop"}]}"#

        XCTAssertNil(try StreamChunk.event(from: line))
    }
}

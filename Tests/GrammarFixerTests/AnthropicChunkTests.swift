import XCTest
@testable import GrammarFixerCore

/// Anthropic's stream, one line at a time. Kept pure and apart from the client
/// for the same reason as the OpenAI one: this is where a provider's small
/// print lives, and checking small print against a live provider costs money
/// and depends on their uptime.
///
/// The payloads below are copied from Anthropic's own streaming documentation
/// rather than invented.
final class AnthropicChunkTests: XCTestCase {
    private func piece(_ line: String) throws -> AnthropicChunk.Piece? {
        try AnthropicChunk.piece(from: line)
    }

    func testTextArrivesInContentBlockDeltas() throws {
        let line = #"data: {"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"ello frien"}}"#

        XCTAssertEqual(try piece(line), .text("ello frien"))
    }

    /// A reasoning model's train of thought is not the answer. Pasting it into
    /// somebody's message instead of their corrected sentence is the worst
    /// thing this parser could do.
    func testThinkingIsNotPartOfTheAnswer() throws {
        let thinking = #"data: {"type":"content_block_delta","index":0,"delta":{"type":"thinking_delta","thinking":"Сначала подумаю"}}"#
        let signature = #"data: {"type":"content_block_delta","index":0,"delta":{"type":"signature_delta","signature":"EqQBCg"}}"#

        XCTAssertNil(try piece(thinking))
        XCTAssertNil(try piece(signature))
    }

    func testTheOpeningEventCarriesBothTokenCounts() throws {
        let line = #"data: {"type":"message_start","message":{"id":"msg_1","type":"message","role":"assistant","model":"claude-haiku-4-5-20251001","content":[],"stop_reason":null,"usage":{"input_tokens":25,"output_tokens":1}}}"#

        XCTAssertEqual(try piece(line), .usage(input: 25, output: 1))
    }

    /// The closing event reports only what was written, and says nothing about
    /// what was read. Whoever accumulates these has to keep the earlier number.
    func testTheClosingEventCarriesOnlyTheOutputCount() throws {
        let line = #"data: {"type":"message_delta","delta":{"stop_reason":"end_turn"},"usage":{"output_tokens":15}}"#

        XCTAssertEqual(try piece(line), .usage(input: nil, output: 15))
    }

    /// The ceiling on the answer is this app's own doing, so running into it is
    /// this app's problem to notice. An answer cut off mid-sentence would be
    /// sanitized like any other and pasted over the person's selection, eating
    /// the tail of their own text — the one outcome the whole round trip exists
    /// to prevent.
    func testAnAnswerCutOffByTheCeilingIsRaisedRatherThanPassedOn() {
        let line = #"data: {"type":"message_delta","delta":{"stop_reason":"max_tokens"},"usage":{"output_tokens":8192}}"#

        XCTAssertThrowsError(try piece(line)) { error in
            XCTAssertEqual(error as? LLMError, .answerTruncated)
        }
    }

    func testAnOrdinaryEndingIsNotMistakenForTruncation() throws {
        let line = #"data: {"type":"message_delta","delta":{"stop_reason":"end_turn"},"usage":{"output_tokens":15}}"#

        XCTAssertEqual(try piece(line), .usage(input: nil, output: 15))
    }

    func testTheStreamIsEndedByMessageStop() throws {
        XCTAssertEqual(try piece(#"data: {"type":"message_stop"}"#), .stop)
    }

    /// Keep-alives and block boundaries are not text and not the end.
    func testPingsAndBlockBoundariesAreNothing() throws {
        XCTAssertNil(try piece(#"data: {"type":"ping"}"#))
        XCTAssertNil(try piece(#"data: {"type":"content_block_start","index":0,"content_block":{"type":"text","text":""}}"#))
        XCTAssertNil(try piece(#"data: {"type":"content_block_stop","index":0}"#))
    }

    /// Anthropic sends an `event:` line before each `data:` line. Every payload
    /// names its own type, so the label is ignored and the transport stays the
    /// plain line reader both adapters share.
    func testTheEventLabelLineIsIgnored() throws {
        XCTAssertNil(try piece("event: content_block_delta"))
        XCTAssertNil(try piece(""))
    }

    /// A refusal can arrive in the middle of a stream that already started
    /// with HTTP 200. Swallowing it would leave the person with half a
    /// sentence and no explanation.
    func testAnErrorInTheMiddleOfTheStreamIsRaised() {
        let line = #"data: {"type":"error","error":{"type":"overloaded_error","message":"Overloaded"}}"#

        XCTAssertThrowsError(try piece(line)) { error in
            XCTAssertEqual(error as? LLMError, .providerRejected("Overloaded"))
        }
    }

    /// Anthropic's own versioning policy says new event types will appear and
    /// that a reader must live with them.
    func testAnUnknownEventTypeIsSkippedRatherThanFatal() throws {
        XCTAssertNil(try piece(#"data: {"type":"something_new_in_2027","field":1}"#))
    }

    func testAnUnreadableLineIsSkipped() throws {
        XCTAssertNil(try piece("data: {это не json"))
    }
}

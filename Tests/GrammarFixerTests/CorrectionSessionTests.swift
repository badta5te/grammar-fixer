import XCTest
@testable import GrammarFixerCore

/// A stream that is driven by hand. The whole point of the session is what the
/// person sees *while* the model is answering, and that cannot be checked
/// against a stream that is already complete.
@MainActor
final class ScriptedStream {
    private var continuation: AsyncThrowingStream<CorrectionEvent, any Error>.Continuation?
    private var pending: [(AsyncThrowingStream<CorrectionEvent, any Error>.Continuation) -> Void] = []
    private(set) var sources: [String] = []

    func make(_ source: String) -> AsyncThrowingStream<CorrectionEvent, any Error> {
        sources.append(source)
        return AsyncThrowingStream { continuation in
            self.continuation = continuation
            for step in self.pending { step(continuation) }
            self.pending = []
        }
    }

    func send(_ event: CorrectionEvent) { apply { $0.yield(event) } }
    func finish() { apply { $0.finish() } }
    func fail(_ error: any Error) { apply { $0.finish(throwing: error) } }

    /// The session subscribes from inside a task of its own, so a test cannot
    /// know it has happened yet. Anything sent early waits for the subscriber
    /// instead of vanishing, or the tests measure scheduling rather than
    /// behaviour.
    private func apply(_ step: @escaping (AsyncThrowingStream<CorrectionEvent, any Error>.Continuation) -> Void) {
        if let continuation {
            step(continuation)
        } else {
            pending.append(step)
        }
    }
}

@MainActor
final class CorrectionSessionTests: XCTestCase {
    private var stream: ScriptedStream!

    override func setUp() async throws {
        stream = ScriptedStream()
    }

    fileprivate func makeSession(source: String = "исходный текст") -> CorrectionSession {
        CorrectionSession(source: source, produce: { [stream] in stream!.make($0) })
    }

    /// Lets the session's task run: it lives outside the test's own flow.
    fileprivate func settle() async {
        for _ in 0..<50 { await Task.yield() }
    }

    /// A round takes seconds. Until the first piece arrives there is nothing to
    /// show, and the panel has to say so rather than stand empty.
    func testTheSessionWaitsUntilTheFirstPiece() async {
        let session = makeSession()
        session.start()
        await settle()

        XCTAssertEqual(session.state, .waiting)
        XCTAssertNil(session.result)
    }

    func testPiecesAccumulateAsTheyArrive() async {
        let session = makeSession()
        session.start()
        await settle()

        stream.send(.delta("Привет, "))
        await settle()
        XCTAssertEqual(session.state, .streaming("Привет, "))

        stream.send(.delta("как дела?"))
        await settle()
        XCTAssertEqual(session.state, .streaming("Привет, как дела?"))
    }

    /// Sanitizing needs the whole answer, so the text shown while streaming and
    /// the text that gets pasted are not always the same string. The finished
    /// answer wins: it is the one that leaves for somebody else's document.
    func testTheFinishedAnswerReplacesWhatWasStreamed() async {
        let session = makeSession()
        session.start()
        await settle()

        stream.send(.delta("\"Привет, как дела?\""))
        stream.send(.finished("Привет, как дела?"))
        stream.finish()
        await settle()

        XCTAssertEqual(session.state, .finished("Привет, как дела?"))
        XCTAssertEqual(session.result, "Привет, как дела?")
    }

    /// The footer names the model. A round that costs money should say who is
    /// being paid, especially right after the config was edited.
    func testTheModelNameIsRemembered() async {
        let session = makeSession()
        session.start()
        await settle()

        stream.send(.model("deepseek-flash"))
        await settle()

        XCTAssertEqual(session.model, "deepseek-flash")
    }

    /// The error belongs in the panel now, not in a separate window: the person
    /// is already looking at the panel, waiting for their text.
    func testAFailureBecomesSomethingToRead() async {
        let session = makeSession()
        session.start()
        await settle()

        stream.fail(LLMError.noConnection)
        await settle()

        XCTAssertEqual(
            session.state,
            .failed(title: LLMError.noConnection.title, message: LLMError.noConnection.message)
        )
        XCTAssertTrue(session.hasFailed)
        XCTAssertNil(session.result)
    }

    /// Retrying matters most exactly when it failed: the selection has already
    /// been captured, and losing it to a dropped connection would cost the
    /// person the whole round again.
    func testRetryingStartsTheRoundOver() async {
        let session = makeSession()
        session.start()
        await settle()
        stream.fail(LLMError.timedOut)
        await settle()
        XCTAssertTrue(session.hasFailed)

        session.start()
        await settle()
        XCTAssertEqual(session.state, .waiting)

        stream.send(.finished("Готово."))
        stream.finish()
        await settle()

        XCTAssertEqual(session.result, "Готово.")
        XCTAssertEqual(stream.sources, ["исходный текст", "исходный текст"])
    }

    /// A stream that ends without an answer must not leave the panel waiting
    /// forever. Silence here is the one outcome the round trip never allows.
    func testAStreamThatEndsWithNoAnswerIsAFailure() async {
        let session = makeSession()
        session.start()
        await settle()

        stream.send(.delta("кусок"))
        stream.finish()
        await settle()

        XCTAssertEqual(
            session.state,
            .failed(title: LLMError.emptyAnswer.title, message: LLMError.emptyAnswer.message)
        )
    }
}

/// Closing the panel is not a failure. A cancelled stream ends its loop without
/// throwing anything, so the difference between "nobody is waiting any more"
/// and "the model answered with nothing" has to be told apart on purpose.
extension CorrectionSessionTests {
    func testClosingThePanelIsNotAFailure() async {
        let session = makeSession()
        session.start()
        await settle()

        session.cancel()
        await settle()

        XCTAssertFalse(session.hasFailed)
        XCTAssertEqual(session.state, .waiting)
    }
}

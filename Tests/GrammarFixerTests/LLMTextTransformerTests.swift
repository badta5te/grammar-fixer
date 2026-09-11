import XCTest
@testable import GrammarFixerCore

/// The client is replaced whole: what is checked is that the answer is
/// assembled out of stream chunks, and that a refusal from the model reaches
/// the caller instead of turning into empty text.
final class FakeLLMClient: LLMClient, @unchecked Sendable {
    var events: [StreamEvent] = []
    var failure: (any Error)?
    private(set) var prompts: [String] = []

    func stream(prompt: String) -> AsyncThrowingStream<StreamEvent, any Error> {
        prompts.append(prompt)
        let events = events
        let failure = failure
        return AsyncThrowingStream { continuation in
            for event in events { continuation.yield(event) }
            continuation.finish(throwing: failure)
        }
    }
}

@MainActor
final class LLMTextTransformerTests: XCTestCase {
    private var client: FakeLLMClient!

    override func setUp() async throws {
        client = FakeLLMClient()
    }

    private func makeTransformer(
        configuration: @escaping () throws -> ProviderConfiguration = { .forTesting }
    ) -> LLMTextTransformer {
        LLMTextTransformer(
            loadConfiguration: configuration,
            makeClient: { [client] _ in client! }
        )
    }

    func testPiecesOfTheStreamAreJoinedIntoTheAnswer() async throws {
        client.events = [.delta("Привет, "), .delta("как дела?"), .done]

        let fixed = try await makeTransformer().transform("привет как дела")

        XCTAssertEqual(fixed, "Привет, как дела?")
    }

    func testTheSelectionGoesIntoThePrompt() async throws {
        client.events = [.delta("Готово"), .done]

        _ = try await makeTransformer().transform("исходный текст")

        XCTAssertTrue(client.prompts.first?.contains("исходный текст") == true)
        XCTAssertTrue(client.prompts.first?.hasSuffix("Rewritten text:") == true)
    }

    /// Sanitizing stands between the stream and the person's text, not beside
    /// it.
    func testTheAnswerIsSanitizedOnTheWayOut() async throws {
        client.events = [.delta("Вот исправленный текст:\n\"Привет, как дела?\""), .done]

        let fixed = try await makeTransformer().transform("привет как дела")

        XCTAssertEqual(fixed, "Привет, как дела?")
    }

    func testEmptyAnswerIsAnError() async {
        client.events = [.delta("   "), .done]

        await XCTAssertThrowsErrorAsync(try await makeTransformer().transform("текст")) { error in
            XCTAssertEqual(error as? LLMError, .emptyAnswer)
        }
    }

    func testProviderFailureReachesTheCaller() async {
        client.failure = LLMError.unauthorized(nil)

        await XCTAssertThrowsErrorAsync(try await makeTransformer().transform("текст")) { error in
            XCTAssertEqual(error as? LLMError, .unauthorized(nil))
        }
    }

    /// An unconfigured provider has to say so before the request, not after.
    func testMissingConfigurationStopsBeforeTheRequest() async {
        let transformer = makeTransformer(configuration: { throw LLMError.notConfigured })

        await XCTAssertThrowsErrorAsync(try await transformer.transform("текст")) { error in
            XCTAssertEqual(error as? LLMError, .notConfigured)
        }
        XCTAssertTrue(client.prompts.isEmpty)
    }
}

extension ProviderConfiguration {
    static let forTesting = ProviderConfiguration(
        model: "test-model",
        baseURL: URL(string: "https://example.com/v1")!,
        apiKey: "k",
        requestsUsage: true,
        reasoning: .off
    )
}

/// XCTAssertThrowsError cannot await an asynchronous expression.
@MainActor
func XCTAssertThrowsErrorAsync<T>(
    _ expression: @autoclosure () async throws -> T,
    file: StaticString = #filePath,
    line: UInt = #line,
    _ check: (any Error) -> Void
) async {
    do {
        _ = try await expression()
        XCTFail("expected a failure", file: file, line: line)
    } catch {
        check(error)
    }
}

/// The panel is the reason streaming exists at all, so what it receives is
/// worth its own test: a name to show and text arriving piece by piece.
@MainActor
final class LLMTextTransformerStreamTests: XCTestCase {
    func testThePanelSeesTheModelAndThePiecesAsTheyArrive() async throws {
        let client = FakeLLMClient()
        client.events = [.delta("Привет, "), .delta("как дела?"), .done]
        let transformer = LLMTextTransformer(
            loadConfiguration: { .forTesting },
            makeClient: { _ in client }
        )

        var received: [CorrectionEvent] = []
        for try await event in transformer.stream("привет как дела") {
            received.append(event)
        }

        XCTAssertEqual(received, [
            .model("test-model"),
            .delta("Привет, "),
            .delta("как дела?"),
            .finished("Привет, как дела?"),
        ])
    }

    /// The stream must end in a refusal rather than in an empty answer: an
    /// empty answer would be pasted over somebody's text.
    func testAFailureEndsTheStreamInsteadOfFinishingIt() async {
        let client = FakeLLMClient()
        client.failure = LLMError.rateLimited(nil)
        let transformer = LLMTextTransformer(
            loadConfiguration: { .forTesting },
            makeClient: { _ in client }
        )

        var received: [CorrectionEvent] = []
        do {
            for try await event in transformer.stream("текст") { received.append(event) }
            XCTFail("expected a failure")
        } catch {
            XCTAssertEqual(error as? LLMError, .rateLimited(nil))
        }
        XCTAssertEqual(received, [.model("test-model")])
    }
}

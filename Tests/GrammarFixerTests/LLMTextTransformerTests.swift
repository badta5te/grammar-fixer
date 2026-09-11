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

/// What the round costs is recorded where the round happens, because this is
/// the one place that knows both what was asked and what came back.
@MainActor
final class LLMTextTransformerBillingTests: XCTestCase {
    private var client: FakeLLMClient!
    private var recorded: [UsageRecord] = []

    override func setUp() async throws {
        client = FakeLLMClient()
        recorded = []
    }

    private func makeTransformer(
        configuration: @escaping () throws -> ProviderConfiguration = { .forTesting }
    ) -> LLMTextTransformer {
        LLMTextTransformer(
            loadConfiguration: configuration,
            makeClient: { [client] _ in client! },
            record: { [weak self] record in self?.recorded.append(record) }
        )
    }

    func testWhatTheProviderReportedIsWhatGoesOnTheRecord() async throws {
        client.events = [
            .delta("Привет, как дела?"),
            .usage(TokenUsage(promptTokens: 120, completionTokens: 30)),
            .done,
        ]

        _ = try await makeTransformer().transform("привет как дела")

        let record = try XCTUnwrap(recorded.first)
        XCTAssertEqual(record.promptTokens, 120)
        XCTAssertEqual(record.completionTokens, 30)
        XCTAssertFalse(record.isEstimated)
        XCTAssertEqual(record.model, "test-model")
        XCTAssertEqual(record.provider, ProviderConfiguration.forTesting.providerId)
    }

    /// A provider that reports nothing still charged for the round, and a
    /// round counted as free is the one figure that is certainly wrong.
    func testAProviderThatReportsNothingIsGuessedFromTheText() async throws {
        client.events = [.delta("Привет, как дела?"), .done]

        _ = try await makeTransformer().transform("привет как дела")

        let record = try XCTUnwrap(recorded.first)
        XCTAssertTrue(record.isEstimated)
        XCTAssertGreaterThan(record.completionTokens, 0)
        // The whole prompt is paid for, not just the selection inside it.
        XCTAssertGreaterThan(record.promptTokens, TokenEstimate.tokens(in: "привет как дела"))
    }

    /// Nothing was sent, so nothing was charged.
    func testARoundThatNeverLeftIsNotRecorded() async {
        let transformer = makeTransformer(configuration: { throw LLMError.notConfigured })

        await XCTAssertThrowsErrorAsync(try await transformer.transform("текст")) { _ in }

        XCTAssertTrue(recorded.isEmpty)
    }

    /// A refusal before a single token costs nothing and should not leave a
    /// row behind pretending otherwise.
    func testARefusalWithNoAnswerIsNotRecorded() async {
        client.failure = LLMError.unauthorized(nil)

        await XCTAssertThrowsErrorAsync(try await makeTransformer().transform("текст")) { _ in }

        XCTAssertTrue(recorded.isEmpty)
    }

    /// A stream that broke halfway had already generated text, and the
    /// provider bills for text it generated.
    func testAnAnswerThatBrokeOffHalfwayIsStillPaidFor() async {
        client.events = [.delta("Привет, ")]
        client.failure = LLMError.noConnection

        await XCTAssertThrowsErrorAsync(try await makeTransformer().transform("привет")) { _ in }

        XCTAssertEqual(recorded.count, 1)
        XCTAssertEqual(recorded.first?.isEstimated, true)
    }

    /// An answer that sanitized away to nothing was paid for, and paid for
    /// once. It is billed before it is refused, and the refusal must not put
    /// the same round through a second time.
    func testAnAnswerThatSanitizedToNothingIsPaidForExactlyOnce() async {
        client.events = [.delta("   "), .done]

        await XCTAssertThrowsErrorAsync(try await makeTransformer().transform("текст")) { error in
            XCTAssertEqual(error as? LLMError, .emptyAnswer)
        }

        XCTAssertEqual(recorded.count, 1)
    }

    /// Retrying after a failure is a second round and costs a second time.
    /// Rolling the two into one would understate exactly the month somebody is
    /// looking at the counter for.
    func testARetryIsRecordedAsARoundOfItsOwn() async throws {
        client.events = [.delta("Привет"), .done]
        let transformer = makeTransformer()

        _ = try await transformer.transform("привет")
        _ = try await transformer.transform("привет")

        XCTAssertEqual(recorded.count, 2)
    }
}

import XCTest
@testable import GrammarFixerCore

/// Клиент подменяется целиком: проверяется сборка ответа из кусков потока и
/// то, что отказ модели доходит наружу, а не превращается в пустой текст.
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

    /// Санитизация стоит между потоком и текстом пользователя, а не рядом.
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

    /// Ненастроенный провайдер обязан сказать об этом до запроса, а не после.
    func testMissingConfigurationStopsBeforeTheRequest() async {
        let transformer = makeTransformer(configuration: { throw LLMError.noConfiguration(path: "~/c.json") })

        await XCTAssertThrowsErrorAsync(try await transformer.transform("текст")) { error in
            XCTAssertEqual(error as? LLMError, .noConfiguration(path: "~/c.json"))
        }
        XCTAssertTrue(client.prompts.isEmpty)
    }
}

extension ProviderConfiguration {
    static let forTesting = ProviderConfiguration(
        model: "test-model",
        baseURL: URL(string: "https://example.com/v1")!,
        apiKey: "k",
        requestsUsage: true
    )
}

/// XCTAssertThrowsError не умеет ждать асинхронное выражение.
@MainActor
func XCTAssertThrowsErrorAsync<T>(
    _ expression: @autoclosure () async throws -> T,
    file: StaticString = #filePath,
    line: UInt = #line,
    _ check: (any Error) -> Void
) async {
    do {
        _ = try await expression()
        XCTFail("ожидалась ошибка", file: file, line: line)
    } catch {
        check(error)
    }
}

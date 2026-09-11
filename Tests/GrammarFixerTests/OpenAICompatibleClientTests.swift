import XCTest
@testable import GrammarFixerCore

/// Транспорт подменяется целиком: живой запрос к провайдеру в тестах — это
/// деньги, сеть и чужая доступность, а проверять надо своё поведение.
actor FakeTransport: HTTPLineStreaming {
    struct Answer {
        var status = 200
        var lines: [String] = []
        var failure: (any Error)?
    }

    private var answers: [Answer]
    private(set) var sent: [URLRequest] = []

    init(answers: [Answer]) {
        self.answers = answers
    }

    func send(_ request: URLRequest) async throws -> HTTPStream {
        sent.append(request)
        let answer = answers.isEmpty ? Answer() : answers.removeFirst()
        if let failure = answer.failure { throw failure }
        return HTTPStream(status: answer.status, lines: AsyncThrowingStream { continuation in
            for line in answer.lines { continuation.yield(line) }
            continuation.finish()
        })
    }

    /// Разбор тела остаётся снаружи: словарь с Any через границу актора не
    /// проходит, а Data проходит.
    func body(ofRequest index: Int) -> Data? { sent[index].httpBody }
}

private func json(_ data: Data?) -> [String: Any] {
    guard let data, let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    else { return [:] }
    return object
}

final class OpenAICompatibleClientTests: XCTestCase {
    private let configuration = ProviderConfiguration(
        model: "deepseek-chat",
        baseURL: URL(string: "https://api.deepseek.com/v1")!,
        apiKey: "secret-key",
        requestsUsage: true
    )

    private func collect(
        _ client: OpenAICompatibleClient
    ) async throws -> [StreamEvent] {
        var events: [StreamEvent] = []
        for try await event in client.stream(prompt: "исправь это") { events.append(event) }
        return events
    }

    private func makeClient(
        _ answers: [FakeTransport.Answer],
        configuration: ProviderConfiguration? = nil
    ) -> (OpenAICompatibleClient, FakeTransport) {
        let transport = FakeTransport(answers: answers)
        let client = OpenAICompatibleClient(
            configuration: configuration ?? self.configuration,
            transport: transport
        )
        return (client, transport)
    }

    func testRequestGoesToTheCompletionsEndpoint() async throws {
        let (client, transport) = makeClient([.init(lines: ["data: [DONE]"])])
        _ = try await collect(client)

        let request = await transport.sent[0]
        XCTAssertEqual(request.url?.absoluteString, "https://api.deepseek.com/v1/chat/completions")
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer secret-key")
    }

    /// Промпт уходит одним пользовательским сообщением. Системного нет
    /// намеренно: якорь живёт в конце шаблона и при разрезании теряется.
    func testPromptIsSentAsASingleUserMessage() async throws {
        let (client, transport) = makeClient([.init(lines: ["data: [DONE]"])])
        _ = try await collect(client)

        let body = json(await transport.body(ofRequest: 0))
        let messages = body["messages"] as? [[String: String]]
        XCTAssertEqual(messages?.count, 1)
        XCTAssertEqual(messages?.first?["role"], "user")
        XCTAssertEqual(messages?.first?["content"], "исправь это")
        XCTAssertEqual(body["model"] as? String, "deepseek-chat")
        XCTAssertEqual(body["stream"] as? Bool, true)
    }

    func testUsageIsRequestedWhenTheConfigurationAsksForIt() async throws {
        let (client, transport) = makeClient([.init(lines: ["data: [DONE]"])])
        _ = try await collect(client)

        let options = json(await transport.body(ofRequest: 0))["stream_options"] as? [String: Any]
        XCTAssertEqual(options?["include_usage"] as? Bool, true)
    }

    /// Просьбу о расходе токенов понимают не все OpenAI-совместимые серверы.
    /// Отказ из-за неё не должен оставлять человека без исправления.
    func testRejectedUsageOptionIsRetriedOnceWithoutIt() async throws {
        let (client, transport) = makeClient([
            .init(status: 400, lines: [#"{"error":{"message":"unknown field stream_options"}}"#]),
            .init(lines: [#"data: {"choices":[{"delta":{"content":"Готово"}}]}"#, "data: [DONE]"]),
        ])

        let events = try await collect(client)

        XCTAssertEqual(events, [.delta("Готово"), .done])
        let sent = await transport.sent.count
        XCTAssertEqual(sent, 2)
        let second = json(await transport.body(ofRequest: 1))
        XCTAssertNil(second["stream_options"])
    }

    func testRetryHappensOnlyOnce() async throws {
        let (client, transport) = makeClient([
            .init(status: 400, lines: [#"{"error":{"message":"bad model"}}"#]),
            .init(status: 400, lines: [#"{"error":{"message":"bad model"}}"#]),
        ])

        do {
            _ = try await collect(client)
            XCTFail("ожидался отказ провайдера")
        } catch {
            XCTAssertEqual(error as? LLMError, .providerRejected("bad model"))
        }
        let sent = await transport.sent.count
        XCTAssertEqual(sent, 2)
    }

    func testRefusedKeyIsNamedAsSuch() async throws {
        let (client, _) = makeClient([
            .init(status: 401, lines: [#"{"error":{"message":"Incorrect API key provided"}}"#]),
        ])

        do {
            _ = try await collect(client)
            XCTFail("ожидался отказ по ключу")
        } catch {
            XCTAssertEqual(error as? LLMError, .unauthorized("Incorrect API key provided"))
        }
    }

    func testThrottlingIsNamedAsSuch() async throws {
        let (client, _) = makeClient([.init(status: 429, lines: ["slow down"])])

        do {
            _ = try await collect(client)
            XCTFail("ожидалось ограничение частоты")
        } catch {
            XCTAssertEqual(error as? LLMError, .rateLimited("slow down"))
        }
    }

    func testProviderOutageKeepsTheStatus() async throws {
        let (client, _) = makeClient([.init(status: 503, lines: [""])])

        do {
            _ = try await collect(client)
            XCTFail("ожидалась недоступность провайдера")
        } catch {
            XCTAssertEqual(error as? LLMError, .providerUnavailable(status: 503, detail: nil))
        }
    }

    func testNetworkFailureBecomesAReadableError() async throws {
        let (client, _) = makeClient([
            .init(failure: URLError(.notConnectedToInternet)),
        ])

        do {
            _ = try await collect(client)
            XCTFail("ожидалась потеря связи")
        } catch {
            XCTAssertEqual(error as? LLMError, .noConnection)
        }
    }

    func testEventsArriveInOrderAndTheStreamStopsAtDone() async throws {
        let (client, _) = makeClient([.init(lines: [
            #"data: {"choices":[{"delta":{"content":"При"}}]}"#,
            ": keep-alive",
            #"data: {"choices":[{"delta":{"content":"вет"}}]}"#,
            #"data: {"choices":[],"usage":{"prompt_tokens":7,"completion_tokens":2}}"#,
            "data: [DONE]",
            #"data: {"choices":[{"delta":{"content":"лишнее"}}]}"#,
        ])])

        let events = try await collect(client)

        XCTAssertEqual(events, [
            .delta("При"),
            .delta("вет"),
            .usage(TokenUsage(promptTokens: 7, completionTokens: 2)),
            .done,
        ])
    }
}

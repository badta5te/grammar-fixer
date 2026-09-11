import XCTest
@testable import GrammarFixerCore

/// The transport is replaced whole: a live request to a provider costs money,
/// needs a network and depends on somebody else's uptime, while what is under
/// test is our own behaviour.
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

    /// Parsing the body stays outside: a dictionary of Any does not cross an
    /// actor boundary, while Data does.
    func body(ofRequest index: Int) -> Data? { sent[index].httpBody }
}

private func json(_ data: Data?) -> [String: Any] {
    guard let data, let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    else { return [:] }
    return object
}

final class OpenAICompatibleClientTests: XCTestCase {
    private var configuration = ProviderConfiguration(
        model: "deepseek-flash",
        baseURL: URL(string: "https://api.deepseek.com/v1")!,
        apiKey: "secret-key",
        requestsUsage: true,
        reasoning: .off
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

    /// The prompt goes out as a single user message. There is deliberately no
    /// system message: the anchor lives at the end of the template and is lost
    /// if the template is split.
    func testPromptIsSentAsASingleUserMessage() async throws {
        let (client, transport) = makeClient([.init(lines: ["data: [DONE]"])])
        _ = try await collect(client)

        let body = json(await transport.body(ofRequest: 0))
        let messages = body["messages"] as? [[String: String]]
        XCTAssertEqual(messages?.count, 1)
        XCTAssertEqual(messages?.first?["role"], "user")
        XCTAssertEqual(messages?.first?["content"], "исправь это")
        XCTAssertEqual(body["model"] as? String, "deepseek-flash")
        XCTAssertEqual(body["stream"] as? Bool, true)
    }

    func testUsageIsRequestedWhenTheConfigurationAsksForIt() async throws {
        let (client, transport) = makeClient([.init(lines: ["data: [DONE]"])])
        _ = try await collect(client)

        let options = json(await transport.body(ofRequest: 0))["stream_options"] as? [String: Any]
        XCTAssertEqual(options?["include_usage"] as? Bool, true)
    }

    /// Fixing spelling needs no deliberation, and a reasoning model spends
    /// both seconds and tokens on it: DeepSeek billed 2966 output tokens for a
    /// 205-character answer and took sixteen seconds.
    func testThinkingIsTurnedOffByDefault() async throws {
        let (client, transport) = makeClient([.init(lines: ["data: [DONE]"])])
        _ = try await collect(client)

        let body = json(await transport.body(ofRequest: 0))
        XCTAssertEqual(body["reasoning_effort"] as? String, "none")
    }

    func testThinkingIsLeftAloneWhenTheConfigurationAsksForIt() async throws {
        var thinking = configuration
        thinking.reasoning = ProviderConfiguration.Reasoning.providerDefault
        let (client, transport) = makeClient([.init(lines: ["data: [DONE]"])], configuration: thinking)
        _ = try await collect(client)

        let body = json(await transport.body(ofRequest: 0))
        XCTAssertNil(body["reasoning_effort"])
    }

    /// Not every OpenAI-compatible server understands the request for token
    /// usage. A refusal caused by it must not leave the person without a
    /// correction.
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
        XCTAssertNil(second["reasoning_effort"])
        XCTAssertEqual(second["model"] as? String, "deepseek-flash")
    }

    func testRetryHappensOnlyOnce() async throws {
        let (client, transport) = makeClient([
            .init(status: 400, lines: [#"{"error":{"message":"bad model"}}"#]),
            .init(status: 400, lines: [#"{"error":{"message":"bad model"}}"#]),
        ])

        do {
            _ = try await collect(client)
            XCTFail("expected the provider to refuse")
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
            XCTFail("expected the key to be refused")
        } catch {
            XCTAssertEqual(error as? LLMError, .unauthorized("Incorrect API key provided"))
        }
    }

    func testThrottlingIsNamedAsSuch() async throws {
        let (client, _) = makeClient([.init(status: 429, lines: ["slow down"])])

        do {
            _ = try await collect(client)
            XCTFail("expected to be rate limited")
        } catch {
            XCTAssertEqual(error as? LLMError, .rateLimited("slow down"))
        }
    }

    func testProviderOutageKeepsTheStatus() async throws {
        let (client, _) = makeClient([.init(status: 503, lines: [""])])

        do {
            _ = try await collect(client)
            XCTFail("expected the provider to be unavailable")
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
            XCTFail("expected a lost connection")
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

/// The list of models comes from the provider rather than from a list written
/// into this app. A name typed here goes stale the moment a provider renames
/// something, and they rename things far more often than this app is released.
final class OpenAICompatibleModelsTests: XCTestCase {
    private let configuration = ProviderConfiguration(
        model: "",
        baseURL: URL(string: "https://api.openai.com/v1")!,
        apiKey: "secret-key",
        requestsUsage: true,
        reasoning: .off
    )

    private func makeClient(_ answers: [FakeTransport.Answer]) -> (OpenAICompatibleClient, FakeTransport) {
        let transport = FakeTransport(answers: answers)
        return (OpenAICompatibleClient(configuration: configuration, transport: transport), transport)
    }

    func testTheListIsAskedForWithTheSameKeyAsACorrection() async throws {
        let (client, transport) = makeClient([.init(lines: [#"{"data":[]}"#])])
        _ = try await client.models()

        let request = await transport.sent[0]
        XCTAssertEqual(request.url?.absoluteString, "https://api.openai.com/v1/models")
        XCTAssertEqual(request.httpMethod, "GET")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer secret-key")
    }

    /// Newest first, because the reason somebody opens this list is that a new
    /// model came out.
    func testTheNewestModelsComeFirst() async throws {
        let (client, _) = makeClient([.init(lines: [#"""
            {"data":[{"id":"older","created":1000},{"id":"newer","created":3000},{"id":"middling","created":2000}]}
            """#])])

        let models = try await client.models()

        XCTAssertEqual(models, ["newer", "middling", "older"])
    }

    /// A list without timestamps still has to come back in an order somebody
    /// can look things up in.
    func testWithoutTimestampsTheListIsAlphabetical() async throws {
        let (client, _) = makeClient([.init(lines: [#"{"data":[{"id":"second"},{"id":"first"}]}"#])])

        let models = try await client.models()

        XCTAssertEqual(models, ["first", "second"])
    }

    /// OpenAI answers this question with everything it sells, most of which
    /// cannot correct a sentence. A list where the text models are buried is a
    /// list nobody reads.
    func testModelsThatCannotWriteTextAreLeftOut() async throws {
        let (client, _) = makeClient([.init(lines: [#"""
            {"data":[{"id":"gpt-4o"},{"id":"whisper-1"},{"id":"tts-1-hd"},
            {"id":"dall-e-3"},{"id":"text-embedding-3-small"},{"id":"omni-moderation-latest"},
            {"id":"gpt-4o-audio-preview"},{"id":"sora-2"}]}
            """#])])

        let models = try await client.models()

        XCTAssertEqual(models, ["gpt-4o"])
    }

    /// OpenRouter answers with several hundred. A menu of several hundred is
    /// not a menu, and the field beside it is still free to type in.
    func testAVeryLongListIsCutToTheNewest() async throws {
        let many = (1...200).map { #"{"id":"model-\#($0)","created":\#($0)}"# }.joined(separator: ",")
        let (client, _) = makeClient([.init(lines: ["{\"data\":[\(many)]}"])])

        let models = try await client.models()

        XCTAssertEqual(models.count, 50)
        XCTAssertEqual(models.first, "model-200")
    }

    func testARefusedKeyIsNamedRatherThanShownAsAnEmptyList() async {
        let (client, _) = makeClient([
            .init(status: 401, lines: [#"{"error":{"message":"Incorrect API key provided"}}"#]),
        ])

        do {
            _ = try await client.models()
            XCTFail("expected the key to be refused")
        } catch {
            XCTAssertEqual(error as? LLMError, .unauthorized("Incorrect API key provided"))
        }
    }

    /// A local server need not implement this at all, and that is not a broken
    /// key. The field stays free to type in either way.
    func testAServerWithoutSuchAListSaysSoRatherThanLooksEmpty() async {
        let (client, _) = makeClient([.init(status: 404, lines: ["not found"])])

        do {
            _ = try await client.models()
            XCTFail("expected a refusal")
        } catch {
            XCTAssertEqual(error as? LLMError, .providerRejected("not found"))
        }
    }

    func testAnAnswerThatIsNotAListIsNotReadAsAnEmptyOne() async {
        let (client, _) = makeClient([.init(lines: ["это не json"])])

        do {
            _ = try await client.models()
            XCTFail("expected a refusal")
        } catch {
            XCTAssertEqual(error as? LLMError, .modelsUnreadable)
        }
    }
}

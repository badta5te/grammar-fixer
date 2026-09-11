import XCTest
@testable import GrammarFixerCore

private func body(_ data: Data?) -> [String: Any] {
    guard let data, let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    else { return [:] }
    return object
}

/// The second adapter. It exists because Anthropic differs from everyone else
/// in four ways at once: another path, another authorisation header, a
/// mandatory limit on the answer, and token counts split across two events.
final class AnthropicClientTests: XCTestCase {
    private let configuration = ProviderConfiguration(
        model: "claude-haiku-4-5-20251001",
        baseURL: URL(string: "https://api.anthropic.com/v1")!,
        apiKey: "secret-key",
        requestsUsage: true,
        reasoning: .off,
        kind: .anthropic
    )

    private func makeClient(_ answers: [FakeTransport.Answer]) -> (AnthropicClient, FakeTransport) {
        let transport = FakeTransport(answers: answers)
        return (AnthropicClient(configuration: configuration, transport: transport), transport)
    }

    private func collect(_ client: AnthropicClient, prompt: String = "исправь это") async throws -> [StreamEvent] {
        var events: [StreamEvent] = []
        for try await event in client.stream(prompt: prompt) { events.append(event) }
        return events
    }

    private let stop = #"data: {"type":"message_stop"}"#

    func testRequestGoesToTheMessagesEndpointWithAnthropicsOwnHeaders() async throws {
        let (client, transport) = makeClient([.init(lines: [stop])])
        _ = try await collect(client)

        let request = await transport.sent[0]
        XCTAssertEqual(request.url?.absoluteString, "https://api.anthropic.com/v1/messages")
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.value(forHTTPHeaderField: "x-api-key"), "secret-key")
        XCTAssertEqual(request.value(forHTTPHeaderField: "anthropic-version"), "2023-06-01")
        // Anthropic ignores a bearer token, so sending one would only be one
        // more place the key travels for no reason.
        XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"))
    }

    /// The same decision as for every other provider: the prompt stays whole
    /// and the system field is left empty. The closing anchor lives at the end
    /// of the template and splitting the template loses it.
    func testThePromptStaysWholeInASingleUserMessage() async throws {
        let (client, transport) = makeClient([.init(lines: [stop])])
        _ = try await collect(client)

        let sent = body(await transport.body(ofRequest: 0))
        let messages = sent["messages"] as? [[String: String]]
        XCTAssertEqual(messages?.count, 1)
        XCTAssertEqual(messages?.first?["role"], "user")
        XCTAssertEqual(messages?.first?["content"], "исправь это")
        XCTAssertNil(sent["system"])
        XCTAssertEqual(sent["model"] as? String, "claude-haiku-4-5-20251001")
        XCTAssertEqual(sent["stream"] as? Bool, true)
    }

    /// Anthropic refuses a request without a ceiling on the answer, so unlike
    /// every other field this one cannot be left out and cannot be dropped on
    /// a retry.
    func testTheAnswerIsGivenACeilingLargeEnoughForTheText() async throws {
        let (client, transport) = makeClient([.init(lines: [stop]), .init(lines: [stop])])

        _ = try await collect(client, prompt: "коротко")
        let short = body(await transport.body(ofRequest: 0))["max_tokens"] as? Int
        XCTAssertEqual(short, 1024, "a short text gets the floor")

        _ = try await collect(client, prompt: String(repeating: "текст ", count: 3000))
        let long = body(await transport.body(ofRequest: 1))["max_tokens"] as? Int
        XCTAssertGreaterThan(long ?? 0, 1024, "a long text must not be cut off by the floor")
        XCTAssertLessThanOrEqual(long ?? .max, 8192, "the ceiling must not go above what a model accepts")
    }

    func testTextArrivesInOrderAndTheStreamStopsAtMessageStop() async throws {
        let (client, _) = makeClient([.init(lines: [
            "event: content_block_delta",
            #"data: {"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"При"}}"#,
            #"data: {"type":"ping"}"#,
            #"data: {"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"вет"}}"#,
            stop,
            #"data: {"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"лишнее"}}"#,
        ])])

        let events = try await collect(client)

        XCTAssertEqual(events, [.delta("При"), .delta("вет"), .done])
    }

    /// The counts come in two events: how much was read at the start, how much
    /// was written at the end. Passing them on as they arrive would leave the
    /// spending counter with the last one only, and the input count zeroed.
    func testTheTwoHalvesOfTheTokenCountAreAddedUp() async throws {
        let (client, _) = makeClient([.init(lines: [
            #"data: {"type":"message_start","message":{"usage":{"input_tokens":25,"output_tokens":1}}}"#,
            #"data: {"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"Привет"}}"#,
            #"data: {"type":"message_delta","delta":{"stop_reason":"end_turn"},"usage":{"output_tokens":15}}"#,
            stop,
        ])])

        let events = try await collect(client)

        XCTAssertEqual(events, [
            .delta("Привет"),
            .usage(TokenUsage(promptTokens: 25, completionTokens: 15)),
            .done,
        ])
    }

    /// A provider that reported nothing must not be recorded as having cost
    /// nothing: that is a lie the spending counter would repeat.
    func testNoReportedUsageMeansNoUsageEvent() async throws {
        let (client, _) = makeClient([.init(lines: [
            #"data: {"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"Привет"}}"#,
            stop,
        ])])

        let events = try await collect(client)

        XCTAssertEqual(events, [.delta("Привет"), .done])
    }

    /// A stream that ends without its closing event still has to hand over
    /// what did arrive.
    func testAStreamCutShortStillReportsWhatArrived() async throws {
        let (client, _) = makeClient([.init(lines: [
            #"data: {"type":"message_start","message":{"usage":{"input_tokens":25,"output_tokens":1}}}"#,
            #"data: {"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"Приве"}}"#,
        ])])

        let events = try await collect(client)

        XCTAssertEqual(events, [
            .delta("Приве"),
            .usage(TokenUsage(promptTokens: 25, completionTokens: 1)),
            .done,
        ])
    }

    func testRefusedKeyIsNamedAsSuch() async throws {
        let (client, _) = makeClient([
            .init(status: 401, lines: [#"{"type":"error","error":{"type":"authentication_error","message":"invalid x-api-key"}}"#]),
        ])

        do {
            _ = try await collect(client)
            XCTFail("expected the key to be refused")
        } catch {
            XCTAssertEqual(error as? LLMError, .unauthorized("invalid x-api-key"))
        }
    }

    /// A wrong model name is refused after the response has already begun with
    /// HTTP 200 often enough to be worth its own path.
    func testAnErrorInTheMiddleOfTheStreamReachesTheCaller() async throws {
        let (client, _) = makeClient([.init(lines: [
            #"data: {"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"При"}}"#,
            #"data: {"type":"error","error":{"type":"overloaded_error","message":"Overloaded"}}"#,
        ])])

        do {
            _ = try await collect(client)
            XCTFail("expected the provider to refuse")
        } catch {
            XCTAssertEqual(error as? LLMError, .providerRejected("Overloaded"))
        }
    }

    func testNetworkFailureBecomesAReadableError() async throws {
        let (client, _) = makeClient([.init(failure: URLError(.notConnectedToInternet))])

        do {
            _ = try await collect(client)
            XCTFail("expected a lost connection")
        } catch {
            XCTAssertEqual(error as? LLMError, .noConnection)
        }
    }

    /// There is nothing optional in this request to strip, so the retry the
    /// OpenAI adapter performs would only cost a second refusal here.
    func testARefusalIsNotRetried() async throws {
        let (client, transport) = makeClient([
            .init(status: 400, lines: [#"{"type":"error","error":{"message":"bad model"}}"#]),
        ])

        _ = try? await collect(client)

        let sent = await transport.sent.count
        XCTAssertEqual(sent, 1)
    }
}

/// Anthropic lists its models at a path of its own, with the same headers as a
/// correction and a timestamp in another format.
final class AnthropicModelsTests: XCTestCase {
    private let configuration = ProviderConfiguration(
        model: "",
        baseURL: URL(string: "https://api.anthropic.com/v1")!,
        apiKey: "secret-key",
        requestsUsage: true,
        reasoning: .off,
        kind: .anthropic
    )

    private func makeClient(_ answers: [FakeTransport.Answer]) -> (AnthropicClient, FakeTransport) {
        let transport = FakeTransport(answers: answers)
        return (AnthropicClient(configuration: configuration, transport: transport), transport)
    }

    func testTheListIsAskedForWithAnthropicsOwnHeaders() async throws {
        let (client, transport) = makeClient([.init(lines: [#"{"data":[]}"#])])
        _ = try await client.models()

        let request = await transport.sent[0]
        XCTAssertEqual(request.url?.absoluteString, "https://api.anthropic.com/v1/models")
        XCTAssertEqual(request.httpMethod, "GET")
        XCTAssertEqual(request.value(forHTTPHeaderField: "x-api-key"), "secret-key")
        XCTAssertEqual(request.value(forHTTPHeaderField: "anthropic-version"), "2023-06-01")
    }

    func testTheNewestModelsComeFirst() async throws {
        let (client, _) = makeClient([.init(lines: [#"""
            {"data":[
              {"type":"model","id":"claude-older","display_name":"Old","created_at":"2024-02-29T00:00:00Z"},
              {"type":"model","id":"claude-newer","display_name":"New","created_at":"2025-10-01T00:00:00Z"}
            ],"has_more":false}
            """#])])

        let models = try await client.models()

        XCTAssertEqual(models, ["claude-newer", "claude-older"])
    }

    func testARefusedKeyIsNamedRatherThanShownAsAnEmptyList() async {
        let (client, _) = makeClient([
            .init(status: 401, lines: [#"{"type":"error","error":{"message":"invalid x-api-key"}}"#]),
        ])

        do {
            _ = try await client.models()
            XCTFail("expected the key to be refused")
        } catch {
            XCTAssertEqual(error as? LLMError, .unauthorized("invalid x-api-key"))
        }
    }
}

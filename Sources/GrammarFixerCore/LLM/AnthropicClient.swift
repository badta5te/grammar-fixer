import Foundation

/// A client for Anthropic's `/v1/messages`.
///
/// The second adapter, and the only one. Anthropic differs from the
/// OpenAI-compatible crowd in four ways at once: another path, a key in a
/// header of its own, a mandatory ceiling on the answer, and token counts split
/// across two events. Any one of those could have been patched into the other
/// client; all four together are a different protocol.
public struct AnthropicClient: LLMClient, ModelListing {
    /// Anthropic dates its API rather than numbering it, and the date is
    /// mandatory. This value is the one their current documentation sends.
    static let version = "2023-06-01"

    /// The ceiling on the answer, in tokens.
    ///
    /// The floor covers an ordinary sentence with room to spare. Above it the
    /// ceiling follows the length of the request, because a correction comes
    /// back about as long as the text that went in: roughly 0.4 tokens per
    /// character for Cyrillic, doubled so that a long selection is never cut
    /// off mid-word. The cap is what current models accept in one answer.
    static func ceiling(forPromptOf characters: Int) -> Int {
        min(8192, max(1024, Int(Double(characters) * 0.8)))
    }

    private let configuration: ProviderConfiguration
    private let transport: any HTTPLineStreaming
    private let timeout: TimeInterval

    public init(
        configuration: ProviderConfiguration,
        transport: any HTTPLineStreaming,
        timeout: TimeInterval = 30
    ) {
        self.configuration = configuration
        self.transport = transport
        self.timeout = timeout
    }

    public func stream(prompt: String) -> AsyncThrowingStream<StreamEvent, any Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let response = try await transport.send(request(prompt: prompt))
                    guard (200..<300).contains(response.status) else {
                        throw LLMError.from(status: response.status, body: await body(of: response))
                    }

                    // Both halves of the count are kept until the end and
                    // handed over together. Passing each on as it arrives
                    // would leave whoever records them with the last one only,
                    // and the input count zeroed.
                    var input: Int?
                    var output: Int?

                    for try await line in response.lines {
                        switch try AnthropicChunk.piece(from: line) {
                        case .text(let text):
                            continuation.yield(.delta(text))
                        case .usage(let readTokens, let writtenTokens):
                            // Each count is cumulative and only reported when
                            // it changes, so a nil means "as before" rather
                            // than "none".
                            input = readTokens ?? input
                            output = writtenTokens ?? output
                        case .stop:
                            // Anything after the closing event is not part of
                            // the answer, and appending it would append it to
                            // somebody's text.
                            finish(continuation, input: input, output: output)
                            return
                        case nil:
                            continue
                        }
                    }

                    // A stream can end without its closing event. What did
                    // arrive is still the answer.
                    finish(continuation, input: input, output: output)
                } catch {
                    continuation.finish(throwing: LLMError.from(error))
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// A provider that reported nothing is not a provider that cost nothing, so
    /// an absent count is passed on as absent rather than as zero.
    private func finish(
        _ continuation: AsyncThrowingStream<StreamEvent, any Error>.Continuation,
        input: Int?,
        output: Int?
    ) {
        if input != nil || output != nil {
            continuation.yield(.usage(TokenUsage(
                promptTokens: input ?? 0,
                completionTokens: output ?? 0
            )))
        }
        continuation.yield(.done)
        continuation.finish()
    }

    /// The models this provider has, newest first.
    public func models() async throws -> [String] {
        do {
            var request = URLRequest(
                url: configuration.baseURL.appending(path: "models"),
                timeoutInterval: timeout
            )
            request.setValue(configuration.apiKey, forHTTPHeaderField: "x-api-key")
            request.setValue(Self.version, forHTTPHeaderField: "anthropic-version")

            let response = try await transport.send(request)
            guard (200..<300).contains(response.status) else {
                throw LLMError.from(status: response.status, body: await body(of: response))
            }
            return try ModelCatalog.parse(await ModelCatalog.body(of: response))
        } catch {
            throw LLMError.from(error)
        }
    }

    /// There is nothing optional in this request. The OpenAI adapter can drop
    /// a field and try again; here `max_tokens` is mandatory, so a refusal is
    /// a refusal and a second attempt would only cost another one.
    private func request(prompt: String) -> URLRequest {
        var request = URLRequest(
            url: configuration.baseURL.appending(path: "messages"),
            timeoutInterval: timeout
        )
        request.httpMethod = "POST"
        request.setValue(configuration.apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue(Self.version, forHTTPHeaderField: "anthropic-version")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")

        // No `system` field on purpose, as with every other provider: the
        // prompt is one piece and its closing anchor is what stops a model
        // from writing "Here is the corrected text:".
        //
        // Nothing is sent about deliberation either. These models do not think
        // before answering unless asked to, and this app never asks.
        request.httpBody = try? JSONSerialization.data(withJSONObject: [
            "model": configuration.model,
            "stream": true,
            "max_tokens": Self.ceiling(forPromptOf: prompt.count),
            "messages": [["role": "user", "content": prompt]],
        ])
        return request
    }

    private func body(of response: HTTPStream) async -> String {
        var collected: [String] = []
        var length = 0
        do {
            for try await line in response.lines {
                collected.append(line)
                length += line.count
                if collected.count >= 20 || length >= 2000 { break }
            }
        } catch {
            // A truncated error body is no reason to lose the status code.
        }
        return collected.joined(separator: "\n")
    }
}

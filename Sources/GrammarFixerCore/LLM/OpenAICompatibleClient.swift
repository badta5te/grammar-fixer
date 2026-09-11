import Foundation

/// A client for `/chat/completions`. One path covers OpenAI, DeepSeek,
/// OpenRouter, Groq and local servers. What differs between them is not the
/// protocol but the small print, and the small print is handled here.
public struct OpenAICompatibleClient: LLMClient {
    private let configuration: ProviderConfiguration
    private let transport: any HTTPLineStreaming
    private let timeout: TimeInterval

    /// Thirty seconds is enough for any model to write a couple of paragraphs.
    /// URLSession's default of sixty will not do: the round trip holds the
    /// shortcut busy, and a minute of silence is indistinguishable from a
    /// broken app.
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
                    let response = try await open(prompt: prompt)
                    for try await line in response.lines {
                        guard let event = try StreamChunk.event(from: line) else { continue }
                        continuation.yield(event)
                        // Some servers add more lines after [DONE]. Reading
                        // them means appending junk to the person's text.
                        if event == .done { break }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: LLMError.from(error))
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private func open(prompt: String) async throws -> HTTPStream {
        var response = try await transport.send(request(prompt: prompt, includeUsage: configuration.requestsUsage))

        // Not every server understands the request for token usage, and some
        // refuse the whole call because of it. One retry without it is cheaper
        // than leaving the person without a correction for the sake of a
        // spending counter that does not exist yet.
        if response.status == 400 && configuration.requestsUsage {
            response = try await transport.send(request(prompt: prompt, includeUsage: false))
        }

        guard (200..<300).contains(response.status) else {
            throw LLMError.from(status: response.status, body: await body(of: response))
        }
        return response
    }

    private func request(prompt: String, includeUsage: Bool) -> URLRequest {
        var request = URLRequest(
            url: configuration.baseURL.appending(path: "chat/completions"),
            timeoutInterval: timeout
        )
        request.httpMethod = "POST"
        request.setValue("Bearer \(configuration.apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")

        var body: [String: Any] = [
            "model": configuration.model,
            "stream": true,
            "messages": [["role": "user", "content": prompt]],
        ]
        if includeUsage {
            body["stream_options"] = ["include_usage": true]
        }
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        return request
    }

    /// The body of a failed response. Without it the person gets a status code
    /// and nothing they could fix.
    private func body(of response: HTTPStream) async -> String {
        var collected: [String] = []
        var length = 0
        do {
            for try await line in response.lines {
                collected.append(line)
                length += line.count
                // An error body can be a stream too. There is no reason to
                // read all of it.
                if collected.count >= 20 || length >= 2000 { break }
            }
        } catch {
            // An error body that breaks off is no reason to lose the status
            // code itself.
        }
        return collected.joined(separator: "\n")
    }
}

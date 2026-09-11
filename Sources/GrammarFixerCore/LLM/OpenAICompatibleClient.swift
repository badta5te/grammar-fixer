import Foundation

/// A client for `/chat/completions`. One path covers OpenAI, DeepSeek,
/// OpenRouter, Groq and local servers. What differs between them is not the
/// protocol but the small print, and the small print is handled here.
public struct OpenAICompatibleClient: LLMClient, ModelListing {
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

    /// The models this provider has, newest first.
    public func models() async throws -> [String] {
        do {
            var request = URLRequest(
                url: configuration.baseURL.appending(path: "models"),
                timeoutInterval: timeout
            )
            request.setValue("Bearer \(configuration.apiKey)", forHTTPHeaderField: "Authorization")

            let response = try await transport.send(request)
            guard (200..<300).contains(response.status) else {
                throw LLMError.from(status: response.status, body: await body(of: response))
            }
            return try ModelCatalog.parse(await ModelCatalog.body(of: response))
        } catch {
            throw LLMError.from(error)
        }
    }

    private func open(prompt: String) async throws -> HTTPStream {
        var response = try await transport.send(request(prompt: prompt, withExtras: true))

        // The optional parts of the request are the parts servers disagree
        // about: asking for token usage, asking the model not to deliberate.
        // Some refuse the whole call because of one of them. A single retry
        // with the bare request is cheaper than leaving the person without a
        // correction for the sake of a setting.
        if response.status == 400 && hasExtras {
            await MainActor.run { Log.write("провайдер отказал с 400, повтор без необязательных полей") }
            response = try await transport.send(request(prompt: prompt, withExtras: false))
        }

        guard (200..<300).contains(response.status) else {
            throw LLMError.from(status: response.status, body: await body(of: response))
        }
        return response
    }

    /// Whether the request carries anything a server might refuse.
    private var hasExtras: Bool {
        configuration.requestsUsage || configuration.reasoning == .off
    }

    private func request(prompt: String, withExtras extras: Bool) -> URLRequest {
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
        if extras, configuration.requestsUsage {
            body["stream_options"] = ["include_usage": true]
        }
        if extras, configuration.reasoning == .off {
            body["reasoning_effort"] = "none"
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

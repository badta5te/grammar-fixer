import Foundation

/// Клиент к `/chat/completions`. Один путь покрывает OpenAI, DeepSeek,
/// OpenRouter, Groq и локальные серверы — расходится у них не протокол, а
/// мелочи, и мелочи разобраны здесь.
public struct OpenAICompatibleClient: LLMClient {
    private let configuration: ProviderConfiguration
    private let transport: any HTTPLineStreaming
    private let timeout: TimeInterval

    /// Тридцати секунд хватает любой модели на пару абзацев. Шестьдесят секунд
    /// по умолчанию от URLSession здесь не годятся: круг держит хоткей занятым,
    /// и минута молчания неотличима от поломки.
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
                        // После [DONE] сервер иногда добавляет ещё строки.
                        // Читать их — значит дописывать в текст лишнее.
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

        // Просьбу о расходе токенов понимают не все серверы, и отвечают на неё
        // отказом всего запроса. Один повтор без неё дешевле, чем оставить
        // человека без исправления ради будущего счётчика расходов.
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

    /// Тело ответа с ошибкой. Без него человек получает один код и ничего,
    /// что можно исправить.
    private func body(of response: HTTPStream) async -> String {
        var collected: [String] = []
        var length = 0
        do {
            for try await line in response.lines {
                collected.append(line)
                length += line.count
                // Тело ошибки бывает и потоком. Читать его целиком незачем.
                if collected.count >= 20 || length >= 2000 { break }
            }
        } catch {
            // Оборвавшееся тело ошибки — не повод потерять сам код ответа.
        }
        return collected.joined(separator: "\n")
    }
}

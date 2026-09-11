import Foundation

/// Разбор одной строки Server-Sent Events. Вынесен отдельно и чистым, потому
/// что расходятся серверы именно здесь: пробел после `data:`, комментарии для
/// поддержания соединения, кусок расхода токенов с пустым списком choices.
/// Проверять это живым запросом к провайдеру дорого и ненадёжно.
enum StreamChunk {
    static func event(from line: String) throws -> StreamEvent? {
        let line = line.trimmed
        guard line.hasPrefix("data:") else { return nil }

        let payload = String(line.dropFirst("data:".count)).trimmed
        guard !payload.isEmpty else { return nil }
        if payload == "[DONE]" { return .done }

        guard let data = payload.data(using: .utf8),
              let chunk = try? JSONDecoder().decode(Chunk.self, from: data)
        else {
            // Нечитаемый кусок — не повод рушить круг: если ответа так и не
            // будет, клиент скажет об этом сам, увидев пустой результат.
            return nil
        }

        if let error = chunk.error {
            throw LLMError.providerRejected(error.message)
        }

        // Текст идёт первым: сервер, шлющий расход вместе с последним куском
        // текста, отдаёт в нём пустую строку, так что порядок ничего не теряет.
        if let content = chunk.choices?.first?.delta?.content, !content.isEmpty {
            return .delta(content)
        }

        if let usage = chunk.usage {
            return .usage(TokenUsage(
                promptTokens: usage.promptTokens ?? 0,
                completionTokens: usage.completionTokens ?? 0
            ))
        }

        return nil
    }

    private struct Chunk: Decodable {
        let choices: [Choice]?
        let usage: Usage?
        let error: ProviderErrorBody?

        struct Choice: Decodable {
            let delta: Delta?
        }

        /// Рассуждающие модели кладут ход мысли в отдельное поле. Сюда оно не
        /// попадает намеренно: в текст пользователя оно не идёт.
        struct Delta: Decodable {
            let content: String?
        }

        struct Usage: Decodable {
            let promptTokens: Int?
            let completionTokens: Int?

            enum CodingKeys: String, CodingKey {
                case promptTokens = "prompt_tokens"
                case completionTokens = "completion_tokens"
            }
        }
    }
}

/// Тело ошибки провайдера. Одни серверы кладут в `error` объект с полем
/// `message`, другие — просто строку.
struct ProviderErrorBody: Decodable {
    let message: String?

    init(from decoder: any Decoder) throws {
        if let single = try? decoder.singleValueContainer(),
           let text = try? single.decode(String.self) {
            message = text
            return
        }
        let container = try decoder.container(keyedBy: CodingKeys.self)
        message = try? container.decode(String.self, forKey: .message)
    }

    private enum CodingKeys: String, CodingKey { case message }

    /// Достаёт человеческое описание из тела ответа с ошибкой.
    static func message(fromBody body: String) -> String? {
        guard let data = body.data(using: .utf8) else { return nil }
        struct Envelope: Decodable { let error: ProviderErrorBody? }
        if let envelope = try? JSONDecoder().decode(Envelope.self, from: data),
           let message = envelope.error?.message, !message.trimmed.isEmpty {
            return message.trimmed
        }
        let trimmed = body.trimmed
        return trimmed.isEmpty ? nil : String(trimmed.prefix(200))
    }
}

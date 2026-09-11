import Foundation

/// Parsing a single Server-Sent Events line. Kept separate and pure because
/// this is exactly where servers diverge: the space after `data:`, keep-alive
/// comments, the token usage chunk with an empty list of choices. Checking that
/// against a live provider is expensive and unreliable.
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
            // An unreadable chunk is no reason to tear down the round trip.
            // If no answer arrives at all, the caller says so on seeing an
            // empty result.
            return nil
        }

        if let error = chunk.error {
            throw LLMError.providerRejected(error.message)
        }

        // Text comes first: a server that sends usage together with the last
        // chunk of text puts an empty string in it, so this order loses
        // nothing.
        if let content = chunk.choices?.first?.delta?.content, !content.isEmpty {
            return .delta(content)
        }

        // No ceiling is asked for here, but a provider has one of its own, and
        // a correction cut short is just as destructive whoever cut it.
        if chunk.choices?.first?.finishReason == "length" { throw LLMError.answerTruncated }

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
            let finishReason: String?

            enum CodingKeys: String, CodingKey {
                case delta
                case finishReason = "finish_reason"
            }
        }

        /// Reasoning models put their train of thought in a separate field.
        /// It is deliberately absent here: it does not belong in the answer.
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

/// A provider's error body. Some servers put an object with a `message` field
/// in `error`, others just a string.
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

    /// Digs a human description out of a failed response body.
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

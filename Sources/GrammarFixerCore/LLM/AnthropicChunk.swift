import Foundation

/// Parsing one line of Anthropic's stream.
///
/// Only the `data:` lines are read. Anthropic labels each one with a preceding
/// `event:` line, but every payload names its own type, so the label is
/// redundant and ignoring it keeps both adapters on the same plain line reader.
enum AnthropicChunk {
    /// What a single line amounts to. Token counts arrive as two separate
    /// events, so they are reported as they come and added up by the caller
    /// rather than here: this stays a function of one line.
    enum Piece: Equatable {
        case text(String)
        case usage(input: Int?, output: Int?)
        case stop
    }

    static func piece(from line: String) throws -> Piece? {
        let line = line.trimmed
        guard line.hasPrefix("data:") else { return nil }

        let payload = String(line.dropFirst("data:".count)).trimmed
        guard !payload.isEmpty, let data = payload.data(using: .utf8),
              let event = try? JSONDecoder().decode(Event.self, from: data)
        else {
            // An unreadable line is no reason to tear down the round trip. An
            // answer that never arrives is reported by the caller, which sees
            // an empty result.
            return nil
        }

        switch event.type {
        case "error":
            throw LLMError.providerRejected(event.error?.message)
        case "content_block_delta":
            // Only text. A reasoning model's thinking arrives here too, in a
            // delta of its own type, and it is not the answer.
            guard event.delta?.type == "text_delta", let text = event.delta?.text else { return nil }
            return .text(text)
        case "message_start":
            guard let usage = event.message?.usage else { return nil }
            return .usage(input: usage.inputTokens, output: usage.outputTokens)
        case "message_delta":
            // The ceiling on the answer is this app's own doing, so running
            // into it is this app's problem to notice. Passed on quietly, a
            // half-written correction would be sanitized like any other and
            // pasted over the selection, eating the tail of somebody's own
            // text.
            if event.delta?.stopReason == "max_tokens" { throw LLMError.answerTruncated }
            guard let usage = event.usage else { return nil }
            return .usage(input: usage.inputTokens, output: usage.outputTokens)
        case "message_stop":
            return .stop
        default:
            // Pings, block boundaries, and whatever Anthropic adds next. Their
            // versioning policy says to expect new types.
            return nil
        }
    }

    private struct Event: Decodable {
        let type: String
        let delta: Delta?
        let message: Message?
        let usage: Usage?
        let error: ProviderErrorBody?

        struct Delta: Decodable {
            let type: String?
            let text: String?
            let stopReason: String?

            enum CodingKeys: String, CodingKey {
                case type
                case text
                case stopReason = "stop_reason"
            }
        }

        struct Message: Decodable {
            let usage: Usage?
        }

        struct Usage: Decodable {
            let inputTokens: Int?
            let outputTokens: Int?

            enum CodingKeys: String, CodingKey {
                case inputTokens = "input_tokens"
                case outputTokens = "output_tokens"
            }
        }
    }
}

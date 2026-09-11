import Foundation

/// What arrives from the model's stream. Streaming is not decoration: ticket
/// 05's panel shows the text as it lands, and token usage arrives in the last
/// chunk, where the spending counter needs it.
public enum StreamEvent: Equatable, Sendable {
    case delta(String)
    case usage(TokenUsage)
    case done
}

public struct TokenUsage: Equatable, Sendable {
    public let promptTokens: Int
    public let completionTokens: Int

    public init(promptTokens: Int, completionTokens: Int) {
        self.promptTokens = promptTokens
        self.completionTokens = completionTokens
    }
}

/// A model's stream. One implementation covers every OpenAI-compatible server;
/// the Anthropic adapter arrives in its own ticket and fits in right here.
public protocol LLMClient: Sendable {
    func stream(prompt: String) -> AsyncThrowingStream<StreamEvent, any Error>
}

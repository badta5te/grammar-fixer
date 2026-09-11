import Foundation

/// Что приходит из потока модели. Поток нужен не ради красоты: панель тикета 05
/// показывает текст по мере прихода, а расход токенов приезжает последним
/// куском и нужен учёту расходов.
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

/// Поток модели. Реализация одна на все OpenAI-совместимые серверы, адаптер
/// Anthropic придёт отдельным тикетом и встанет сюда же.
public protocol LLMClient: Sendable {
    func stream(prompt: String) -> AsyncThrowingStream<StreamEvent, any Error>
}

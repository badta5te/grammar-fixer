import Foundation

/// Заглушку из тикета 03 здесь заменяет настоящая модель. Шов тот же, круг не
/// тронут: захват и вставка не знают, что между ними появилась сеть.
@MainActor
public struct LLMTextTransformer: TextTransforming {
    private let prompt: Prompt
    private let loadConfiguration: () throws -> ProviderConfiguration
    private let makeClient: (ProviderConfiguration) -> any LLMClient

    public init(
        prompt: Prompt = .default,
        loadConfiguration: @escaping () throws -> ProviderConfiguration
            = { try ProviderConfigurationFile().load() },
        makeClient: @escaping (ProviderConfiguration) -> any LLMClient
            = { OpenAICompatibleClient(configuration: $0, transport: URLSessionLineStream()) }
    ) {
        self.prompt = prompt
        self.loadConfiguration = loadConfiguration
        self.makeClient = makeClient
    }

    public func transform(_ text: String) async throws -> String {
        // Настройки перечитываются на каждом круге: смена модели должна
        // действовать без перезапуска приложения-агента, у которого и окна-то
        // нет, чтобы заметить перезапуск.
        let configuration = try loadConfiguration()
        let client = makeClient(configuration)
        let started = Date()

        var answer = ""
        var usage: TokenUsage?
        for try await event in client.stream(prompt: prompt.render(selection: text)) {
            switch event {
            case .delta(let piece): answer += piece
            case .usage(let value): usage = value
            case .done: break
            }
        }

        let cleaned = ResponseSanitizer.clean(answer, original: text)

        // Ни промпт, ни ответ, ни ключ в журнал не идут. Журнал лежит
        // открытым файлом, а через приложение проходит чужая переписка.
        Log.write(String(
            format: "модель %@: %d → %d символов за %.0f мс, токены %@",
            configuration.model,
            text.count,
            cleaned.count,
            Date().timeIntervalSince(started) * 1000,
            usage.map { "\($0.promptTokens)+\($0.completionTokens)" } ?? "не сообщены"
        ))

        guard !cleaned.isEmpty else { throw LLMError.emptyAnswer }
        return cleaned
    }
}

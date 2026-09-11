import Foundation

/// The real model in place of ticket 03's placeholder. Same seam, and the round
/// trip is untouched: capture and paste do not know a network appeared between
/// them.
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
        // The configuration is re-read on every round: switching models has to
        // take effect without restarting an agent app, which has no window in
        // which a restart would even be visible.
        let configuration = try loadConfiguration()
        let client = makeClient(configuration)
        let started = Date()

        var answer = ""
        var usage: TokenUsage?
        for try await event in client.stream(prompt: prompt.render(selection: text)) {
            switch event {
            case .delta(let piece): answer += piece
            case .usage(let value): usage = value
            // There is deliberately no branch that stops here: `break` inside
            // a switch ends the switch, not the loop, and would read as a stop
            // that never happens. The client itself cuts the stream at [DONE].
            case .done: continue
            }
        }

        let cleaned = ResponseSanitizer.clean(answer, original: text)

        // Neither the prompt, nor the answer, nor the key goes to the log. The
        // log is a plain file, and other people's correspondence passes through
        // this app.
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

import Foundation

/// The real model in place of ticket 03's placeholder. Same seam, and the round
/// trip is untouched: capture and paste do not know a network appeared between
/// them.
@MainActor
public struct LLMTextTransformer: TextTransforming {
    private let loadConfiguration: () throws -> ProviderConfiguration
    private let loadPrompt: () -> Prompt
    private let makeClient: (ProviderConfiguration) -> any LLMClient

    /// Both the configuration and the prompt arrive as closures rather than as
    /// values. They are read again on every round, so a model or a prompt
    /// changed in the settings window reaches the very next press of the
    /// shortcut, with nothing to restart.
    public init(
        loadConfiguration: @escaping () throws -> ProviderConfiguration,
        loadPrompt: @escaping () -> Prompt = { .default },
        makeClient: @escaping (ProviderConfiguration) -> any LLMClient
            = { ProviderStore.makeClient(for: $0) }
    ) {
        self.loadConfiguration = loadConfiguration
        self.loadPrompt = loadPrompt
        self.makeClient = makeClient
    }

    /// The correction as it happens. The panel draws this: the answer appears
    /// piece by piece, and the whole, sanitized text arrives at the end as a
    /// separate event — a preamble or a pair of quotes can only be recognised
    /// once both ends of the answer are in hand.
    public func stream(_ text: String) -> AsyncThrowingStream<CorrectionEvent, any Error> {
        AsyncThrowingStream { continuation in
            let task = Task { @MainActor in
                do {
                    // Both are re-read on every round: switching models or
                    // editing the prompt has to take effect without restarting
                    // an agent app, which has no window in which a restart
                    // would even be visible.
                    let configuration = try loadConfiguration()
                    let prompt = loadPrompt()
                    continuation.yield(.model(configuration.model))

                    let client = makeClient(configuration)
                    let started = Date()
                    var answer = ""
                    var usage: TokenUsage?

                    for try await event in client.stream(prompt: prompt.render(selection: text)) {
                        switch event {
                        case .delta(let piece):
                            answer += piece
                            continuation.yield(.delta(piece))
                        case .usage(let value):
                            usage = value
                        // There is deliberately no branch that stops here:
                        // `break` inside a switch ends the switch, not the
                        // loop, and would read as a stop that never happens.
                        // The client itself cuts the stream at [DONE].
                        case .done:
                            continue
                        }
                    }

                    // The same gap one layer down: a cancelled stream leaves
                    // the loop without an error, and everything below would
                    // then treat a half-arrived answer as a finished one. The
                    // log would report character counts for text that was cut
                    // off, which is exactly the kind of entry that makes a log
                    // useless later.
                    guard !Task.isCancelled else {
                        Log.write(String(
                            format: "круг прерван: %d символов ответа за %.0f мс",
                            answer.count,
                            Date().timeIntervalSince(started) * 1000
                        ))
                        continuation.finish()
                        return
                    }

                    let cleaned = ResponseSanitizer.clean(answer, original: text)

                    // Neither the prompt, nor the answer, nor the key goes to
                    // the log. The log is a plain file, and other people's
                    // correspondence passes through this app.
                    Log.write(String(
                        format: "модель %@: %d → %d символов за %.0f мс, токены %@",
                        configuration.model,
                        text.count,
                        cleaned.count,
                        Date().timeIntervalSince(started) * 1000,
                        usage.map { "\($0.promptTokens)+\($0.completionTokens)" } ?? "не сообщены"
                    ))

                    guard !cleaned.isEmpty else { throw LLMError.emptyAnswer }
                    continuation.yield(.finished(cleaned))
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            // A panel closed halfway through leaves a stream nobody is reading
            // and a provider still being paid for it.
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// The same round with no one watching: used by the menu item and by
    /// anything that only wants the finished text.
    public func transform(_ text: String) async throws -> String {
        for try await event in stream(text) {
            if case .finished(let fixed) = event { return fixed }
        }
        throw LLMError.emptyAnswer
    }
}

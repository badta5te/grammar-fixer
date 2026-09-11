import Foundation

/// The real model in place of ticket 03's placeholder. Same seam, and the round
/// trip is untouched: capture and paste do not know a network appeared between
/// them.
@MainActor
public struct LLMTextTransformer: TextTransforming {
    private let loadConfiguration: () throws -> ProviderConfiguration
    private let loadPrompt: () -> Prompt
    private let makeClient: (ProviderConfiguration) -> any LLMClient
    private let record: @MainActor (UsageRecord) -> Void

    /// Both the configuration and the prompt arrive as closures rather than as
    /// values. They are read again on every round, so a model or a prompt
    /// changed in the settings window reaches the very next press of the
    /// shortcut, with nothing to restart.
    public init(
        loadConfiguration: @escaping () throws -> ProviderConfiguration,
        loadPrompt: @escaping () -> Prompt = { .default },
        makeClient: @escaping (ProviderConfiguration) -> any LLMClient
            = { ProviderStore.makeClient(for: $0) },
        record: @escaping @MainActor (UsageRecord) -> Void = { _ in }
    ) {
        self.loadConfiguration = loadConfiguration
        self.loadPrompt = loadPrompt
        self.makeClient = makeClient
        self.record = record
    }

    /// The correction as it happens. The panel draws this: the answer appears
    /// piece by piece, and the whole, sanitized text arrives at the end as a
    /// separate event — a preamble or a pair of quotes can only be recognised
    /// once both ends of the answer are in hand.
    public func stream(_ text: String) -> AsyncThrowingStream<CorrectionEvent, any Error> {
        AsyncThrowingStream { continuation in
            let task = Task { @MainActor in
                // Declared out here so that every way out of the round can
                // pay for it. A round that was cut short or broke off halfway
                // was still generated, and a provider bills for what it
                // generated.
                var answer = ""
                var usage: TokenUsage?
                var round: (configuration: ProviderConfiguration, prompt: String)?
                var billed = false

                @MainActor func bill() {
                    // Once per round, whichever way the round ends. An answer
                    // that sanitized to nothing is paid for here and then
                    // throws, and the catch below would otherwise charge the
                    // same round a second time.
                    guard !billed else { return }
                    guard let round else { return }
                    guard usage != nil || !answer.isEmpty else { return }
                    record(UsageRecord(
                        date: Date(),
                        provider: round.configuration.providerId,
                        model: round.configuration.model,
                        // The whole prompt is paid for, not just the selection
                        // inside it: the instructions go to the provider on
                        // every round.
                        promptTokens: usage?.promptTokens ?? TokenEstimate.tokens(in: round.prompt),
                        completionTokens: usage?.completionTokens ?? TokenEstimate.tokens(in: answer),
                        isEstimated: usage == nil
                    ))
                    billed = true
                }

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

                    let rendered = prompt.render(selection: text)
                    round = (configuration, rendered)

                    for try await event in client.stream(prompt: rendered) {
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
                        bill()
                        Log.write(String(
                            format: "round cut short: %d characters of answer in %.0f ms",
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
                        format: "model %@: %d → %d characters in %.0f ms, tokens %@",
                        configuration.model,
                        text.count,
                        cleaned.count,
                        Date().timeIntervalSince(started) * 1000,
                        usage.map { "\($0.promptTokens)+\($0.completionTokens)" } ?? "not reported"
                    ))

                    bill()
                    guard !cleaned.isEmpty else { throw LLMError.emptyAnswer }
                    continuation.yield(.finished(cleaned))
                    continuation.finish()
                } catch {
                    // A stream that broke after a few pieces had arrived was
                    // paid for as far as it got. One that never left costs
                    // nothing and leaves no row behind, which is what the
                    // guard inside bill() is for.
                    bill()
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

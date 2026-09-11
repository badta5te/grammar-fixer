import Foundation

/// One correction, from the shortcut to a decision. The panel draws this and
/// nothing else; the round trip drives it and reads the result.
///
/// It is a type of its own rather than state inside the panel because what the
/// person sees during those seconds is the substance of this ticket, and a
/// window is not something a test can watch.
@MainActor
@Observable
public final class CorrectionSession {
    public enum State: Equatable {
        /// The request has left and nothing has come back yet.
        case waiting
        case streaming(String)
        case finished(String)
        /// A refusal worth reading, with the retry still open.
        case failed(title: String, message: String)
    }

    public private(set) var state: State = .waiting
    public private(set) var model: String = ""

    private let source: String
    private let produce: @MainActor (String) -> AsyncThrowingStream<CorrectionEvent, any Error>
    private let budget: @MainActor () -> BudgetNotice?
    private var task: Task<Void, Never>?

    public init(
        source: String,
        produce: @escaping @MainActor (String) -> AsyncThrowingStream<CorrectionEvent, any Error>,
        budget: @escaping @MainActor () -> BudgetNotice? = { nil }
    ) {
        self.source = source
        self.produce = produce
        self.budget = budget
    }

    /// Where the month stands, or nothing at all while it is quiet.
    ///
    /// Asked for rather than stored, so that the round which passes the limit
    /// says so on the panel it is being watched on. The panel redraws with
    /// every piece of the answer, and the round is recorded before the last
    /// one lands.
    public var budgetNotice: BudgetNotice? { budget() }

    /// The text that may be pasted, or nil while there is nothing to paste.
    public var result: String? {
        guard case .finished(let text) = state else { return nil }
        return text
    }

    public var hasFailed: Bool {
        guard case .failed = state else { return false }
        return true
    }

    /// Starts the round, and starts it again on a retry. Retrying is worth the
    /// most precisely when it failed: the selection is already captured, and a
    /// dropped connection would otherwise cost the person the whole round.
    public func start() {
        task?.cancel()
        state = .waiting
        model = ""
        task = Task { @MainActor in
            var accumulated = ""
            do {
                for try await event in produce(source) {
                    switch event {
                    case .model(let name):
                        model = name
                    case .delta(let piece):
                        accumulated += piece
                        state = .streaming(accumulated)
                    case .finished(let text):
                        state = .finished(text)
                    }
                }
                // Cancelling a stream ends its loop without throwing
                // anything, so a closed panel arrives here looking exactly
                // like a model that answered with nothing. Calling that a
                // failure would write "correction did not happen" into the log
                // every time somebody pressed Esc, and a log that cries wolf is
                // worse than no log.
                guard !Task.isCancelled else { return }

                // A stream that ends without an answer would leave the panel
                // waiting forever, and waiting forever is the one outcome this
                // round trip never allows.
                if result == nil { fail(LLMError.emptyAnswer) }
            } catch {
                guard !Task.isCancelled else { return }
                fail(error)
            }
        }
    }

    /// Stops the round. Called when the panel goes away: without it the stream
    /// would go on being read into nothing, and go on being paid for.
    public func cancel() {
        task?.cancel()
        task = nil
    }

    private func fail(_ error: any Error) {
        let failure = (error as? any UserFacingError) ?? LLMError.from(error)
        Log.write("correction did not happen: \(failure.title)")
        state = .failed(title: failure.title, message: failure.message)
    }
}

import Foundation

/// What happens to captured text between capture and paste. The seam exists so
/// that ticket 04 could swap one implementation instead of touching the round
/// trip.
@MainActor
public protocol TextTransforming {
    /// Throws a `UserFacingError`: a failure from the model has to have
    /// something to say to a person. Silence here would mean the selection
    /// vanished into nothing.
    func transform(_ text: String) async throws -> String

    /// The same correction, reported as it happens. The panel needs this one:
    /// a round takes seconds, and seconds of an empty window read as a broken
    /// app.
    func stream(_ text: String) -> AsyncThrowingStream<CorrectionEvent, any Error>
}

extension TextTransforming {
    /// A transformer with nothing to stream still fits the panel: the answer
    /// arrives in one piece and the panel shows waiting until it does. The
    /// default is what keeps `transform` the simpler thing to implement.
    public func stream(_ text: String) -> AsyncThrowingStream<CorrectionEvent, any Error> {
        AsyncThrowingStream { continuation in
            let task = Task { @MainActor in
                do {
                    continuation.yield(.finished(try await transform(text)))
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}

/// A placeholder in place of the model: upper case is visible to the eye, and
/// the round trip can be checked by hand with no network, key or money. Kept on
/// purpose: when the round trip and the model disagree, swapping one line in
/// AppDelegate says which half is at fault.
public struct UppercasePlaceholder: TextTransforming {
    public init() {}

    public func transform(_ text: String) async -> String { text.uppercased() }
}

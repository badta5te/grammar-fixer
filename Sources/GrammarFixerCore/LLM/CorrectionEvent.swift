import Foundation

/// What the panel learns while the model is answering.
///
/// Deltas and the finished answer are separate cases on purpose. Sanitizing
/// needs the whole answer — a preamble or a pair of quotes can only be
/// recognised once both ends are in hand — so the text that flows past the eye
/// and the text that ends up in somebody's document are not always the same
/// string.
public enum CorrectionEvent: Equatable, Sendable {
    /// Which model is answering. The footer names it: a round that costs money
    /// should say who is being paid, above all right after the file was edited.
    case model(String)
    /// The next piece of the answer, exactly as the provider sent it.
    case delta(String)
    /// The whole answer, sanitized. This is the one that gets pasted.
    case finished(String)
}

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
}

/// A placeholder in place of the model: upper case is visible to the eye, and
/// the round trip can be checked by hand with no network, key or money. Kept on
/// purpose: when the round trip and the model disagree, swapping one line in
/// AppDelegate says which half is at fault.
public struct UppercasePlaceholder: TextTransforming {
    public init() {}

    public func transform(_ text: String) async -> String { text.uppercased() }
}

import Foundation

/// Answers one question: does this key work?
///
/// Worth a button of its own because the alternative way of finding out is to
/// select some text somewhere, press the shortcut and read a refusal in the
/// panel. A key is typed once and then trusted for months, so the moment it is
/// typed is the moment to say whether it is good.
@MainActor
public enum KeyCheck {
    public enum Outcome: Equatable {
        /// A correction came back: the key works and so does the model.
        case working(model: String)
        /// No model has been chosen yet, so the key was proved the other way,
        /// by asking the provider what it offers. The list is handed back
        /// because it is exactly what the person needs next.
        case accepted(models: [String])
        /// The provider's own words, not a status code.
        case refused(title: String, message: String)
    }

    /// The key is checked with whatever request can be made right now.
    ///
    /// A correction needs a model to send it to, and the model is usually
    /// chosen after the key is pasted — the list of models cannot be fetched
    /// before there is a key to fetch it with. So with no model yet, the key is
    /// proved by asking for that list, which is an authenticated request like
    /// any other. Refusing to check until a model is chosen would send somebody
    /// to fix the one thing that was not wrong.
    public static func run(
        configuration: ProviderConfiguration,
        makeClient: (ProviderConfiguration) -> any LLMClient = { ProviderStore.makeClient(for: $0) },
        makeListing: (ProviderConfiguration) -> any ModelListing = { ProviderStore.makeListing(for: $0) }
    ) async -> Outcome {
        do {
            guard !configuration.model.trimmed.isEmpty else {
                let models = try await makeListing(configuration).models()
                Log.write("key accepted, models offered: \(models.count)")
                return .accepted(models: models)
            }

            // Short on purpose: the check is about the key, and every token of
            // it is billed to the person pressing the button.
            for try await event in makeClient(configuration).stream(prompt: "Reply with OK.") {
                // The first piece of text is proof enough. Leaving the loop
                // here cancels the request, so the rest of the answer is never
                // generated and never paid for.
                if case .delta = event { break }
            }
        } catch {
            let failure = (error as? any UserFacingError) ?? LLMError.from(error)
            Log.write("key check failed: \(failure.title)")
            return .refused(title: failure.title, message: failure.message)
        }
        // A provider that answered without complaining accepted the key, even
        // if the model chose to say nothing.
        Log.write("key check passed: model \(configuration.model)")
        return .working(model: configuration.model)
    }
}

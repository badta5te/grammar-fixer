import Foundation

/// Which model to use, where to reach it and which adapter speaks to it.
///
/// A plain value assembled by `ProviderStore` for each round. It carries no
/// knowledge of where the pieces came from: a window, the Keychain or an
/// environment variable all produce the same thing, and the adapters below are
/// spared the question.
public struct ProviderConfiguration: Equatable, Sendable {
    public let model: String

    /// Who is being paid. Carried alongside the model because the same model
    /// name reaches different bills through a reseller, and the spending
    /// counter prices a round by both.
    public let providerId: String
    public let baseURL: URL
    public let apiKey: String

    /// Not every server understands a request for token usage. The flag turns
    /// the request off up front for servers that complain about it.
    public var requestsUsage: Bool

    /// Whether the model is allowed to deliberate before answering.
    ///
    /// Fixing spelling needs no deliberation, and deliberation is not free.
    /// DeepSeek's flash model billed 2966 output tokens for a 205-character
    /// answer and took sixteen seconds; with thinking off the same correction
    /// came back identical in eight tokens.
    public var reasoning: Reasoning

    /// Which of the two adapters to use.
    public var kind: ProviderPreset.Kind

    public enum Reasoning: String, CaseIterable, Sendable {
        /// Ask the provider not to think. The default.
        case off
        /// Leave the provider to its own default, for anyone who wants it.
        case providerDefault = "default"
    }

    public init(
        model: String,
        providerId: String = ProviderPreset.custom.id,
        baseURL: URL,
        apiKey: String,
        requestsUsage: Bool,
        reasoning: Reasoning,
        kind: ProviderPreset.Kind = .openAICompatible
    ) {
        self.model = model
        self.providerId = providerId
        self.baseURL = baseURL
        self.apiKey = apiKey
        self.requestsUsage = requestsUsage
        self.reasoning = reasoning
        self.kind = kind
    }
}

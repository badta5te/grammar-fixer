import Foundation

/// A provider as offered in the settings window: where it lives and which
/// adapter speaks to it.
///
/// One list, not two. The same entries resolve an address, fill the window's
/// menu and build the message that names what is on offer when a provider name
/// is not recognised. A second copy would drift from this one and the drift
/// would show up as an error message naming a provider that no longer exists.
///
/// What is deliberately not here is model names. Any list of those written into
/// this app goes stale the next time a provider renames something, and they do
/// that far more often than this app is released. The window asks the provider
/// instead, with the key it already has.
public struct ProviderPreset: Identifiable, Equatable, Sendable {
    /// Which adapter speaks to this provider. There are two and there is no
    /// reason for a third: one OpenAI-compatible path covers everyone else,
    /// including local servers.
    public enum Kind: String, Equatable, Sendable {
        case openAICompatible
        case anthropic
    }

    public let id: String
    public let name: String
    /// `nil` means the address is the person's to type.
    public let baseURL: String?
    public let kind: Kind
    public var wantsItsOwnAddress: Bool { baseURL == nil }

    public static let openai = ProviderPreset(
        id: "openai",
        name: "OpenAI",
        baseURL: "https://api.openai.com/v1",
        kind: .openAICompatible
    )

    public static let anthropic = ProviderPreset(
        id: "anthropic",
        name: "Anthropic",
        baseURL: "https://api.anthropic.com/v1",
        kind: .anthropic
    )

    public static let deepseek = ProviderPreset(
        id: "deepseek",
        name: "DeepSeek",
        baseURL: "https://api.deepseek.com",
        kind: .openAICompatible
    )

    public static let openrouter = ProviderPreset(
        id: "openrouter",
        name: "OpenRouter",
        baseURL: "https://openrouter.ai/api/v1",
        kind: .openAICompatible
    )

    /// Kept from the previous ticket rather than dropped: it was documented and
    /// somebody may be pointing at it already.
    public static let groq = ProviderPreset(
        id: "groq",
        name: "Groq",
        baseURL: "https://api.groq.com/openai/v1",
        kind: .openAICompatible
    )

    /// Anything OpenAI-compatible: another provider, or a model running on this
    /// machine. Nothing can be suggested about somebody's own server.
    public static let custom = ProviderPreset(
        id: "custom",
        name: "Your own OpenAI-compatible address",
        baseURL: nil,
        kind: .openAICompatible
    )

    /// The order is the order of the menu, and the entry for your own address
    /// comes last because it is the one that asks for typing.
    public static let all: [ProviderPreset] = [
        openai, anthropic, deepseek, openrouter, groq, custom,
    ]

    public static func named(_ id: String?) -> ProviderPreset? {
        guard let wanted = id?.trimmed.lowercased(), !wanted.isEmpty else { return nil }
        return all.first { $0.id == wanted }
    }

    /// For the message that names what is on offer. The entry for your own
    /// address is left out: it is not a name anybody can type as a provider.
    public static var namesForMessage: String {
        all.filter { !$0.wantsItsOwnAddress }.map(\.id).sorted().joined(separator: ", ")
    }
}

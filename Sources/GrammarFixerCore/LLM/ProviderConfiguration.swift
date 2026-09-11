import Foundation

/// Which model to use and where to reach it.
///
/// There are no settings with a window yet; those arrive in ticket 06 together
/// with the Keychain. For now the provider is described by a file, and the
/// environment overrides it, which is convenient for trying another model
/// without touching the file.
///
/// The other order would be a mistake: the app is launched through `open`, and
/// a shell's environment never reaches it. That is exactly why the file comes
/// first.
public struct ProviderConfiguration: Equatable, Sendable {
    public let model: String
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

    public enum Reasoning: String, Sendable {
        /// Ask the provider not to think. The default.
        case off
        /// Leave the provider to its own default, for anyone who wants it.
        case providerDefault = "default"
    }

    /// One OpenAI-compatible path covers everyone except Anthropic. Any other
    /// address goes in baseURL and works without a preset.
    static let presets = [
        "openai": "https://api.openai.com/v1",
        "deepseek": "https://api.deepseek.com",
        "openrouter": "https://openrouter.ai/api/v1",
        "groq": "https://api.groq.com/openai/v1",
    ]

    static func make(
        fileContents: Data?,
        environment: [String: String],
        path: String
    ) throws -> ProviderConfiguration {
        var file = FileShape()
        if let fileContents {
            do {
                file = try JSONDecoder().decode(FileShape.self, from: fileContents)
            } catch {
                throw LLMError.brokenConfiguration(path: path, reason: error.localizedDescription)
            }
        }

        let provider = environment["GRAMMARFIXER_PROVIDER"] ?? file.provider
        let model = (environment["GRAMMARFIXER_MODEL"] ?? file.model ?? "").trimmed
        let key = (environment["GRAMMARFIXER_API_KEY"] ?? file.apiKey ?? "").trimmed
        let address = (environment["GRAMMARFIXER_BASE_URL"] ?? file.baseURL)?.trimmed

        guard !key.isEmpty else {
            // No file at all means a first launch, and that calls for
            // different advice than "add a key to the file you already have".
            throw fileContents == nil
                ? LLMError.noConfiguration(path: path)
                : LLMError.noKey(path: path)
        }
        guard !model.isEmpty else {
            throw LLMError.brokenConfiguration(path: path, reason: "model is missing")
        }

        let chosen = address?.isEmpty == false
            ? address
            : provider.flatMap { presets[$0.lowercased().trimmed] }
        guard let chosen, let url = URL(string: chosen), url.scheme != nil else {
            throw LLMError.brokenConfiguration(
                path: path,
                reason: "provider is not one of \(presets.keys.sorted().joined(separator: ", ")), "
                    + "so baseURL must be set"
            )
        }

        return ProviderConfiguration(
            model: model,
            baseURL: url,
            apiKey: key,
            requestsUsage: file.requestUsage ?? true,
            reasoning: Reasoning(rawValue: file.reasoning?.lowercased().trimmed ?? "") ?? .off
        )
    }

    private struct FileShape: Decodable {
        var provider: String?
        var model: String?
        var apiKey: String?
        var baseURL: String?
        var requestUsage: Bool?
        var reasoning: String?
    }
}

/// Reading the configuration from disk. The file is re-read on every round so
/// that switching models takes effect without a restart.
public struct ProviderConfigurationFile: Sendable {
    public static let url = FileManager.default
        .homeDirectoryForCurrentUser
        .appending(path: ".config/grammar-fixer/config.json")

    /// The path as shown to a person: the home directory spelled out in full
    /// helps nobody.
    public static var displayPath: String {
        url.path.replacingOccurrences(
            of: FileManager.default.homeDirectoryForCurrentUser.path,
            with: "~"
        )
    }

    public init() {}

    /// Creates the file from a template. Opening emptiness is pointless, and
    /// the shape of the file is easier to fill in than to retype from an error
    /// message.
    @discardableResult
    public func createIfMissing() throws -> URL {
        guard !FileManager.default.fileExists(atPath: Self.url.path) else { return Self.url }
        try FileManager.default.createDirectory(
            at: Self.url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Self.template.write(to: Self.url, atomically: true, encoding: .utf8)
        // The key sits in a plain file until ticket 06 brings the Keychain.
        // Permissions are at least not world-readable.
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: Self.url.path)
        return Self.url
    }

    /// The hint lives in the file itself: unknown fields are ignored when the
    /// file is parsed, so the explanation costs nothing and is where it is
    /// needed.
    static let template = """
        {
          "_help": "provider: \(ProviderConfiguration.presets.keys.sorted().joined(separator: ", ")). \
        Any other OpenAI-compatible server works too: set baseURL instead of provider. \
        Take the model name from your provider's own documentation: they rename models often. \
        Add \\"reasoning\\": \\"default\\" if you want the model to deliberate before answering.",
          "provider": "deepseek",
          "model": "",
          "apiKey": ""
        }

        """

    public func load() throws -> ProviderConfiguration {
        try ProviderConfiguration.make(
            fileContents: try? Data(contentsOf: Self.url),
            environment: ProcessInfo.processInfo.environment,
            path: Self.displayPath
        )
    }
}

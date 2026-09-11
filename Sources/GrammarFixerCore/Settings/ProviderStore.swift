import Foundation

/// Which fields the environment has taken over.
///
/// The window has to be able to say so. A field showing one value while
/// requests go out with another is the window equivalent of a menu with the
/// wrong check marks, and that was already ruled out once.
public struct EnvironmentOverrides: Equatable, Sendable {
    public var provider = false
    public var model = false
    public var address = false
    public var key = false

    public var any: Bool { provider || model || address || key }
}

/// Everything needed to send a request, assembled afresh each time.
///
/// Nothing is cached on purpose: a model chosen in the window has to reach the
/// very next press of the shortcut, and an agent app has no window in which a
/// restart would even be visible.
///
/// The key is the one piece that does not live in UserDefaults. It goes to the
/// Keychain under the provider's name, so `defaults read` shows settings and
/// nothing worth stealing, and each provider keeps its own key.
@MainActor
public final class ProviderStore {
    private let settings: Settings
    private let secrets: any SecretStore
    private let environment: [String: String]

    public init(
        settings: Settings,
        secrets: any SecretStore = Keychain(),
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) {
        self.settings = settings
        self.secrets = secrets
        self.environment = environment
    }

    // MARK: - For a round

    public func configuration() throws -> ProviderConfiguration {
        try configuration(requiringModel: true)
    }

    /// Listing the models is the one thing worth doing before a model has been
    /// chosen, so the check for one is skipped there. Everything else still
    /// has to be in place: a list cannot be asked for without a key.
    func configuration(requiringModel: Bool) throws -> ProviderConfiguration {
        let name = chosenProviderId
        guard let preset = ProviderPreset.named(name) else {
            throw LLMError.unknownProvider(name)
        }

        let model = (environment["GRAMMARFIXER_MODEL"] ?? settings.model(for: preset.id)).trimmed
        // A Keychain that refuses to answer is not an empty Keychain, so this
        // is deliberately not softened into nil: "no key" would send somebody
        // to retype a key that is already there.
        let key = (try environment["GRAMMARFIXER_API_KEY"] ?? secrets.secret(for: preset.id) ?? "").trimmed

        // Nothing at all is a first launch and deserves different advice from
        // a setting that was half filled in.
        if requiringModel, key.isEmpty, model.isEmpty { throw LLMError.notConfigured }
        guard !key.isEmpty else { throw LLMError.noKey }
        if requiringModel, model.isEmpty { throw LLMError.noModel }

        let address = (environment["GRAMMARFIXER_BASE_URL"]
            ?? (preset.wantsItsOwnAddress ? settings.address : preset.baseURL) ?? "").trimmed
        guard let url = URL(string: address), url.scheme != nil, url.host != nil else {
            throw LLMError.badAddress(address)
        }

        return ProviderConfiguration(
            model: model,
            providerId: preset.id,
            baseURL: url,
            apiKey: key,
            requestsUsage: settings.requestsUsage,
            reasoning: settings.reasoning,
            kind: preset.kind
        )
    }

    /// The prompt as edited, or the original if the edit lost the placeholder.
    ///
    /// A template with no `{selection}` in it would send the model a prompt
    /// with no text, and whatever came back would be pasted over somebody's
    /// selection. Refusing outright would leave the shortcut dead instead, so
    /// the original stands in and the window says so as it is typed.
    public func prompt() -> Prompt {
        let template = settings.promptTemplate
        guard template.contains(Prompt.placeholder) else {
            Log.write("the prompt has no \(Prompt.placeholder), so the original one is used")
            return .default
        }
        return Prompt(template: template)
    }

    /// The models this provider has, asked of the provider itself.
    ///
    /// Nothing of the sort is written into this app: a list of model names
    /// would be stale the next time a provider renamed something, and keeping
    /// it current by hand is exactly the chore this app exists to avoid.
    public func models() async throws -> [String] {
        try await Self.makeListing(for: configuration(requiringModel: false)).models()
    }

    public static func makeListing(for configuration: ProviderConfiguration) -> any ModelListing {
        switch configuration.kind {
        case .openAICompatible:
            OpenAICompatibleClient(configuration: configuration, transport: URLSessionLineStream())
        case .anthropic:
            AnthropicClient(configuration: configuration, transport: URLSessionLineStream())
        }
    }

    /// Which adapter speaks to this configuration. The one place the choice is
    /// made, so a new provider kind needs changing here and nowhere else.
    public static func makeClient(for configuration: ProviderConfiguration) -> any LLMClient {
        switch configuration.kind {
        case .openAICompatible:
            OpenAICompatibleClient(configuration: configuration, transport: URLSessionLineStream())
        case .anthropic:
            AnthropicClient(configuration: configuration, transport: URLSessionLineStream())
        }
    }

    // MARK: - For the window

    /// The provider the requests actually go to, which is not always the one
    /// stored: the environment can take the choice over.
    ///
    /// The window edits this one. Reading only the stored name would have it
    /// editing DeepSeek's key while every request went to Anthropic, so the key
    /// pasted to fix a refusal would change nothing and the refusal would
    /// repeat.
    public var preset: ProviderPreset {
        get { ProviderPreset.named(chosenProviderId) ?? .custom }
        set { settings.providerId = newValue.id }
    }

    private var chosenProviderId: String {
        environment["GRAMMARFIXER_PROVIDER"] ?? settings.providerId
    }

    /// The model of whichever provider is chosen right now.
    public var model: String {
        get { settings.model(for: preset.id) }
        set { settings.setModel(newValue, for: preset.id) }
    }

    public var overrides: EnvironmentOverrides {
        EnvironmentOverrides(
            provider: environment["GRAMMARFIXER_PROVIDER"] != nil,
            model: environment["GRAMMARFIXER_MODEL"] != nil,
            address: environment["GRAMMARFIXER_BASE_URL"] != nil,
            key: environment["GRAMMARFIXER_API_KEY"] != nil
        )
    }

    public func key(for preset: ProviderPreset) throws -> String {
        try secrets.secret(for: preset.id) ?? ""
    }

    /// An emptied field removes the key rather than storing an empty one:
    /// otherwise clearing it would leave something behind in the Keychain that
    /// nothing on screen accounts for.
    public func setKey(_ key: String, for preset: ProviderPreset) throws {
        let key = key.trimmed
        if key.isEmpty {
            try secrets.removeSecret(for: preset.id)
        } else {
            try secrets.store(key, for: preset.id)
        }
    }

    // MARK: - What the previous ticket left in a file

    /// Carries `~/.config/grammar-fixer/config.json` over into the window and
    /// the Keychain, once.
    ///
    /// The file is read and never written or removed: it is somebody's key, and
    /// this app has no business deleting it. The import is skipped as soon as
    /// anything is configured here, so it cannot run twice and undo what has
    /// since been typed into the window.
    @discardableResult
    public func importLegacyFile(contents: Data? = LegacyProviderFile.contents()) -> Bool {
        guard model.isEmpty, ((try? key(for: preset)) ?? "").isEmpty else { return false }
        guard let fields = LegacyProviderFile.read(contents) else { return false }

        // An address written into the file wins over the provider name beside
        // it, exactly as it did when the file was still being read on every
        // round. A file naming a preset while pointing at a local server is
        // somebody running a model on this machine, and taking the name would
        // send their key to the preset's real endpoint instead.
        let hasAddress = fields.baseURL?.trimmed.isEmpty == false
        let preset = hasAddress ? ProviderPreset.custom : ProviderPreset.named(fields.provider)
        guard let preset, let key = fields.apiKey?.trimmed, !key.isEmpty else { return false }

        settings.providerId = preset.id
        if let model = fields.model?.trimmed, !model.isEmpty {
            settings.setModel(model, for: preset.id)
        }
        if let address = fields.baseURL?.trimmed, !address.isEmpty { settings.address = address }
        if let requestUsage = fields.requestUsage { settings.requestsUsage = requestUsage }
        if let reasoning = fields.reasoning.flatMap({
            ProviderConfiguration.Reasoning(rawValue: $0.lowercased().trimmed)
        }) {
            settings.reasoning = reasoning
        }

        // The key is the part that can fail, and a key that vanishes without a
        // word is the worst outcome here. Everything else is already carried
        // over, so the window will show the provider with an empty key field,
        // which is the state this message explains.
        do {
            try setKey(key, for: preset)
            Log.write("settings carried over from the file: provider \(preset.id), key in the Keychain")
        } catch {
            Log.write("settings carried over from the file, but the key did not reach the Keychain: "
                + ((error as? any UserFacingError)?.title ?? "\(error)"))
        }
        return true
    }
}

/// The provider file as the previous ticket wrote it. Read once, at launch, and
/// never written to.
public enum LegacyProviderFile {
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

    public static func contents() -> Data? {
        try? Data(contentsOf: url)
    }

    public struct Fields: Decodable, Equatable, Sendable {
        public var provider: String?
        public var model: String?
        public var apiKey: String?
        public var baseURL: String?
        public var requestUsage: Bool?
        public var reasoning: String?
    }

    /// A file that cannot be read is nothing to carry over, and nothing to
    /// complain about either: most people never had one.
    public static func read(_ contents: Data?) -> Fields? {
        guard let contents, let fields = try? JSONDecoder().decode(Fields.self, from: contents)
        else { return nil }
        return fields
    }
}

import XCTest
@testable import GrammarFixerCore

/// Where the provider settings come from now. The window writes here, every
/// round reads here, and the key never passes through UserDefaults on its way.
///
/// This is the one place that can leave somebody with a shortcut that does
/// nothing, so each way of being half-configured has to name itself.
@MainActor
final class ProviderStoreTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suiteName: String!
    private var settings: Settings!
    private var secrets: FakeSecrets!

    override func setUp() async throws {
        suiteName = "com.badta5te.GrammarFixer.tests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        settings = Settings(defaults: defaults)
        secrets = FakeSecrets()
    }

    override func tearDown() async throws {
        defaults.removePersistentDomain(forName: suiteName)
    }

    private func makeStore(environment: [String: String] = [:]) -> ProviderStore {
        ProviderStore(settings: settings, secrets: secrets, environment: environment)
    }

    private func configureDeepSeek() {
        settings.providerId = ProviderPreset.deepseek.id
        settings.setModel("deepseek-chat", for: ProviderPreset.deepseek.id)
        secrets.stored["deepseek"] = "sk-key"
    }

    func testAPresetSuppliesTheAddressAndTheAdapter() throws {
        configureDeepSeek()

        let configuration = try makeStore().configuration()

        XCTAssertEqual(configuration.baseURL.absoluteString, "https://api.deepseek.com")
        XCTAssertEqual(configuration.model, "deepseek-chat")
        XCTAssertEqual(configuration.apiKey, "sk-key")
        XCTAssertEqual(configuration.kind, .openAICompatible)
    }

    /// Who is being paid travels with the round, because the spending counter
    /// prices a model by its provider: the same name through a reseller is a
    /// different bill. A round filed under the wrong provider is priced by
    /// somebody else's rates, quietly and for ever.
    func testTheRoundCarriesTheNameOfWhoeverIsBeingPaid() throws {
        configureDeepSeek()

        XCTAssertEqual(try makeStore().configuration().providerId, ProviderPreset.deepseek.id)
    }

    /// The reason the second adapter exists at all: the choice of provider has
    /// to reach the code that speaks the protocol.
    func testChoosingAnthropicChoosesTheOtherAdapter() throws {
        settings.providerId = ProviderPreset.anthropic.id
        settings.setModel("claude-haiku-4-5-20251001", for: ProviderPreset.anthropic.id)
        secrets.stored["anthropic"] = "sk-ant"

        XCTAssertEqual(try makeStore().configuration().kind, .anthropic)
    }

    func testYourOwnAddressNeedsNoPreset() throws {
        settings.providerId = ProviderPreset.custom.id
        settings.address = "http://localhost:11434/v1"
        settings.setModel("qwen2.5", for: ProviderPreset.custom.id)
        secrets.stored["custom"] = "whatever"

        let configuration = try makeStore().configuration()

        XCTAssertEqual(configuration.baseURL.absoluteString, "http://localhost:11434/v1")
        XCTAssertEqual(configuration.kind, .openAICompatible)
    }

    /// Each provider keeps its own key, so trying another one for a week and
    /// coming back does not cost the first key.
    func testSwitchingProviderPicksUpThatProvidersOwnKey() throws {
        secrets.stored["deepseek"] = "key-deepseek"
        secrets.stored["openai"] = "key-openai"
        settings.setModel("whichever", for: "deepseek")
        settings.setModel("whichever", for: "openai")

        settings.providerId = ProviderPreset.openai.id
        XCTAssertEqual(try makeStore().configuration().apiKey, "key-openai")

        settings.providerId = ProviderPreset.deepseek.id
        XCTAssertEqual(try makeStore().configuration().apiKey, "key-deepseek")
    }

    /// Criterion three of the ticket, and the reason nothing is cached: the
    /// next press of the shortcut has to use what the window last wrote.
    func testAChangeMadeInTheWindowIsSeenByTheNextRound() throws {
        configureDeepSeek()
        let store = makeStore()
        XCTAssertEqual(try store.configuration().model, "deepseek-chat")

        settings.setModel("deepseek-flash", for: ProviderPreset.deepseek.id)

        XCTAssertEqual(try store.configuration().model, "deepseek-flash")
    }

    /// A model name belongs to the provider it was typed for. Carrying it over
    /// to another provider guarantees a refusal, and the refusal names the key
    /// rather than the model, which sends the person to fix the wrong thing.
    func testSwitchingProviderAndBackKeepsEachProvidersOwnModel() throws {
        configureDeepSeek()
        secrets.stored["anthropic"] = "sk-ant"
        let store = makeStore()

        store.preset = .anthropic
        XCTAssertEqual(store.model, "", "a model belonging to another provider must not come along")
        store.model = "claude-haiku-4-5-20251001"

        store.preset = .deepseek
        XCTAssertEqual(store.model, "deepseek-chat")
        XCTAssertEqual(try store.configuration().model, "deepseek-chat")

        store.preset = .anthropic
        XCTAssertEqual(try store.configuration().model, "claude-haiku-4-5-20251001")
    }

    /// The model was kept in one place before the settings window existed, and
    /// the first launch with a window has to find it where it was left.
    func testAModelStoredBeforeProvidersHadTheirOwnIsNotLost() {
        defaults.set("deepseek-flash", forKey: "Model")

        let settings = Settings(defaults: defaults)

        XCTAssertEqual(settings.model(for: ProviderPreset.deepseek.id), "deepseek-flash")
        XCTAssertNil(defaults.string(forKey: "Model"), "the old key should have been cleaned up")
    }

    // MARK: - Being half-configured

    func testNothingConfiguredAtAllSaysSo() {
        XCTAssertThrowsError(try makeStore().configuration()) { error in
            XCTAssertEqual(error as? LLMError, .notConfigured)
        }
    }

    /// Distinguished from having nothing at all: the advice is different.
    func testAMissingKeyIsNamedOnItsOwn() {
        settings.setModel("deepseek-chat", for: ProviderPreset.deepseek.id)

        XCTAssertThrowsError(try makeStore().configuration()) { error in
            XCTAssertEqual(error as? LLMError, .noKey)
        }
    }

    func testAMissingModelIsNamedOnItsOwn() {
        secrets.stored["deepseek"] = "sk-key"

        XCTAssertThrowsError(try makeStore().configuration()) { error in
            XCTAssertEqual(error as? LLMError, .noModel)
        }
    }

    func testABlankKeyIsTheSameAsNoKey() {
        settings.setModel("deepseek-chat", for: ProviderPreset.deepseek.id)
        secrets.stored["deepseek"] = "   "

        XCTAssertThrowsError(try makeStore().configuration()) { error in
            XCTAssertEqual(error as? LLMError, .noKey)
        }
    }

    func testYourOwnAddressLeftEmptyIsNamed() {
        settings.providerId = ProviderPreset.custom.id
        settings.setModel("qwen2.5", for: ProviderPreset.custom.id)
        secrets.stored["custom"] = "a-key"

        XCTAssertThrowsError(try makeStore().configuration()) { error in
            XCTAssertEqual(error as? LLMError, .badAddress(""))
        }
    }

    func testAnAddressThatIsNotAnAddressIsNamed() {
        settings.providerId = ProviderPreset.custom.id
        settings.address = "localhost:11434"
        settings.setModel("qwen2.5", for: ProviderPreset.custom.id)
        secrets.stored["custom"] = "a-key"

        XCTAssertThrowsError(try makeStore().configuration()) { error in
            XCTAssertEqual(error as? LLMError, .badAddress("localhost:11434"))
        }
    }

    /// A provider name can only get here by being typed into the environment or
    /// left behind by an older version. Either way it must name itself rather
    /// than quietly becoming something else.
    func testAnUnknownProviderNameIsNamed() {
        settings.setModel("m", for: "madeup")
        secrets.stored["madeup"] = "k"
        settings.providerId = "madeup"

        XCTAssertThrowsError(try makeStore().configuration()) { error in
            XCTAssertEqual(error as? LLMError, .unknownProvider("madeup"))
        }
    }

    /// A Keychain that refuses to answer is not an empty Keychain. Saying "no
    /// key" would send the person to retype a key that is already there.
    func testAKeychainRefusalIsPassedOnRatherThanReadAsAnEmptyKey() {
        settings.setModel("deepseek-chat", for: ProviderPreset.deepseek.id)
        secrets.failure = KeychainError(status: -25293, account: "deepseek", action: .read)

        XCTAssertThrowsError(try makeStore().configuration()) { error in
            XCTAssertTrue(error is KeychainError, "got \(error)")
        }
    }

    // MARK: - The environment

    func testTheEnvironmentStillWins() throws {
        configureDeepSeek()

        let configuration = try makeStore(environment: [
            "GRAMMARFIXER_API_KEY": "from-the-environment",
            "GRAMMARFIXER_MODEL": "another",
            "GRAMMARFIXER_BASE_URL": "http://localhost:1234/v1",
        ]).configuration()

        XCTAssertEqual(configuration.apiKey, "from-the-environment")
        XCTAssertEqual(configuration.model, "another")
        XCTAssertEqual(configuration.baseURL.absoluteString, "http://localhost:1234/v1")
    }

    /// The window edits the provider whose requests actually go out. Reading
    /// only the stored name would have it editing DeepSeek's key while every
    /// request went to Anthropic, and the key pasted to fix the refusal would
    /// change nothing at all.
    func testTheWindowFollowsTheProviderTheEnvironmentChose() throws {
        settings.providerId = ProviderPreset.deepseek.id
        secrets.stored["anthropic"] = "key-anthropic"
        let store = makeStore(environment: ["GRAMMARFIXER_PROVIDER": "anthropic"])

        XCTAssertEqual(store.preset, .anthropic)
        XCTAssertEqual(try store.key(for: store.preset), "key-anthropic")

        store.model = "claude-haiku-4-5-20251001"
        XCTAssertEqual(settings.model(for: "anthropic"), "claude-haiku-4-5-20251001")
        XCTAssertEqual(settings.model(for: "deepseek"), "", "another slot must be left alone")
    }

    /// A window showing a value that is not the one in use is worse than no
    /// window. What the environment has taken over has to be sayable.
    func testWhatTheEnvironmentHasTakenOverCanBeNamed() {
        let store = makeStore(environment: [
            "GRAMMARFIXER_API_KEY": "from-the-environment",
            "GRAMMARFIXER_MODEL": "another",
        ])

        XCTAssertTrue(store.overrides.key)
        XCTAssertTrue(store.overrides.model)
        XCTAssertFalse(store.overrides.address)
        XCTAssertFalse(store.overrides.provider)
        XCTAssertTrue(store.overrides.any)
    }

    func testWithoutTheEnvironmentNothingIsOverridden() {
        XCTAssertFalse(makeStore().overrides.any)
    }

    // MARK: - The prompt

    func testThePromptIsTheDefaultUntilItIsEdited() {
        XCTAssertEqual(makeStore().prompt().template, Prompt.default.template)
    }

    func testAnEditedPromptIsUsed() {
        settings.promptTemplate = "Исправь: {selection}"

        XCTAssertEqual(makeStore().prompt().template, "Исправь: {selection}")
    }

    /// A template that lost its placeholder would send the model a prompt with
    /// no text in it, and whatever came back would be pasted over somebody's
    /// selection. Falling back leaves the shortcut working; the window says so
    /// while it is being typed.
    func testAPromptWithoutThePlaceholderFallsBackToTheDefault() {
        settings.promptTemplate = "Исправь орфографию"

        XCTAssertEqual(makeStore().prompt().template, Prompt.default.template)
    }

    func testReturningToTheDefaultForgetsTheEditedPrompt() {
        settings.promptTemplate = "Исправь: {selection}"
        XCTAssertFalse(settings.promptIsTheDefault)

        settings.promptTemplate = Prompt.default.template

        XCTAssertTrue(settings.promptIsTheDefault)
        XCTAssertEqual(makeStore().prompt().template, Prompt.default.template)
    }

    // MARK: - What the previous ticket left in a file

    func testTheOldFileIsCarriedOverOnceIntoTheWindowAndTheKeychain() throws {
        let imported = makeStore().importLegacyFile(contents: Data(#"""
            {"provider":"openai","model":"gpt-4o-mini","apiKey":"sk-old","reasoning":"default"}
            """#.utf8))

        XCTAssertTrue(imported)
        XCTAssertEqual(settings.providerId, "openai")
        XCTAssertEqual(settings.model(for: "openai"), "gpt-4o-mini")
        XCTAssertEqual(settings.reasoning, .providerDefault)
        XCTAssertEqual(secrets.stored["openai"], "sk-old")
    }

    /// The file is read and never written, so the import cannot run twice and
    /// quietly undo what somebody has since typed into the window.
    func testAnAlreadyConfiguredAppLeavesTheOldFileAlone() {
        configureDeepSeek()

        let imported = makeStore().importLegacyFile(contents: Data(#"""
            {"provider":"openai","model":"gpt-4o-mini","apiKey":"sk-old"}
            """#.utf8))

        XCTAssertFalse(imported)
        XCTAssertEqual(settings.model(for: "deepseek"), "deepseek-chat")
        XCTAssertEqual(secrets.stored["deepseek"], "sk-key")
    }

    func testThereIsNothingToCarryOverFromAMissingOrBrokenFile() {
        XCTAssertFalse(makeStore().importLegacyFile(contents: nil))
        XCTAssertFalse(makeStore().importLegacyFile(contents: Data("{это не json".utf8)))
        XCTAssertFalse(makeStore().importLegacyFile(contents: Data("{}".utf8)))
    }

    /// An address written into the old file won over the provider name there,
    /// and it has to keep winning here. A file naming `openai` while pointing
    /// at a local server is somebody running a model on this machine: reading
    /// the name and dropping the address would send their key to OpenAI's real
    /// endpoint, and the window would not even show the address field to
    /// explain why.
    func testAnAddressInTheOldFileStillWinsOverTheProviderName() throws {
        let imported = makeStore().importLegacyFile(contents: Data(#"""
            {"provider":"openai","model":"qwen2.5","apiKey":"k","baseURL":"http://localhost:11434/v1"}
            """#.utf8))

        XCTAssertTrue(imported)
        XCTAssertEqual(settings.providerId, ProviderPreset.custom.id)
        XCTAssertEqual(settings.address, "http://localhost:11434/v1")

        let configuration = try makeStore().configuration()
        XCTAssertEqual(configuration.baseURL.absoluteString, "http://localhost:11434/v1")
    }

    /// A file with an address and no provider is somebody's local server, and
    /// it has to land on the entry that keeps an address of its own.
    func testAFileWithOnlyAnAddressBecomesYourOwnAddress() {
        let imported = makeStore().importLegacyFile(contents: Data(#"""
            {"model":"qwen2.5","apiKey":"k","baseURL":"http://localhost:11434/v1"}
            """#.utf8))

        XCTAssertTrue(imported)
        XCTAssertEqual(settings.providerId, ProviderPreset.custom.id)
        XCTAssertEqual(settings.address, "http://localhost:11434/v1")
    }
}

import XCTest
@testable import GrammarFixerCore

/// The button that says whether a key works. What it must never do is report
/// success on a refusal: somebody would then go on believing the app is set up
/// and meet the same refusal later, in the middle of writing a message.
@MainActor
final class KeyCheckTests: XCTestCase {
    private let configuration = ProviderConfiguration(
        model: "deepseek-chat",
        baseURL: URL(string: "https://api.deepseek.com")!,
        apiKey: "sk-ключ",
        requestsUsage: true,
        reasoning: .off
    )

    private func run(_ client: FakeLLMClient) async -> KeyCheck.Outcome {
        await KeyCheck.run(configuration: configuration, makeClient: { _ in client })
    }

    func testAnAnsweringProviderMeansTheKeyWorks() async {
        let client = FakeLLMClient()
        client.events = [.delta("OK"), .done]

        let outcome = await run(client)

        XCTAssertEqual(outcome, .working(model: "deepseek-chat"))
    }

    /// A model that says nothing is still a provider that accepted the key.
    func testSilenceWithoutARefusalStillMeansTheKeyWorks() async {
        let client = FakeLLMClient()
        client.events = [.done]

        let outcome = await run(client)

        XCTAssertEqual(outcome, .working(model: "deepseek-chat"))
    }

    /// The point of the button. A wrong key has to be named as a wrong key,
    /// not as "something went wrong".
    func testARefusedKeyIsReportedInTheProvidersOwnWords() async {
        let client = FakeLLMClient()
        client.failure = LLMError.unauthorized("Incorrect API key provided")

        let outcome = await run(client)

        XCTAssertEqual(outcome, .refused(
            title: LLMError.unauthorized("Incorrect API key provided").title,
            message: LLMError.unauthorized("Incorrect API key provided").message
        ))
    }

    /// A wrong model name is refused by a provider that was perfectly happy
    /// with the key, and the two are worth telling apart.
    func testAWrongModelIsReportedAsWhatItIs() async {
        let client = FakeLLMClient()
        client.failure = LLMError.providerRejected("model not found")

        guard case .refused(let title, _) = await run(client) else {
            return XCTFail("ожидался отказ")
        }
        XCTAssertEqual(title, LLMError.providerRejected(nil).title)
    }

    func testALostConnectionIsNotBlamedOnTheKey() async {
        let client = FakeLLMClient()
        client.failure = URLError(.notConnectedToInternet)

        guard case .refused(let title, _) = await run(client) else {
            return XCTFail("ожидался отказ")
        }
        XCTAssertEqual(title, LLMError.noConnection.title)
    }

    /// The check is billed to whoever presses the button, so it stops at the
    /// first sign of life instead of reading out a whole answer.
    func testTheCheckStopsAtTheFirstSignOfLife() async {
        let client = FakeLLMClient()
        client.events = [.delta("O"), .delta("K"), .done]

        _ = await run(client)

        XCTAssertEqual(client.prompts.count, 1)
    }
}

/// A key is pasted before a model is chosen, because the list of models cannot
/// be fetched without a key. Checking the key has to work in that order, or the
/// button is useless exactly when it is first pressed.
@MainActor
final class KeyCheckWithoutAModelTests: XCTestCase {
    private let configuration = ProviderConfiguration(
        model: "",
        baseURL: URL(string: "https://api.anthropic.com/v1")!,
        apiKey: "sk-ключ",
        requestsUsage: true,
        reasoning: .off,
        kind: .anthropic
    )

    private func run(_ listing: FakeModelListing) async -> KeyCheck.Outcome {
        await KeyCheck.run(
            configuration: configuration,
            makeClient: { _ in FakeLLMClient() },
            makeListing: { _ in listing }
        )
    }

    /// The list is handed back rather than thrown away: it is the very next
    /// thing the person needs.
    func testWithoutAModelTheKeyIsProvedByAskingForTheModelList() async {
        let listing = FakeModelListing()
        listing.models = ["claude-haiku", "claude-sonnet"]

        let outcome = await run(listing)

        XCTAssertEqual(outcome, .accepted(models: ["claude-haiku", "claude-sonnet"]))
    }

    func testARefusedKeyIsStillNamedWhenThereIsNoModel() async {
        let listing = FakeModelListing()
        listing.failure = LLMError.unauthorized("invalid x-api-key")

        guard case .refused(let title, _) = await run(listing) else {
            return XCTFail("ожидался отказ")
        }
        XCTAssertEqual(title, LLMError.unauthorized(nil).title)
    }

    /// A provider that accepted the key but offers no list is not a refusal:
    /// the name can still be typed in by hand.
    func testAnEmptyListIsStillAnAcceptedKey() async {
        let outcome = await run(FakeModelListing())

        XCTAssertEqual(outcome, .accepted(models: []))
    }

    /// Whitespace is not a model name, and sending it as one would be refused
    /// by the provider with a message about the model rather than the key.
    func testAModelOfNothingButSpacesCountsAsNoModel() async {
        let listing = FakeModelListing()
        listing.models = ["claude-haiku"]
        var blank = configuration
        blank = ProviderConfiguration(
            model: "   ",
            baseURL: blank.baseURL,
            apiKey: blank.apiKey,
            requestsUsage: true,
            reasoning: .off,
            kind: .anthropic
        )

        let outcome = await KeyCheck.run(
            configuration: blank,
            makeClient: { _ in FakeLLMClient() },
            makeListing: { _ in listing }
        )

        XCTAssertEqual(outcome, .accepted(models: ["claude-haiku"]))
    }
}

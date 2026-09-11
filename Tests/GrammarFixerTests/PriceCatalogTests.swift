import XCTest
@testable import GrammarFixerCore

/// Prices come from a catalogue rather than from this app.
///
/// The same argument as the model names: a table typed into the source is
/// wrong the next time a provider changes a figure, and the first version of
/// this ticket shipped a price for DeepSeek's chat model that was already two
/// and a half times too high on the output side.
@MainActor
final class PriceCatalogTests: XCTestCase {
    /// The shape models.dev answers with, trimmed to what is read. A model
    /// with no price of its own is included on purpose: the catalogue holds
    /// plenty.
    private let answer = Data("""
    {
      "deepseek": {
        "id": "deepseek",
        "name": "DeepSeek",
        "models": {
          "deepseek-flash": { "id": "deepseek-flash", "cost": { "input": 0.15, "output": 0.6 } },
          "deepseek-chat": { "id": "deepseek-chat", "cost": { "input": 0.28, "output": 0.42 } },
          "deepseek-secret": { "id": "deepseek-secret" },
          "deepseek-unfilled": { "id": "deepseek-unfilled", "cost": { "input": 0, "output": 0 } }
        }
      },
      "openrouter": {
        "id": "openrouter",
        "models": {
          "anthropic/claude-sonnet-4": {
            "id": "anthropic/claude-sonnet-4",
            "cost": { "input": 3, "output": 15 }
          }
        }
      }
    }
    """.utf8)

    private var cacheURL: URL!

    override func setUp() async throws {
        cacheURL = FileManager.default.temporaryDirectory
            .appending(path: "prices-\(UUID().uuidString).json")
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: cacheURL)
    }

    private func catalog(
        now: Date = Date(),
        fetch: @escaping () async throws -> Data
    ) -> PriceCatalog {
        PriceCatalog(cacheURL: cacheURL, now: { now }, fetch: fetch)
    }

    // MARK: - Reading the catalogue

    func testPricesAreReadPerProviderAndModel() throws {
        let entries = try ModelsDev.parse(answer)

        XCTAssertEqual(entries[PriceTable.key(provider: "deepseek", model: "deepseek-flash")],
                       Price(input: 0.15, output: 0.6))
        XCTAssertEqual(entries[PriceTable.key(provider: "deepseek", model: "deepseek-chat")],
                       Price(input: 0.28, output: 0.42))
    }

    /// A reseller's model names carry slashes of their own, and the provider
    /// is only the part before the first one.
    func testAModelNameMayHoldSlashesOfItsOwn() throws {
        let entries = try ModelsDev.parse(answer)

        XCTAssertEqual(entries["openrouter/anthropic/claude-sonnet-4"], Price(input: 3, output: 15))
    }

    func testAModelWithNoPriceIsLeftOut() throws {
        let entries = try ModelsDev.parse(answer)

        XCTAssertNil(entries[PriceTable.key(provider: "deepseek", model: "deepseek-secret")])
        XCTAssertEqual(entries.count, 3)
    }

    /// The catalogue lists several closed, paid models at $0.00/$0.00 because
    /// nobody has filled the figures in. Reading that as free would count a
    /// paid round as costing nothing.
    func testAPairOfZerosIsAGapRatherThanAFreeModel() throws {
        let entries = try ModelsDev.parse(answer)

        XCTAssertNil(entries[PriceTable.key(provider: "deepseek", model: "deepseek-unfilled")])
    }

    func testSomethingThatIsNotTheCatalogueIsRefused() {
        XCTAssertThrowsError(try ModelsDev.parse(Data("<html>nope</html>".utf8)))
    }

    // MARK: - Keeping it

    func testPricesFetchedOnceSurviveARestart() async throws {
        let first = catalog { [answer] in answer }
        await first.refresh()

        XCTAssertEqual(first.entries.count, 3)

        let second = catalog { XCTFail("the cache should have been enough"); return Data() }

        XCTAssertEqual(second.entries.count, 3)
        XCTAssertNotNil(second.fetchedAt)
    }

    /// Prices change, so the catalogue is asked again the next day. Not on
    /// every round: a correction must never wait on a price list.
    func testTheCatalogueIsAskedAgainOnceADay() async throws {
        let start = Date(timeIntervalSince1970: 1_000_000)
        let first = PriceCatalog(cacheURL: cacheURL, now: { start }, fetch: { [answer] in answer })
        await first.refresh()

        var asked = 0
        let sameDay = PriceCatalog(cacheURL: cacheURL, now: { start.addingTimeInterval(3_600) }) {
            asked += 1
            return Data("{}".utf8)
        }
        await sameDay.refreshIfStale()

        XCTAssertEqual(asked, 0)

        let nextDay = PriceCatalog(cacheURL: cacheURL, now: { start.addingTimeInterval(90_000) }) {
            asked += 1
            return Data("{}".utf8)
        }
        await nextDay.refreshIfStale()

        XCTAssertEqual(asked, 1)
    }

    /// No network is not an empty price list. The prices already in hand go on
    /// being used, and the window says when they were last fetched.
    func testAFetchThatFailsLeavesThePricesAlreadyInHand() async throws {
        let first = catalog { [answer] in answer }
        await first.refresh()

        let offline = catalog { throw LLMError.noConnection }
        await offline.refresh()

        XCTAssertEqual(offline.entries.count, 3)
        XCTAssertNotNil(offline.failure)
    }

    func testADamagedCacheIsNoPricesRatherThanADeadApp() async throws {
        try Data("this is not json".utf8).write(to: cacheURL)

        let catalog = catalog { Data("{}".utf8) }

        XCTAssertTrue(catalog.entries.isEmpty)
        XCTAssertNil(catalog.fetchedAt)
    }

    /// A price typed by hand wins over the catalogue: somebody running a model
    /// on their own machine pays nothing per token, and somebody on a deal
    /// pays less than the list.
    func testAPriceTypedByHandWinsOverTheCatalogue() async throws {
        let catalog = catalog { [answer] in answer }
        await catalog.refresh()

        let table = catalog.table(with: ["deepseek/deepseek-flash": Price(input: 0, output: 0)])

        XCTAssertEqual(table.price(provider: "deepseek", model: "deepseek-flash"),
                       Price(input: 0, output: 0))
        XCTAssertEqual(table.price(provider: "deepseek", model: "deepseek-chat"),
                       Price(input: 0.28, output: 0.42))
    }
}

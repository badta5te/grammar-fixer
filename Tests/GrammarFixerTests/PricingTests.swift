import XCTest
@testable import GrammarFixerCore

/// What a round cost. The arithmetic is trivial and the lookup is not: model
/// names carry dates, the same name is sold by more than one provider at more
/// than one price, and a name nobody has a price for must leave the counter
/// standing rather than bring it down.
final class PricingTests: XCTestCase {
    private let table = PriceTable(entries: [
        "openai/gpt-test": Price(input: 2, output: 10),
        "openrouter/gpt-test": Price(input: 4, output: 20),
        "deepseek/deepseek-chat": Price(input: 0.27, output: 1.1),
    ])

    func testCostIsTokensTimesThePricePerMillion() {
        let record = UsageRecord(
            date: Date(),
            provider: "openai",
            model: "gpt-test",
            promptTokens: 1_000,
            completionTokens: 500
        )

        XCTAssertEqual(try XCTUnwrap(table.cost(of: record)), 0.007, accuracy: 1e-9)
    }

    /// The price belongs to the provider, not to the name. The same model
    /// through a reseller costs something else, and a counter that cannot tell
    /// them apart is wrong for whichever one it guessed.
    func testTheSameModelCostsWhatItsOwnProviderCharges() {
        XCTAssertEqual(table.price(provider: "openrouter", model: "gpt-test"), Price(input: 4, output: 20))
    }

    /// Providers append release dates to model names. Pricing by exact name
    /// alone would leave every dated name unpriced, which is most of them.
    func testADatedNameTakesThePriceOfTheModelItNames() {
        XCTAssertEqual(table.price(provider: "openai", model: "gpt-test-2025-01-30"),
                       Price(input: 2, output: 10))
    }

    /// A model this app has never heard of is the normal case, not an error:
    /// the whole point of the app is that a cheaper model can appear tomorrow.
    func testAnUnknownModelIsLeftUnpricedRatherThanCountedAsFree() {
        let record = UsageRecord(
            date: Date(),
            provider: "deepseek",
            model: "deepseek-brand-new",
            promptTokens: 1_000,
            completionTokens: 500
        )

        XCTAssertNil(table.cost(of: record))
        XCTAssertNil(table.price(provider: "deepseek", model: "deepseek-brand-new"))
    }

    /// A price typed by hand wins over the one that was fetched: somebody
    /// running a model on their own machine pays nothing per token, and
    /// somebody on a deal pays less than the list.
    func testATypedPriceWinsOverAFetchedOne() {
        let merged = table.merging(["openai/gpt-test": Price(input: 9, output: 9)])

        XCTAssertEqual(merged.price(provider: "openai", model: "gpt-test"), Price(input: 9, output: 9))
    }

    /// Amounts are shown to the cent, and a round costs a fraction of one. A
    /// counter reading exactly zero after a paid round looks broken, so
    /// anything above nothing is said to be above nothing.
    func testAmountsTooSmallForACentAreNotShownAsZero() {
        XCTAssertEqual(Money.text(0), "$0.00")
        XCTAssertEqual(Money.text(0.0004), "<$0.01")
        XCTAssertEqual(Money.text(0.42), "$0.42")
        XCTAssertEqual(Money.text(3), "$3.00")
    }
}

/// A price is typed into two fields by hand. What arrives is not always a
/// number, and a table that accepted nonsense would quietly make the counter
/// wrong rather than refuse.
final class PriceParsingTests: XCTestCase {
    func testAPlainPairOfNumbersIsAPrice() {
        XCTAssertEqual(Price.parse(input: "0.27", output: "1.10"), Price(input: 0.27, output: 1.10))
    }

    /// Half the world types a comma, and the provider's own page shows a dot.
    func testACommaIsADecimalPointToo() {
        XCTAssertEqual(Price.parse(input: "0,27", output: "1,10"), Price(input: 0.27, output: 1.10))
    }

    /// The field is a price and the label says dollars, so a dollar sign
    /// pasted along with the figure is not a mistake worth refusing.
    func testADollarSignIsIgnored() {
        XCTAssertEqual(Price.parse(input: "$3", output: "$15"), Price(input: 3, output: 15))
    }

    func testAnythingThatIsNotANumberIsNotAPrice() {
        XCTAssertNil(Price.parse(input: "", output: "1"))
        XCTAssertNil(Price.parse(input: "free", output: "1"))
        XCTAssertNil(Price.parse(input: "-1", output: "1"))
    }
}

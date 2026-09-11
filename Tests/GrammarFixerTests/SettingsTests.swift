import XCTest
@testable import GrammarFixerCore

/// Settings are read afresh on every round so a switch takes effect without a
/// restart. The defaults matter in their own right: on a first launch there are
/// no keys at all.
@MainActor
final class SettingsTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUp() async throws {
        suiteName = "com.badta5te.GrammarFixer.tests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() async throws {
        defaults.removePersistentDomain(forName: suiteName)
    }

    func testClipboardIsRestoredByDefault() {
        XCTAssertTrue(Settings(defaults: defaults).restoreClipboardAfterPaste)
    }

    func testClipboardRestorationCanBeTurnedOff() {
        let settings = Settings(defaults: defaults)
        settings.restoreClipboardAfterPaste = false

        XCTAssertFalse(Settings(defaults: defaults).restoreClipboardAfterPaste)
    }

    func testPasteGoesThroughTheClipboardByDefault() {
        XCTAssertEqual(Settings(defaults: defaults).pasteMethod, .clipboard)
    }

    func testPasteMethodSurvivesARestart() {
        Settings(defaults: defaults).pasteMethod = .typing

        XCTAssertEqual(Settings(defaults: defaults).pasteMethod, .typing)
    }

    /// A key can be corrupted by hand through defaults write, and that must
    /// not stop the app from pasting.
    func testAnUnknownPasteMethodFallsBackToTheClipboard() {
        defaults.set("carrier pigeon", forKey: Settings.pasteMethodKey)

        XCTAssertEqual(Settings(defaults: defaults).pasteMethod, .clipboard)
    }

    // MARK: - Spending

    /// Three dollars a month, because the subscription this app replaces cost
    /// eight and the point is to see the difference.
    func testTheLimitStartsAtThreeDollarsAMonth() {
        XCTAssertEqual(Settings(defaults: defaults).monthlyLimit, 3, accuracy: 1e-9)
    }

    func testTheLimitSurvivesARestart() {
        Settings(defaults: defaults).monthlyLimit = 10

        XCTAssertEqual(Settings(defaults: defaults).monthlyLimit, 10, accuracy: 1e-9)
    }

    /// Nobody has to have a limit, and a limit of nothing would make every
    /// round a warning.
    func testTheLimitCanBeTurnedOffAltogether() {
        let settings = Settings(defaults: defaults)
        settings.monthlyLimit = 0

        XCTAssertFalse(Budget(limit: Settings(defaults: defaults).monthlyLimit).isSet)
    }

    func testThePricesShippedWithTheAppAreThereFromTheStart() {
        XCTAssertNotNil(Settings(defaults: defaults).prices.price(provider: "deepseek", model: "deepseek-chat"))
    }

    /// Only what somebody typed is stored, the way the prompt is, so a price
    /// corrected in a later version reaches everybody who never edited that
    /// row.
    func testAnEditedPriceIsKeptAndWinsOverTheShippedOne() {
        let settings = Settings(defaults: defaults)
        settings.setPrice(Price(input: 9, output: 9), provider: "deepseek", model: "deepseek-chat")

        let reloaded = Settings(defaults: defaults)

        XCTAssertEqual(reloaded.prices.price(provider: "deepseek", model: "deepseek-chat"),
                       Price(input: 9, output: 9))
        XCTAssertEqual(reloaded.priceOverrides.count, 1)
    }

    func testAPriceCanBeTypedInForAModelTheAppNeverHeardOf() {
        let settings = Settings(defaults: defaults)
        settings.setPrice(Price(input: 1, output: 2), provider: "deepseek", model: "deepseek-flash")

        XCTAssertEqual(Settings(defaults: defaults).prices.price(provider: "deepseek", model: "deepseek-flash"),
                       Price(input: 1, output: 2))
    }

    /// Putting a row back is the same act as forgetting it was ever edited.
    func testForgettingAnEditedPriceBringsTheShippedOneBack() {
        let settings = Settings(defaults: defaults)
        settings.setPrice(Price(input: 9, output: 9), provider: "deepseek", model: "deepseek-chat")
        settings.removePrice(provider: "deepseek", model: "deepseek-chat")

        XCTAssertEqual(Settings(defaults: defaults).prices.price(provider: "deepseek", model: "deepseek-chat"),
                       PriceTable.builtIn.price(provider: "deepseek", model: "deepseek-chat"))
    }

    /// A price typed by hand can be corrupted by hand as well, and the round
    /// trip must not depend on it being readable.
    func testADamagedPriceTableFallsBackToTheShippedOne() {
        defaults.set("not a price table", forKey: Settings.pricesKey)

        XCTAssertEqual(Settings(defaults: defaults).priceOverrides, [:])
        XCTAssertNotNil(Settings(defaults: defaults).prices.price(provider: "openai", model: "gpt-4o"))
    }
}

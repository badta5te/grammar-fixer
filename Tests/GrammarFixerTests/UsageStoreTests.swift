import XCTest
@testable import GrammarFixerCore

/// The spending history. It is the only part of this app that has to be true
/// about the past: everything else is recomputed on the next round, and this
/// is the one thing that would simply be gone.
@MainActor
final class UsageStoreTests: XCTestCase {
    private var fileURL: URL!
    private var calendar: Calendar!

    override func setUp() async throws {
        fileURL = FileManager.default.temporaryDirectory
            .appending(path: "usage-\(UUID().uuidString).json")
        // A fixed zone, or the month boundary would depend on where the tests
        // are run, which is exactly the ambiguity this ticket set out to end.
        calendar = {
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = TimeZone(identifier: "Europe/Warsaw")!
            return calendar
        }()
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: fileURL)
    }

    private func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 12, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(
            year: year, month: month, day: day, hour: hour, minute: minute
        ))!
    }

    private func store(now: Date) -> UsageStore {
        UsageStore(fileURL: fileURL, calendar: calendar, now: { now })
    }

    private func round(
        _ date: Date,
        model: String = "gpt-test",
        provider: String = "openai",
        prompt: Int = 1_000,
        completion: Int = 500,
        estimated: Bool = false
    ) -> UsageRecord {
        UsageRecord(
            date: date,
            provider: provider,
            model: model,
            promptTokens: prompt,
            completionTokens: completion,
            isEstimated: estimated
        )
    }

    private let prices = PriceTable(entries: ["openai/gpt-test": Price(input: 2, output: 10)])

    // MARK: - Keeping it

    func testHistorySurvivesARestart() {
        let first = store(now: date(2026, 9, 11))
        first.add(round(date(2026, 9, 11)))
        first.add(round(date(2026, 9, 11)))

        let second = store(now: date(2026, 9, 11))

        XCTAssertEqual(second.records.count, 2)
        XCTAssertEqual(second.summary(prices: prices).rounds, 2)
    }

    func testNoFileYetIsAnEmptyHistory() {
        XCTAssertEqual(store(now: date(2026, 9, 11)).records, [])
    }

    /// The file is read at launch. A damaged one that threw would be an app
    /// that will not start, and it holds nothing worth dying for.
    func testADamagedFileIsAnEmptyHistoryRatherThanADeadApp() throws {
        try Data("this is not json".utf8).write(to: fileURL)

        XCTAssertEqual(store(now: date(2026, 9, 11)).records, [])
    }

    // MARK: - Which rounds belong to the month

    func testLastMonthDoesNotCountTowardsThisMonth() {
        let store = store(now: date(2026, 9, 11))
        store.add(round(date(2026, 8, 20)))
        store.add(round(date(2026, 9, 2)))

        XCTAssertEqual(store.summary(prices: prices).rounds, 1)
    }

    /// The month is the calendar one in the local time zone, and it turns at
    /// midnight on the first. Written down as a test because otherwise the
    /// rule stays a matter of opinion for ever.
    func testTheMonthTurnsAtMidnightOnTheFirst() {
        let store = store(now: date(2026, 9, 1, 0, 30))
        store.add(round(date(2026, 8, 31, 23, 59)))
        store.add(round(date(2026, 9, 1, 0, 0)))

        let summary = store.summary(prices: prices)

        XCTAssertEqual(summary.rounds, 1)
        XCTAssertEqual(summary.total, 0.007, accuracy: 1e-9)
    }

    // MARK: - What the month cost

    func testTheTotalIsWhatTheRoundsOfThisMonthCost() {
        let store = store(now: date(2026, 9, 11))
        store.add(round(date(2026, 9, 3)))
        store.add(round(date(2026, 9, 4)))

        XCTAssertEqual(store.summary(prices: prices).total, 0.014, accuracy: 1e-9)
    }

    /// A model with no price leaves the total standing and says so. Counting
    /// it as free would be the one answer that is certainly wrong.
    func testARoundNobodyHasAPriceForIsCountedApartFromTheTotal() {
        let store = store(now: date(2026, 9, 11))
        store.add(round(date(2026, 9, 3)))
        store.add(round(date(2026, 9, 4), model: "brand-new"))

        let summary = store.summary(prices: prices)

        XCTAssertEqual(summary.total, 0.007, accuracy: 1e-9)
        XCTAssertEqual(summary.unpricedRounds, 1)
        XCTAssertTrue(summary.isApproximate)
    }

    /// A price typed in afterwards heals the rounds that went unpriced. This
    /// is why the history keeps tokens and not dollars.
    func testAPriceAddedLaterCountsTheRoundsThatCameBeforeIt() {
        let store = store(now: date(2026, 9, 11))
        store.add(round(date(2026, 9, 3), model: "brand-new"))

        let withPrice = prices.merging(["openai/brand-new": Price(input: 2, output: 10)])

        XCTAssertEqual(store.summary(prices: withPrice).total, 0.007, accuracy: 1e-9)
        XCTAssertEqual(store.summary(prices: withPrice).unpricedRounds, 0)
    }

    func testGuessedRoundsAreCountedButMarkedApproximate() {
        let store = store(now: date(2026, 9, 11))
        store.add(round(date(2026, 9, 3), estimated: true))

        let summary = store.summary(prices: prices)

        XCTAssertEqual(summary.total, 0.007, accuracy: 1e-9)
        XCTAssertEqual(summary.estimatedRounds, 1)
        XCTAssertTrue(summary.isApproximate)
    }

    func testAMonthOfExactlyPricedRoundsIsNotApproximate() {
        let store = store(now: date(2026, 9, 11))
        store.add(round(date(2026, 9, 3)))

        XCTAssertFalse(store.summary(prices: prices).isApproximate)
    }

    /// The app runs in the background for months and nobody cleans up after
    /// it. Old rounds are dropped, but not before the counter could still need
    /// them.
    func testRoundsOlderThanAYearAreForgotten() {
        let first = store(now: date(2026, 9, 11))
        first.add(round(date(2024, 1, 5)))
        first.add(round(date(2026, 9, 3)))

        XCTAssertEqual(first.records.count, 1)
        XCTAssertEqual(store(now: date(2026, 9, 11)).records.count, 1)
    }

    /// The menu bar icon changes when the limit is passed, and a menu that is
    /// only redrawn when opened would show yesterday's state.
    func testSomethingIsToldWhenARoundIsRecorded() {
        let store = store(now: date(2026, 9, 11))
        var changes = 0
        store.onChange = { changes += 1 }

        store.add(round(date(2026, 9, 3)))

        XCTAssertEqual(changes, 1)
    }
}

import XCTest
@testable import GrammarFixerCore

/// The soft limit. Soft is the whole point: the request goes out either way,
/// and the app's job is to say where the month stands, not to stand in the way.
final class BudgetTests: XCTestCase {
    private let budget = Budget(limit: 3)

    private func summary(_ total: Double, estimated: Int = 0, unpriced: Int = 0) -> SpendSummary {
        SpendSummary(
            monthStart: Date(),
            total: total,
            rounds: 1,
            estimatedRounds: estimated,
            unpricedRounds: unpriced
        )
    }

    func testWellUnderTheLimitNothingIsSaid() {
        XCTAssertEqual(budget.level(spent: 1.20), .fine)
        XCTAssertNil(budget.notice(for: summary(1.20)))
    }

    /// Eighty per cent is a warning rather than a refusal: there is still room
    /// to decide what to do about it, which is the only moment a warning is
    /// worth anything.
    func testEightyPerCentIsAWarning() {
        XCTAssertEqual(budget.level(spent: 2.40), .approaching)
        XCTAssertEqual(budget.level(spent: 2.99), .approaching)
    }

    func testPassingTheLimitIsSaidPlainly() {
        XCTAssertEqual(budget.level(spent: 3.00), .over)
        XCTAssertEqual(budget.level(spent: 4.10), .over)

        let notice = budget.notice(for: summary(4.10))

        XCTAssertEqual(notice?.level, .over)
        XCTAssertEqual(notice?.text.contains("$4.10"), true)
        XCTAssertEqual(notice?.text.contains("$3.00"), true)
    }

    /// A total built partly from guesses is a floor, not a sum, and saying so
    /// costs one word.
    func testAnApproximateTotalSaysItIsAtLeastThatMuch() {
        let notice = budget.notice(for: summary(4.10, estimated: 1))

        XCTAssertEqual(notice?.text.contains("at least"), true)
    }

    /// Nobody has to have a limit. Zero means no limit rather than a limit of
    /// nothing, which would make every round a warning.
    func testNoLimitMeansNothingToWarnAbout() {
        let none = Budget(limit: 0)

        XCTAssertEqual(none.level(spent: 99), .fine)
        XCTAssertNil(none.notice(for: summary(99)))
    }
}

/// The line the menu shows. It is the only place the spending is visible
/// without opening a window, so it has to carry the month, the amount and the
/// limit at a glance.
final class SpendLineTests: XCTestCase {
    private func summary(_ total: Double, estimated: Int = 0, unpriced: Int = 0) -> SpendSummary {
        SpendSummary(
            monthStart: Calendar.current.date(from: DateComponents(year: 2026, month: 9, day: 1))!,
            total: total,
            rounds: 3,
            estimatedRounds: estimated,
            unpricedRounds: unpriced
        )
    }

    func testTheLineNamesTheMonthTheAmountAndTheLimit() {
        XCTAssertEqual(summary(0.42).describe(limit: 3), "Spent in September: $0.42 of $3.00")
    }

    func testWithoutALimitTheLineIsJustTheAmount() {
        XCTAssertEqual(summary(0.42).describe(limit: 0), "Spent in September: $0.42")
    }

    /// A month holding guessed or unpriced rounds is a floor and not a sum.
    func testAnApproximateMonthSaysSoInTheMenu() {
        XCTAssertEqual(summary(0.42, unpriced: 1).describe(limit: 3),
                       "Spent in September: at least $0.42 of $3.00")
    }
}

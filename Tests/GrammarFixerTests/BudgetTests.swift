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
        // Never a bare figure: the amount rests on a published price list
        // rather than on an invoice.
        XCTAssertEqual(notice?.text.contains("about"), true)
    }

    /// A round nothing can price is not in the total at all, and the notice
    /// says how many such rounds the month holds. Leaving it out would let a
    /// month of unpriced rounds read as a cheap month.
    func testRoundsWithNoPriceAreSaidToBeMissingFromTheFigure() {
        let notice = budget.notice(for: summary(4.10, unpriced: 2))

        XCTAssertEqual(notice?.text.contains("2 rounds are not in that figure"), true)
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

    /// "About" is not a hedge here, it is the truth: the figure comes from a
    /// published price list and not from an invoice.
    func testTheLineNamesTheMonthTheAmountAndTheLimit() {
        XCTAssertEqual(summary(0.42).describe(limit: 3), "Spent in September: about $0.42 of $3.00")
    }

    func testWithoutALimitTheLineIsJustTheAmount() {
        XCTAssertEqual(summary(0.42).describe(limit: 0), "Spent in September: about $0.42")
    }

    /// Tokens are the part that came from the provider rather than from a
    /// price list, so they are shown as they are.
    func testTokensAreShownAsTheyCame() {
        let month = SpendSummary(
            monthStart: Date(),
            total: 0.42,
            rounds: 3,
            promptTokens: 12_400,
            completionTokens: 900,
            estimatedRounds: 0,
            unpricedRounds: 0
        )

        XCTAssertEqual(month.tokens, "12.4k in + 900 out")
    }
}

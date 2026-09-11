import Foundation

/// The monthly limit, and what to say about it.
///
/// The limit is soft by design. The request always goes out: an app that
/// refused to correct a sentence because of a figure somebody typed once would
/// be worse than the subscription it replaced. What it does instead is make the
/// number impossible to miss.
public struct Budget: Equatable, Sendable {
    public static let `default` = 3.0

    /// Dollars a month. Zero or less means no limit at all, rather than a
    /// limit of nothing.
    public let limit: Double

    /// Warning while there is still room to decide what to do about it. A
    /// warning that arrives only once the money is gone is a receipt.
    public static let warningFraction = 0.8

    public init(limit: Double) {
        self.limit = limit
    }

    public enum Level: Equatable, Sendable {
        case fine
        case approaching
        case over
    }

    public var isSet: Bool { limit > 0 }

    public func level(spent: Double) -> Level {
        guard isSet else { return .fine }
        // Compared with room to spare on purpose. Eighty per cent of $3.00 is
        // not $2.40 in binary but a hair above it, so an exact comparison
        // would let the amount that is meant to trigger the warning pass
        // silently. A hundredth of a cent is below anything that could be
        // shown anyway.
        let epsilon = 0.000_01
        if spent >= limit - epsilon { return .over }
        if spent >= limit * Self.warningFraction - epsilon { return .approaching }
        return .fine
    }

    /// What the panel says, or nothing at all while the month is quiet.
    public func notice(for summary: SpendSummary) -> BudgetNotice? {
        let level = level(spent: summary.total)
        guard level != .fine else { return nil }

        // "At least" because a month holding guessed or unpriced rounds is a
        // floor and not a sum. One word, and the figure stops pretending.
        let spent = summary.isApproximate
            ? "at least \(Money.text(summary.total))"
            : Money.text(summary.total)

        switch level {
        case .over:
            return BudgetNotice(
                level: .over,
                text: "\(spent) spent this month, past the \(Money.text(limit)) limit. "
                    + "Corrections go on working."
            )
        case .approaching:
            return BudgetNotice(
                level: .approaching,
                text: "\(spent) of the \(Money.text(limit)) monthly limit spent."
            )
        case .fine:
            return nil
        }
    }
}

public struct BudgetNotice: Equatable, Sendable {
    public let level: Budget.Level
    public let text: String

    public init(level: Budget.Level, text: String) {
        self.level = level
        self.text = text
    }
}

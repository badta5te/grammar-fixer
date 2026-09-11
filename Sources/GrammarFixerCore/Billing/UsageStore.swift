import Foundation

/// What the month cost so far.
public struct SpendSummary: Equatable, Sendable {
    /// Midnight on the first, in the local time zone.
    public var monthStart: Date
    /// The dollars that could actually be priced.
    public var total: Double
    public var rounds: Int
    /// Rounds counted from guessed token numbers. They are in the total and
    /// they are not exact.
    public var estimatedRounds: Int
    /// Rounds nothing here can price. They are not in the total at all, so the
    /// total is a floor whenever this is above zero.
    public var unpricedRounds: Int

    public init(
        monthStart: Date,
        total: Double,
        rounds: Int,
        estimatedRounds: Int,
        unpricedRounds: Int
    ) {
        self.monthStart = monthStart
        self.total = total
        self.rounds = rounds
        self.estimatedRounds = estimatedRounds
        self.unpricedRounds = unpricedRounds
    }

    /// Whether the total is a lower bound rather than a sum. Shown wherever
    /// the amount is: a figure that looks exact without being exact is worse
    /// than a vaguer one that admits it.
    public var isApproximate: Bool { estimatedRounds > 0 || unpricedRounds > 0 }

    /// The line in the menu. It names the month, because a total with no month
    /// on it invites the question every time it is read.
    public func describe(limit: Double) -> String {
        let spent = isApproximate ? "at least \(Money.text(total))" : Money.text(total)
        let month = Self.monthName.string(from: monthStart)
        guard limit > 0 else { return "Spent in \(month): \(spent)" }
        return "Spent in \(month): \(spent) of \(Money.text(limit))"
    }

    /// English month names in an app whose every other word is English. A
    /// localized name here would be the one translated word on the screen.
    private static let monthName: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US")
        formatter.setLocalizedDateFormatFromTemplate("LLLL")
        return formatter
    }()
}

/// The spending history, kept in a file of its own.
///
/// Tokens are what is stored. Money is worked out on the way out, from the
/// price table as it stands now, so a price corrected in the settings window
/// reaches the rounds that came before it. A month total is therefore always
/// the current answer to "what did this cost", not a frozen one.
@MainActor
@Observable
public final class UsageStore {
    public static let fileURL = FileManager.default
        .homeDirectoryForCurrentUser
        .appending(path: "Library/Application Support/GrammarFixer/usage.json")

    /// Old rounds are dropped, but only well past the point where any counter
    /// could still want them: the app lives in the background for months and
    /// nobody ever cleans this file up.
    private static let keepFor = DateComponents(month: -13)

    public private(set) var records: [UsageRecord] = []

    /// Called when a round lands. The settings window redraws itself, being a
    /// view of an observable object, but the menu bar icon is not a view of
    /// anything and would otherwise tell the truth only to whoever happened to
    /// open the menu.
    @ObservationIgnored
    public var onChange: () -> Void = {}

    @ObservationIgnored private let fileURL: URL
    @ObservationIgnored private let calendar: Calendar
    @ObservationIgnored private let now: () -> Date

    public init(
        fileURL: URL = UsageStore.fileURL,
        calendar: Calendar = .current,
        now: @escaping () -> Date = Date.init
    ) {
        self.fileURL = fileURL
        self.calendar = calendar
        self.now = now
        records = Self.read(fileURL)
    }

    public func add(_ record: UsageRecord) {
        records.append(record)
        forgetTheDistantPast()
        write()
        onChange()
    }

    /// The month a date falls in, by the local calendar, turning at midnight
    /// on the first. The rule is stated here and nowhere else.
    public func summary(prices: PriceTable, containing date: Date? = nil) -> SpendSummary {
        let month = calendar.dateInterval(of: .month, for: date ?? now())
        let start = month?.start ?? (date ?? now())
        let thisMonth = records.filter { month?.contains($0.date) ?? false }

        var total = 0.0
        var unpriced = 0
        for record in thisMonth {
            if let cost = prices.cost(of: record) {
                total += cost
            } else {
                unpriced += 1
            }
        }

        return SpendSummary(
            monthStart: start,
            total: total,
            rounds: thisMonth.count,
            estimatedRounds: thisMonth.count { $0.isEstimated },
            unpricedRounds: unpriced
        )
    }

    private func forgetTheDistantPast() {
        guard let oldest = calendar.date(byAdding: Self.keepFor, to: now()) else { return }
        records.removeAll { $0.date < oldest }
    }

    private func write() {
        do {
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(records).write(to: fileURL, options: .atomic)
        } catch {
            // A history that cannot be written is a counter that forgets, not
            // a round that failed. The correction itself is already done and
            // saying nothing about it here is deliberate.
            Log.write("the spending history could not be written: \(error.localizedDescription)")
        }
    }

    /// A missing file is a first launch and a damaged one is not worth dying
    /// for: this is read while the app is starting, and throwing here would be
    /// an app that will not start because of a counter.
    private static func read(_ url: URL) -> [UsageRecord] {
        guard let data = try? Data(contentsOf: url) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let records = try? decoder.decode([UsageRecord].self, from: data) else {
            Log.write("the spending history could not be read, starting a new one")
            return []
        }
        return records
    }
}

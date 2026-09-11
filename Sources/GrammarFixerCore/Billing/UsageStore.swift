import Foundation

/// One provider's share of the month. Somebody who tried three providers
/// during a month is owed the breakdown: a single total says nothing about
/// which of them the money went to, and that is the question behind trying
/// them at all.
public struct ProviderSpend: Equatable, Sendable, Identifiable {
    public var id: String { provider }
    public var provider: String
    public var rounds: Int
    public var promptTokens: Int
    public var completionTokens: Int
    public var total: Double
    public var estimatedRounds: Int
    public var unpricedRounds: Int

    public init(
        provider: String,
        rounds: Int,
        promptTokens: Int,
        completionTokens: Int,
        total: Double,
        estimatedRounds: Int,
        unpricedRounds: Int
    ) {
        self.provider = provider
        self.rounds = rounds
        self.promptTokens = promptTokens
        self.completionTokens = completionTokens
        self.total = total
        self.estimatedRounds = estimatedRounds
        self.unpricedRounds = unpricedRounds
    }

    public var isApproximate: Bool { estimatedRounds > 0 || unpricedRounds > 0 }
}

/// What the month cost so far.
public struct SpendSummary: Equatable, Sendable {
    /// Midnight on the first, in the local time zone.
    public var monthStart: Date
    /// The dollars that could actually be priced.
    public var total: Double
    public var rounds: Int
    /// Tokens are the exact part of all this. They come from the provider,
    /// and unlike the money they are not read off a price list that could be
    /// stale, missing or wrong.
    public var promptTokens: Int
    public var completionTokens: Int
    /// The month split by provider, biggest spender first. Empty when only
    /// one provider was used: a breakdown of one row is a row repeated.
    public var providers: [ProviderSpend]
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
        promptTokens: Int = 0,
        completionTokens: Int = 0,
        providers: [ProviderSpend] = [],
        estimatedRounds: Int,
        unpricedRounds: Int
    ) {
        self.monthStart = monthStart
        self.total = total
        self.rounds = rounds
        self.promptTokens = promptTokens
        self.completionTokens = completionTokens
        self.providers = providers
        self.estimatedRounds = estimatedRounds
        self.unpricedRounds = unpricedRounds
    }

    /// Whether the total is a lower bound rather than a sum. Shown wherever
    /// the amount is: a figure that looks exact without being exact is worse
    /// than a vaguer one that admits it.
    public var isApproximate: Bool { estimatedRounds > 0 || unpricedRounds > 0 }

    /// The line in the menu. It names the month, because a total with no month
    /// on it invites the question every time it is read.
    ///
    /// "About", always. Every figure here rests on a published price list
    /// rather than on an invoice: the price may be a day out of date, it may
    /// not cover the model at all, and some rounds are counted from the text.
    /// Calling the number exact would be the one thing this counter must not
    /// do.
    public func describe(limit: Double) -> String {
        let month = Self.monthName.string(from: monthStart)
        let spent = "about \(Money.text(total))"
        guard limit > 0 else { return "Spent in \(month): \(spent)" }
        return "Spent in \(month): \(spent) of \(Money.text(limit))"
    }

    /// The tokens of the month, which are the part that is not guesswork.
    public var tokens: String {
        "\(TokenCount.text(promptTokens)) in + \(TokenCount.text(completionTokens)) out"
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
            promptTokens: thisMonth.reduce(0) { $0 + $1.promptTokens },
            completionTokens: thisMonth.reduce(0) { $0 + $1.completionTokens },
            providers: Self.split(thisMonth, prices: prices),
            estimatedRounds: thisMonth.count { $0.isEstimated },
            unpricedRounds: unpriced
        )
    }

    /// The month by provider, dearest first, and nothing at all when there
    /// was only one of them.
    private static func split(_ records: [UsageRecord], prices: PriceTable) -> [ProviderSpend] {
        let names = Set(records.map(\.provider))
        guard names.count > 1 else { return [] }

        return names.map { name in
            let mine = records.filter { $0.provider == name }
            return ProviderSpend(
                provider: name,
                rounds: mine.count,
                promptTokens: mine.reduce(0) { $0 + $1.promptTokens },
                completionTokens: mine.reduce(0) { $0 + $1.completionTokens },
                total: mine.reduce(0.0) { $0 + (prices.cost(of: $1) ?? 0) },
                estimatedRounds: mine.count { $0.isEstimated },
                unpricedRounds: mine.count { prices.cost(of: $0) == nil }
            )
        }
        // Dearest first, and by name where nothing can be priced, so the
        // order does not shuffle about between openings of the window.
        .sorted {
            $0.total == $1.total ? $0.provider < $1.provider : $0.total > $1.total
        }
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

import Foundation

/// What a provider charges per million tokens, in dollars.
public struct Price: Codable, Equatable, Sendable {
    public var input: Double
    public var output: Double

    public init(input: Double, output: Double) {
        self.input = input
        self.output = output
    }

    /// A price as somebody typed it into two fields. Nil rather than zero when
    /// it is not a number: a price of zero would count a paid round as free,
    /// while nothing at all leaves the round marked unpriced, which is true.
    public static func parse(input: String, output: String) -> Price? {
        guard let input = Money.parse(input), let output = Money.parse(output) else { return nil }
        return Price(input: input, output: output)
    }
}

/// The prices this app knows, keyed by provider and model.
///
/// Two things about the key are deliberate. It carries the provider, because
/// the same model name reaches different bills through a reseller. And a name
/// matches by its prefix as well as exactly, because providers append release
/// dates to their models and pricing by exact name alone would leave most real
/// names unpriced.
public struct PriceTable: Equatable, Sendable {
    /// Keyed `provider/model`. The provider ends at the first slash; model
    /// names may contain slashes of their own, as OpenRouter's do.
    public private(set) var entries: [String: Price]

    public init(entries: [String: Price] = [:]) {
        self.entries = entries
    }

    public static func key(provider: String, model: String) -> String {
        "\(provider.lowercased().trimmed)/\(model.lowercased().trimmed)"
    }

    public static func split(_ key: String) -> (provider: String, model: String) {
        guard let slash = key.firstIndex(of: "/") else { return (key, "") }
        return (String(key[key.startIndex ..< slash]), String(key[key.index(after: slash)...]))
    }

    public func price(provider: String, model: String) -> Price? {
        let wanted = Self.key(provider: provider, model: model)
        if let exact = entries[wanted] { return exact }

        // The longest prefix wins, so `gpt-4.1-mini` is not paid for at
        // `gpt-4.1` rates when both are in the table.
        return entries
            .filter { wanted.hasPrefix($0.key) }
            .max { $0.key.count < $1.key.count }?
            .value
    }

    /// What the round cost, or nil when nothing here can price it. Nil rather
    /// than zero: a round nobody has a price for was not free, and counting it
    /// as free is the one answer that is certainly wrong.
    public func cost(of record: UsageRecord) -> Double? {
        guard let price = price(provider: record.provider, model: record.model) else { return nil }
        return Double(record.promptTokens) / 1_000_000 * price.input
            + Double(record.completionTokens) / 1_000_000 * price.output
    }

    /// The shipped table with somebody's own entries laid over it. Only their
    /// entries are stored, so a corrected price in a later version reaches
    /// everybody who never edited that row.
    public func merging(_ overrides: [String: Price]) -> PriceTable {
        PriceTable(entries: entries.merging(overrides) { _, mine in mine })
    }
}

/// Amounts as they are shown. Dollars because that is what every one of these
/// providers bills in, whatever the machine's own currency happens to be.
public enum Money {
    /// An amount as somebody typed it. Nil when it is not one: a field being
    /// typed into passes through states that are not numbers yet, and the
    /// caller decides what that means rather than being handed a zero.
    public static func parse(_ text: String) -> Double? {
        // A comma for a decimal point is how half the world types, and a
        // dollar sign usually comes along when the figure is pasted from the
        // provider's own page.
        let cleaned = text
            .replacingOccurrences(of: ",", with: ".")
            .replacingOccurrences(of: "$", with: "")
            .trimmed
        guard let value = Double(cleaned), value >= 0 else { return nil }
        return value
    }

    public static func text(_ amount: Double) -> String {
        // A single correction costs a fraction of a cent. Rounding it to
        // "$0.00" makes a counter that has just been paid look broken, and
        // inventing extra decimals makes an estimate look precise.
        if amount > 0 && amount < 0.005 { return "<$0.01" }
        return String(format: "$%.2f", amount)
    }
}

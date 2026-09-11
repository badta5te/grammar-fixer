import Foundation

/// The catalogue this app takes its prices from.
///
/// models.dev publishes one JSON file covering every provider here, keyed by
/// the same provider names and the same model names the providers themselves
/// use. It is read rather than trusted blindly: prices are shown as
/// approximate wherever they appear, and a figure typed by hand always wins.
public enum ModelsDev {
    public static let url = URL(string: "https://models.dev/api.json")!

    /// The shown source of the prices. Somebody is entitled to know where a
    /// figure about their own money came from.
    public static let name = "models.dev"

    /// `{ provider: { models: { model: { cost: { input, output } } } } }`,
    /// flattened to the keys `PriceTable` uses. Amounts are per million
    /// tokens, which is what the file already holds.
    ///
    /// Read with JSONSerialization rather than Decodable: the file is four
    /// megabytes of fields this app has no interest in, and a Codable mirror
    /// of it would be a second thing to maintain whenever they add one.
    public static func parse(_ data: Data) throws -> [String: Price] {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw LLMError.pricesUnreadable
        }

        var entries: [String: Price] = [:]
        for (provider, value) in root {
            guard let provider = provider as String?,
                  let models = (value as? [String: Any])?["models"] as? [String: Any]
            else { continue }

            for (model, model_) in models {
                guard let cost = (model_ as? [String: Any])?["cost"] as? [String: Any],
                      let input = cost["input"] as? Double,
                      let output = cost["output"] as? Double
                else { continue }
                // A pair of zeros in the catalogue is a gap rather than a
                // free model: several closed, paid models are listed at
                // $0.00/$0.00 because nobody has filled the figures in.
                // Reading that as free would count a paid round as costing
                // nothing, which is the one answer this counter must never
                // give. Anybody genuinely running something free can type a
                // zero themselves, and a typed price always wins.
                guard input > 0 || output > 0 else { continue }
                entries[PriceTable.key(provider: provider, model: model)] =
                    Price(input: input, output: output)
            }
        }

        guard !entries.isEmpty else { throw LLMError.pricesUnreadable }
        return entries
    }
}

/// The prices in hand, and the one job of keeping them current.
///
/// Nothing is compiled into the app any more. A price table in the source is
/// wrong the moment a provider changes a figure, and the first version of this
/// counter shipped an output price two and a half times too high — the same
/// argument that took the list of model names out of the source.
@MainActor
@Observable
public final class PriceCatalog {
    public static let cacheURL = FileManager.default
        .homeDirectoryForCurrentUser
        .appending(path: "Library/Application Support/GrammarFixer/prices.json")

    /// Once a day is plenty. Prices change a few times a year, and a
    /// correction must never wait on a price list.
    private static let staleAfter: TimeInterval = 24 * 60 * 60

    public private(set) var entries: [String: Price] = [:]
    public private(set) var fetchedAt: Date?
    /// Why the last attempt came back with nothing. Shown in the window: a
    /// counter that stopped being updated has to be able to say so.
    public private(set) var failure: String?
    public private(set) var isLoading = false

    @ObservationIgnored private let cacheURL: URL
    @ObservationIgnored private let now: () -> Date
    @ObservationIgnored private let fetch: () async throws -> Data
    @ObservationIgnored private var overrides: () -> [String: Price] = { [:] }

    public init(
        cacheURL: URL = PriceCatalog.cacheURL,
        now: @escaping () -> Date = Date.init,
        fetch: @escaping () async throws -> Data = PriceCatalog.download
    ) {
        self.cacheURL = cacheURL
        self.now = now
        self.fetch = fetch
        if let cached = Cache.read(cacheURL) {
            entries = cached.entries
            fetchedAt = cached.fetchedAt
        }
    }

    /// Where the hand-typed prices come from. Set once by the app so that
    /// everything asking this object for a price gets the whole answer,
    /// instead of four callers each remembering to merge.
    public func readOverrides(from settings: Settings) {
        overrides = { settings.priceOverrides }
    }

    public var table: PriceTable { table(with: overrides()) }

    public func table(with overrides: [String: Price]) -> PriceTable {
        PriceTable(entries: entries).merging(overrides)
    }

    public var isStale: Bool {
        guard let fetchedAt else { return true }
        return now().timeIntervalSince(fetchedAt) > Self.staleAfter
    }

    public func refreshIfStale() async {
        guard isStale else { return }
        await refresh()
    }

    /// Asks the catalogue. A failure keeps whatever prices are already in
    /// hand: no network is not the same as nothing being worth anything.
    public func refresh() async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }

        do {
            let parsed = try ModelsDev.parse(try await fetch())
            entries = parsed
            fetchedAt = now()
            failure = nil
            Cache.write(Cache(fetchedAt: now(), entries: parsed), to: cacheURL)
            Log.write("prices from \(ModelsDev.name): \(parsed.count) models")
        } catch {
            failure = (error as? any UserFacingError)?.message ?? error.localizedDescription
            Log.write("prices not fetched: \(failure ?? "")")
        }
    }

    public static func download() async throws -> Data {
        var request = URLRequest(url: ModelsDev.url, timeoutInterval: 20)
        // A plain GET of a public file. Nothing of this person goes with it:
        // not the key, not the prompt, not the model they use.
        request.httpMethod = "GET"
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let status = (response as? HTTPURLResponse)?.statusCode,
                  (200..<300).contains(status)
            else { throw LLMError.pricesUnreadable }
            return data
        } catch {
            throw LLMError.from(error)
        }
    }

    /// The prices as last fetched, so a launch with no network still knows
    /// what a round costs.
    private struct Cache: Codable {
        var fetchedAt: Date
        var entries: [String: Price]

        @MainActor static func read(_ url: URL) -> Cache? {
            guard let data = try? Data(contentsOf: url) else { return nil }
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            return try? decoder.decode(Cache.self, from: data)
        }

        @MainActor static func write(_ cache: Cache, to url: URL) {
            do {
                try FileManager.default.createDirectory(
                    at: url.deletingLastPathComponent(),
                    withIntermediateDirectories: true
                )
                let encoder = JSONEncoder()
                encoder.dateEncodingStrategy = .iso8601
                try encoder.encode(cache).write(to: url, options: .atomic)
            } catch {
                // The prices are in memory and the month still adds up. They
                // will simply be fetched again on the next launch.
                Log.write("the price cache could not be written: \(error.localizedDescription)")
            }
        }
    }
}

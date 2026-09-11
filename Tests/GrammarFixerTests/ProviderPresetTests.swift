import XCTest
@testable import GrammarFixerCore

/// The preset list is the one place that knows where a provider lives. It feeds
/// the settings window, the address resolution and the error message that names
/// what is on offer, so a second copy of it anywhere would drift.
final class ProviderPresetTests: XCTestCase {
    func testTheFourNamedProvidersAreOnOffer() {
        let ids = ProviderPreset.all.map(\.id)

        for expected in ["openai", "anthropic", "deepseek", "openrouter"] {
            XCTAssertTrue(ids.contains(expected), "нет пресета \(expected)")
        }
    }

    /// Anything that is not one of the named providers is still reachable, so
    /// the list ends with an entry whose address the person types.
    func testTheListEndsWithAnEntryForYourOwnAddress() {
        XCTAssertEqual(ProviderPreset.all.last, .custom)
        XCTAssertNil(ProviderPreset.custom.baseURL)
        XCTAssertTrue(ProviderPreset.custom.wantsItsOwnAddress)
    }

    func testEveryNamedProviderCarriesAnAbsoluteAddress() {
        for preset in ProviderPreset.all where !preset.wantsItsOwnAddress {
            guard let address = preset.baseURL, let url = URL(string: address) else {
                return XCTFail("\(preset.id): адрес не разбирается")
            }
            XCTAssertEqual(url.scheme, "https", "\(preset.id): адрес не https")
        }
    }

    /// A person types a provider name into the file by hand, and a capital
    /// letter or a stray space is not a different provider.
    func testLookupForgivesCaseAndSpaces() {
        XCTAssertEqual(ProviderPreset.named("  DeepSeek ")?.id, "deepseek")
    }

    func testAnUnknownNameIsNotAPreset() {
        XCTAssertNil(ProviderPreset.named("выдумка"))
    }

    /// The whole reason there are two adapters rather than one.
    func testAnthropicIsTheOnlyOneThatIsNotOpenAiCompatible() {
        let odd = ProviderPreset.all.filter { $0.kind != .openAICompatible }

        XCTAssertEqual(odd.map(\.id), ["anthropic"])
    }

    /// The message a person sees when a provider name is not recognised is
    /// built from this same list, so it cannot name a provider that is gone.
    func testTheNamesForAMessageListEveryPresetExceptYourOwnAddress() {
        let names = ProviderPreset.namesForMessage

        XCTAssertTrue(names.contains("deepseek"))
        XCTAssertTrue(names.contains("anthropic"))
        XCTAssertFalse(names.contains(ProviderPreset.custom.id))
    }

    func testIdentifiersAreUnique() {
        XCTAssertEqual(Set(ProviderPreset.all.map(\.id)).count, ProviderPreset.all.count)
    }
}

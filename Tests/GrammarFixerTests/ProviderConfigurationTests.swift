import XCTest
@testable import GrammarFixerCore

/// There are no settings with a window yet; those arrive in ticket 06. For now
/// the provider is described by a file, and parsing that file is the one place
/// where a person can go wrong silently.
final class ProviderConfigurationTests: XCTestCase {
    private let path = "~/.config/grammar-fixer/config.json"

    private func make(_ json: String?, environment: [String: String] = [:]) throws -> ProviderConfiguration {
        try ProviderConfiguration.make(
            fileContents: json?.data(using: .utf8),
            environment: environment,
            path: path
        )
    }

    func testPresetGivesTheBaseUrl() throws {
        let config = try make(#"{"provider":"deepseek","model":"deepseek-flash","apiKey":"k"}"#)
        XCTAssertEqual(config.baseURL.absoluteString, "https://api.deepseek.com")
        XCTAssertEqual(config.model, "deepseek-flash")
        XCTAssertEqual(config.apiKey, "k")
    }

    func testExplicitBaseUrlWins() throws {
        let config = try make(
            #"{"provider":"openai","model":"m","apiKey":"k","baseURL":"http://localhost:1234/v1"}"#
        )
        XCTAssertEqual(config.baseURL.absoluteString, "http://localhost:1234/v1")
    }

    func testAnyOpenAiCompatibleEndpointWorksWithoutAPreset() throws {
        let config = try make(#"{"model":"m","apiKey":"k","baseURL":"http://localhost:11434/v1"}"#)
        XCTAssertEqual(config.baseURL.absoluteString, "http://localhost:11434/v1")
    }

    func testEnvironmentOverridesTheFile() throws {
        let config = try make(
            #"{"provider":"openai","model":"gpt-4o-mini","apiKey":"from-file"}"#,
            environment: ["GRAMMARFIXER_API_KEY": "from-env", "GRAMMARFIXER_MODEL": "other"]
        )
        XCTAssertEqual(config.apiKey, "from-env")
        XCTAssertEqual(config.model, "other")
    }

    /// The first launch after this ticket is a launch with no file. It has to
    /// explain what to do rather than fail with a network error.
    func testMissingFileNamesItself() {
        XCTAssertThrowsError(try make(nil)) { error in
            XCTAssertEqual(error as? LLMError, .noConfiguration(path: path))
        }
    }

    func testBrokenJsonSaysSo() {
        XCTAssertThrowsError(try make("{это не json")) { error in
            guard case LLMError.brokenConfiguration(let path, _)? = error as? LLMError else {
                return XCTFail("ожидался разбор файла, получено \(error)")
            }
            XCTAssertEqual(path, self.path)
        }
    }

    func testEmptyKeyIsTheSameAsNoKey() {
        XCTAssertThrowsError(try make(#"{"provider":"openai","model":"m","apiKey":"  "}"#)) { error in
            XCTAssertEqual(error as? LLMError, .noKey(path: path))
        }
    }

    func testMissingModelIsNamed() {
        XCTAssertThrowsError(try make(#"{"provider":"openai","apiKey":"k"}"#)) { error in
            guard case LLMError.brokenConfiguration(_, let reason)? = error as? LLMError else {
                return XCTFail("ожидался разбор файла, получено \(error)")
            }
            XCTAssertTrue(reason.contains("model"))
        }
    }

    func testUnknownProviderWithoutBaseUrlIsNamed() {
        XCTAssertThrowsError(try make(#"{"provider":"выдумка","model":"m","apiKey":"k"}"#)) { error in
            guard case LLMError.brokenConfiguration(_, let reason)? = error as? LLMError else {
                return XCTFail("ожидался разбор файла, получено \(error)")
            }
            XCTAssertTrue(reason.contains("baseURL"))
        }
    }

    func testUsageRequestIsOnUnlessTurnedOff() throws {
        let on = try make(#"{"provider":"openai","model":"m","apiKey":"k"}"#)
        XCTAssertTrue(on.requestsUsage)
        let off = try make(#"{"provider":"openai","model":"m","apiKey":"k","requestUsage":false}"#)
        XCTAssertFalse(off.requestsUsage)
    }
}

/// Nobody eyeballs the template, and a broken template is what greets a person
/// on their very first launch.
extension ProviderConfigurationTests {
    func testTheTemplateIsValidJsonWithBlanksToFillIn() {
        XCTAssertThrowsError(
            try ProviderConfiguration.make(
                fileContents: ProviderConfigurationFile.template.data(using: .utf8),
                environment: [:],
                path: path
            )
        ) { error in
            XCTAssertEqual(error as? LLMError, .noKey(path: path))
        }

        // The model is left blank on purpose. A plausible but outdated name
        // looks filled in, and the provider's refusal then reads as a broken
        // app rather than as a name to change.
        XCTAssertThrowsError(
            try ProviderConfiguration.make(
                fileContents: ProviderConfigurationFile.template.data(using: .utf8),
                environment: ["GRAMMARFIXER_API_KEY": "k"],
                path: path
            )
        ) { error in
            guard case LLMError.brokenConfiguration(_, let reason)? = error as? LLMError else {
                return XCTFail("ожидался разбор файла, получено \(error)")
            }
            XCTAssertTrue(reason.contains("model"))
        }
    }

    func testTheTemplateStartsWithAnOpeningBrace() {
        XCTAssertTrue(ProviderConfigurationFile.template.hasPrefix("{"))
    }
}

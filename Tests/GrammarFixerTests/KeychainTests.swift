import XCTest
@testable import GrammarFixerCore

/// Checked against the real Keychain under a service name unique to the run,
/// the same way the clipboard is checked against a named pasteboard: a test has
/// no right to touch what a person actually stores.
///
/// The real thing rather than a double, because the whole point of this type is
/// the four calls into Security.framework, and those are exactly what a double
/// would replace.
final class KeychainTests: XCTestCase {
    private var keychain: Keychain!

    override func setUp() async throws {
        keychain = Keychain(service: "com.badta5te.GrammarFixer.tests.\(UUID().uuidString)")
    }

    override func tearDown() async throws {
        try? keychain.removeSecret(for: "deepseek")
        try? keychain.removeSecret(for: "openai")
    }

    func testAStoredSecretComesBack() throws {
        try keychain.store("sk-секрет", for: "deepseek")

        XCTAssertEqual(try keychain.secret(for: "deepseek"), "sk-секрет")
    }

    /// An account with nothing in it is the first launch, not a failure. If it
    /// threw, the app would greet a new person with a Keychain error instead of
    /// an empty field.
    func testAnUnknownAccountIsEmptyRatherThanAFailure() throws {
        XCTAssertNil(try keychain.secret(for: "deepseek"))
    }

    /// Storing twice is what happens when somebody pastes a new key over an
    /// old one. SecItemAdd alone would answer errSecDuplicateItem and the new
    /// key would never be saved.
    func testAKeyPastedOverAnOldOneReplacesIt() throws {
        try keychain.store("первый", for: "deepseek")
        try keychain.store("второй", for: "deepseek")

        XCTAssertEqual(try keychain.secret(for: "deepseek"), "второй")
    }

    func testRemovingLeavesNothingBehind() throws {
        try keychain.store("sk-секрет", for: "deepseek")

        try keychain.removeSecret(for: "deepseek")

        XCTAssertNil(try keychain.secret(for: "deepseek"))
    }

    /// Removing what is not there is what a person does by clearing an already
    /// empty field. Nothing to report.
    func testRemovingNothingIsNotAFailure() throws {
        XCTAssertNoThrow(try keychain.removeSecret(for: "deepseek"))
    }

    /// Keys are kept per provider on purpose: trying DeepSeek for a week and
    /// coming back to OpenAI must not cost the OpenAI key.
    func testEachProviderKeepsItsOwnKey() throws {
        try keychain.store("ключ-deepseek", for: "deepseek")
        try keychain.store("ключ-openai", for: "openai")

        XCTAssertEqual(try keychain.secret(for: "deepseek"), "ключ-deepseek")
        XCTAssertEqual(try keychain.secret(for: "openai"), "ключ-openai")
    }
}

import XCTest
@testable import GrammarFixerCore

/// Settings are read afresh on every round so a switch takes effect without a
/// restart. The defaults matter in their own right: on a first launch there are
/// no keys at all.
@MainActor
final class SettingsTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUp() async throws {
        suiteName = "com.badta5te.GrammarFixer.tests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() async throws {
        defaults.removePersistentDomain(forName: suiteName)
    }

    func testClipboardIsRestoredByDefault() {
        XCTAssertTrue(Settings(defaults: defaults).restoreClipboardAfterPaste)
    }

    func testClipboardRestorationCanBeTurnedOff() {
        let settings = Settings(defaults: defaults)
        settings.restoreClipboardAfterPaste = false

        XCTAssertFalse(Settings(defaults: defaults).restoreClipboardAfterPaste)
    }

    func testPasteGoesThroughTheClipboardByDefault() {
        XCTAssertEqual(Settings(defaults: defaults).pasteMethod, .clipboard)
    }

    func testPasteMethodSurvivesARestart() {
        Settings(defaults: defaults).pasteMethod = .typing

        XCTAssertEqual(Settings(defaults: defaults).pasteMethod, .typing)
    }

    /// A key can be corrupted by hand through defaults write, and that must
    /// not stop the app from pasting.
    func testAnUnknownPasteMethodFallsBackToTheClipboard() {
        defaults.set("carrier pigeon", forKey: Settings.pasteMethodKey)

        XCTAssertEqual(Settings(defaults: defaults).pasteMethod, .clipboard)
    }
}

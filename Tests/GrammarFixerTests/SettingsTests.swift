import XCTest
@testable import GrammarFixerCore

/// Настройки читаются заново на каждом круге, чтобы переключатель действовал
/// без перезапуска. Значения по умолчанию важны сами по себе: при первом
/// запуске никаких ключей ещё нет.
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

    /// Ключ можно испортить руками через defaults write, и приложение не должно
    /// от этого перестать вставлять.
    func testAnUnknownPasteMethodFallsBackToTheClipboard() {
        defaults.set("carrier pigeon", forKey: Settings.pasteMethodKey)

        XCTAssertEqual(Settings(defaults: defaults).pasteMethod, .clipboard)
    }
}

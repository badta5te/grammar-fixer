import AppKit
import Carbon.HIToolbox
import XCTest
@testable import GrammarFixerCore

/// The settings window's hold on the shortcut.
///
/// While the field listens for a combination the global hot key is given back,
/// or the very combination somebody is replacing would start a round instead of
/// being recorded. Everything that can end that listening has to hand the key
/// back, including the ways that do not go through the field at all: the app has
/// no Dock icon and no window of its own, so a key left unregistered is an app
/// with no way in until the next launch.
@MainActor
final class SettingsPanelTests: XCTestCase {
    private var suiteName: String!
    private var directory: URL!
    private var settings: Settings!
    private var registrar: FakeHotKeyRegistrar!
    private var notices: FakeNotices!

    override func setUp() async throws {
        suiteName = "com.badta5te.GrammarFixer.tests.\(UUID().uuidString)"
        settings = Settings(defaults: UserDefaults(suiteName: suiteName)!)
        directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        registrar = FakeHotKeyRegistrar()
        notices = FakeNotices()
    }

    override func tearDown() async throws {
        UserDefaults().removePersistentDomain(forName: suiteName)
        try? FileManager.default.removeItem(at: directory)
    }

    private func makeBinder() -> ShortcutBinder {
        ShortcutBinder(
            settings: settings,
            notices: notices,
            systemShortcuts: { [] },
            register: { [registrar] shortcut, action in registrar!.register(shortcut, action) },
            action: {}
        )
    }

    private func makePanel(shortcut binder: ShortcutBinder) -> SettingsPanel {
        SettingsPanel(
            settings: settings,
            store: ProviderStore(settings: settings, secrets: FakeSecrets(), environment: [:]),
            usage: UsageStore(fileURL: directory.appendingPathComponent("usage.json")),
            catalog: PriceCatalog(
                cacheURL: directory.appendingPathComponent("prices.json"),
                fetch: { throw URLError(.notConnectedToInternet) }
            ),
            shortcut: binder
        )
    }

    private func close(_ panel: SettingsPanel) {
        panel.windowWillClose(Notification(name: NSWindow.willCloseNotification))
    }

    /// The close button is the ordinary way out of this window, and closing a
    /// window does not make its first responder resign. Without asking for the
    /// key back here the hot key stays let go with nobody left to take it
    /// again, and the shortcut is dead until the app is launched afresh.
    func testClosingTheWindowWhileTheFieldListensTakesTheShortcutBack() {
        let binder = makeBinder()
        binder.start()
        let panel = makePanel(shortcut: binder)

        binder.suspend()
        close(panel)

        XCTAssertEqual(
            registrar.events,
            ["register ⌃⌥⇧⌘G", "invalidate ⌃⌥⇧⌘G", "register ⌃⌥⇧⌘G"]
        )
    }

    /// Closing the window the usual way, with nothing being recorded, must not
    /// give the key back and take it again: that is a moment with no shortcut
    /// at all, in the commonest thing anybody does with this window.
    func testClosingTheWindowOtherwiseLeavesTheShortcutAlone() {
        let binder = makeBinder()
        binder.start()
        let panel = makePanel(shortcut: binder)

        close(panel)

        XCTAssertEqual(registrar.events, ["register ⌃⌥⇧⌘G"])
    }
}

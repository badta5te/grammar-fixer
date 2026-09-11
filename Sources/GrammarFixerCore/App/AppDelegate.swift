import AppKit

@MainActor
public final class AppDelegate: NSObject, NSApplicationDelegate {
    private var menuBar: MenuBarController?
    private var roundTrip: RoundTripController?
    private var settingsPanel: SettingsPanel?
    private let onboarding = OnboardingPanel()

    public override init() {
        super.init()
    }

    public func applicationDidFinishLaunching(_ notification: Notification) {
        let settings = Settings()
        Log.isEnabled = settings.writesLog
        Log.trimIfNeeded()
        Log.section("launched \(AppInfo.name) \(AppInfo.version)")
        Log.write("Accessibility access: \(Accessibility.isTrusted)")

        // Without a main menu the standard editing shortcuts never reach a
        // text field, and the settings window exists to have a key pasted into
        // it.
        MainMenu.install()
        settings.theme.apply()

        let store = ProviderStore(settings: settings)
        // Whatever the previous ticket left in ~/.config/grammar-fixer is
        // carried over once, into the window and the Keychain. The file itself
        // is only read: it holds somebody's key and is not ours to remove.
        store.importLegacyFile()

        let clipboard = SystemClipboard()
        let keyboard = SystemKeyboard()
        let notices = NoticePanel()
        let results = ResultPanel()
        let roundTrip = RoundTripController(
            settings: settings,
            clipboard: clipboard,
            capture: TextCapture(clipboard: clipboard, keyboard: keyboard),
            paster: TextPaster(clipboard: clipboard, keyboard: keyboard, focus: FocusRestorer()),
            transform: LLMTextTransformer(
                loadConfiguration: { try store.configuration() },
                loadPrompt: { store.prompt() }
            ),
            notices: notices,
            results: results,
            onAccessibilityDenied: { [onboarding] in onboarding.show() }
        )
        roundTrip.registerHotKey()
        self.roundTrip = roundTrip

        let settingsPanel = SettingsPanel(settings: settings, store: store)
        self.settingsPanel = settingsPanel

        menuBar = MenuBarController(
            settings: settings,
            notices: notices,
            onFixSelection: { roundTrip.run() },
            onShowOnboarding: { [onboarding] in onboarding.show() },
            onShowSettings: { settingsPanel.show() }
        )

        // The round trip cannot work without access, and saying nothing about
        // that on a first launch leaves a person with a shortcut that does
        // nothing.
        if !Accessibility.isTrusted {
            onboarding.show()
        }
    }
}

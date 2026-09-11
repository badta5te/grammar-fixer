import AppKit

@MainActor
public final class AppDelegate: NSObject, NSApplicationDelegate {
    private var menuBar: MenuBarController?
    private var roundTrip: RoundTripController?
    private var shortcut: ShortcutBinder?
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

        // The history is read once, at launch, and written on every round.
        let usage = UsageStore()

        // Prices are fetched rather than shipped, and the last fetch is
        // cached, so a launch without a network still knows what a round
        // costs. Asking for them must never hold up a correction, so it
        // happens in a task of its own and nothing waits on it.
        let catalog = PriceCatalog()
        catalog.readOverrides(from: settings)
        Task { await catalog.refreshIfStale() }

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
                loadPrompt: { store.prompt() },
                record: { usage.add($0) }
            ),
            notices: notices,
            results: results,
            budget: { [settings, usage] in
                settings.budget.notice(for: usage.summary(prices: catalog.table))
            },
            onAccessibilityDenied: { [onboarding] in onboarding.show(shortcut: settings.shortcut.display) }
        )
        self.roundTrip = roundTrip

        // The combination lives here rather than in the round trip: it can be
        // changed while the app runs, and every way that can fail has to lead
        // somewhere other than an app with no shortcut at all.
        let shortcut = ShortcutBinder(settings: settings, notices: notices) { roundTrip.run() }
        shortcut.start()
        self.shortcut = shortcut

        let settingsPanel = SettingsPanel(
            settings: settings,
            store: store,
            usage: usage,
            catalog: catalog,
            shortcut: shortcut
        )
        self.settingsPanel = settingsPanel

        let menuBar = MenuBarController(
            settings: settings,
            usage: usage,
            catalog: catalog,
            notices: notices,
            onFixSelection: { roundTrip.run() },
            onShowOnboarding: { [onboarding] in onboarding.show(shortcut: settings.shortcut.display) },
            onShowSettings: { settingsPanel.show() }
        )
        self.menuBar = menuBar

        // The icon stands on screen while the menu under it is redrawn only
        // when opened, so the round that passes the limit has to say so itself.
        usage.onChange = { [weak menuBar] in
            menuBar?.refresh()
            // A model nobody has a price for is the moment the catalogue is
            // worth asking again: it may have gained one since.
            Task { await catalog.refreshIfStale() }
        }

        // The round trip cannot work without access, and saying nothing about
        // that on a first launch leaves a person with a shortcut that does
        // nothing.
        if !Accessibility.isTrusted {
            onboarding.show(shortcut: settings.shortcut.display)
        }
    }
}

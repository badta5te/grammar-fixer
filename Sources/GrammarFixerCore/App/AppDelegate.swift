import AppKit

@MainActor
public final class AppDelegate: NSObject, NSApplicationDelegate {
    private var menuBar: MenuBarController?
    private var roundTrip: RoundTripController?
    private let onboarding = OnboardingPanel()

    public override init() {
        super.init()
    }

    public func applicationDidFinishLaunching(_ notification: Notification) {
        let settings = Settings()
        Log.isEnabled = settings.writesLog
        Log.trimIfNeeded()
        Log.section("запуск \(AppInfo.name) \(AppInfo.version)")
        Log.write("доступ Accessibility: \(Accessibility.isTrusted)")

        let clipboard = SystemClipboard()
        let keyboard = SystemKeyboard()
        let roundTrip = RoundTripController(
            settings: settings,
            clipboard: clipboard,
            capture: TextCapture(clipboard: clipboard, keyboard: keyboard),
            paster: TextPaster(clipboard: clipboard, keyboard: keyboard, focus: FocusRestorer()),
            transform: UppercasePlaceholder(),
            notices: NoticePanel(),
            onAccessibilityDenied: { [onboarding] in onboarding.show() }
        )
        roundTrip.registerHotKey()
        self.roundTrip = roundTrip

        menuBar = MenuBarController(
            settings: settings,
            onFixSelection: { roundTrip.run() },
            onShowOnboarding: { [onboarding] in onboarding.show() }
        )

        // Без доступа круг работать не может, и молчать об этом при первом
        // запуске значит оставить человека с хоткеем, который ничего не делает.
        if !Accessibility.isTrusted {
            onboarding.show()
        }
    }
}

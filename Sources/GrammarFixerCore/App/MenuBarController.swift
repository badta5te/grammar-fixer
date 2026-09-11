import AppKit
import UniformTypeIdentifiers

/// The menu bar icon and its menu.
///
/// Main-thread isolation is stated explicitly. Today the controller is built
/// from applicationDidFinishLaunching, which is on the main thread anyway, but
/// the caller's discipline is not something to lean on: updates from network
/// responses will arrive here later, and without the annotation that would
/// become a race the compiler cannot catch.
@MainActor
final class MenuBarController: NSObject, NSMenuDelegate {
    private let statusItem: NSStatusItem
    private let settings: Settings
    private let notices: any NoticePresenting
    private let onFixSelection: () -> Void
    private let onShowOnboarding: () -> Void
    private let onShowSettings: () -> Void

    private var restoreClipboardItem: NSMenuItem?
    private var pasteByTypingItem: NSMenuItem?
    private var writeLogItem: NSMenuItem?

    init(
        settings: Settings,
        notices: any NoticePresenting,
        onFixSelection: @escaping () -> Void,
        onShowOnboarding: @escaping () -> Void,
        onShowSettings: @escaping () -> Void
    ) {
        self.settings = settings
        self.notices = notices
        self.onFixSelection = onFixSelection
        self.onShowOnboarding = onShowOnboarding
        self.onShowSettings = onShowSettings
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        super.init()

        if let button = statusItem.button {
            button.image = NSImage(
                systemSymbolName: "text.badge.checkmark",
                accessibilityDescription: AppInfo.name
            )
            button.image?.isTemplate = true
        }

        statusItem.menu = makeMenu()
    }

    private func makeMenu() -> NSMenu {
        let menu = NSMenu()
        menu.delegate = self

        let title = NSMenuItem(title: "\(AppInfo.name) \(AppInfo.version)", action: nil, keyEquivalent: "")
        title.isEnabled = false
        menu.addItem(title)

        menu.addItem(.separator())

        let fix = NSMenuItem(title: "Fix Selection", action: #selector(fixSelection), keyEquivalent: "g")
        fix.keyEquivalentModifierMask = [.command, .shift, .option, .control]
        fix.target = self
        menu.addItem(fix)

        let onboarding = NSMenuItem(title: "Accessibility Access…", action: #selector(showOnboarding), keyEquivalent: "")
        onboarding.target = self
        menu.addItem(onboarding)

        let settingsItem = NSMenuItem(title: "Settings…", action: #selector(showSettings), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)

        menu.addItem(.separator())

        // The two switches that are worth reaching without opening a window
        // stay here as well. The same switches are available from a terminal
        // through defaults write, because the menu bar itself may be hidden.
        restoreClipboardItem = addToggle(to: menu, title: "Restore Clipboard After Paste", action: #selector(toggleRestoreClipboard))
        pasteByTypingItem = addToggle(to: menu, title: "Paste by Typing", action: #selector(togglePasteByTyping))
        writeLogItem = addToggle(to: menu, title: "Write Log", action: #selector(toggleWriteLog))

        let openLog = NSMenuItem(title: "Open Log", action: #selector(openLog), keyEquivalent: "")
        openLog.target = self
        menu.addItem(openLog)

        menu.addItem(.separator())

        menu.addItem(
            withTitle: "Quit",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )

        return menu
    }

    private func addToggle(to menu: NSMenu, title: String, action: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        menu.addItem(item)
        return item
    }

    /// Check marks are set when the menu opens rather than when it is built:
    /// the same settings change from a terminal, and the menu must not lie.
    func menuNeedsUpdate(_ menu: NSMenu) {
        restoreClipboardItem?.state = settings.restoreClipboardAfterPaste ? .on : .off
        pasteByTypingItem?.state = settings.pasteMethod == .typing ? .on : .off
        writeLogItem?.state = settings.writesLog ? .on : .off
    }

    @objc private func fixSelection() { onFixSelection() }

    @objc private func showOnboarding() { onShowOnboarding() }

    @objc private func showSettings() { onShowSettings() }

    @objc private func toggleRestoreClipboard() {
        settings.restoreClipboardAfterPaste.toggle()
        Log.write("restore clipboard: \(settings.restoreClipboardAfterPaste)")
    }

    @objc private func togglePasteByTyping() {
        settings.pasteMethod = settings.pasteMethod == .typing ? .clipboard : .typing
        Log.write("paste method: \(settings.pasteMethod.rawValue)")
    }

    @objc private func toggleWriteLog() {
        settings.writesLog.toggle()
        Log.isEnabled = settings.writesLog
    }

    @objc private func openLog() {
        // There may be no log at all: it was turned off, or it was just
        // trimmed away. Opening a file that does not exist opens nothing and
        // says nothing.
        guard FileManager.default.fileExists(atPath: Log.fileURL.path) else {
            notices.show(Notice(
                title: "No log yet",
                message: settings.writesLog
                    ? "Nothing has been logged since the log was last cleared. Run the shortcut once."
                    : "Writing the log is turned off, so there is nothing to open."
            ))
            return
        }
        NSWorkspace.shared.open(Log.fileURL)
    }
}

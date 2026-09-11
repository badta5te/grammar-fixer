import AppKit

/// Иконка в меню-баре и её меню.
///
/// Привязка к главному потоку объявлена явно. Сейчас контроллер создаётся из
/// applicationDidFinishLaunching, который и так на главном потоке, но полагаться
/// на дисциплину вызывающего нельзя: позже сюда придут обновления из сетевых
/// ответов, и без аннотации это стало бы гонкой, которую компилятор не поймает.
@MainActor
final class MenuBarController: NSObject, NSMenuDelegate {
    private let statusItem: NSStatusItem
    private let settings: Settings
    private let onFixSelection: () -> Void
    private let onShowOnboarding: () -> Void

    private var restoreClipboardItem: NSMenuItem?
    private var pasteByTypingItem: NSMenuItem?
    private var writeLogItem: NSMenuItem?

    init(
        settings: Settings,
        onFixSelection: @escaping () -> Void,
        onShowOnboarding: @escaping () -> Void
    ) {
        self.settings = settings
        self.onFixSelection = onFixSelection
        self.onShowOnboarding = onShowOnboarding
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

        menu.addItem(.separator())

        // Настройки живут здесь до появления отдельного окна настроек. То же
        // самое переключается из терминала через defaults write, потому что
        // меню-бар у пользователя может быть скрыт.
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

    /// Галочки проставляются при открытии меню, а не при создании: те же
    /// настройки меняются из терминала, и меню не должно врать.
    func menuNeedsUpdate(_ menu: NSMenu) {
        restoreClipboardItem?.state = settings.restoreClipboardAfterPaste ? .on : .off
        pasteByTypingItem?.state = settings.pasteMethod == .typing ? .on : .off
        writeLogItem?.state = settings.writesLog ? .on : .off
    }

    @objc private func fixSelection() { onFixSelection() }

    @objc private func showOnboarding() { onShowOnboarding() }

    @objc private func toggleRestoreClipboard() {
        settings.restoreClipboardAfterPaste.toggle()
        Log.write("восстановление буфера: \(settings.restoreClipboardAfterPaste)")
    }

    @objc private func togglePasteByTyping() {
        settings.pasteMethod = settings.pasteMethod == .typing ? .clipboard : .typing
        Log.write("способ вставки: \(settings.pasteMethod.rawValue)")
    }

    @objc private func toggleWriteLog() {
        settings.writesLog.toggle()
        Log.isEnabled = settings.writesLog
    }

    @objc private func openLog() {
        NSWorkspace.shared.open(Log.fileURL)
    }
}

import AppKit

/// Иконка в меню-баре и её меню. Пока умеет только закрыть приложение —
/// остальные пункты появятся вместе с настройками и счётчиком расходов.
///
/// Привязка к главному потоку объявлена явно. Сейчас контроллер создаётся из
/// applicationDidFinishLaunching, который и так на главном потоке, но полагаться
/// на дисциплину вызывающего нельзя: позже сюда придут обновления из сетевых
/// ответов, и без аннотации это стало бы гонкой, которую компилятор не поймает.
@MainActor
final class MenuBarController {
    private let statusItem: NSStatusItem

    init() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)

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

        let title = NSMenuItem(title: "\(AppInfo.name) \(AppInfo.version)", action: nil, keyEquivalent: "")
        title.isEnabled = false
        menu.addItem(title)

        menu.addItem(.separator())

        menu.addItem(
            withTitle: "Quit",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )

        return menu
    }
}

import AppKit

/// The application's main menu.
///
/// An agent app shows no menu bar of its own, so it is tempting not to build
/// one. It is needed anyway: AppKit routes the standard editing shortcuts
/// through the main menu before they reach a text field, and without an Edit
/// menu ⌘V does nothing in any window this app opens. Pasting an API key is
/// the main thing the settings window is for.
enum MainMenu {
    static func install() {
        let main = NSMenu()

        // The first menu is the application menu whatever it is called, and
        // macOS puts Quit's ⌘Q in it.
        let app = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(
            withTitle: "Quit \(AppInfo.name)",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )
        app.submenu = appMenu
        main.addItem(app)

        let edit = NSMenuItem()
        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        editMenu.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "Z")
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        edit.submenu = editMenu
        main.addItem(edit)

        NSApp.mainMenu = main
    }
}

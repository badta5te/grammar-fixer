import AppKit
import GrammarFixerCore

// Меню-бар приложение без иконки в доке. Политика активации дублирует
// LSUIElement из Info.plist: plist решает для запуска через Finder и open,
// setActivationPolicy — для запуска бинарника напрямую при отладке.
let app = NSApplication.shared
app.setActivationPolicy(.accessory)

let delegate = AppDelegate()
app.delegate = delegate
app.run()

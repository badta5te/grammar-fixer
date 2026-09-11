import AppKit
import GrammarFixerCore

// A menu bar app with no Dock icon. The activation policy duplicates
// LSUIElement from Info.plist: the plist decides for launches through Finder
// and open, setActivationPolicy for running the binary directly while
// debugging.
let app = NSApplication.shared
app.setActivationPolicy(.accessory)

let delegate = AppDelegate()
app.delegate = delegate
app.run()

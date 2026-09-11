import AppKit

public final class AppDelegate: NSObject, NSApplicationDelegate {
    private var menuBar: MenuBarController?

    public override init() {
        super.init()
    }

    public func applicationDidFinishLaunching(_ notification: Notification) {
        menuBar = MenuBarController()
    }
}

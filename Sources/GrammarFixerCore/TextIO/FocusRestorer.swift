import AppKit

@MainActor
public protocol FocusRestoring {
    func activate(_ app: NSRunningApplication, timeout: TimeInterval) async -> Bool
}

/// Returning focus is confirmed by observation, not by a fixed delay. A fixed
/// delay produces "sometimes it pasted into the wrong window": ⌘V leaves while
/// the source app has not become active yet.
///
/// In the normal case this costs nothing: the panel does not take focus, and
/// the early check succeeds at once. To measure the case where focus really was
/// lost, the prototype sent it to Finder on purpose: four runs came back in
/// 8 to 11 ms, and the notification arrived every time.
@MainActor
public final class FocusRestorer: FocusRestoring {
    public init() {}

    public func activate(_ app: NSRunningApplication, timeout: TimeInterval) async -> Bool {
        let target = app.processIdentifier
        if NSWorkspace.shared.frontmostApplication?.processIdentifier == target {
            return true
        }

        let center = NSWorkspace.shared.notificationCenter
        var observer: NSObjectProtocol?
        var resumed = false

        let confirmed: Bool = await withCheckedContinuation { continuation in
            observer = center.addObserver(
                forName: NSWorkspace.didActivateApplicationNotification,
                object: nil,
                queue: .main
            ) { notification in
                let activated = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
                guard activated?.processIdentifier == target else { return }
                MainActor.assumeIsolated {
                    guard !resumed else { return }
                    resumed = true
                    continuation.resume(returning: true)
                }
            }

            app.activate()

            Task { @MainActor in
                try? await Task.sleep(for: .seconds(timeout))
                guard !resumed else { return }
                resumed = true
                // The notification may never arrive even though the app is
                // already frontmost.
                let front = NSWorkspace.shared.frontmostApplication?.processIdentifier
                continuation.resume(returning: front == target)
            }
        }

        if let observer { center.removeObserver(observer) }
        return confirmed
    }
}

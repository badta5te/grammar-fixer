import AppKit

@MainActor
public protocol FocusRestoring {
    func activate(_ app: NSRunningApplication, timeout: TimeInterval) async -> Bool
}

/// Возврат фокуса подтверждается наблюдением, а не фиксированной задержкой.
/// Фиксированная задержка даёт «иногда вставилось не туда»: ⌘V улетает, пока
/// исходное приложение ещё не стало активным.
///
/// В штатном случае это бесплатно: панель не забирает фокус, и ранняя проверка
/// срабатывает сразу. Когда фокус действительно терялся, прототип намеренно
/// уводил его в Finder: четыре замера дали возврат за 8–11 мс, уведомление
/// приходило каждый раз.
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
                // Уведомление могло не прийти, хотя приложение уже впереди.
                let front = NSWorkspace.shared.frontmostApplication?.processIdentifier
                continuation.resume(returning: front == target)
            }
        }

        if let observer { center.removeObserver(observer) }
        return confirmed
    }
}

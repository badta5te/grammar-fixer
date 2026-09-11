import AppKit
import Carbon.HIToolbox

/// Всё, что круг спрашивает у системы. Отдельный шов нужен не ради чистоты:
/// без него ни одна ветка выхода из круга не проверяется тестом, а именно
/// ветки выхода — то, что ломается незаметно.
@MainActor
public protocol RoundTripEnvironment {
    var isAccessibilityTrusted: Bool { get }
    var isSecureInputActive: Bool { get }
    var frontmostApplication: NSRunningApplication? { get }
    func beep()
}

public struct SystemEnvironment: RoundTripEnvironment {
    public init() {}

    public var isAccessibilityTrusted: Bool { Accessibility.isTrusted }
    public var isSecureInputActive: Bool { SecureInput.isActive }
    public var frontmostApplication: NSRunningApplication? { NSWorkspace.shared.frontmostApplication }
    public func beep() { NSSound.beep() }
}

/// Показ сообщения человеку. Панель за этим швом рисует настоящее окно, а тест
/// смотрит только на то, что сообщение вообще было.
@MainActor
public protocol NoticePresenting {
    func show(_ error: any UserFacingError)
}

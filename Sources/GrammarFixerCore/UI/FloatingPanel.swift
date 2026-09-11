import AppKit
import Carbon.HIToolbox
import SwiftUI

/// Окно приложения-агента. Два свойства здесь обязательны, и каждое найдено
/// ошибкой в прототипе, когда панель не появлялась вовсе при `isVisible = true`:
///
/// 1. `hidesOnDeactivate = false`. NSPanel, в отличие от NSWindow, по умолчанию
///    прячется, когда его приложение неактивно. Агент неактивен всегда.
/// 2. `.nonactivatingPanel`. Форма Spotlight: панель берёт клавиатурный ввод, а
///    приложение при этом не становится активным. Без этого на macOS 15
///    `NSApp.activate` просто игнорируется и фокус не приходит.
///
/// Уровень `.popUpMenu`, а не `.floating`: со своей тройкой панель оказалась бы
/// под Dock на слое 20 и под соседями вроде AlDente на 24.
@MainActor
public class FloatingPanel: NSPanel {
    private var outsideClickMonitor: Any?
    private var onDismiss: (() -> Void)?

    public init<Content: View>(styleMask: NSWindow.StyleMask, @ViewBuilder content: () -> Content) {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 200),
            styleMask: styleMask.union([.nonactivatingPanel]),
            backing: .buffered,
            defer: false
        )

        isFloatingPanel = true
        level = .popUpMenu
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        animationBehavior = .utilityWindow

        // Прозрачный фон нужен только окну без рамки, которое рисует себе
        // подложку само. У окна с заголовком он оставил бы полосу заголовка
        // пустой.
        if !styleMask.contains(.titled) {
            isOpaque = false
            backgroundColor = .clear
        }

        // Именно contentViewController, а не contentView: окно тогда само
        // берёт размер у SwiftUI и пересчитывает его, когда содержимое меняется.
        // С голым NSHostingView окно осталось бы в размере, заданном здесь, а
        // содержимое вылезло бы за край и заехало под заголовок.
        contentViewController = NSHostingController(rootView: content())
    }

    public override var canBecomeKey: Bool { true }

    /// Показывает панель по центру экрана, где сейчас курсор.
    /// `orderFrontRegardless`, а не `makeKeyAndOrderFront`: последний из
    /// неактивного приложения окно на текущее пространство не выводит.
    public func present() {
        layoutIfNeeded()
        setContentSize(contentViewController?.view.fittingSize ?? frame.size)
        if let screen = NSScreen.screens.first(where: { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) })
            ?? NSScreen.main {
            let size = frame.size
            setFrameOrigin(NSPoint(
                x: screen.visibleFrame.midX - size.width / 2,
                y: screen.visibleFrame.midY - size.height / 2 + screen.visibleFrame.height * 0.15
            ))
        }
        orderFrontRegardless()
        makeKey()
    }

    /// Закрытие по клику мимо панели. Глобальный монитор получает только
    /// события, ушедшие мимо нашего приложения, то есть ровно клики снаружи.
    public func dismissOnOutsideClick(_ handler: @escaping () -> Void) {
        onDismiss = handler
        outsideClickMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.onDismiss?() }
        }
    }

    public func dismiss() {
        if let outsideClickMonitor {
            NSEvent.removeMonitor(outsideClickMonitor)
            self.outsideClickMonitor = nil
        }
        onDismiss = nil
        orderOut(nil)
    }

    public override func cancelOperation(_ sender: Any?) {
        onDismiss?()
    }

    /// Esc обрабатывается и здесь: до cancelOperation нажатие доходит не через
    /// каждый содержащийся в панели вид.
    public override func keyDown(with event: NSEvent) {
        guard Int(event.keyCode) == kVK_Escape else {
            super.keyDown(with: event)
            return
        }
        onDismiss?()
    }
}

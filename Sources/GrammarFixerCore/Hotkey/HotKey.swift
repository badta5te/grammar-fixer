import AppKit
import Carbon.HIToolbox

/// Carbon-обработчик — это указатель на C-функцию, он не умеет захватывать
/// контекст. Замыкания лежат в таблице по идентификатору хоткея. Carbon
/// вызывает обработчик на главном потоке в ходе диспетчеризации событий,
/// поэтому изоляция главного актора здесь не нарушается.
@MainActor private var hotKeyActions: [UInt32: () -> Void] = [:]
@MainActor private var nextHotKeyID: UInt32 = 1
@MainActor private var sharedHandler: EventHandlerRef?

private func hotKeyEventHandler(
    _ call: EventHandlerCallRef?,
    _ event: EventRef?,
    _ userData: UnsafeMutableRawPointer?
) -> OSStatus {
    var id = EventHotKeyID()
    let status = GetEventParameter(
        event,
        EventParamName(kEventParamDirectObject),
        EventParamType(typeEventHotKeyID),
        nil,
        MemoryLayout<EventHotKeyID>.size,
        nil,
        &id
    )
    guard status == noErr else { return status }

    MainActor.assumeIsolated {
        hotKeyActions[id.id]?()
    }
    return noErr
}

/// Глобальный хоткей через Carbon. Этот путь не требует доступа Accessibility,
/// в отличие от CGEventTap, и переживает смену активного приложения.
///
/// Успешная регистрация не означает, что комбинация свободна: прототип получил
/// noErr на сочетании, занятом Raycast. Полагаться на код возврата как на
/// детектор конфликта нельзя.
@MainActor
public final class HotKey {
    private var reference: EventHotKeyRef?
    private let id: UInt32

    /// - Returns: nil, если система отказалась регистрировать комбинацию.
    public init?(keyCode: UInt32, carbonModifiers: UInt32, action: @escaping () -> Void) {
        id = nextHotKeyID
        nextHotKeyID += 1

        if sharedHandler == nil {
            var type = EventTypeSpec(
                eventClass: OSType(kEventClassKeyboard),
                eventKind: UInt32(kEventHotKeyPressed)
            )
            let status = InstallEventHandler(
                GetApplicationEventTarget(),
                hotKeyEventHandler,
                1,
                &type,
                nil,
                &sharedHandler
            )
            guard status == noErr else {
                Log.write("InstallEventHandler не удался: \(status)")
                return nil
            }
        }

        // Подпись — произвольные четыре байта, отличающие наши хоткеи от чужих.
        let hotKeyID = EventHotKeyID(signature: OSType(0x4746_5849), id: id)
        let status = RegisterEventHotKey(
            keyCode,
            carbonModifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &reference
        )
        guard status == noErr else {
            Log.write("RegisterEventHotKey не удался: \(status)")
            return nil
        }

        hotKeyActions[id] = action
    }

    /// Снимает регистрацию. Отдельным методом, а не в deinit: deinit не
    /// изолирован главным актором и не имеет права трогать ни таблицу, ни
    /// EventHotKeyRef. Пригодится редактору хоткея из тикета 09.
    public func invalidate() {
        if let reference {
            UnregisterEventHotKey(reference)
            self.reference = nil
        }
        hotKeyActions[id] = nil
    }
}

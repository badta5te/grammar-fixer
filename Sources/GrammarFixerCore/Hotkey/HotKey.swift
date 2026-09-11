import AppKit
import Carbon.HIToolbox

/// A Carbon handler is a plain C function pointer and cannot capture context.
/// The closures live in a table keyed by hot key identifier. Carbon calls the
/// handler on the main thread while dispatching events, so main actor isolation
/// is not violated here.
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

/// A global hot key through Carbon. Unlike CGEventTap this path needs no
/// Accessibility access, and it survives a change of the active app.
///
/// A successful registration does not mean the combination is free: the
/// prototype got noErr for a combination Raycast already owned. The return code
/// cannot be relied on as a conflict detector.
@MainActor
public final class HotKey {
    private var reference: EventHotKeyRef?
    private let id: UInt32

    /// - Returns: nil if the system refused to register the combination.
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

        // The signature is four arbitrary bytes telling our hot keys from
        // everybody else's.
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

    /// Unregisters the hot key. A method of its own rather than deinit: deinit
    /// is not isolated to the main actor and has no right to touch either the
    /// table or the EventHotKeyRef. The shortcut editor in ticket 09 will want
    /// this.
    public func invalidate() {
        if let reference {
            UnregisterEventHotKey(reference)
            self.reference = nil
        }
        hotKeyActions[id] = nil
    }
}

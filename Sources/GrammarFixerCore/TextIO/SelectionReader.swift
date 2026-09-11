import AppKit
import ApplicationServices

/// The selection as the system knows it, without copying anything.
@MainActor
public protocol SelectionReading {
    /// - Returns: the selected text, or nil when the app in front does not
    ///   answer — which is the common case and not a failure. An answer that
    ///   is blank is no answer either, and whoever asked decides that: a
    ///   selection of nothing but spaces and an app that does not support the
    ///   question look identical from here.
    func selectedText() -> String?
}

/// Reading the selection through the accessibility API.
///
/// Worth trying because it takes the clipboard out of the round entirely:
/// nothing is overwritten, nothing has to be put back, and nothing of
/// somebody's own can be lost to a correction. Support is uneven — anything
/// built on web technology often says nothing at all — so this is an attempt
/// and never a requirement. Silence here costs one call and falls back to the
/// synthetic ⌘C that has always worked.
///
/// The same Accessibility access the round trip already needs covers this, so
/// it asks for nothing new.
@MainActor
public final class AccessibilitySelection: SelectionReading {
    /// How long to wait for an app to answer. The round is in front of
    /// somebody waiting for their text, and an app that is busy or wedged
    /// would otherwise hold the main thread with the default timeout of six
    /// seconds. A quarter of a second is longer than a healthy app needs and
    /// short enough to pass for the fallback happening straight away.
    private let timeout: Float

    public init(timeout: Float = 0.25) {
        self.timeout = timeout
    }

    public func selectedText() -> String? {
        let system = AXUIElementCreateSystemWide()
        AXUIElementSetMessagingTimeout(system, timeout)

        guard let focused = copy(kAXFocusedUIElementAttribute, from: system),
              CFGetTypeID(focused) == AXUIElementGetTypeID()
        else {
            Log.write("the system named no focused element")
            return nil
        }

        let element = focused as! AXUIElement
        AXUIElementSetMessagingTimeout(element, timeout)
        guard let value = copy(kAXSelectedTextAttribute, from: element),
              let text = value as? String
        else { return nil }

        Log.write("the system answered with a selection of \(text.count) characters")
        return text
    }

    private func copy(_ attribute: String, from element: AXUIElement) -> CFTypeRef? {
        var value: CFTypeRef?
        let status = AXUIElementCopyAttributeValue(element, attribute as CFString, &value)
        guard status == .success else { return nil }
        return value
    }
}

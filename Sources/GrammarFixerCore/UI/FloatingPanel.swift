import AppKit
import Carbon.HIToolbox
import SwiftUI

/// A window for an agent app. Two properties here are mandatory, and each was
/// found the hard way in the prototype, where the panel did not appear at all
/// while reporting `isVisible = true`:
///
/// 1. `hidesOnDeactivate = false`. NSPanel, unlike NSWindow, hides itself by
///    default when its app is inactive. An agent is always inactive.
/// 2. `.nonactivatingPanel`. The Spotlight shape: the panel takes keyboard
///    input without the app becoming active. Without it, macOS 15 simply
///    ignores `NSApp.activate` and focus never arrives.
///
/// The level is `.popUpMenu` rather than `.floating`: at floating's level of
/// three the panel would sit under the Dock at twenty and under neighbours such
/// as AlDente at twenty-four.
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

        // A clear background is only for a borderless window, which draws its
        // own backing. On a titled window it would leave the title bar empty.
        if !styleMask.contains(.titled) {
            isOpaque = false
            backgroundColor = .clear
        }

        // contentViewController rather than contentView on purpose: the window
        // then takes its size from SwiftUI and recomputes it when the content
        // changes. With a bare NSHostingView the window would keep the size set
        // here while the content spilled over the edge and under the title.
        contentViewController = NSHostingController(rootView: content())
    }

    public override var canBecomeKey: Bool { true }

    /// Shows the panel centred on the screen the cursor is on.
    /// `orderFrontRegardless` rather than `makeKeyAndOrderFront`: from an
    /// inactive app the latter does not bring the window to the current space.
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

    /// Dismissal on a click outside the panel. A global monitor receives only
    /// events that went past our app, which is exactly the outside clicks.
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

    /// Escape is handled here as well: the press does not reach cancelOperation
    /// through every view a panel may contain.
    public override func keyDown(with event: NSEvent) {
        guard Int(event.keyCode) == kVK_Escape else {
            super.keyDown(with: event)
            return
        }
        onDismiss?()
    }
}

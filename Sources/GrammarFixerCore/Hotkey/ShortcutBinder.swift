import Foundation

/// A registered hot key, seen from the outside. The only thing anybody needs
/// of one is the ability to give it back.
@MainActor
public protocol HotKeyHandle: AnyObject {
    func invalidate()
}

extension HotKey: HotKeyHandle {}

/// The app's one shortcut, and the ability to change it while the app runs.
///
/// All the ways a combination can fail come through here, so that none of them
/// can end in an app with no shortcut at all: it has no Dock icon and no
/// window of its own, and the combination is the only way in.
@MainActor
public final class ShortcutBinder {
    /// Registering one, or nil if the system refused.
    public typealias Register = @MainActor (Shortcut, @escaping () -> Void) -> (any HotKeyHandle)?

    private let settings: Settings
    private let notices: any NoticePresenting
    private let systemShortcuts: @MainActor () -> Set<Shortcut>
    private let register: Register
    private let action: () -> Void
    private var handle: (any HotKeyHandle)?

    public init(
        settings: Settings,
        notices: any NoticePresenting,
        systemShortcuts: @escaping @MainActor () -> Set<Shortcut> = { SystemShortcuts.current },
        register: @escaping Register = { shortcut, action in
            HotKey(keyCode: shortcut.keyCode, carbonModifiers: shortcut.carbonModifiers, action: action)
        },
        action: @escaping () -> Void
    ) {
        self.settings = settings
        self.notices = notices
        self.systemShortcuts = systemShortcuts
        self.register = register
        self.action = action
    }

    public var shortcut: Shortcut { settings.shortcut }

    /// Takes the stored combination at launch. No Accessibility access is
    /// needed for this: a Carbon hot key fires before the permission is
    /// granted, so the press reaches us and the onboarding screen can be
    /// shown instead of nothing happening.
    public func start() {
        guard bind(shortcut) else {
            // Without this the person gets an app that simply does nothing and
            // no way to find out why. It does not catch every conflict: the
            // prototype got noErr for a combination Raycast already owned, so
            // a taken shortcut can still register and stay silent.
            notices.show(ShortcutRefusal.refusedByTheSystem.notice(for: shortcut))
            return
        }
    }

    /// Changes the combination. Nothing is stored until the system has agreed,
    /// and a refusal puts back the one that was working.
    @discardableResult
    public func apply(_ new: Shortcut) -> ShortcutRefusal? {
        // Recording the same combination again is not a change, and giving the
        // key back only to take it again is a moment with no shortcut at all.
        guard new != shortcut || handle == nil else { return nil }

        if let refusal = ShortcutCheck.run(new, takenBy: systemShortcuts()) {
            Log.write("shortcut \(new.display) refused: \(refusal.rawValue)")
            return refusal
        }

        let old = shortcut
        release()
        guard bind(new) else {
            // The old combination back rather than none: it was working a
            // moment ago, and the refusal already says what happened.
            _ = bind(old)
            return .refusedByTheSystem
        }
        settings.shortcut = new
        return nil
    }

    /// Gives the key back while the editor listens for a combination. A global
    /// hot key fires wherever the keyboard is pointing, our own window
    /// included, so without this the editor would never see the very
    /// combination somebody is trying to replace — a round would start
    /// instead.
    public func suspend() {
        release()
    }

    public func resume() {
        guard handle == nil else { return }
        guard bind(shortcut) else {
            notices.show(ShortcutRefusal.refusedByTheSystem.notice(for: shortcut))
            return
        }
    }

    private func bind(_ shortcut: Shortcut) -> Bool {
        handle = register(shortcut, action)
        Log.write("shortcut \(shortcut.display) \(handle == nil ? "could NOT be registered" : "registered")")
        return handle != nil
    }

    private func release() {
        handle?.invalidate()
        handle = nil
    }
}

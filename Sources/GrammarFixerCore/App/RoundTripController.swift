import AppKit
import Carbon.HIToolbox

/// The whole round trip: shortcut, capture, correction by the model, paste.
///
/// Every way out of here ends in something, whether a beep, a message or the
/// onboarding screen. Not one silent failure is left: a silent failure here
/// means somebody is waiting for a result that will never come.
@MainActor
public final class RoundTripController {
    private let settings: Settings
    private let clipboard: Clipboard
    private let capture: TextCapture
    private let paster: TextPaster
    private let transform: TextTransforming
    private let notices: any NoticePresenting
    private let environment: any RoundTripEnvironment
    private let onAccessibilityDenied: () -> Void

    private var hotKey: HotKey?
    private var isRunning = false

    public init(
        settings: Settings,
        clipboard: Clipboard,
        capture: TextCapture,
        paster: TextPaster,
        transform: TextTransforming,
        notices: any NoticePresenting,
        environment: any RoundTripEnvironment = SystemEnvironment(),
        onAccessibilityDenied: @escaping () -> Void
    ) {
        self.settings = settings
        self.clipboard = clipboard
        self.capture = capture
        self.paster = paster
        self.transform = transform
        self.notices = notices
        self.environment = environment
        self.onAccessibilityDenied = onAccessibilityDenied
    }

    /// Registers ⇧⌃⌥⌘G. No Accessibility access is needed for this: a Carbon
    /// hot key fires before the permission is granted, so the press reaches us
    /// and we can show the onboarding screen instead of staying silent.
    public func registerHotKey() {
        hotKey = HotKey(
            keyCode: UInt32(kVK_ANSI_G),
            carbonModifiers: UInt32(cmdKey | shiftKey | optionKey | controlKey)
        ) { [weak self] in
            self?.run()
        }
        guard hotKey == nil else {
            Log.write("хоткей ⇧⌃⌥⌘G зарегистрирован")
            return
        }
        // Without a message the person gets an app that simply does nothing,
        // and no way to find out why. This does not catch every conflict: the
        // prototype got noErr for a combination Raycast already owned, so a
        // taken shortcut can still register successfully and stay silent.
        Log.write("хоткей ⇧⌃⌥⌘G зарегистрировать НЕ удалось")
        notices.show(RoundTripError.hotKeyUnavailable)
    }

    public func run() {
        guard !isRunning else {
            // A round trip with a model takes seconds. A second press happens
            // precisely because no result is visible yet, and silence in reply
            // reads as "the shortcut is broken".
            Log.write("повторное нажатие во время круга, пропущено")
            environment.beep()
            return
        }
        isRunning = true
        Task { @MainActor in
            await roundTrip()
            isRunning = false
        }
    }

    private func roundTrip() async {
        let sourceApp = environment.frontmostApplication
        Log.section("хоткей: \(sourceApp?.localizedName ?? "неизвестно")")
        Log.write("флаги: \(ModifierFlags.describeCurrent()), способ вставки: \(settings.pasteMethod.rawValue)")

        // Access is checked again on every round: it can be revoked in System
        // Settings, and then the round trip has to lead to onboarding.
        guard environment.isAccessibilityTrusted else {
            Log.write("доступа Accessibility нет, показываем онбординг")
            onAccessibilityDenied()
            return
        }

        // Without this check secure input is indistinguishable from an empty
        // selection: events are dropped silently, the clipboard change count
        // never moves, and the person is told nothing was selected while their
        // text plainly is.
        guard !environment.isSecureInputActive else {
            Log.write("защищённый ввод включён, захват невозможен")
            notices.show(RoundTripError.secureInputActive)
            return
        }

        guard let sourceApp else {
            notices.show(RoundTripError.unknownTargetApp)
            return
        }

        let result = await capture.capture()
        switch result.outcome {
        case .nothingSelected:
            // The beep comes at once while the clipboard is watched for
            // another half second: a quick refusal and the guard against a
            // late copy are on different clocks.
            environment.beep()
            if settings.restoreClipboardAfterPaste {
                // The guard deliberately holds the round open. Letting it go
                // in a task of its own would allow the next round to start
                // while this one can still touch the clipboard, and a stale
                // snapshot would land on top of a fresh capture.
                await capture.restoreIfCopyLandsLate(after: result)
            }

        case .unsupportedSelection:
            // The same beep as an empty selection, on purpose. A window here
            // would explain what the person can already see, and cost them a
            // click to put away. Which of the two cases it was stays in the
            // log, where it is diagnosis rather than news.
            Log.write("выделение не пришло текстом")
            environment.beep()
            if settings.restoreClipboardAfterPaste {
                clipboard.restore(result.snapshot)
            }

        case .captured(let text):
            await fix(text, in: sourceApp, snapshot: result.snapshot)
        }
    }

    private func fix(_ text: String, in sourceApp: NSRunningApplication, snapshot: ClipboardSnapshot) async {
        let fixed: String
        do {
            fixed = try await transform.transform(text)
        } catch {
            // By this point the person's selection is already in the
            // clipboard: capture put it there. A failed model without a
            // restore would mean a dropped connection quietly ate whatever the
            // clipboard held.
            if settings.restoreClipboardAfterPaste {
                clipboard.restore(snapshot)
            }
            let failure = (error as? any UserFacingError) ?? LLMError.from(error)
            Log.write("исправление не состоялось: \(failure.title)")
            notices.show(failure)
            return
        }

        let outcome = await paster.paste(
            fixed,
            into: sourceApp,
            method: settings.pasteMethod,
            restoreClipboard: settings.restoreClipboardAfterPaste,
            snapshot: snapshot
        )
        if case .failure(let error) = outcome {
            notices.show(error)
        }
    }
}

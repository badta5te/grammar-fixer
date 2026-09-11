import AppKit
import Carbon.HIToolbox

/// Everything the round trip asks the system. The seam is not here for
/// tidiness: without it not one of the ways out of the round is covered by a
/// test, and the ways out are exactly what breaks unnoticed.
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

/// Showing a message to a person. The panel behind this seam draws a real
/// window; a test only looks at whether a message happened at all.
@MainActor
public protocol NoticePresenting {
    func show(_ error: any UserFacingError)
}

/// What the person decided about the correction in front of them.
public enum ResultDecision: Equatable, Sendable {
    case paste(String)
    /// Into the clipboard and nowhere else. The clipboard is then deliberately
    /// not put back: taking it over is the whole request.
    case copy(String)
    case dismissed
}

/// Showing a correction and waiting for a decision about it. The panel behind
/// this seam draws a window; a test only looks at what came back.
@MainActor
public protocol ResultPresenting {
    /// Returns once the person has decided. Every way out of the panel ends
    /// here, a click past it included: a decision that never arrives leaves the
    /// round open and the shortcut dead until a restart.
    func present(_ session: CorrectionSession) async -> ResultDecision
}

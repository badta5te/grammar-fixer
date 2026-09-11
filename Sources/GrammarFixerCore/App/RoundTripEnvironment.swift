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

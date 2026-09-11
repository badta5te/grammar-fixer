import Foundation
import ServiceManagement

/// Where the system stands on starting the app at login.
public enum LoginItemState: Equatable, Sendable {
    case on
    case off
    /// Registered, and the system is waiting for the person to allow it under
    /// System Settings → General → Login Items. A real third state: a switch
    /// that simply flips on while the system quietly waits would be a lie the
    /// person only finds out about at the next login.
    case waitingForApproval
}

@MainActor
public protocol LoginItemRegistering {
    var state: LoginItemState { get }
    func register() throws
    func unregister() throws
}

/// The switch for starting at login.
///
/// The state is asked of the system every time rather than kept beside it. A
/// login item can be removed in System Settings while this window is open, and
/// a remembered switch would then show the opposite of what happens at the next
/// login.
@MainActor
public final class LoginItem {
    private let registrar: any LoginItemRegistering

    public init(registrar: any LoginItemRegistering = SystemLoginItem()) {
        self.registrar = registrar
    }

    public var state: LoginItemState { registrar.state }

    /// On covers waiting for approval: the app did ask, and the window says
    /// separately that the system has not finished agreeing.
    public var isOn: Bool { state != .off }

    public var waitsForApproval: Bool { state == .waitingForApproval }

    /// - Returns: nil when the system agreed, otherwise something to show.
    @discardableResult
    public func set(_ on: Bool) -> Notice? {
        // Registering something already registered is itself an error, and the
        // window writes every change through, including the ones that change
        // nothing.
        guard on != isOn else { return nil }

        do {
            if on {
                try registrar.register()
            } else {
                try registrar.unregister()
            }
            Log.write("start at login: \(state)")
            return nil
        } catch {
            // The system's own words, whatever they are. A refusal here is
            // usually about where the app is kept, and only the system knows
            // which of its rules the copy in this particular folder broke.
            Log.write("start at login could not be changed: \(error)")
            return Notice(
                title: on ? "Could not be added to Login Items" : "Could not be removed from Login Items",
                message: "macOS refused: \(error.localizedDescription)"
            )
        }
    }
}

/// The system side, through ServiceManagement. The app registers itself, so
/// there is no helper bundle to keep in step with it.
@MainActor
public final class SystemLoginItem: LoginItemRegistering {
    public init() {}

    public var state: LoginItemState {
        switch SMAppService.mainApp.status {
        case .enabled: return .on
        case .requiresApproval: return .waitingForApproval
        case .notRegistered: return .off
        case .notFound:
            // Nothing to start: the registration names a bundle the system can
            // no longer find, which is what moving or renaming the app leaves
            // behind. Off is the truth, and the log says why.
            Log.write("the login item points at a bundle the system cannot find")
            return .off
        @unknown default: return .off
        }
    }

    public func register() throws { try SMAppService.mainApp.register() }

    public func unregister() throws { try SMAppService.mainApp.unregister() }
}

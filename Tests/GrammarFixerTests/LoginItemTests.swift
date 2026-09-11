import XCTest
@testable import GrammarFixerCore

/// A login item that the system, not the app, keeps the truth about. Somebody
/// can remove it in System Settings while the window is open, and a remembered
/// switch would then show the opposite of what happens at the next login.
@MainActor
final class LoginItemTests: XCTestCase {
    func testTheSystemIsAskedRatherThanRemembered() {
        let registrar = FakeLoginItemRegistrar()
        // A registration the system accepts and then quietly drops, which is
        // what a removal in System Settings looks like from here.
        registrar.followsThrough = false
        let item = LoginItem(registrar: registrar)

        XCTAssertNil(item.set(true))

        XCTAssertEqual(registrar.calls, ["register"])
        XCTAssertFalse(item.isOn)
    }

    func testTurningItOnRegistersTheApp() {
        let registrar = FakeLoginItemRegistrar()
        let item = LoginItem(registrar: registrar)

        XCTAssertNil(item.set(true))

        XCTAssertEqual(registrar.calls, ["register"])
        XCTAssertTrue(item.isOn)
        XCTAssertFalse(item.waitsForApproval)
    }

    func testTurningItOffUnregistersTheApp() {
        let registrar = FakeLoginItemRegistrar()
        registrar.state = .on
        let item = LoginItem(registrar: registrar)

        XCTAssertNil(item.set(false))

        XCTAssertEqual(registrar.calls, ["unregister"])
        XCTAssertFalse(item.isOn)
    }

    /// The commonest refusal is an app the system will not start from where it
    /// stands. Saying nothing would leave a switch that flips back by itself.
    func testARefusalIsSomethingToRead() {
        let registrar = FakeLoginItemRegistrar()
        registrar.failure = NSError(
            domain: "SMAppServiceErrorDomain",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: "Operation not permitted"]
        )
        let item = LoginItem(registrar: registrar)

        let notice = item.set(true)

        XCTAssertNotNil(notice)
        XCTAssertTrue(notice?.message.contains("Operation not permitted") ?? false)
        XCTAssertFalse(item.isOn)
    }

    /// The system may accept the registration and still wait for the person to
    /// allow it. The switch stays on, because the app did ask — but the window
    /// has to say that the system has not finished agreeing.
    func testWaitingForApprovalIsNotTheSameAsOff() {
        let registrar = FakeLoginItemRegistrar()
        registrar.stateAfterRegistering = .waitingForApproval
        let item = LoginItem(registrar: registrar)

        XCTAssertNil(item.set(true))

        XCTAssertTrue(item.isOn)
        XCTAssertTrue(item.waitsForApproval)
    }

    /// Registering twice is an error in itself, and the window writes through
    /// on every change, including the ones that change nothing.
    func testFlippingItToWhereItAlreadyStandsAsksTheSystemForNothing() {
        let registrar = FakeLoginItemRegistrar()
        registrar.state = .waitingForApproval
        let item = LoginItem(registrar: registrar)

        XCTAssertNil(item.set(true))
        registrar.state = .off
        XCTAssertNil(item.set(false))

        XCTAssertEqual(registrar.calls, [])
    }
}

@MainActor
private final class FakeLoginItemRegistrar: LoginItemRegistering {
    var state: LoginItemState = .off
    /// What the system reports once the registration is accepted.
    var stateAfterRegistering: LoginItemState = .on
    /// Whether the registration actually sticks.
    var followsThrough = true
    var failure: (any Error)?
    private(set) var calls: [String] = []

    func register() throws {
        calls.append("register")
        if let failure { throw failure }
        if followsThrough { state = stateAfterRegistering }
    }

    func unregister() throws {
        calls.append("unregister")
        if let failure { throw failure }
        if followsThrough { state = .off }
    }
}

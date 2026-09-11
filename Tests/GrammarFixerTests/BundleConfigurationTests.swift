import XCTest
@testable import GrammarFixerCore

/// Info.plist is assembled by hand rather than by Xcode, so nothing catches a
/// typo in it: the app would simply turn up in the Dock, or take on a different
/// identifier and lose the Accessibility access it was granted.
final class BundleConfigurationTests: XCTestCase {
    private var repositoryRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private var plist: [String: Any] {
        let url = repositoryRoot.appending(path: "Resources/Info.plist")
        guard let data = try? Data(contentsOf: url),
              let parsed = try? PropertyListSerialization.propertyList(from: data, format: nil),
              let dict = parsed as? [String: Any]
        else {
            XCTFail("Не удалось прочитать Resources/Info.plist")
            return [:]
        }
        return dict
    }

    func testAppIsAMenuBarAgent() {
        XCTAssertEqual(plist["LSUIElement"] as? Bool, true)
    }

    func testBundleIdentifierMatchesTheOneUsedInCode() {
        XCTAssertEqual(plist["CFBundleIdentifier"] as? String, AppInfo.bundleIdentifier)
    }

    /// The executable name inside the bundle comes from the executable target
    /// in Package.swift. If the two drift apart the bundle will not launch at
    /// all, so this compares against the manifest rather than against yet
    /// another constant in the code.
    func testExecutableNameMatchesTheExecutableTargetInTheManifest() throws {
        let manifest = try String(contentsOf: repositoryRoot.appending(path: "Package.swift"), encoding: .utf8)
        let pattern = #/\.executableTarget\(\s*name:\s*"(?<name>[^"]+)"/#
        let target = try XCTUnwrap(manifest.firstMatch(of: pattern)?.name)

        XCTAssertEqual(plist["CFBundleExecutable"] as? String, String(target))
        XCTAssertEqual(String(target), AppInfo.name)
    }

    func testMinimumSystemVersionIsDeclared() {
        XCTAssertEqual(plist["LSMinimumSystemVersion"] as? String, "14.0")
    }

    /// The version is written in two places: the plist, and a fallback in the
    /// code for running outside a bundle. They must not diverge.
    func testFallbackVersionMatchesThePlist() {
        XCTAssertEqual(plist["CFBundleShortVersionString"] as? String, AppInfo.fallbackVersion)
    }
}

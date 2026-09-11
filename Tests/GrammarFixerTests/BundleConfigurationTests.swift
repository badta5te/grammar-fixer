import XCTest
@testable import GrammarFixerCore

/// Info.plist собирается руками, а не Xcode, поэтому опечатка в нём ничем не
/// ловится: приложение просто молча появится в доке или получит чужой
/// идентификатор и потеряет выданный доступ Accessibility.
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

    /// Имя исполняемого файла в бандле задаётся именем исполняемой цели в
    /// Package.swift. Если они разойдутся, бандл не запустится вовсе, поэтому
    /// сравниваем именно с манифестом, а не с ещё одной константой в коде.
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

    /// Версия записана в двух местах: в plist и запасным значением в коде на
    /// случай запуска вне бандла. Разойтись они не должны.
    func testFallbackVersionMatchesThePlist() {
        XCTAssertEqual(plist["CFBundleShortVersionString"] as? String, AppInfo.fallbackVersion)
    }
}

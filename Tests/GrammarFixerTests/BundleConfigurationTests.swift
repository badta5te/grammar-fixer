import XCTest
@testable import GrammarFixerCore

/// Info.plist собирается руками, а не Xcode, поэтому опечатка в нём ничем не
/// ловится: приложение просто молча появится в доке или получит чужой
/// идентификатор и потеряет выданный доступ Accessibility.
final class BundleConfigurationTests: XCTestCase {
    private var plist: [String: Any] {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let url = root.appending(path: "Resources/Info.plist")
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

    /// Имя исполняемого файла в бандле задаётся именем цели в Package.swift.
    /// Если они разойдутся, бандл не запустится вовсе.
    func testExecutableNameMatchesTheProductName() {
        XCTAssertEqual(plist["CFBundleExecutable"] as? String, AppInfo.name)
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

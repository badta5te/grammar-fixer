import Foundation

/// Значения из Info.plist. Когда бинарник запущен вне бандла, например при
/// отладке, plist недоступен — тогда подставляется fallbackVersion, чтобы
/// интерфейс не показывал пустоту. Тест следит, чтобы она не разошлась с plist.
public enum AppInfo {
    public static let bundleIdentifier = "com.badta5te.GrammarFixer"
    public static let name = "GrammarFixer"
    public static let fallbackVersion = "0.1.0"

    public static var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
            ?? fallbackVersion
    }
}

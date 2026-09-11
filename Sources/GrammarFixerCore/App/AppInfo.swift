import Foundation

/// Values from Info.plist. When the binary runs outside a bundle, during
/// debugging for instance, there is no plist, and fallbackVersion stands in so
/// the interface shows something rather than nothing. A test keeps the two from
/// drifting apart.
public enum AppInfo {
    public static let bundleIdentifier = "com.badta5te.GrammarFixer"
    public static let name = "GrammarFixer"
    public static let fallbackVersion = "0.1.0"

    public static var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
            ?? fallbackVersion
    }
}

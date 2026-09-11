import Foundation

/// The round trip's log. Not debugging for its own sake: a ticket is verified
/// by hand, and three times over the prototype the impression that it worked
/// disagreed with what had actually happened. The log is the only way to tell
/// those apart.
///
/// The content of a selection never reaches the log, only its length: this app
/// works on top of other people's passwords and correspondence.
@MainActor
public enum Log {
    /// Off by default: the app turns the log on at launch according to the
    /// setting. Otherwise tests would write into the user's own file.
    public static var isEnabled = false

    public static let fileURL = FileManager.default
        .homeDirectoryForCurrentUser
        .appending(path: "Library/Logs/GrammarFixer.log")

    private static let maximumSize = 1_000_000
    private static let formatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"
        return formatter
    }()

    public static func write(_ message: String) {
        guard isEnabled else { return }
        append("\(formatter.string(from: Date()))  \(message)\n")
    }

    public static func section(_ title: String) {
        guard isEnabled else { return }
        append("\n=== \(formatter.string(from: Date()))  \(title)\n")
    }

    /// Trims the log once it has grown. The app lives in the background for
    /// months and nobody cleans the file up.
    public static func trimIfNeeded() {
        let attributes = try? FileManager.default.attributesOfItem(atPath: fileURL.path)
        guard let size = attributes?[.size] as? Int, size > maximumSize else { return }
        try? FileManager.default.removeItem(at: fileURL)
        write("log trimmed, it was \(size) bytes")
    }

    private static func append(_ line: String) {
        guard let data = line.data(using: .utf8) else { return }
        if let handle = try? FileHandle(forWritingTo: fileURL) {
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: data)
        } else {
            try? data.write(to: fileURL)
        }
    }
}

import Foundation

/// Журнал круга. Нужен не для отладки ради отладки: проверка тикета ручная, и
/// впечатление «сработало» трижды за прототип расходилось с тем, что произошло
/// на самом деле. Журнал — единственный способ это различить.
///
/// Содержимое выделения в журнал не попадает никогда, только длина: приложение
/// работает поверх чужих паролей и переписки.
@MainActor
public enum Log {
    /// По умолчанию выключен: журнал включает приложение при запуске по
    /// настройке. Иначе тесты писали бы в файл пользователя.
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

    /// Обрезает журнал, если он разросся. Приложение живёт месяцами в фоне, а
    /// файл никто не чистит.
    public static func trimIfNeeded() {
        let attributes = try? FileManager.default.attributesOfItem(atPath: fileURL.path)
        guard let size = attributes?[.size] as? Int, size > maximumSize else { return }
        try? FileManager.default.removeItem(at: fileURL)
        write("журнал обрезан, прежний размер \(size) байт")
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

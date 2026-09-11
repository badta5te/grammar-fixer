import AppKit

/// Снимок буфера обмена со всеми типами каждого элемента.
///
/// Хранится значениями, а не живыми `NSPasteboardItem`: элемент можно отдать
/// системе ровно один раз, поэтому снимок из объектов после первого
/// восстановления молча перестал бы работать.
///
/// Чего снимок не берёт: обещанные и отложенные типы, у которых данных ещё нет
/// и `data(forType:)` возвращает nil. Скопированный из Finder файл, отданный
/// обещанием, круг переживёт не целиком. Ради этого случая и существует
/// выключатель восстановления.
public struct ClipboardSnapshot: Equatable, Sendable {
    public struct Item: Equatable, Sendable {
        public var payloads: [String: Data]

        public init(payloads: [String: Data]) { self.payloads = payloads }
    }

    public var items: [Item]

    public init(items: [Item]) { self.items = items }

    public var isEmpty: Bool { items.allSatisfy(\.payloads.isEmpty) }

    public var typeCount: Int { items.reduce(0) { $0 + $1.payloads.count } }
}

@MainActor
public protocol Clipboard: AnyObject {
    var changeCount: Int { get }
    func readText() -> String?
    func snapshot() -> ClipboardSnapshot
    @discardableResult func restore(_ snapshot: ClipboardSnapshot) -> Bool
    func write(_ text: String)
}

@MainActor
public final class SystemClipboard: Clipboard {
    private let pasteboard: NSPasteboard

    public init(pasteboard: NSPasteboard = .general) {
        self.pasteboard = pasteboard
    }

    public var changeCount: Int { pasteboard.changeCount }

    public func readText() -> String? { pasteboard.string(forType: .string) }

    public func snapshot() -> ClipboardSnapshot {
        let items = (pasteboard.pasteboardItems ?? []).map { item in
            var payloads: [String: Data] = [:]
            for type in item.types {
                if let data = item.data(forType: type) { payloads[type.rawValue] = data }
            }
            return ClipboardSnapshot.Item(payloads: payloads)
        }
        return ClipboardSnapshot(items: items)
    }

    @discardableResult
    public func restore(_ snapshot: ClipboardSnapshot) -> Bool {
        // Пустой снимок не значит «очистить буфер»: скорее всего мы просто не
        // смогли ничего прочитать, и затирать чужое содержимое на этом
        // основании нельзя.
        guard !snapshot.isEmpty else {
            Log.write("восстанавливать нечего, снимок пуст")
            return false
        }

        let items = snapshot.items.compactMap { item -> NSPasteboardItem? in
            guard !item.payloads.isEmpty else { return nil }
            let restored = NSPasteboardItem()
            for (type, data) in item.payloads {
                restored.setData(data, forType: NSPasteboard.PasteboardType(type))
            }
            return restored
        }
        guard !items.isEmpty else { return false }

        pasteboard.clearContents()
        let written = pasteboard.writeObjects(items)
        Log.write("буфер восстановлен: \(written), элементов \(items.count), типов \(snapshot.typeCount)")
        return written
    }

    public func write(_ text: String) {
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }
}

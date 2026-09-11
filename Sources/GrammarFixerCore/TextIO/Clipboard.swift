import AppKit

/// A snapshot of the clipboard with every type of every item.
///
/// Held as values rather than live `NSPasteboardItem`s: an item can be handed
/// to the system exactly once, so a snapshot made of objects would quietly stop
/// working after the first restore.
///
/// What the snapshot does not take: promised and lazy types, which have no data
/// yet and answer `data(forType:)` with nil. A file copied from Finder and
/// handed over as a promise will not survive a round trip whole. That case is
/// the reason the restore switch exists.
public struct ClipboardSnapshot: Equatable, Sendable {
    public struct Item: Equatable, Sendable {
        public var payloads: [String: Data]

        public init(payloads: [String: Data]) { self.payloads = payloads }
    }

    public var items: [Item]

    /// The clipboard could be read at all. `pasteboardItems` returns nil, and
    /// without this flag "could not be read" is indistinguishable from "was
    /// empty", while the right thing to do in those two cases is opposite.
    public var wasRead: Bool

    public init(items: [Item], wasRead: Bool = true) {
        self.items = items
        self.wasRead = wasRead
    }

    public var isEmpty: Bool { items.allSatisfy(\.payloads.isEmpty) }

    /// The clipboard was genuinely empty, as opposed to "we could not read
    /// anything". Two different failures hide behind an empty snapshot: a read
    /// that returned nothing at all, and promised types that have an item with
    /// no data in it. Neither is an empty clipboard, and neither may be put
    /// back by clearing.
    public var wasEmpty: Bool { wasRead && items.isEmpty }

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
        let contents = pasteboard.pasteboardItems
        let items = (contents ?? []).map { item in
            var payloads: [String: Data] = [:]
            for type in item.types {
                if let data = item.data(forType: type) { payloads[type.rawValue] = data }
            }
            return ClipboardSnapshot.Item(payloads: payloads)
        }
        return ClipboardSnapshot(items: items, wasRead: contents != nil)
    }

    @discardableResult
    public func restore(_ snapshot: ClipboardSnapshot) -> Bool {
        // A clipboard that was empty is put back empty: otherwise the
        // selection that capture left there stays in the clipboard after a
        // round that failed.
        if snapshot.wasEmpty {
            pasteboard.clearContents()
            Log.write("буфер очищен: до круга он был пуст")
            return true
        }

        // Anything else that looks empty means a failed read: either the
        // pasteboard would not be read at all, or the types were promised and
        // carried no data. Neither is grounds for wiping somebody's clipboard.
        guard !snapshot.isEmpty else {
            Log.write("восстанавливать нечего, данных в снимке нет")
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

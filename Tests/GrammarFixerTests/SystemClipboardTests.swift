import AppKit
import XCTest
@testable import GrammarFixerCore

/// Проверяется на именованном буфере, а не на общем: тесты не имеют права
/// уничтожать то, что пользователь скопировал.
///
/// Прототип сохранял только строку, и круг поверх скопированного скриншота
/// уничтожал картинку безвозвратно. Поэтому снимок обязан быть по всем типам.
@MainActor
final class SystemClipboardTests: XCTestCase {
    private var pasteboard: NSPasteboard!
    private var clipboard: SystemClipboard!

    private let png = NSPasteboard.PasteboardType("public.png")
    private let tiff = NSPasteboard.PasteboardType("public.tiff")

    override func setUp() async throws {
        pasteboard = NSPasteboard(name: NSPasteboard.Name("com.badta5te.GrammarFixer.tests"))
        pasteboard.clearContents()
        clipboard = SystemClipboard(pasteboard: pasteboard)
    }

    override func tearDown() async throws {
        pasteboard.releaseGlobally()
    }

    private func writeItem(_ payloads: [NSPasteboard.PasteboardType: Data]) {
        let item = NSPasteboardItem()
        for (type, data) in payloads { item.setData(data, forType: type) }
        pasteboard.clearContents()
        XCTAssertTrue(pasteboard.writeObjects([item]))
    }

    func testSnapshotKeepsEveryTypeOfEveryItem() {
        writeItem([png: Data([0x89, 0x50]), tiff: Data([0x4D, 0x4D]), .string: Data("подпись".utf8)])

        let snapshot = clipboard.snapshot()

        XCTAssertEqual(snapshot.items.count, 1)
        XCTAssertEqual(snapshot.typeCount, 3)
        XCTAssertEqual(snapshot.items[0].payloads["public.png"], Data([0x89, 0x50]))
    }

    func testRestoreBringsBackNonTextualContentByteForByte() {
        let image = Data([0x89, 0x50, 0x4E, 0x47])
        writeItem([png: image, .string: Data("подпись".utf8)])
        let snapshot = clipboard.snapshot()

        clipboard.write("ПРОМЕЖУТОЧНЫЙ ТЕКСТ")
        XCTAssertNil(pasteboard.data(forType: png))

        XCTAssertTrue(clipboard.restore(snapshot))

        XCTAssertEqual(pasteboard.data(forType: png), image)
        XCTAssertEqual(clipboard.readText(), "подпись")
    }

    /// NSPasteboardItem можно отдать системе только один раз, поэтому снимок
    /// хранится значениями. Иначе второе восстановление молча ничего не вернёт.
    func testTheSameSnapshotCanBeRestoredTwice() {
        writeItem([.string: Data("исходное".utf8)])
        let snapshot = clipboard.snapshot()

        clipboard.write("чужое")
        XCTAssertTrue(clipboard.restore(snapshot))
        clipboard.write("снова чужое")
        XCTAssertTrue(clipboard.restore(snapshot))

        XCTAssertEqual(clipboard.readText(), "исходное")
    }

    func testRestoringAnEmptySnapshotDoesNotWipeTheClipboard() {
        writeItem([.string: Data("что-то".utf8)])

        XCTAssertFalse(clipboard.restore(ClipboardSnapshot(items: [])))

        XCTAssertEqual(clipboard.readText(), "что-то")
    }

    func testChangeCountMovesOnWrite() {
        let before = clipboard.changeCount
        clipboard.write("новое")
        XCTAssertNotEqual(clipboard.changeCount, before)
    }
}

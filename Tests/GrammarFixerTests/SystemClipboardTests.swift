import AppKit
import XCTest
@testable import GrammarFixerCore

/// Checked against a named pasteboard rather than the general one: tests have
/// no right to destroy what somebody copied.
///
/// The prototype saved only the string, and a round trip run over a copied
/// screenshot destroyed the image for good. That is why the snapshot has to
/// cover every type.
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

    /// An NSPasteboardItem can be handed to the system only once, which is why
    /// the snapshot is held as values. Otherwise a second restore would
    /// quietly put nothing back.
    func testTheSameSnapshotCanBeRestoredTwice() {
        writeItem([.string: Data("исходное".utf8)])
        let snapshot = clipboard.snapshot()

        clipboard.write("чужое")
        XCTAssertTrue(clipboard.restore(snapshot))
        clipboard.write("снова чужое")
        XCTAssertTrue(clipboard.restore(snapshot))

        XCTAssertEqual(clipboard.readText(), "исходное")
    }

    /// A snapshot with no items means the clipboard was empty, and putting
    /// such a clipboard back means clearing it. Otherwise the captured
    /// selection would stay in the clipboard after a round that failed.
    func testRestoringAnEmptyClipboardClearsIt() {
        writeItem([.string: Data("захваченное выделение".utf8)])

        XCTAssertTrue(clipboard.restore(ClipboardSnapshot(items: [])))

        XCTAssertNil(clipboard.readText())
    }

    /// A pasteboard that could not be read at all looks exactly like an empty
    /// one. Clearing on that basis destroys whatever the person had copied.
    func testSnapshotThatCouldNotBeTakenDoesNotWipeTheClipboard() {
        writeItem([.string: Data("что-то".utf8)])
        let unread = ClipboardSnapshot(items: [], wasRead: false)

        XCTAssertFalse(clipboard.restore(unread))

        XCTAssertEqual(clipboard.readText(), "что-то")
    }

    /// A snapshot with an item but no data means something else: the types
    /// were promised and nothing could be read. That is no grounds for wiping
    /// somebody's clipboard.
    func testSnapshotThatCouldNotBeReadDoesNotWipeTheClipboard() {
        writeItem([.string: Data("что-то".utf8)])
        let unreadable = ClipboardSnapshot(items: [ClipboardSnapshot.Item(payloads: [:])])

        XCTAssertFalse(clipboard.restore(unreadable))

        XCTAssertEqual(clipboard.readText(), "что-то")
    }

    func testChangeCountMovesOnWrite() {
        let before = clipboard.changeCount
        clipboard.write("новое")
        XCTAssertNotEqual(clipboard.changeCount, before)
    }
}

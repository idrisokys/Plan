import XCTest
@testable import Plan

/// Geçici bir klasörde gerçek dosya işlemlerini dener (~/Link'e dokunmaz).
final class StoreFileTests: XCTestCase {
    private var dir: URL!

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("plan-test-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: dir)
    }

    func testAddLinkRoundTrip() {
        XCTAssertTrue(NotesStore.addLink(dir, title: "Example: Site", url: "https://example.com"))
        let items = NotesStore.list(dir)
        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items[0].title, "Example - Site")
        XCTAssertEqual(NotesStore.readLink(items[0].url).0, "https://example.com")
    }

    func testNewItemsGoToTop() {
        for t in ["b", "a", "c"] { XCTAssertTrue(NotesStore.addLink(dir, title: t, url: "https://example.com/\(t)")) }
        XCTAssertEqual(NotesStore.list(dir).map { $0.title }, ["c", "a", "b"])
        XCTAssertNotNil(NotesStore.addFolder(dir, "Klasör"))
        XCTAssertEqual(NotesStore.list(dir).first?.title, "Klasör")
    }

    func testDuplicateTitlesGetNumberSuffix() {
        XCTAssertTrue(NotesStore.addLink(dir, title: "b", url: "https://example.com/1"))
        XCTAssertTrue(NotesStore.addLink(dir, title: "b", url: "https://example.com/2"))
        XCTAssertEqual(NotesStore.list(dir).map { $0.title }, ["b (2)", "b"])
    }

    func testNoteKeepsNewlines() {
        XCTAssertTrue(NotesStore.addNote(dir, text: "line1\nline2"))
        let e = NotesStore.list(dir)[0]
        let (url, text) = NotesStore.readLink(e.url)
        XCTAssertNil(url)
        XCTAssertEqual(text, "line1\nline2")
    }

    func testTextFileRoundTrip() {
        XCTAssertTrue(NotesStore.addTextFile(dir, text: "hello world"))
        let e = NotesStore.list(dir)[0]
        XCTAssertTrue(e.isTxt)
        XCTAssertEqual(NotesStore.readPlain(e.url), "hello world")
        XCTAssertTrue(NotesStore.writePlain(e.url, "changed"))
        XCTAssertEqual(NotesStore.readPlain(e.url), "changed")
    }

    func testRenameKeepsExtension() {
        XCTAssertTrue(NotesStore.addLink(dir, title: "old", url: "https://example.com"))
        let e = NotesStore.list(dir)[0]
        XCTAssertTrue(NotesStore.rename(dir, e, "new"))
        let after = NotesStore.list(dir)
        XCTAssertEqual(after.map { $0.title }, ["new"])
        XCTAssertEqual(after[0].name, "new.url")
    }

    func testRenameNoteUpdatesContent() {
        XCTAssertTrue(NotesStore.addNote(dir, text: "old text"))
        let e = NotesStore.list(dir)[0]
        XCTAssertTrue(NotesStore.rename(dir, e, "new text"))
        let after = NotesStore.list(dir)[0]
        XCTAssertEqual(NotesStore.readLink(after.url).1, "new text")
    }

    func testConvertToTxtKeepsPosition() {
        XCTAssertTrue(NotesStore.addLink(dir, title: "first", url: "https://example.com/1"))
        XCTAssertTrue(NotesStore.addLink(dir, title: "second", url: "https://example.com/2"))
        XCTAssertTrue(NotesStore.addLink(dir, title: "third", url: "https://example.com/3"))
        let e = NotesStore.list(dir)[1]
        XCTAssertTrue(NotesStore.convertToTxt(dir, e, "long text\nhttps://example.com/2"))
        let after = NotesStore.list(dir)
        XCTAssertEqual(after.count, 3)
        XCTAssertTrue(after[1].isTxt)
        XCTAssertEqual(NotesStore.readPlain(after[1].url), "long text\nhttps://example.com/2")
    }

    func testSyncResolveRejectsEscapes() {
        XCTAssertNil(NoteSync.resolve("../evil.url", root: dir))
        XCTAssertNil(NoteSync.resolve("a/../../evil.url", root: dir))
        XCTAssertNil(NoteSync.resolve("note.exe", root: dir))
        XCTAssertNotNil(NoteSync.resolve("folder/note.url", root: dir))
    }

    func testTxtSearchFoldKeepsLength() {
        let s = "İstanbul ŞĞÜÖÇ ıI"
        XCTAssertEqual((NotesModel.fk(s) as NSString).length, (s as NSString).length)
    }

    func testSearchFindsAcrossFoldersAndTurkishLetters() {
        let sub = NotesStore.addFolder(dir, "Work")
        XCTAssertNotNil(sub)
        XCTAssertTrue(NotesStore.addLink(sub!, title: "Swift Docs", url: "https://developer.apple.com/swift"))
        XCTAssertTrue(NotesStore.addNote(dir, text: "Çalışma Notları"))

        let a = NotesStore.search(root: dir, query: "SWIFT", alive: { true })
        XCTAssertEqual(a.count, 1)
        XCTAssertEqual(a.first?.entry.title, "Swift Docs")
        XCTAssertEqual(a.first?.path.map { $0.name }, ["Work"])

        let b = NotesStore.search(root: dir, query: "calisma notlari", alive: { true })
        XCTAssertEqual(b.count, 1)
    }

    // Panel ve Notlarım penceresi aynı ekleme / arama kodunu kullanır
    func testSharedSubmitRules() async {
        let short = await NotesStore.submit(dir, "kısa bir not")
        XCTAssertEqual(short, .added)
        let long = await NotesStore.submit(dir, String(repeating: "uzun metin ", count: 40))
        XCTAssertEqual(long, .textFile)
        let items = NotesStore.list(dir)
        XCTAssertEqual(items.count, 2)
        XCTAssertEqual(items.filter { $0.isTxt }.count, 1)
        let empty = await NotesStore.submit(dir, "   ")
        XCTAssertEqual(empty, .failed)
    }

    func testSharedSearchAsyncFindsSubmittedNote() async {
        _ = await NotesStore.submit(dir, "Çiçek sulama notu")
        let hits = await NotesStore.searchAsync(root: dir, query: "cicek", alive: { true })
        XCTAssertEqual(hits.count, 1)
    }
}

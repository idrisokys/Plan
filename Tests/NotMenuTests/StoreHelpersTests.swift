import XCTest
@testable import NotMenu

final class StoreHelpersTests: XCTestCase {
    func testFoldIgnoresTurkishLettersCaseAndAccents() {
        XCTAssertEqual(NotesStore.fold("İstanbul"), "istanbul")
        XCTAssertEqual(NotesStore.fold("ŞĞÜÖÇı"), "sguoci")
        XCTAssertEqual(NotesStore.fold("Café"), "cafe")
    }

    func testExtractUrlStripsTrailingPunctuation() {
        XCTAssertEqual(NotesStore.extractUrl("bak https://example.com/a?b=1."), "https://example.com/a?b=1")
        XCTAssertEqual(NotesStore.extractUrl("(https://example.com/x)"), "https://example.com/x")
        XCTAssertEqual(NotesStore.extractUrl("https://en.wikipedia.org/wiki/Swift_(programming_language)"),
                       "https://en.wikipedia.org/wiki/Swift_(programming_language)")
        XCTAssertNil(NotesStore.extractUrl("burada link yok"))
    }

    func testCleanProducesSafeFileNames() {
        XCTAssertEqual(NotesStore.clean("a:b"), "a - b")
        XCTAssertEqual(NotesStore.clean("what?"), "what")
        XCTAssertEqual(NotesStore.clean("  ..hidden"), "hidden")
        XCTAssertEqual(NotesStore.clean("***"), "link")
        XCTAssertEqual(NotesStore.clean(String(repeating: "a", count: 300), 10), String(repeating: "a", count: 10))
    }

    func testFitBytesStaysWithinLimit() {
        let s = String(repeating: "ş", count: 200)   // her biri 2 bayt
        XCTAssertEqual(NotesStore.fitBytes(s, limit: 240).utf8.count, 240)
    }

    func testEntryTitleAndKind() {
        let dir = URL(fileURLWithPath: "/tmp")
        let link = Entry(name: "a.url", url: dir.appendingPathComponent("a.url"), isDir: false)
        XCTAssertEqual(link.title, "a")
        XCTAssertFalse(link.isTxt)
        let txt = Entry(name: "n.TXT", url: dir.appendingPathComponent("n.TXT"), isDir: false)
        XCTAssertTrue(txt.isTxt)
        XCTAssertEqual(txt.title, "n")
        XCTAssertEqual(txt.ext, ".txt")
        let folder = Entry(name: "Klasör", url: dir.appendingPathComponent("Klasör"), isDir: true)
        XCTAssertEqual(folder.title, "Klasör")
    }
}

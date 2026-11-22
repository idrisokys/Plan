import XCTest
@testable import Plan

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

// Rust çekirdeği köprüsü (rust/plan_core)
final class RustCoreTests: XCTestCase {
    func testAnalyzeComputesSha256AndSize() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("rc-\(UUID().uuidString).txt")
        try Data("abc".utf8).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        let info = RustCore.analyze([url, URL(fileURLWithPath: "/yok/boyle/dosya")])
        XCTAssertEqual(info.count, 2)
        XCTAssertTrue(info[0].ok)
        XCTAssertEqual(info[0].size, 3)
        XCTAssertEqual(info[0].sha256, "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
        XCTAssertFalse(info[1].ok)
    }

    func testScanListsTreeWithoutHiddenFiles() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("rs-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir.appendingPathComponent("a"), withIntermediateDirectories: true)
        try Data("x".utf8).write(to: dir.appendingPathComponent("a/n.txt"))
        try Data("x".utf8).write(to: dir.appendingPathComponent(".gizli"))
        defer { try? FileManager.default.removeItem(at: dir) }
        let items = RustCore.scan(dir)
        XCTAssertEqual(items.map { $0.url.lastPathComponent }, ["a", "n.txt"])
        XCTAssertEqual(items.map { $0.isDir }, [true, false])
    }
}

import Foundation

/// Android'deki MyLauncher / Notlarım ile aynı dosya biçimi: ~/Link altında .url (URL= veya TEXT=) ve .txt dosyaları.
struct Note: Identifiable, Hashable {
    let id: String
    let url: URL
    let title: String
    let body: String      // link adresi ya da not metni
    let isLink: Bool
    let isTxt: Bool
    let folder: String
    let modified: Date
}

enum Store {
    static let addMax = 220
    static var defaultDir: URL { FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Link", isDirectory: true) }
    static var dir: URL {
        let d = UserDefaults.standard.string(forKey: "notesDir").map { URL(fileURLWithPath: $0, isDirectory: true) } ?? defaultDir
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }

    /// Türkçe i/ı/İ, ş, ğ... ve büyük/küçük harf farkını yok sayar.
    static func fold(_ s: String) -> String {
        s.replacingOccurrences(of: "İ", with: "i").replacingOccurrences(of: "ı", with: "i")
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil)
    }

    static func loadAll() -> [Note] {
        let root = dir
        guard let en = FileManager.default.enumerator(
            at: root, includingPropertiesForKeys: [.isDirectoryKey, .contentModificationDateKey],
            options: [.skipsHiddenFiles]) else { return [] }
        var out: [Note] = []
        for case let u as URL in en {
            let v = try? u.resourceValues(forKeys: [.isDirectoryKey, .contentModificationDateKey])
            if v?.isDirectory == true { continue }
            let ext = u.pathExtension.lowercased()
            guard ext == "url" || ext == "txt" else { continue }
            guard let raw = try? String(contentsOf: u, encoding: .utf8) else { continue }
            let title = u.deletingPathExtension().lastPathComponent
            var link: String?, text: String?
            if ext == "txt" { text = raw.replacingOccurrences(of: "\u{FEFF}", with: "") }
            else {
                for l in raw.components(separatedBy: .newlines) {
                    let t = l.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "\u{FEFF}", with: "")
                    if t.uppercased().hasPrefix("URL=") && link == nil { link = String(t.dropFirst(4)) }
                    if t.uppercased().hasPrefix("TEXT=") && text == nil { text = unescape(String(t.dropFirst(5))) }
                }
            }
            let rel = u.path.replacingOccurrences(of: root.path + "/", with: "")
            let folder = (rel as NSString).deletingLastPathComponent
            out.append(Note(id: rel, url: u, title: title, body: link ?? text ?? "", isLink: link != nil,
                            isTxt: ext == "txt", folder: folder, modified: v?.contentModificationDate ?? .distantPast))
        }
        return out.sorted { $0.modified > $1.modified }
    }

    static func search(_ notes: [Note], _ query: String) -> [Note] {
        let terms = fold(query).split(whereSeparator: { $0.isWhitespace }).map(String.init)
        if terms.isEmpty { return notes }
        let hits = notes.filter { n in
            let all = fold(n.title) + "\n" + fold(n.body)
            return terms.allSatisfy { all.contains($0) }
        }
        // başlıkta geçenler önce
        return hits.sorted { a, b in
            let ta = terms.allSatisfy { fold(a.title).contains($0) }
            let tb = terms.allSatisfy { fold(b.title).contains($0) }
            return ta && !tb
        }
    }

    // MARK: Ekleme (tek "gönder" kuralı: link → .url, kısa metin → not, uzun metin → .txt)
    @discardableResult
    static func submit(_ text: String, subject: String? = nil) -> Bool {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.isEmpty { return false }
        let url = extractURL(t)
        let singleURL = url != nil && !t.contains(where: { $0.isWhitespace })
        if t.count > addMax && !singleURL { return write(base: t, ext: "txt", data: Data(t.utf8), max: 100) }
        if let url = url {
            let title = subject?.components(separatedBy: .newlines).first(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty })
                ?? t.replacingOccurrences(of: url, with: "").components(separatedBy: .newlines)
                    .first(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty })?.trimmingCharacters(in: .whitespaces)
                ?? URL(string: url)?.host ?? "link"
            return write(base: title, ext: "url", data: Data("[InternetShortcut]\r\nURL=\(url)\r\n".utf8))
        }
        let enc = t.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\r", with: "")
            .replacingOccurrences(of: "\n", with: "\\n")
        return write(base: t, ext: "url", data: Data("[InternetShortcut]\r\nTEXT=\(enc)\r\n".utf8))
    }

    static func delete(_ n: Note) { try? FileManager.default.trashItem(at: n.url, resultingItemURL: nil) }

    // MARK: Yardımcılar
    private static func write(base: String, ext: String, data: Data, max: Int = 80) -> Bool {
        let b = clean(base, max)
        let fm = FileManager.default
        var name = "\(b).\(ext)", i = 2
        while fm.fileExists(atPath: dir.appendingPathComponent(name).path) { name = "\(b) (\(i)).\(ext)"; i += 1 }
        do { try data.write(to: dir.appendingPathComponent(name)); return true } catch { return false }
    }

    private static func clean(_ s: String, _ max: Int) -> String {
        var r = s.components(separatedBy: .controlCharacters).joined(separator: " ")
        for c in ["/", "\\", ":", "*", "?", "\"", "<", ">", "|"] { r = r.replacingOccurrences(of: c, with: " - ") }
        r = r.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
        r = String(r.prefix(max)).trimmingCharacters(in: CharacterSet(charactersIn: ". -"))
        while r.utf8.count > 240 { r.removeLast() }
        return r.isEmpty ? "not" : r
    }

    static func extractURL(_ s: String) -> String? {
        let d = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)
        let m = d?.firstMatch(in: s, range: NSRange(s.startIndex..., in: s))
        guard let u = m?.url, let sch = u.scheme, sch.hasPrefix("http") else { return nil }
        return u.absoluteString == s ? s : (m.flatMap { Range($0.range, in: s).map { String(s[$0]) } } ?? u.absoluteString)
    }

    private static func unescape(_ s: String) -> String {
        var out = "", it = s.makeIterator()
        while let c = it.next() {
            if c == "\\", let n = it.next() { out.append(n == "n" ? "\n" : n) } else { out.append(c) }
        }
        return out
    }
}

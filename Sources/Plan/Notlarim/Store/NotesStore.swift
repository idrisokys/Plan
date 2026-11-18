import Foundation

/// Disk işlemleri: ~/Link altındaki klasör/.url/.txt dosyalarını okur ve yazar.
/// Tüm yazma işlemleri `lock` ile sıralanır. Ad temizleme, okuma, arama ve sayfa başlığı
/// ayrı dosyalarda (NotesStore+*.swift, PageTitle.swift) durur.
enum NotesStore {
    private static let ORDER = ".order.txt"
    private static let PINNED = ".pinned.txt"   // sabitlenen öğelerin adları (yalnızca bu cihazda, eşitlenmez)
    private static let lock = NSRecursiveLock()

    // MARK: - Kök klasör

    /// Varsayılan veri klasörü: <ana dizin>/Link.
    static var defaultRoot: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Link", isDirectory: true)
    }

    private static func usable(_ p: String) -> Bool {
        var isDir: ObjCBool = false
        let fm = FileManager.default
        return fm.fileExists(atPath: p, isDirectory: &isDir) && isDir.boolValue && fm.isWritableFile(atPath: p)
    }

    /// Kök klasör: her zaman ~/Link (gerekirse oluşturulur). Oluşturulamaz ya da yazılamazsa nil.
    static var root: URL? {
        let d = defaultRoot
        if !usable(d.path) {
            try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
            if !usable(d.path) { return nil }
        }
        return d
    }

    // MARK: - Listeleme ve sıra

    private static func children(_ dir: URL) -> [Entry] {
        let fm = FileManager.default
        guard let names = try? fm.contentsOfDirectory(atPath: dir.path) else { return [] }
        return names.map { n in
            let u = dir.appendingPathComponent(n)
            var d: ObjCBool = false
            fm.fileExists(atPath: u.path, isDirectory: &d)
            return Entry(name: n, url: u, isDir: d.boolValue)
        }
    }

    private static func readOrder(_ all: [Entry]) -> [String] {
        guard let f = all.first(where: { $0.name == ORDER }),
              let data = try? Data(contentsOf: f.url) else { return [] }
        return String(decoding: data, as: UTF8.self)
            .components(separatedBy: .newlines)
            .filter { !$0.trimmed.isEmpty }
    }

    private static func ordered(_ all: [Entry]) -> [Entry] {
        let files = all.filter {
            let l = $0.name.lowercased()
            return !$0.name.hasPrefix(".") && ($0.isDir || l.hasSuffix(".url") || l.hasSuffix(".txt"))
        }
        var byName = [String: Entry]()
        for f in files { byName[f.name.precomposedStringWithCanonicalMapping] = f }
        var seen = Set<String>()
        var ord = [Entry]()
        for n in readOrder(all) {
            let k = n.precomposedStringWithCanonicalMapping
            if !seen.contains(k), let e = byName[k] { ord.append(e); seen.insert(k) }
        }
        let rest = files
            .filter { !seen.contains($0.name.precomposedStringWithCanonicalMapping) }
            .sorted { a, b in
                if a.isDir != b.isDir { return a.isDir }
                return a.name.lowercased() < b.name.lowercased()
            }
        let all2 = ord + rest
        let pins = readPinned(all)
        if pins.isEmpty { return all2 }
        var marked = all2.map { e -> Entry in
            var c = e
            c.pinned = pins.contains(e.name.precomposedStringWithCanonicalMapping)
            return c
        }
        // Sabitlenenler başta (kendi aralarında mevcut sıra korunur)
        marked = marked.filter { $0.pinned } + marked.filter { !$0.pinned }
        return marked
    }

    private static func readPinned(_ all: [Entry]) -> Set<String> {
        guard let f = all.first(where: { $0.name == PINNED }),
              let data = try? Data(contentsOf: f.url) else { return [] }
        return Set(String(decoding: data, as: UTF8.self)
            .components(separatedBy: .newlines)
            .filter { !$0.trimmed.isEmpty }
            .map { $0.precomposedStringWithCanonicalMapping })
    }

    private static func writePinned(_ dir: URL, _ pins: Set<String>) {
        let f = dir.appendingPathComponent(PINNED)
        if pins.isEmpty { try? FileManager.default.removeItem(at: f); return }
        try? Data(pins.sorted().joined(separator: "\n").utf8).write(to: f, options: .atomic)
    }

    /// Öğeleri sabitler / sabitlemeyi kaldırır.
    static func setPinned(_ dir: URL, _ names: [String], _ pinned: Bool) {
        lock.lock(); defer { lock.unlock() }
        var pins = readPinned(children(dir))
        for n in names {
            let k = n.precomposedStringWithCanonicalMapping
            if pinned { pins.insert(k) } else { pins.remove(k) }
        }
        writePinned(dir, pins)
    }

    /// Ad değişince / öğe taşınınca / silinince eski ada ait sabitlemeyi yeni ada aktarır (new nil ise kaldırır).
    private static func renamePin(_ dir: URL, _ old: String, _ new: String?) {
        var pins = readPinned(children(dir))
        let k = old.precomposedStringWithCanonicalMapping
        guard pins.contains(k) else { return }
        pins.remove(k)
        if let n = new { pins.insert(n.precomposedStringWithCanonicalMapping) }
        writePinned(dir, pins)
    }

    static func list(_ dir: URL) -> [Entry] {
        lock.lock(); defer { lock.unlock() }
        return ordered(children(dir))
    }

    private static func saveOrderIn(_ dir: URL, _ names: [String]) {
        let data = Data(names.joined(separator: "\n").utf8)
        try? data.write(to: dir.appendingPathComponent(ORDER), options: .atomic)   // yarım yazılmış sıra dosyası kalmasın
    }

    static func saveOrder(_ dir: URL, _ names: [String]) {
        lock.lock(); defer { lock.unlock() }
        saveOrderIn(dir, names)
    }

    // MARK: - Yazma

    private static func write(_ dir: URL, _ base: String, _ data: Data, limitChars: Int = 220, ext: String = ".url") -> Bool {
        lock.lock(); defer { lock.unlock() }
        let all = children(dir)
        let taken = Set(all.map { norm($0.name) })
        let b = clean(base, limitChars)
        var name = b + ext
        var i = 2
        while taken.contains(norm(name)) { name = "\(b) (\(i))\(ext)"; i += 1 }
        do { try data.write(to: dir.appendingPathComponent(name), options: .atomic) } catch { return false }
        // Yeni eklenen öğe listenin EN ÜSTÜNE konur; mevcut sıra altta aynen devam eder.
        saveOrderIn(dir, [name] + ordered(all).map { $0.name })
        return true
    }

    static func addLink(_ dir: URL, title: String, url: String) -> Bool {
        write(dir, title, Data("[InternetShortcut]\r\nURL=\(url)\r\n".utf8))
    }

    /// Düz metni de kaydeder (URL olmayan kayıt).
    static func addNote(_ dir: URL, text: String) -> Bool {
        var title = text.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression).trimmed
        if title.isEmpty { title = "not" }
        return write(otherDir(for: dir), title, noteBytes(text))
    }

    /// Kısa metin (not) kaydı: .url içinde TEXT= satırı.
    static func noteBytes(_ text: String) -> Data {
        let enc = text.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\r", with: "")
            .replacingOccurrences(of: "\n", with: "\\n")
        return Data("[InternetShortcut]\r\nTEXT=\(enc)\r\n".utf8)
    }

    /// Metni, uzunluk sınırı olmadan düz .txt dosyası olarak kaydeder; ad metnin ilk 100 karakteridir.
    static func addTextFile(_ dir: URL, text: String) -> Bool {
        var title = text.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression).trimmed
        if title.isEmpty { title = "not" }
        return write(otherDir(for: dir), title, Data(text.utf8), limitChars: 100, ext: ".txt")
    }

    static func readPlain(_ url: URL) -> String? {
        guard let d = try? Data(contentsOf: url) else { return nil }
        var s = String(decoding: d, as: UTF8.self)
        if s.hasPrefix("\u{FEFF}") { s.removeFirst() }
        return s
    }

    /// Mevcut .txt dosyasının içeriğini baştan yazar (dosya adı değişmez).
    static func writePlain(_ url: URL, _ text: String) -> Bool {
        lock.lock(); defer { lock.unlock() }
        do { try Data(text.utf8).write(to: url, options: .atomic); return true } catch { return false }
    }

    /// Metindeki ilk linki bulur; sondaki noktalama işaretlerini atar.
    static func extractUrl(_ text: String) -> String? {
        guard let r = text.range(of: "https?://\\S+", options: [.regularExpression, .caseInsensitive]) else { return nil }
        var u = String(text[r])
        while let last = u.last {
            let strip = ".,;:!?\"'>]}".contains(last) || (last == ")" && !u.contains("("))
            if strip { u.removeLast() } else { break }
        }
        return u.count > 8 ? u : nil
    }

    /// Linklerin varsayılan klasörü: kök klasörün altındaki "Url" (yoksa oluşturulur).
    static let linkFolderName = "Url"

    // MARK: - Veri yeri U / D (⋮ menüsünden seçilir; yalnızca bu Mac'te tutulur)

    private static let placeUKey = "dataPlaceU"   // linklerin (URL) varsayılan kayıt klasörü
    private static let placeDKey = "dataPlaceD"   // diğer kayıtların (kısa metin .url ve .txt) varsayılan kayıt klasörü

    /// Kayıtlı veri yeri yazılabilir bir klasörse onu, değilse (ayarlanmamış / silinmiş) nil döndürür.
    private static func place(_ key: String) -> URL? {
        guard let p = UserDefaults.standard.string(forKey: key), usable(p) else { return nil }
        return URL(fileURLWithPath: p, isDirectory: true)
    }
    static var placeU: URL? { place(placeUKey) }
    static var placeD: URL? { place(placeDKey) }
    static func setPlaceU(_ u: URL) { UserDefaults.standard.set(u.standardizedFileURL.path, forKey: placeUKey) }
    static func setPlaceD(_ u: URL) { UserDefaults.standard.set(u.standardizedFileURL.path, forKey: placeDKey) }

    /// Bir klasör yeniden adlandırılınca / taşınınca / silinince veri yeri yollarını günceller (new nil ise kaldırır).
    private static func remapPlaces(old: URL, new: URL?) {
        let o = old.standardizedFileURL.path
        let d = UserDefaults.standard
        for k in [placeUKey, placeDKey] {
            guard let p = d.string(forKey: k) else { continue }
            if p == o || p.hasPrefix(o + "/") {
                if let n = new { d.set(n.standardizedFileURL.path + String(p.dropFirst(o.count)), forKey: k) }
                else { d.removeObject(forKey: k) }
            }
        }
    }

    private static func isRoot(_ dir: URL) -> Bool {
        guard let r = root else { return false }
        return dir.standardizedFileURL.path == r.standardizedFileURL.path
    }

    /// Link dışındaki kayıtlar (kısa metin, .txt): `dir` kök klasörse Veri yeri D'ye gider; başka bir klasörün içindeyse orada kalır.
    static func otherDir(for dir: URL) -> URL {
        guard isRoot(dir), let d = placeD else { return dir }
        return d
    }

    /// Linkler: `dir` kök klasörse Veri yeri U'ya (ayarlı değilse Url klasörüne) gider; başka bir klasörün içindeyse aynen döndürür.
    static func linkDir(for dir: URL) -> URL {
        guard let r = root, dir.standardizedFileURL.path == r.standardizedFileURL.path else { return dir }
        if let u = placeU { return u }
        lock.lock(); defer { lock.unlock() }
        let all = children(r)
        if let e = all.first(where: { $0.isDir && norm($0.name) == norm(linkFolderName) }) { return e.url }
        return addFolder(r, linkFolderName) ?? dir
    }

    /// Link veya metni uygun şekilde kaydeder. Ağ erişimi yaptığı için arka planda çağrılmalı.
    static func addFromText(_ dir: URL, _ text: String, _ subject: String? = nil) async -> Bool {
        let t = text.trimmed
        if t.isEmpty { return false }
        guard let url = extractUrl(t) else { return addNote(dir, text: t) }
        // Linkler varsayılan olarak Link/Url klasörüne kaydedilir (kullanıcı başka bir alt klasörün içindeyse orada kalır).
        let dir = linkDir(for: dir)
        // Paylaşan tarayıcı sayfanın başlığını veriyorsa (Safari/Chrome) o kullanılır; yoksa sayfa indirilip <title> alınır.
        var title: String? = nil
        if let s = subject?.components(separatedBy: .newlines).first(where: { !$0.trimmed.isEmpty })?.trimmed,
           extractUrl(s) == nil { title = s }
        if title == nil { title = await PageTitle.fetch(url) }
        if title == nil {
            title = t.replacingOccurrences(of: url, with: "")
                .components(separatedBy: .newlines).first(where: { !$0.trimmed.isEmpty })?.trimmed
        }
        if title == nil { title = makeURL(url)?.host }
        return addLink(dir, title: title ?? "link", url: url)
    }

    // MARK: - Taşı / yeniden adlandır / sil

    static func moveEntry(_ e: Entry, to target: URL) -> Bool {
        lock.lock(); defer { lock.unlock() }
        if e.isDir && (target.path == e.url.path || target.path.hasPrefix(e.url.path + "/")) { return false }
        let all = children(target)
        let taken = Set(all.map { norm($0.name) })
        let base = e.isDir ? e.name : e.title
        let ext = e.isDir ? "" : e.ext
        var name = base + ext
        var i = 2
        while taken.contains(norm(name)) { name = "\(base) (\(i))\(ext)"; i += 1 }
        do { try FileManager.default.moveItem(at: e.url, to: target.appendingPathComponent(name)) } catch { return false }
        renamePin(e.url.deletingLastPathComponent(), e.name, nil)
        if e.isDir { remapPlaces(old: e.url, new: target.appendingPathComponent(name)) }
        saveOrderIn(target, ordered(all).map { $0.name } + [name])
        return true
    }

    @discardableResult
    static func addFolder(_ dir: URL, _ name: String) -> URL? {
        lock.lock(); defer { lock.unlock() }
        let all = children(dir)
        let base = clean(name)
        var n = base
        var i = 2
        while all.contains(where: { norm($0.name) == norm(n) }) { n = "\(base) (\(i))"; i += 1 }
        let u = dir.appendingPathComponent(n, isDirectory: true)
        do { try FileManager.default.createDirectory(at: u, withIntermediateDirectories: false) } catch { return nil }
        saveOrderIn(dir, [n] + ordered(all).map { $0.name })     // yeni klasör de en üstte
        return u
    }

    /// Link (.url/.txt) veya klasör adını değiştirir; sıralamayı korur.
    static func rename(_ dir: URL, _ e: Entry, _ title: String) -> Bool {
        lock.lock(); defer { lock.unlock() }
        let base = clean(title, 220)
        let newName = e.isDir ? base : base + e.ext
        // Kısa metin (not) ise: kopyalanan içerik de yeni ada uysun diye dosya içeriği güncellenir
        let isNote = !e.isDir && !e.isTxt && readLink(e.url).1 != nil
        if newName == e.name {
            if isNote { try? noteBytes(title.trimmed).write(to: e.url, options: .atomic) }
            return true
        }
        let all = children(dir)
        if all.contains(where: { norm($0.name) == norm(newName) && $0.url != e.url }) { return false }
        let order = ordered(all).map { $0.name }
        let dest = dir.appendingPathComponent(newName)
        let fm = FileManager.default
        do {
            if norm(newName) == norm(e.name) {
                // Yalnızca büyük/küçük harf değişiyor: büyük/küçük harfe duyarsız disklerde geçici ad gerekir.
                let tmp = dir.appendingPathComponent(".tmp-" + UUID().uuidString)
                try fm.moveItem(at: e.url, to: tmp)
                try fm.moveItem(at: tmp, to: dest)
            } else {
                try fm.moveItem(at: e.url, to: dest)
            }
        } catch { return false }
        if isNote { try? noteBytes(title.trimmed).write(to: dest, options: .atomic) }
        saveOrderIn(dir, order.map { $0 == e.name ? newName : $0 })
        renamePin(dir, e.name, newName)
        if e.isDir { remapPlaces(old: e.url, new: dest) }
        return true
    }

    /// Düzenlenen .url kaydı ad sınırını (220) aşınca çağrılır: kayıt aynı yerde .txt dosyasına dönüşür
    /// (içerik = text; sıralamadaki yeri korunur, eski .url silinir). Dosya adı metnin ilk 100 karakteridir.
    static func convertToTxt(_ dir: URL, _ e: Entry, _ text: String) -> Bool {
        lock.lock(); defer { lock.unlock() }
        let all = children(dir)
        let order = ordered(all).map { $0.name }
        let taken = Set(all.filter { $0.url != e.url }.map { norm($0.name) })
        var t = text.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression).trimmed
        if t.isEmpty { t = "not" }
        let b = clean(t, 100)
        var name = b + ".txt"
        var i = 2
        while taken.contains(norm(name)) { name = "\(b) (\(i)).txt"; i += 1 }
        do { try Data(text.utf8).write(to: dir.appendingPathComponent(name), options: .atomic) } catch { return false }
        try? FileManager.default.removeItem(at: e.url)
        saveOrderIn(dir, order.map { $0 == e.name ? name : $0 })
        renamePin(dir, e.name, name)
        return true
    }

    /// Ana dizindeki gizli .onemsiz klasörü ("Sil" öğeleri buraya taşır).
    static var onemsizDir: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".onemsiz", isDirectory: true)
    }

    /// "Sil": öğeyi silmez, ana dizindeki gizli .onemsiz klasörüne taşır (klasörse içeriğiyle; aynı ad varsa ad_1, ad_2…).
    @discardableResult
    static func trash(_ url: URL) -> Bool {
        lock.lock(); defer { lock.unlock() }
        let fm = FileManager.default
        let d = onemsizDir
        do { try fm.createDirectory(at: d, withIntermediateDirectories: true) } catch { return false }
        let name = url.lastPathComponent
        let base = (name as NSString).deletingPathExtension
        let ext = (name as NSString).pathExtension
        var t = d.appendingPathComponent(name)
        var n = 1
        while fm.fileExists(atPath: t.path) {
            t = d.appendingPathComponent(ext.isEmpty ? "\(base)_\(n)" : "\(base)_\(n).\(ext)")
            n += 1
        }
        do { try fm.moveItem(at: url, to: t) } catch { return false }
        renamePin(url.deletingLastPathComponent(), name, nil)
        remapPlaces(old: url, new: nil)
        return true
    }

    /// Eski davranış: Çöp Kutusu'na gönderir (artık kullanılmıyor).
    static func delete(_ url: URL) {
        lock.lock(); defer { lock.unlock() }
        let fm = FileManager.default
        do { try fm.trashItem(at: url, resultingItemURL: nil) }
        catch { try? fm.removeItem(at: url) }
    }
}

import Foundation
import Network

/// Notlarım eşitleme (istemci): Hızlı Paylaş'ın (_qshare._tcp) ağdaki açık cihazlarıyla ~/Link içindeki
/// .url / .txt dosyaları ve klasörleri karşılaştırır (Android'deki NoteSync ile aynı protokol):
///  - karşı cihazda olmayan dosya gönderilir, bizde olmayan dosya alınır (eksikler tamamlanır),
///  - iki tarafta da olan aynı yoldaki dosyanın DEĞİŞTİRİLME ZAMANI yeni olanı eskisinin üzerine yazar.
/// Silinen dosyalar eşitlenmez (silinen, diğer cihazda varsa geri gelir).
/// Uç noktalar: GET /m (liste), GET /f (dosya), POST /d (klasör), POST /u + X-Sync (dosya yaz).
enum NoteSync {
    /// Dosya sistemlerinin zaman çözünürlüğü farkı için tolerans (ms): bundan yakın zamanlar "aynı" sayılır.
    private static let tol: Int64 = 2000
    private static let maxDepth = 24

    struct Item { let rel: String; let dir: Bool; let size: Int64; let mtime: Int64 }
    struct Peer { let name: String; let endpoint: NWEndpoint }
    struct SyncError: Error { let text: String }

    struct Outcome {
        var peers = 0, sent = 0, got = 0
        var errors: [String] = []
        var error: String?

        var message: String {
            if let e = error { return L("Eşitleme hatası: \(e)", "Sync error: \(e)") }
            if peers == 0 { return errors.first ?? L("Açık cihaz bulunamadı", "No open device found") }
            let base = L("Eşitlendi: \(peers) cihaz, \(sent) gönderildi, \(got) alındı", "Synced: \(peers) device(s), \(sent) sent, \(got) received")
            return errors.isEmpty ? base : base + "\n" + errors[0]
        }
    }

    // MARK: Ortak yardımcılar

    private static func isNoteName(_ n: String) -> Bool {
        let l = n.lowercased()
        return !l.hasSuffix(".part") && (l.hasSuffix(".url") || l.hasSuffix(".txt"))
    }

    private static func enc(_ s: String) -> String {
        s.addingPercentEncoding(withAllowedCharacters: CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-._~"))) ?? s
    }

    private static func dec(_ s: String) -> String {
        s.replacingOccurrences(of: "+", with: " ").removingPercentEncoding ?? s
    }

    private static func errText(_ e: Error) -> String { (e as? SyncError)?.text ?? e.localizedDescription }

    /// Karşı taraftan gelen göreli yolu Link klasörü içinde güvenli bir dosyaya çevirir; geçersizse nil.
    /// Her bölüm ayrı doğrulanır (".." ve kontrol karakterleri yok), sonuç Link dışına çıkamaz.
    static func resolve(_ rel: String, root: URL, dir: Bool = false) -> URL? {
        let segs = rel.components(separatedBy: "/")
        if segs.isEmpty || segs.count > maxDepth { return nil }
        let bad = CharacterSet(charactersIn: ":*?\"<>|\\")
        for sg in segs {
            if sg.isEmpty || sg == "." || sg == ".." || sg.utf8.count > 240 { return nil }
            if sg.unicodeScalars.contains(where: { $0.value < 32 || bad.contains($0) }) { return nil }
        }
        if !dir, let last = segs.last, !(isNoteName(last) || last == ".order.txt") { return nil }
        let f = segs.reduce(root) { $0.appendingPathComponent($1) }
        let bc = root.standardizedFileURL.resolvingSymlinksInPath().path
        let fc = f.standardizedFileURL.resolvingSymlinksInPath().path
        return fc.hasPrefix(bc + "/") ? f : nil
    }

    private static func ms(_ d: Date?) -> Int64 { Int64((d?.timeIntervalSince1970 ?? 0) * 1000) }

    /// Yerel not ağacı: göreli yol → öğe (yollar NFC; Android ile aynı yazım).
    static func local(root: URL) -> [String: Item] {
        var out = [String: Item]()
        let fm = FileManager.default
        func walk(_ d: URL, _ prefix: String, _ depth: Int) {
            if depth > maxDepth { return }
            guard let fs = try? fm.contentsOfDirectory(at: d, includingPropertiesForKeys: [.isDirectoryKey, .contentModificationDateKey, .fileSizeKey], options: []) else { return }
            for f in fs {
                let name = f.lastPathComponent.precomposedStringWithCanonicalMapping
                let v = try? f.resourceValues(forKeys: [.isDirectoryKey, .contentModificationDateKey, .fileSizeKey])
                let rel = prefix + name
                if v?.isDirectory == true {
                    if name.hasPrefix(".") { continue }
                    out[rel] = Item(rel: rel, dir: true, size: 0, mtime: 0)
                    walk(f, rel + "/", depth + 1)
                } else if isNoteName(name) {
                    out[rel] = Item(rel: rel, dir: false, size: Int64(v?.fileSize ?? 0), mtime: ms(v?.contentModificationDate))
                }
            }
        }
        walk(root, "", 0)
        return out
    }

    // MARK: Bağlantı (eşzamanlı, arka plan kuyruğunda çağrılır)

    private final class Conn {
        private let c: NWConnection
        private var buf = Data()

        init(_ ep: NWEndpoint) throws {
            c = NWConnection(to: ep, using: .tcp)
            let sem = DispatchSemaphore(value: 0)
            var ok = false
            c.stateUpdateHandler = { st in
                switch st {
                case .ready: ok = true; sem.signal()
                case .failed, .cancelled: sem.signal()
                default: break
                }
            }
            c.start(queue: DispatchQueue(label: "notesync.conn"))
            if sem.wait(timeout: .now() + 8) != .success || !ok {
                c.cancel()
                throw SyncError(text: L("bağlantı kurulamadı", "could not connect"))
            }
        }

        func close() { c.cancel() }

        func send(_ data: Data) throws {
            let sem = DispatchSemaphore(value: 0)
            var err: Error?
            c.send(content: data, completion: .contentProcessed { e in err = e; sem.signal() })
            if sem.wait(timeout: .now() + 30) != .success { throw SyncError(text: L("zaman aşımı", "timeout")) }
            if let e = err { throw e }
        }

        /// Ağdan biraz okuyup tampona ekler; bağlantı kapandıysa false.
        private func fill() throws -> Bool {
            let sem = DispatchSemaphore(value: 0)
            var got: Data?
            var err: Error?
            c.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { d, _, _, e in got = d; err = e; sem.signal() }
            if sem.wait(timeout: .now() + 30) != .success { throw SyncError(text: L("zaman aşımı", "timeout")) }
            if let d = got, !d.isEmpty { buf.append(d); return true }
            if let e = err { throw e }
            return false
        }

        func readHead() throws -> (status: Int, headers: [String: String]) {
            let sep = Data("\r\n\r\n".utf8)
            while buf.range(of: sep) == nil {
                if buf.count > 16384 { throw SyncError(text: L("geçersiz yanıt", "invalid response")) }
                if try !fill() { throw SyncError(text: L("bağlantı beklenmedik şekilde kapandı", "connection closed unexpectedly")) }
            }
            guard let r = buf.range(of: sep) else { throw SyncError(text: L("geçersiz yanıt", "invalid response")) }
            let head = String(decoding: buf[..<r.lowerBound], as: UTF8.self)
            buf = Data(buf[r.upperBound...])
            let lines = head.components(separatedBy: "\r\n")
            let parts = lines[0].split(separator: " ")
            let status = parts.count > 1 ? (Int(parts[1]) ?? 0) : 0
            var headers = [String: String]()
            for l in lines.dropFirst() {
                guard let i = l.firstIndex(of: ":") else { continue }
                headers[l[..<i].lowercased()] = l[l.index(after: i)...].trimmingCharacters(in: .whitespaces)
            }
            return (status, headers)
        }

        func readBody(_ len: Int, _ sink: (Data) throws -> Void) throws {
            var left = len
            if !buf.isEmpty && left > 0 {
                let n = min(buf.count, left)
                try sink(Data(buf.prefix(n)))
                buf = Data(buf.dropFirst(n))
                left -= n
            }
            while left > 0 {
                if try !fill() { throw SyncError(text: L("alma yarım kaldı", "incomplete")) }
                let n = min(buf.count, left)
                try sink(Data(buf.prefix(n)))
                buf = Data(buf.dropFirst(n))
                left -= n
            }
        }
    }

    // MARK: İstemci işlemleri

    private static func fetchManifest(_ p: Peer) throws -> [String: Item] {
        let c = try Conn(p.endpoint)
        defer { c.close() }
        try c.send(Data("GET /m HTTP/1.1\r\nHost: qs\r\nConnection: close\r\n\r\n".utf8))
        let h = try c.readHead()
        guard h.status == 200 else { throw SyncError(text: "manifest \(h.status)") }
        let len = min(Int(h.headers["content-length"] ?? "") ?? 0, 8 << 20)
        var data = Data()
        try c.readBody(len) { data.append($0) }
        var out = [String: Item]()
        for ln in String(decoding: data, as: UTF8.self).split(separator: "\n") {
            let a = ln.components(separatedBy: "\t")
            guard a.count == 4 else { continue }
            let rel = dec(a[3])
            out[rel] = Item(rel: rel, dir: a[0] == "D", size: Int64(a[1]) ?? 0, mtime: Int64(a[2]) ?? 0)
        }
        return out
    }

    private static func pull(_ p: Peer, _ it: Item, root: URL) throws {
        guard let dest = resolve(it.rel, root: root) else { return }
        let fm = FileManager.default
        try fm.createDirectory(at: dest.deletingLastPathComponent(), withIntermediateDirectories: true)
        let c = try Conn(p.endpoint)
        defer { c.close() }
        try c.send(Data("GET /f HTTP/1.1\r\nHost: qs\r\nX-Name: \(enc(it.rel))\r\nConnection: close\r\n\r\n".utf8))
        let h = try c.readHead()
        guard h.status == 200 else { throw SyncError(text: "\(it.rel): \(h.status)") }
        let len = Int(h.headers["content-length"] ?? "") ?? 0
        let tmp = dest.deletingLastPathComponent().appendingPathComponent("\(dest.lastPathComponent).\(UUID().uuidString.prefix(8)).part")
        guard fm.createFile(atPath: tmp.path, contents: nil) else { throw SyncError(text: "\(it.rel): " + L("yazılamadı", "write failed")) }
        var ok = false
        defer { if !ok { try? fm.removeItem(at: tmp) } }
        let fh = try FileHandle(forWritingTo: tmp)
        do {
            try c.readBody(len) { try fh.write(contentsOf: $0) }
            try fh.close()
        } catch {
            try? fh.close()
            throw error
        }
        if let mt = Int64(h.headers["x-mtime"] ?? ""), mt > 0 {
            try? fm.setAttributes([.modificationDate: Date(timeIntervalSince1970: Double(mt) / 1000)], ofItemAtPath: tmp.path)
        }
        if fm.fileExists(atPath: dest.path) { try fm.removeItem(at: dest) }
        try fm.moveItem(at: tmp, to: dest)
        ok = true
    }

    private static func push(_ p: Peer, _ it: Item, root: URL) throws {
        guard let f = resolve(it.rel, root: root) else { return }
        let attrs = try FileManager.default.attributesOfItem(atPath: f.path)
        let len = (attrs[.size] as? NSNumber)?.int64Value ?? 0
        let mt = ms(attrs[.modificationDate] as? Date)
        let c = try Conn(p.endpoint)
        defer { c.close() }
        let head = "POST /u HTTP/1.1\r\nHost: qs\r\nX-Name: \(enc(it.rel))\r\nX-Sync: 1\r\nX-Mtime: \(mt)\r\nContent-Length: \(len)\r\nConnection: close\r\n\r\n"
        try c.send(Data(head.utf8))
        let fh = try FileHandle(forReadingFrom: f)
        defer { try? fh.close() }
        var sent: Int64 = 0
        while sent < len {
            guard let chunk = try fh.read(upToCount: Int(min(256 * 1024, len - sent))), !chunk.isEmpty else { break }
            try c.send(chunk)
            sent += Int64(chunk.count)
        }
        guard sent == len else { throw SyncError(text: "\(it.rel): " + L("dosya değişti", "file changed")) }
        let h = try c.readHead()
        guard h.status == 200 else { throw SyncError(text: "\(it.rel): " + L("karşı cihaz kabul etmedi", "refused")) }
    }

    private static func mkdirRemote(_ p: Peer, _ rel: String) throws {
        let c = try Conn(p.endpoint)
        defer { c.close() }
        try c.send(Data("POST /d HTTP/1.1\r\nHost: qs\r\nX-Name: \(enc(rel))\r\nContent-Length: 0\r\nConnection: close\r\n\r\n".utf8))
        let h = try c.readHead()
        guard h.status == 200 else { throw SyncError(text: "\(rel): mkdir") }
    }

    /// Tek cihazla eşitler; (gönderilen, alınan) sayısını döndürür. Dosya bazlı hatalar errs'e eklenir, diğer dosyalar sürer.
    private static func syncPeer(_ p: Peer, root: URL, errs: inout [String]) throws -> (Int, Int) {
        let remote = try fetchManifest(p)
        let loc = local(root: root)
        var sent = 0, got = 0
        let keys = Set(loc.keys).union(remote.keys).sorted { a, b in
            let ca = a.filter { $0 == "/" }.count, cb = b.filter { $0 == "/" }.count
            return ca != cb ? ca < cb : a < b       // üst klasörler önce
        }
        for k in keys {
            let l = loc[k], r = remote[k]
            do {
                if (l ?? r)?.dir == true {
                    if l == nil { if let d = resolve(k, root: root, dir: true) { try FileManager.default.createDirectory(at: d, withIntermediateDirectories: true) } }
                    else if r == nil { try mkdirRemote(p, k) }
                    continue
                }
                if let l = l, let r = r {
                    if l.mtime - r.mtime > tol { try push(p, l, root: root); sent += 1 }
                    else if r.mtime - l.mtime > tol { try pull(p, r, root: root); got += 1 }
                } else if let l = l {
                    try push(p, l, root: root); sent += 1
                } else if let r = r {
                    try pull(p, r, root: root); got += 1
                }
            } catch {
                errs.append("\(p.name): \(errText(error))")
            }
        }
        return (sent, got)
    }

    // MARK: Cihaz keşfi + çalıştırma

    private final class Found: @unchecked Sendable {
        private let l = NSLock()
        private var list = [Peer]()
        func set(_ p: [Peer]) { l.lock(); list = p; l.unlock() }
        func get() -> [Peer] { l.lock(); defer { l.unlock() }; return list }
    }

    /// Ağdaki açık cihazları bulur: ilk cihazdan sonra kısa süre daha beklenir, hiç bulunamazsa 4 sn'de vazgeçilir.
    private static func discover() -> [Peer] {
        let found = Found()
        let me = Host.current().localizedName ?? ""
        let b = NWBrowser(for: .bonjourWithTXTRecord(type: "_qshare._tcp", domain: nil), using: .tcp)
        b.browseResultsChangedHandler = { results, _ in
            var out = [Peer]()
            for r in results {
                guard case let .service(name, _, _, _) = r.endpoint else { continue }
                var title = name
                if case let .bonjour(txt) = r.metadata { title = txt.dictionary["n"] ?? name }
                if !me.isEmpty && title == me { continue }      // bu Mac'in kendisi
                out.append(Peer(name: title, endpoint: r.endpoint))
            }
            found.set(out)
        }
        b.start(queue: .global(qos: .userInitiated))
        defer { b.cancel() }
        let t0 = Date()
        var firstAt: Date?
        while true {
            let now = Date()
            if firstAt == nil, !found.get().isEmpty { firstAt = now }
            if let f = firstAt, now.timeIntervalSince(f) >= 0.8 { break }
            if firstAt == nil, now.timeIntervalSince(t0) >= 4 { break }
            Thread.sleep(forTimeInterval: 0.15)
        }
        return found.get()
    }

    /// Ağdaki tüm açık cihazlarla eşitler. Arka plan iş parçacığında çağrılmalı (ağ + disk).
    static func run() -> Outcome {
        var res = Outcome()
        guard let root = NotesStore.root else { res.error = L("Link klasörü yok", "no Link folder"); return res }
        for p in discover() {
            do {
                let (a, b) = try syncPeer(p, root: root, errs: &res.errors)
                res.peers += 1; res.sent += a; res.got += b
            } catch {
                res.errors.append("\(p.name): \(errText(error))")
            }
        }
        return res
    }
}

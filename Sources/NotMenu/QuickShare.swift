import Foundation
import Network
import UserNotifications

/// Android'deki Hızlı Paylaş ile aynı protokol:
///  - mDNS: `_qshare._tcp`, servis adı "QS"+kimlik[0..10], TXT: n=cihaz adı, i=kimlik
///  - Alma: düz TCP, `POST /u` + `X-Name` (URL kodlu ad) + `Content-Length`, yanıt `HTTP/1.1 200 OK`
/// Telefon/TV, aynı ağdaki açık Mac'i bulur ve dosyayı doğrudan gönderir.
struct QSDevice: Identifiable, Hashable {
    let id: String          // Bonjour servis adı
    let name: String        // TXT "n" (cihaz adı)
    let endpoint: NWEndpoint
}

final class QuickShare: ObservableObject {
    static let shared = QuickShare()
    @Published var running = false
    @Published var message = ""
    @Published var devices: [QSDevice] = []
    @Published var sendingTo = Set<String>()

    private var listener: NWListener?
    private var browser: NWBrowser?
    private var conns = Set<ConnHandler>()

    static var identity: String {
        if let i = UserDefaults.standard.string(forKey: "qsId") { return i }
        let i = UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
        UserDefaults.standard.set(i, forKey: "qsId"); return i
    }

    static var receiveDir: URL {
        let d = UserDefaults.standard.string(forKey: "recvDir").map { URL(fileURLWithPath: $0, isDirectory: true) }
            ?? FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }

    func start() {
        guard listener == nil else { return }
        guard let l = try? NWListener(using: .tcp) else { post("Paylaşım açılamadı"); return }
        let id = Self.identity
        let name = Host.current().localizedName ?? "Mac"
        l.service = NWListener.Service(name: "QS" + String(id.prefix(10)), type: "_qshare._tcp",
                                       txtRecord: NWTXTRecord(["n": name, "i": id]))
        l.newConnectionHandler = { [weak self] c in
            let h = ConnHandler(c, owner: self)
            DispatchQueue.main.async { self?.conns.insert(h) }
            h.start()
        }
        l.stateUpdateHandler = { [weak self] st in
            DispatchQueue.main.async {
                switch st {
                case .ready: self?.running = true
                case .failed, .cancelled: self?.running = false; self?.listener = nil
                default: break
                }
            }
        }
        l.start(queue: .global(qos: .userInitiated))
        listener = l
        UserDefaults.standard.set(true, forKey: "qsOn")
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert]) { _, _ in }
        startBrowsing()
    }

    func stop() {
        listener?.cancel(); listener = nil; running = false
        UserDefaults.standard.set(false, forKey: "qsOn")
        browser?.cancel(); browser = nil
        devices = []
    }

    // MARK: Açık cihazları bul (aynı ağda _qshare._tcp yayınlayanlar)
    private func startBrowsing() {
        browser?.cancel()
        let b = NWBrowser(for: .bonjourWithTXTRecord(type: "_qshare._tcp", domain: nil), using: .tcp)
        let myName = "QS" + String(Self.identity.prefix(10))
        b.browseResultsChangedHandler = { [weak self] results, _ in
            var out: [QSDevice] = []
            for r in results {
                guard case let .service(name, _, _, _) = r.endpoint else { continue }
                var title = name, id = ""
                if case let .bonjour(txt) = r.metadata {
                    title = txt.dictionary["n"] ?? name
                    id = txt.dictionary["i"] ?? ""
                }
                if name == myName || id == Self.identity { continue }   // kendimizi listeleme
                out.append(QSDevice(id: name, name: title, endpoint: r.endpoint))
            }
            out.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
            DispatchQueue.main.async { self?.devices = out }
        }
        b.start(queue: .global(qos: .userInitiated))
        browser = b
    }

    // MARK: Dosya gönder (alıcı tarafın beklediği: POST /u + X-Name + Content-Length)
    func send(_ files: [URL], to d: QSDevice) {
        guard !files.isEmpty else { return }
        DispatchQueue.main.async { self.sendingTo.insert(d.id) }
        DispatchQueue.global(qos: .userInitiated).async { [self] in
            var okCount = 0
            for f in files { if Self.sendOne(f, to: d.endpoint) { okCount += 1 } }
            DispatchQueue.main.async { self.sendingTo.remove(d.id) }
            if okCount == files.count {
                post(files.count == 1 ? "Gönderildi: \(files[0].lastPathComponent)" : "\(okCount) dosya gönderildi → \(d.name)")
            } else {
                post("Gönderilemedi (\(files.count - okCount) dosya) → \(d.name)")
            }
        }
    }

    private static func sendOne(_ url: URL, to endpoint: NWEndpoint) -> Bool {
        guard let size = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize,
              let fh = try? FileHandle(forReadingFrom: url) else { return false }
        defer { try? fh.close() }

        let conn = NWConnection(to: endpoint, using: .tcp)
        let q = DispatchQueue(label: "qs.tx")
        let readySem = DispatchSemaphore(value: 0)
        var isReady = false
        conn.stateUpdateHandler = { st in
            switch st {
            case .ready: isReady = true; readySem.signal()
            case .failed, .cancelled: readySem.signal()
            default: break
            }
        }
        conn.start(queue: q)
        defer { conn.cancel() }
        guard readySem.wait(timeout: .now() + 8) == .success, isReady else { return false }

        func push(_ data: Data) -> Bool {
            let sem = DispatchSemaphore(value: 0)
            var good = true
            conn.send(content: data, completion: .contentProcessed { err in if err != nil { good = false }; sem.signal() })
            sem.wait()
            return good
        }

        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-._~"))
        let encName = url.lastPathComponent.addingPercentEncoding(withAllowedCharacters: allowed) ?? "file"
        let head = "POST /u HTTP/1.1\r\nHost: qs\r\nX-Name: \(encName)\r\nContent-Type: application/octet-stream\r\nContent-Length: \(size)\r\nConnection: close\r\n\r\n"
        guard push(Data(head.utf8)) else { return false }
        while true {
            guard let chunk = try? fh.read(upToCount: 1 << 20), !chunk.isEmpty else { break }
            guard push(chunk) else { return false }
        }

        let rsem = DispatchSemaphore(value: 0)
        var reply = ""
        conn.receive(minimumIncompleteLength: 1, maximumLength: 512) { data, _, _, _ in
            if let d = data { reply = String(decoding: d, as: UTF8.self) }
            rsem.signal()
        }
        guard rsem.wait(timeout: .now() + 30) == .success else { return false }
        return reply.hasPrefix("HTTP/1.1 200") || reply.hasPrefix("HTTP/1.0 200")
    }

    func toggle() { running ? stop() : start() }

    fileprivate func remove(_ h: ConnHandler) { DispatchQueue.main.async { self.conns.remove(h) } }

    fileprivate func received(_ name: String) { post("Dosya alındı: \(name)") }

    func post(_ s: String) {
        DispatchQueue.main.async { self.message = s }
        let c = UNMutableNotificationContent(); c.title = "Hızlı Paylaş"; c.body = s
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: UUID().uuidString, content: c, trigger: nil))
    }
}

private final class ConnHandler: Hashable {
    static func == (a: ConnHandler, b: ConnHandler) -> Bool { a === b }
    func hash(into h: inout Hasher) { h.combine(ObjectIdentifier(self)) }

    private let c: NWConnection
    private let q = DispatchQueue(label: "qs.rx")
    private weak var owner: QuickShare?
    private var buf = Data()
    private var headerDone = false, finished = false, werr = false
    private var name = "file"
    private var left: Int64 = 0
    private var fh: FileHandle?
    private var part: URL?

    init(_ c: NWConnection, owner: QuickShare?) { self.c = c; self.owner = owner }

    func start() { c.start(queue: q); receive() }

    private func receive() {
        c.receive(minimumIncompleteLength: 1, maximumLength: 1 << 20) { [self] data, _, done, err in
            if finished { return }
            if let d = data, !d.isEmpty { headerDone ? write(d) : header(d) }
            if finished { return }
            if err != nil || done { fail(); return }
            receive()
        }
    }

    private func header(_ d: Data) {
        buf.append(d)
        guard let r = buf.range(of: Data("\r\n\r\n".utf8)) else {
            if buf.count > 16384 { reply("400 Bad Request") }
            return
        }
        let head = String(decoding: buf[..<r.lowerBound], as: UTF8.self)
        let rest = Data(buf[r.upperBound...])
        let lines = head.components(separatedBy: "\r\n")
        let first = lines[0].split(separator: " ").map(String.init)
        let method = first.first ?? "", target = first.count > 1 ? first[1] : ""
        var len: Int64 = -1
        for l in lines.dropFirst() {
            guard let i = l.firstIndex(of: ":") else { continue }
            let k = l[..<i].lowercased(), v = l[l.index(after: i)...].trimmingCharacters(in: .whitespaces)
            if k == "content-length" { len = Int64(v) ?? -1 }
            else if k == "x-name" { name = v.replacingOccurrences(of: "+", with: " ").removingPercentEncoding ?? v }
        }
        // Notlarım eşitleme uç noktaları (/m, /f, /d) bu sürümde yok; yalnızca dosya alma (/u) desteklenir.
        guard method == "POST", target == "/u", len >= 0 else { reply(target == "/u" ? "400 Bad Request" : "500 Error"); return }

        name = Self.cleanName(name)
        let p = QuickShare.receiveDir.appendingPathComponent("\(name).\(UUID().uuidString.prefix(8)).part")
        guard FileManager.default.createFile(atPath: p.path, contents: nil), let h = try? FileHandle(forWritingTo: p) else {
            reply("500 Error"); return
        }
        part = p; fh = h; left = len; headerDone = true; buf = Data()
        if left == 0 { complete() } else if !rest.isEmpty { write(rest) }
    }

    private func write(_ d: Data) {
        let n = Int(min(Int64(d.count), left))
        if n > 0 { do { try fh?.write(contentsOf: d.prefix(n)) } catch { werr = true } }
        left -= Int64(n)
        if left == 0 { complete() }
    }

    private func complete() {
        try? fh?.close(); fh = nil
        var ok = !werr
        if ok, let p = part {
            let dest = Self.unique(QuickShare.receiveDir, name)
            do { try FileManager.default.moveItem(at: p, to: dest); name = dest.lastPathComponent } catch { ok = false }
        }
        if !ok, let p = part { try? FileManager.default.removeItem(at: p) }
        if ok { owner?.received(name) } else { owner?.post("Alma yarım kaldı") }
        reply(ok ? "200 OK" : "500 Error")
    }

    private func fail() {
        finished = true
        try? fh?.close()
        if let p = part { try? FileManager.default.removeItem(at: p) }
        c.cancel(); owner?.remove(self)
    }

    private func reply(_ st: String) {
        finished = true
        let r = "HTTP/1.1 \(st)\r\nContent-Length: 0\r\nConnection: close\r\n\r\n"
        c.send(content: Data(r.utf8), completion: .contentProcessed { [self] _ in c.cancel(); owner?.remove(self) })
    }

    // Android ile aynı temizleme: yol parçaları atılır, \u0000-\u001f : * ? " < > | → _, baştaki noktalar, en çok 120 karakter
    private static func cleanName(_ s: String) -> String {
        var n = s.components(separatedBy: "/").last ?? s
        n = n.components(separatedBy: "\\").last ?? n
        n = String(n.unicodeScalars.map { ($0.value < 32 || ":*?\"<>|".unicodeScalars.contains($0)) ? "_" : Character($0) })
        n = String(n.drop(while: { $0 == "." }).prefix(120))
        return n.isEmpty ? "file" : n
    }

    /// Aynı adlı dosya varsa üzerine yazmak yerine "ad (2).uzantı" olarak kaydeder.
    private static func unique(_ dir: URL, _ name: String) -> URL {
        let fm = FileManager.default
        var u = dir.appendingPathComponent(name), i = 2
        let ext = (name as NSString).pathExtension, base = (name as NSString).deletingPathExtension
        while fm.fileExists(atPath: u.path) {
            u = dir.appendingPathComponent(ext.isEmpty ? "\(base) (\(i))" : "\(base) (\(i)).\(ext)"); i += 1
        }
        return u
    }
}

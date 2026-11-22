import Foundation
import CPlanCore

/// Hızlı Paylaş'ın Rust çekirdeğine (rust/plan_core/src/share) köprüsü: alma sunucusu, dosya gönderme, Link eşitleme.
/// Bonjour yayını/keşfi (`_qshare._tcp`) Swift'te kalır; Rust'a yalnızca `ip:port` verilir.
enum RustShare {
    /// Rust'tan dönen hata/özet metinleri cihaz diliyle gelsin.
    static func setLanguage() { plan_qs_set_lang(!Lang.isTurkish) }

    // MARK: Paketleme yardımcıları (little-endian)

    private static func appendStr(_ d: inout Data, _ s: String) {
        let u = Array(s.utf8)
        var n = UInt32(truncatingIfNeeded: u.count).littleEndian
        withUnsafeBytes(of: &n) { d.append(contentsOf: $0) }
        d.append(contentsOf: u)
    }

    private static func take(_ p: UnsafeMutablePointer<UInt8>?, _ n: Int) -> [UInt8]? {
        guard let p else { return nil }
        defer { plan_free(p, n) }
        return Array(UnsafeBufferPointer(start: p, count: n))
    }

    private struct Reader {
        let b: [UInt8]
        var i = 0
        init(_ b: [UInt8]) { self.b = b }
        mutating func u8() -> UInt8? { guard i < b.count else { return nil }; defer { i += 1 }; return b[i] }
        mutating func u32() -> Int? {
            guard i + 4 <= b.count else { return nil }
            defer { i += 4 }
            return Int(b[i]) | Int(b[i + 1]) << 8 | Int(b[i + 2]) << 16 | Int(b[i + 3]) << 24
        }
        mutating func str() -> String? {
            guard let n = u32(), i + n <= b.count else { return nil }
            defer { i += n }
            return String(decoding: b[i..<(i + n)], as: UTF8.self)
        }
    }

    // MARK: Alma sunucusu

    enum Event {
        case receiving(String)
        case received(String, folder: URL)
        case failed(String)
        case notesChanged
    }

    private final class Box {
        let on: (Event) -> Void
        init(_ on: @escaping (Event) -> Void) { self.on = on }
    }

    /// Dinleyen alma sunucusu (POST /u, GET /m, GET /f, DELETE /x, POST /d). `stop()` ya da `deinit` ile kapanır.
    final class Server {
        private var handle: UnsafeMutableRawPointer?
        let port: UInt16

        /// `onEvent` Rust iş parçacıklarından çağrılır. `linkRoot` nil ise eşitleme uç noktaları kapalıdır.
        init?(recvDir: URL, linkRoot: URL?, onEvent: @escaping (Event) -> Void) {
            // Bağlantı iş parçacıkları sunucu kapandıktan sonra da kısa süre geri çağrı yapabilir:
            // kutu bilerek serbest bırakılmaz (başlatma başına birkaç bayt).
            let box = Unmanaged.passRetained(Box(onEvent))
            let ctx = box.toOpaque()
            let rd = Array(recvDir.path.utf8)
            let lr = Array((linkRoot?.path ?? "").utf8)
            var p: UInt16 = 0
            let h: UnsafeMutableRawPointer? = rd.withUnsafeBufferPointer { r in
                lr.withUnsafeBufferPointer { l in
                    plan_qs_server_start(r.baseAddress, r.count, l.baseAddress, l.count, 0,
                                         { c, kind, t, tn, q, qn in
                        guard let c else { return }
                        let b = Unmanaged<Box>.fromOpaque(c).takeUnretainedValue()
                        func s(_ x: UnsafePointer<UInt8>?, _ n: Int) -> String {
                            guard let x, n > 0 else { return "" }
                            return String(decoding: UnsafeBufferPointer(start: x, count: n), as: UTF8.self)
                        }
                        switch kind {
                        case 1: b.on(.receiving(s(t, tn)))
                        case 2: b.on(.received(s(t, tn), folder: URL(fileURLWithPath: s(q, qn), isDirectory: true)))
                        case 3: b.on(.failed(s(t, tn)))
                        default: b.on(.notesChanged)
                        }
                    }, ctx, &p)
                }
            }
            guard let h else { return nil }
            handle = h
            port = p
        }

        func stop() {
            if let h = handle { plan_qs_server_stop(h); handle = nil }
        }

        deinit { stop() }
    }

    // MARK: Gönderme

    /// Dosyaları `addr` (`ip:port`) adresine gönderir; klasörler zip'lenir. Engelleyicidir (arka plan kuyruğunda çağır).
    /// Dönüş: başarıyla giden dosya sayısı.
    static func send(_ files: [URL], toAddress addr: String) -> Int {
        var blob = Data()
        for f in files { appendStr(&blob, f.path) }
        let a = Array(addr.utf8)
        let n = a.withUnsafeBufferPointer { ap in
            blob.withUnsafeBytes { bp in
                plan_qs_send(ap.baseAddress, ap.count, bp.bindMemory(to: UInt8.self).baseAddress, bp.count, nil, nil)
            }
        }
        return Int(max(n, 0))
    }

    // MARK: Eşitleme

    struct SyncResult {
        let ok: Bool
        let sent: Int, got: Int, deleted: Int, peers: Int
        let message: String
        let errors: [String]
    }

    /// mode: 0 iki cihazda aynı, 1 bu cihaza göre, 2 karşıdakine göre. Engelleyicidir.
    static func sync(mode: Int, linkRoot: URL?, peers: [(name: String, addr: String)]) -> SyncResult? {
        var blob = Data()
        for p in peers { appendStr(&blob, p.name); appendStr(&blob, p.addr) }
        let lr = Array((linkRoot?.path ?? "").utf8)
        var n = 0
        let p = lr.withUnsafeBufferPointer { l in
            blob.withUnsafeBytes { bp in
                plan_qs_sync(UInt32(mode), l.baseAddress, l.count, bp.bindMemory(to: UInt8.self).baseAddress, bp.count, &n)
            }
        }
        guard let bytes = take(p, n) else { return nil }
        var r = Reader(bytes)
        guard let ok = r.u8(), let sent = r.u32(), let got = r.u32(), let del = r.u32(), let cnt = r.u32(),
              let msg = r.str(), let ne = r.u32() else { return nil }
        var errs = [String]()
        for _ in 0..<ne { if let e = r.str() { errs.append(e) } }
        return SyncResult(ok: ok == 1, sent: sent, got: got, deleted: del, peers: cnt, message: msg, errors: errs)
    }

    // MARK: Güvenli yol

    /// Karşı taraftan gelen göreli yolu Link içinde güvenli bir dosyaya çevirir; geçersizse nil.
    static func resolve(_ rel: String, root: URL, dir: Bool = false) -> URL? {
        let r = Array(rel.utf8), b = Array(root.path.utf8)
        var n = 0
        let p = r.withUnsafeBufferPointer { rp in
            b.withUnsafeBufferPointer { bp in
                plan_qs_resolve(rp.baseAddress, rp.count, bp.baseAddress, bp.count, dir, &n)
            }
        }
        guard let out = take(p, n) else { return nil }
        return URL(fileURLWithPath: String(decoding: out, as: UTF8.self))
    }
}

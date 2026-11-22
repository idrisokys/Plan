import Foundation
import CoreGraphics
import CPlanCore

/// Rust çekirdeğine (rust/plan_core) köprü. CPU yoğun işler orada çalışır; arayüz kodu değişmez.
enum RustCore {
    // MARK: - Paketleme yardımcıları (little-endian)

    private static func appendU32(_ d: inout Data, _ v: Int) {
        var x = UInt32(truncatingIfNeeded: v).littleEndian
        withUnsafeBytes(of: &x) { d.append(contentsOf: $0) }
    }

    private static func appendStr(_ d: inout Data, _ s: String) {
        let u = Array(s.utf8)
        appendU32(&d, u.count)
        d.append(contentsOf: u)
    }

    /// Rust'ın döndürdüğü tamponu kopyalayıp serbest bırakır.
    private static func take(_ p: UnsafeMutablePointer<UInt8>?, _ n: Int) -> [UInt8]? {
        guard let p else { return nil }
        defer { plan_free(p, n) }
        return Array(UnsafeBufferPointer(start: p, count: n))
    }

    private struct Reader {
        let b: [UInt8]
        var i = 0
        init(_ b: [UInt8]) { self.b = b }
        var atEnd: Bool { i >= b.count }
        mutating func u8() -> UInt8? { guard i < b.count else { return nil }; defer { i += 1 }; return b[i] }
        mutating func u32() -> Int? {
            guard i + 4 <= b.count else { return nil }
            defer { i += 4 }
            return Int(b[i]) | Int(b[i + 1]) << 8 | Int(b[i + 2]) << 16 | Int(b[i + 3]) << 24
        }
        mutating func u64() -> UInt64? {
            guard i + 8 <= b.count else { return nil }
            defer { i += 8 }
            var v: UInt64 = 0
            for k in 0..<8 { v |= UInt64(b[i + k]) << UInt64(8 * k) }
            return v
        }
        mutating func str() -> String? {
            guard let n = u32(), i + n <= b.count else { return nil }
            defer { i += n }
            return String(decoding: b[i..<(i + n)], as: UTF8.self)
        }
    }

    // MARK: - Metin sadeleştirme

    /// Büyük/küçük harf, Türkçe i/ı/İ/I ve aksan farkını yok sayan biçim.
    static func fold(_ s: String) -> String {
        let u = Array(s.utf8)
        var n = 0
        let p = u.withUnsafeBufferPointer { plan_fold($0.baseAddress, $0.count, &n) }
        guard let out = take(p, n) else { return s.lowercased() }
        return String(decoding: out, as: UTF8.self)
    }

    // MARK: - Arama

    struct TreeHit {
        let entry: Entry
        let path: [Entry]
        let detail: String
        let isNote: Bool
        let titleMatch: Bool
    }

    /// `alive` Rust iş parçacıklarından çağrılır; iş parçacığı güvenli olmalıdır.
    private final class AliveBox {
        let f: () -> Bool
        init(_ f: @escaping () -> Bool) { self.f = f }
    }

    private static func readEntry(_ r: inout Reader) -> Entry? {
        guard let name = r.str(), let path = r.str(), let isDir = r.u8(), let pinned = r.u8() else { return nil }
        var e = Entry(name: name, url: URL(fileURLWithPath: path), isDir: isDir == 1)
        e.pinned = pinned == 1
        return e
    }

    /// Klasör dolaşımı (sıra/sabitleme kurallarıyla), dosya okuma, eşleştirme, özet ve sıralama Rust'ta yapılır.
    /// Sonuç: başlıkta geçenler önce, en çok 500 isabet.
    static func searchTree(root: URL, query: String, alive: @escaping () -> Bool) -> [TreeHit] {
        let box = AliveBox(alive)
        let rootBytes = Array(root.path.utf8)
        let q = Array(query.utf8)
        var n = 0
        let p: UnsafeMutablePointer<UInt8>? = withExtendedLifetime(box) {
            let ctx = Unmanaged.passUnretained(box).toOpaque()
            return rootBytes.withUnsafeBufferPointer { rp in
                q.withUnsafeBufferPointer { qp in
                    plan_search_tree(rp.baseAddress, rp.count, qp.baseAddress, qp.count,
                                     { c in Unmanaged<AliveBox>.fromOpaque(c!).takeUnretainedValue().f() },
                                     ctx, &n)
                }
            }
        }
        guard let bytes = take(p, n) else { return [] }
        var r = Reader(bytes)
        guard let count = r.u32() else { return [] }
        var out = [TreeHit]()
        out.reserveCapacity(count)
        for _ in 0..<count {
            guard let flags = r.u8(), let detail = r.str(), let entry = readEntry(&r), let na = r.u32() else { break }
            var path = [Entry]()
            for _ in 0..<na {
                guard let a = readEntry(&r) else { return out }
                path.append(a)
            }
            out.append(TreeHit(entry: entry, path: path, detail: detail,
                               isNote: flags & 1 != 0, titleMatch: flags & 2 != 0))
        }
        return out
    }
}

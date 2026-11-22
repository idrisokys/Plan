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

    struct RawHit {
        let index: Int
        let isNote: Bool
        let titleMatch: Bool
        let detail: String
    }

    /// `alive` Rust iş parçacıklarından çağrılır; iş parçacığı güvenli olmalıdır.
    private final class AliveBox {
        let f: () -> Bool
        init(_ f: @escaping () -> Bool) { self.f = f }
    }

    /// kinds: 0 = .url, 1 = .txt, 2 = klasör. Sonuç Rust'ta sıralanır (başlıkta geçenler önce, en çok 500).
    static func search(items: [(kind: UInt8, path: String, title: String)], query: String,
                       alive: @escaping () -> Bool) -> [RawHit] {
        var buf = Data()
        for it in items {
            buf.append(it.kind)
            appendStr(&buf, it.path)
            appendStr(&buf, it.title)
        }
        let box = AliveBox(alive)
        let q = Array(query.utf8)
        var n = 0
        let p: UnsafeMutablePointer<UInt8>? = withExtendedLifetime(box) {
            let ctx = Unmanaged.passUnretained(box).toOpaque()
            return buf.withUnsafeBytes { raw in
                q.withUnsafeBufferPointer { qp in
                    plan_search(raw.bindMemory(to: UInt8.self).baseAddress, raw.count,
                                qp.baseAddress, qp.count,
                                { c in Unmanaged<AliveBox>.fromOpaque(c!).takeUnretainedValue().f() },
                                ctx, &n)
                }
            }
        }
        guard let bytes = take(p, n) else { return [] }
        var r = Reader(bytes)
        guard let count = r.u32() else { return [] }
        var out = [RawHit]()
        out.reserveCapacity(count)
        for _ in 0..<count {
            guard let idx = r.u32(), let flags = r.u8(), let detail = r.str() else { break }
            out.append(RawHit(index: idx, isNote: flags & 1 != 0, titleMatch: flags & 2 != 0, detail: detail))
        }
        return out
    }

    // MARK: - Dosya analizi (hash + metadata)

    struct FileInfo {
        let ok: Bool
        let size: UInt64
        let modified: Date
        let sha256: String
    }

    /// Dosyaları paralel okuyup SHA-256 ve metadata çıkarır; sonuç girdi sırasındadır.
    static func analyze(_ urls: [URL]) -> [FileInfo] {
        var buf = Data()
        for u in urls { appendStr(&buf, u.path) }
        var n = 0
        let p = buf.withUnsafeBytes { plan_analyze_files($0.bindMemory(to: UInt8.self).baseAddress, $0.count, &n) }
        guard let bytes = take(p, n) else { return [] }
        var r = Reader(bytes)
        var out = [FileInfo]()
        while !r.atEnd {
            guard let ok = r.u8(), let size = r.u64(), let mt = r.u64() else { break }
            var hex = ""
            for _ in 0..<32 { hex += String(format: "%02x", r.u8() ?? 0) }
            out.append(FileInfo(ok: ok == 1, size: size,
                                modified: Date(timeIntervalSince1970: TimeInterval(Int64(bitPattern: mt))),
                                sha256: hex))
        }
        return out
    }

    // MARK: - Dizin tarama

    struct ScanItem {
        let url: URL
        let isDir: Bool
        let size: UInt64
        let modified: Date
    }

    /// Dizin ağacını paralel tarar (symlink izlenmez); sonuç yola göre sıralıdır.
    static func scan(_ root: URL, includeHidden: Bool = false) -> [ScanItem] {
        let u = Array(root.path.utf8)
        var n = 0
        let p = u.withUnsafeBufferPointer { plan_scan($0.baseAddress, $0.count, includeHidden, &n) }
        guard let bytes = take(p, n) else { return [] }
        var r = Reader(bytes)
        var out = [ScanItem]()
        while !r.atEnd {
            guard let kind = r.u8(), let size = r.u64(), let mt = r.u64(), let path = r.str() else { break }
            out.append(ScanItem(url: URL(fileURLWithPath: path), isDir: kind == 1, size: size,
                                modified: Date(timeIntervalSince1970: TimeInterval(Int64(bitPattern: mt)))))
        }
        return out
    }

    // MARK: - Küçük resim

    /// Çözülmüş bir görüntüden, en uzun kenarı `maxSide` olan küçük resim üretir (büyütme yok).
    /// Piksel işi Rust'ta yapılır; çözme/kodlama çağıranın (ImageIO) işidir.
    static func thumbnail(_ image: CGImage, maxSide: Int) -> CGImage? {
        let w = image.width, h = image.height
        guard w > 0, h > 0, maxSide > 0 else { return nil }
        let space = CGColorSpaceCreateDeviceRGB()
        let info = CGImageAlphaInfo.premultipliedLast.rawValue
        var src = [UInt8](repeating: 0, count: w * h * 4)
        let drawn = src.withUnsafeMutableBytes { raw -> Bool in
            guard let ctx = CGContext(data: raw.baseAddress, width: w, height: h, bitsPerComponent: 8,
                                      bytesPerRow: w * 4, space: space, bitmapInfo: info) else { return false }
            ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
            return true
        }
        guard drawn else { return nil }

        var ow: UInt32 = 0, oh: UInt32 = 0, n = 0
        let p = src.withUnsafeBufferPointer {
            plan_thumbnail($0.baseAddress, UInt32(w), UInt32(h), UInt32(maxSide), &ow, &oh, &n)
        }
        guard var out = take(p, n), ow > 0, oh > 0 else { return nil }
        return out.withUnsafeMutableBytes { raw -> CGImage? in
            CGContext(data: raw.baseAddress, width: Int(ow), height: Int(oh), bitsPerComponent: 8,
                      bytesPerRow: Int(ow) * 4, space: space, bitmapInfo: info)?.makeImage()
        }
    }
}

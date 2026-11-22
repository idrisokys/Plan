import Foundation

extension NotesStore {
    // MARK: - Arama

    /// Büyük/küçük harf, Türkçe i/ı/İ/I ve aksan (ş→s, ğ→g, é→e...) farkını yok sayar.
    /// Hesap Rust çekirdeğinde yapılır (rust/plan_core/src/fold.rs).
    static func fold(_ s: String) -> String { RustCore.fold(s) }

    /// Tüm klasörlerde; klasör adı, başlık, link adresi ve not metninde arar. Yazılan her kelime bulunmalıdır.
    /// Klasör dolaşımı (sıra ve sabitleme kurallarıyla) burada; dosya okuma, eşleştirme ve özet çıkarma
    /// paralel olarak Rust'ta yapılır.
    static func search(root: URL, query: String, alive: @escaping () -> Bool) -> [Hit] {
        if fold(query).components(separatedBy: .whitespacesAndNewlines).allSatisfy({ $0.isEmpty }) { return [] }

        var files = [(Entry, [Entry])]()
        func walk(_ dir: URL, _ path: [Entry]) {
            for e in list(dir) {
                if !alive() { return }
                if e.isDir { files.append((e, path)); walk(e.url, path + [e]) } else { files.append((e, path)) }
            }
        }
        walk(root, [])
        let snapshot = files

        let items = snapshot.map { (e, _) in
            (kind: UInt8(e.isDir ? 2 : (e.isTxt ? 1 : 0)), path: e.url.path, title: e.title)
        }
        // Sıralama (başlıkta geçenler önce) ve 500 sonuç sınırı Rust tarafında uygulanır.
        return RustCore.search(items: items, query: query, alive: alive).compactMap { h in
            guard h.index < snapshot.count else { return nil }
            let (e, path) = snapshot[h.index]
            return Hit(entry: e, path: path, detail: h.detail, isNote: h.isNote, titleMatch: h.titleMatch)
        }
    }
}

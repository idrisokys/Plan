import Foundation

extension NotesStore {
    // MARK: - Arama

    /// Büyük/küçük harf, Türkçe i/ı/İ/I ve aksan (ş→s, ğ→g, é→e...) farkını yok sayar.
    /// Hesap Rust çekirdeğinde yapılır (rust/plan_core/src/fold.rs).
    static func fold(_ s: String) -> String { RustCore.fold(s) }

    /// Tüm klasörlerde; klasör adı, başlık, link adresi ve not metninde arar. Yazılan her kelime bulunmalıdır.
    /// Klasör dolaşımı (.order.txt / .pinned.txt sırası dahil), dosya okuma, eşleştirme, özet çıkarma ve
    /// sıralama tamamen Rust'ta yapılır (rust/plan_core/src/tree.rs, search.rs).
    static func search(root: URL, query: String, alive: @escaping () -> Bool) -> [Hit] {
        RustCore.searchTree(root: root, query: query, alive: alive).map {
            Hit(entry: $0.entry, path: $0.path, detail: $0.detail, isNote: $0.isNote, titleMatch: $0.titleMatch)
        }
    }
}

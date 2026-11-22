import Foundation

/// Notlarım eşitlemesinin istemcisi, manifesto ve yol güvenliği artık Rust'ta:
/// rust/plan_core/src/share/sync.rs (çağrı: `QuickShare.sync` → `RustShare.sync`).
/// Burada yalnızca Swift tarafının (ve testlerin) kullandığı ince köprü kalır.
enum NoteSync {
    /// Karşı taraftan gelen göreli yolu Link klasörü içinde güvenli bir dosyaya çevirir; geçersizse nil.
    static func resolve(_ rel: String, root: URL, dir: Bool = false) -> URL? {
        RustShare.resolve(rel, root: root, dir: dir)
    }
}

//! Plan çekirdeği: Swift tarafından C ABI ile çağrılan, bağımlılıksız (yalnızca std) Rust kodu.
//!
//! * `fold`   – Türkçe/aksan duyarsız metin sadeleştirme
//! * `search` – not/link dosyalarında paralel arama
//! * `share`  – Hızlı Paylaş: alma sunucusu, dosya/klasör gönderme, Notlarım eşitlemesi (`qshare_core::share`, Android'le ORTAK)
//! * `unicode`– NFC/NFD (`qshare_core::unicode`, Android'le ORTAK)
//! * `ffi`    – C ABI (`ffi_share`: paylaşım/eşitleme köprüsü)

pub mod ffi;
pub mod ffi_share;
pub mod fold;
pub mod search;
pub mod tree;

// Paylaşım/eşitleme ve Unicode, Android'le paylaşılan `qshare_core` crate'inden gelir; yollar (`crate::share`,
// `crate::unicode`) eskisi gibi çalışsın diye yeniden dışa aktarılır.
pub use qshare_core::share;
pub use qshare_core::unicode;

/// Paralel işler için iş parçacığı sayısı.
pub(crate) fn workers() -> usize {
    std::thread::available_parallelism().map(|n| n.get()).unwrap_or(4).clamp(1, 16)
}

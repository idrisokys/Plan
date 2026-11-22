//! Plan çekirdeği: Swift tarafından C ABI ile çağrılan, bağımlılıksız (yalnızca std) Rust kodu.
//!
//! * `fold`   – Türkçe/aksan duyarsız metin sadeleştirme
//! * `search` – not/link dosyalarında paralel arama
//! * `scan`   – dizin ağacını paralel tarama
//! * `hash`   – SHA-256 ve dosya metadata'sı
//! * `image`  – RGBA küçük resim (alan ortalamalı küçültme)
//! * `share`  – Hızlı Paylaş: alma sunucusu, dosya/klasör gönderme, Notlarım eşitlemesi
//! * `ffi`    – C ABI (`ffi_share`: paylaşım/eşitleme)

pub mod ffi;
pub mod ffi_share;
pub mod fold;
pub mod hash;
pub mod image;
pub mod scan;
pub mod search;
pub mod share;
pub mod tree;
pub mod unicode;
mod unicode_tables;

/// Paralel işler için iş parçacığı sayısı.
pub(crate) fn workers() -> usize {
    std::thread::available_parallelism().map(|n| n.get()).unwrap_or(4).clamp(1, 16)
}

//! Plan çekirdeği: Swift tarafından C ABI ile çağrılan, bağımlılıksız (yalnızca std) Rust kodu.
//!
//! * `fold`   – Türkçe/aksan duyarsız metin sadeleştirme
//! * `search` – not/link dosyalarında paralel arama
//! * `scan`   – dizin ağacını paralel tarama
//! * `hash`   – SHA-256 ve dosya metadata'sı
//! * `image`  – RGBA küçük resim (alan ortalamalı küçültme)
//! * `ffi`    – C ABI

pub mod ffi;
pub mod fold;
pub mod hash;
pub mod image;
pub mod scan;
pub mod search;

/// Paralel işler için iş parçacığı sayısı.
pub(crate) fn workers() -> usize {
    std::thread::available_parallelism().map(|n| n.get()).unwrap_or(4).clamp(1, 16)
}

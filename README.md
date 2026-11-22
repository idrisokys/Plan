# Plan — Rust yeniden yazımı

macOS menü çubuğu uygulaması **Plan / Notlarım**'ın (SwiftUI + AppKit) Rust karşılığı.
Mantığın tamamı **yalnızca standart kütüphaneyle** yazılmış bir çekirdek kütüphanede; üstünde bir CLI ve
(ayrı, dış bağımlılıklı) bir egui arayüzü var.

```
plan-core/   Çekirdek (std-only): depolama, arama, eşitleme, Hızlı Paylaş sunucu/istemci, ayarlar
plan-cli/    `plan` komut satırı (aynı çekirdek)           → cargo build -p plan-cli
plan-gui/    egui + tray-icon + mdns-sd arayüzü            → cargo build --manifest-path plan-gui/Cargo.toml
chrome-extension/   Değişmedi (plan://add?t=…&s=… adresini kullanır)
```

## Durum

| Parça | Durum |
|---|---|
| plan-core | Derlendi, **39 test geçiyor** (Swift testlerinin portu + eşitleme/sunucu entegrasyon testleri) |
| plan-cli | Derlendi, elle denendi |
| plan-gui | **Henüz derlenmedi** — yazıldığı ortamda crates.io erişimi yoktu. eframe/egui 0.29, tray-icon 0.19, mdns-sd 0.11 API'sine göre yazıldı; ilk derlemede küçük düzeltmeler gerekebilir |

## Swift → Rust eşlemesi

| Swift | Rust |
|---|---|
| `NotesStore` (+Naming/Reading/Submit) | `store.rs`, `text.rs` |
| `NotesStore+Search`, `NotesModel+Txt` (arama) | `search.rs` |
| `PageTitle` | `pagetitle.rs` (indirme `curl` ile, ayrıştırma saf Rust) |
| `NoteSync` | `sync.rs` |
| `QuickShare` (sunucu + gönderme) | `quickshare.rs`, `net.rs` |
| `NotesModel+Reorder` | `reorder.rs` |
| `SearchEngine`, `plan://` şeması | `engines.rs` |
| `UserDefaults` | `config.rs` |
| SwiftUI görünümleri | `plan-gui/src/main.rs` |

Tel biçimi (HTTP uç noktaları, başlıklar, manifest satırları, mDNS adı/TXT alanları) birebir korunduğundan
Android uygulaması ve eski Swift sürümüyle birlikte çalışmalıdır.

## Bilinçli farklar

- **`.pinned.txt` artık eşitlenmez.** Swift kodunda yorum "yalnızca bu cihazda, eşitlenmez" diyor ama dosya
  `.txt` olduğu için manifeste giriyordu. Rust'ta hariç tutuldu.
- **Çöp Kutusu yerine `~/.onemsiz`.** Eşitlemeyle silinen öğeler de buraya taşınır (`trashItem` karşılığı std'de yok).
- **mDNS** çekirdekte değil GUI katmanında (`plan-gui/src/share.rs`, `mdns-sd`). CLI'da cihaz `--peer host:port` ile verilir.
- **NFC/NFD:** std'de Unicode normalizasyonu yok; Türkçe dahil Latin-1/Latin Genişletilmiş-A için küçük bir
  birleştirme tablosu var (`text.rs`). Daha geniş kapsam için `unicode-normalization` eklenebilir.
- Sayfa başlığı kodlamaları: UTF-8, Latin-1, ISO-8859-9/Windows-1254 (Türkçe) desteklenir; diğerleri UTF-8 sayılır.
- **macOS'a özgü olanlar taşınmadı:** Paylaş eklentisi (`ShareExtension`), Hizmetler menüsü, Rehber araması
  (`ContactSearch`), sağ alt köşe yüzen çubuk (`FloatingBar`). `plan://` şemasının işletim sistemine
  kaydı paketleme aşamasında yapılır (macOS `Info.plist` → `CFBundleURLTypes`; Linux `.desktop` MimeType).
- README'deki **U / D** (varsayılan kayıt klasörü) düğmeleri Swift kaynağında yer almıyordu; taşınmadı.

## Kullanım

```bash
cargo test --workspace
cargo run -p plan-cli -- add "https://example.com"
cargo run -p plan-cli -- search çay
cargo run -p plan-cli -- serve                      # Hızlı Paylaş sunucusu
cargo run -p plan-cli -- sync --peer 192.168.1.20:PORT --mode 0
```

Ortam değişkenleri: `PLAN_ROOT` (varsayılan `~/Link`), `PLAN_CONFIG_DIR`.

# Plan — macOS menü çubuğu: arama + not ekleme + paylaşım + Notlarım

Tek uygulama, iki parça:

1. **Menü çubuğu paneli** (Plan): arama, hızlı not/link ekleme, Hızlı Paylaş.
2. **Notlarım** : notlar ve linkler için tam pencere. Artık ayrı bir uygulama değil; panelin
   üstündeki **kalem** düğmesi bu uygulamanın içindeki Notlarım penceresini açar.

## Menü çubuğu paneli

- Üst çubuk: [Paylaş] [arama kutusu] [Kalem] [✕]. Kalem = **Notlarım penceresini** açar; Kapat (✕) uygulamayı tamamen kapatır. Paylaşım açılınca cihaz listesinin altında, "ON" simgesinin hizasında **Eşitle ⇄** düğmesi çıkar.
  Yazınca altında tek satır çıkar: (sorgu · eklenen motorlar · **temizle** · **Notlarımda ara** · +). Not sonuçları artık bu çubukta gösterilmez:
  **Notlarımda ara** (büyüteç) simgesine basınca Notlarım penceresi açılır ve sonuçlar pencerenin içinde listelenir.
- Arama motoru ekle: Arama satırındaki + → ad ve adres (`%s` aranan kelimenin yerine geçer) yaz, Ekle. Yeni motor ilk harfiyle
  en sağda görünür (sağ tık → Sil).
- Enter / "Ekle": link ise `~/Link/Url` klasörüne .url (Notlarım'da başka bir alt klasörün içindeyken orada kalır), kısa metin not, 116 karakterden uzunsa .txt olarak kaydeder.
- Herhangi bir uygulamada metin seç → Hizmetler → **"Notlarıma Kaydet"** (ilk seferde Sistem Ayarları > Klavye >
  Klavye Kısayolları > Hizmetler'den açman gerekebilir). Link ise sayfa başlığı otomatik alınır.
- **Küresel kısayollar** (herhangi bir uygulamada; ilk kullanımda Sistem Ayarları → Gizlilik ve Güvenlik → **Erişilebilirlik** izni gerekir):
  - **Notlarıma Kaydet — ⌃⌥N**: seçili metin ya da link Notlarım'a eklenir. Kayıt kuralı basit: **boşluk içeren veri link değildir**
    (kısa ise not, 116 karakterden uzunsa .txt); boşluksuz ve nokta ya da `/` içeren her veri **link** olarak kaydedilir
    (`://` yoksa başına `https://` eklenir); nokta/`/` içermeyen tek kelime not olur.
  - **Cihazlara Gönder — ⌃⌥S**: seçili **dosya/klasörler** olduğu gibi, seçili **metin/link** ise önce yukarıdaki aynı kayıt kuralıyla
    Notlarım'a kaydedilir, sonra kaydedilen dosya (.url / .txt) açık cihazlara gönderilir (Hızlı Paylaş paneli açılır; cihaza dokununca gider).
  - Seçili bir şey yoksa panodaki içerik kullanılır. Menü çubuğu simgesine **sağ tık → Kısayolları Değiştir…**: her kısayol için
    yeni tuş kombinasyonuna bas; **Sıfırla** varsayılana döner, **Kapat** o kısayolu devre dışı bırakır. Aynı menüde iki eylem de elle çalıştırılabilir.
    Kod: `Sources/Plan/QuickCapture.swift`, `ShortcutSettings.swift`.
- Hızlı Paylaş (Android'deki aynı protokol): soldaki anten düğmesi = ağdan dosya almayı aç/kapat (açıkken açık mavi "ON"). Paylaşım ekranındaki "Alındı" satırına tıklayınca dosyanın kaydedildiği klasör açılır. Paylaşım açıkken altta açık cihazlar listelenir; klasör simgesiyle dosya gönderirsin.

- Menü çubuğu simgesine sağ tık: **Notlarım**, **Kayıt yeri** (paylaşımla gelen dosyaların klasörünü seç), **Notlarım klasörü** (~/Link'i Finder'da aç), Çık.

## Notlarım penceresi

Pencere 400 × 600 açılır ve ekranın sağ kenarına tutturulur. Pencere varsayılan olarak her zaman en üstte durur. Uygulama Dock'ta görünmez, yalnızca menü çubuğunda yaşar.

- Notlar `~/Link` klasöründe; Android'deki Link klasörüyle aynı biçim. Klasörler, yeniden adlandırma, taşıma, sıralama.
- Görünüm ve düğmeler Android'deki Notlarım ekranıyla aynıdır (aynı Material simgeleri, koyu tema): üst çubukta başlık ile **klasör ekle**, **U**, **D**, **yenile**; satırda soldaki simge (klasör / link / metin dosyası) ve sağdaki ⋮.
- Satırın sağındaki ⋮: Sabitle / Taşı / Paylaş / Sil. Sabitlenen öğenin ⋮ simgesi koyu kırmızı olur. **U**: içinde bulunulan klasör linklerin varsayılan kayıt yeri olur (varsayılan: `~/Link/Url`). **D**: içinde bulunulan klasör diğer kayıtların (kısa metin ve .txt) varsayılan kayıt yeri olur (varsayılan: `~/Link`). İkisi de yalnızca kök klasörden eklerken geçerlidir; başka bir alt klasörün içindeyken kayıt orada kalır.
- Alt çubuk: çerçeveli ekleme alanı (Enter: kaydet), altında sayaç, **iç içe iki halka** (düzenleme / çoklu seçim / sıralama modu), ara, temizle, yapıştır. Düzenleme modunda satıra dokunarak seç; tek satır seçiliyse adı alttaki alanda düzenlenir (Kaydet), birden çoksa başa al / yukarı / aşağı / sona al düğmeleri çıkar. Sağ üstteki raptiye pencerenin her zaman üstte kalmasını açar/kapatır (varsayılan: kapalı; yalnızca Mac penceresine özgü).
- Paylaş: seçili notların dosyaları (.txt / .url) **Hızlı Paylaş** ile ağdaki açık cihaza gönderilir (Android'deki Paylaş penceresi); Hızlı Paylaş kapalıysa pencerede "Aç" düğmesi çıkar.
- Sil = silmez; `~/.onemsiz` gizli klasörüne taşır.
- Araç çubuğu: en solda başlık (Notlarım ya da klasör adı), sağında klasör ekle, U, D, yenile. Menü çubuğu paneli Notlarım açıkken pencereyi kapatmasın diye sola kayar.
- Kısa not satırına tıklamak metni panoya kopyalar; satıra uzun basmak kopyalar.
- `.txt` içinde arama (⌘F), eşleşmeler işaretli, ▲▼ ile gezinme.
- Eşitleme: Hızlı Paylaş açıkken cihaz listesinin üstündeki ⇄ simgesi; açılan pencerede cihazlar işaretlenir ve "Bu cihaza göre / Karşıdaki cihaza göre / İki cihazda aynı olsun" seçilir. `~/Link` içeriği (Android'deki `<ana dizin>/Link` ile) eşitlenir; silinenler kalıcı silinir (Çöp Kutusu yok); yalnızca "Bu cihaza göre" / "Karşıdaki cihaza göre" modları siler.
- Paylaş menüsü: Safari/Paylaş menüsünde **Notlarım** (uygulamanın içindeki `PlanShare.appex` eklentisi).
- Dosya paylaşımı: **Finder'da** dosya(lar)ı seç → Paylaş → **Notlarım**: açık cihazlar paneli açılır, cihaza dokununca dosyalar gönderilir (klasörler zip'lenir).
- Adres şeması: `plan://add?t=…` (Paylaş menüsü: **pencere açılmaz, uygulama öne gelmez**; kayıt arka planda biter, yalnızca kısa bildirim görünür) ve `plan://search?q=…` (Notlarım açılır, sonuçlar içinde gösterilir).
- Chrome eklentisi: `chrome-extension/` klasörü uygulamanın içine konur. Notlarım penceresi açıkken menü çubuğunda
  **Notlarım → Chrome Eklentisi Klasörünü Aç**. Kurulum: [chrome-extension/README.md](chrome-extension/README.md).

## Klasör yapısı

```
Package.swift            # Plan (uygulama) + PlanTests
Info.plist, version.env  # Tek Info.plist; sürüm numarası version.env'de
build.sh                 # Plan.app + Plan-macOS.zip (yalnızca Apple Silicon / arm64, ad-hoc imzalı)
scripts/build_share.sh   # Paylaş eklentisini derler (build.sh çağırır)
ShareExtension/          # Safari/Paylaş menüsü eklentisi (ayrı derlenir)
chrome-extension/        # Chrome eklentisi (uygulamanın içine konur)
Resources/               # Simgeler, tr/en ServicesMenu.strings
Sources/Plan/
├── App.swift            # Giriş: Notlarım penceresi (Window), menü çubuğu simgesi (StatusItemController), AppDelegate, Hizmetler
├── ContentView.swift    # Arama çubuğu (ekleme: NotesStore.submit; arama Notlarım penceresinde: NotesModel.externalSearch)
├── FloatingBar.swift    # Arama çubuğunu sağ alt köşeye sabitleyen yüzen panel; menü çubuğu simgesi göster/gizle
├── QuickCapture.swift   # Küresel kısayol + seçili metni yakalayıp Notlarım'a kaydetme
├── ShortcutSettings.swift # Kısayolları değiştirme penceresi (tuş yakalayıcı)
├── QuickShare.swift     # Hızlı Paylaş: Bonjour + durum; ağ/dosya işi Rust'ta (RustShare köprüsü)
└── Notlarim/            # Notlarım kodu (Models, Store, Services, ViewModel, Views, Support)
Tests/PlanTests/      # Notlarım depolama katmanı testleri
```

Notlarım kodundaki çakışan adlar yeniden adlandırıldı: `Store` → `NotesStore`, `Model` → `NotesModel`,
`ContentView` → `NotesContentView`.

## Rust çekirdeği (CPU yoğun işler)

Arayüze dokunulmadan, ağır işler `rust/plan_core` içinde (yalnızca std; crates.io bağımlılığı yok) çalışır ve Swift'e
C ABI ile bağlanır (`Sources/CPlanCore/include/plan_core.h` → `Support/RustCore.swift`):

| İş | Rust modülü | Swift'te kullanım |
|---|---|---|
| Arama motoru: klasör dolaşımı (`.order.txt`/`.pinned.txt` sırası), dosya okuma, eşleştirme, özet (paralel) | `tree.rs`, `search.rs`, `fold.rs`, `unicode.rs` (ortak: `qshare_core`) | `NotesStore.search` / `searchAsync` (panel ve Notlarım) |
| Türkçe/aksan duyarsız sadeleştirme | `fold.rs` | `NotesStore.fold` |
| Hızlı Paylaş alma sunucusu (`POST /u`, `GET /m`, `GET /f`, `DELETE /x`, `POST /d`), ad temizleme, `.part` → son ad | `qshare_core/src/share/server.rs`, `proto.rs` | `RustShare.Server` (`QuickShare.start`) |
| Dosya/klasör gönderme (klasör → `ditto` ile zip) | `qshare_core/src/share/client.rs` | `RustShare.send` (`QuickShare.send`) |
| Notlarım eşitleme: manifesto, 3 mod, güvenli yol çözümleme, paralel toplu aktarım | `qshare_core/src/share/sync.rs`, `proto.rs` | `RustShare.sync`, `NoteSync.resolve` |

**Hız tasarımı:** eşitleme önce tam bir plan çıkarır (gönder/al/klasör/sil); karşı cihaz `X-Plan-Proto: 2` bildirirse
dosyalar ~8 MiB / 512 dosyalık paketlere bölünüp en çok 4 paralel bağlantıda tek akışla taşınır (`POST /b`, `POST /g`;
`qshare_core/src/share/bundle.rs`), yerel tarama ile karşı manifesto indirme eşzamanlıdır. Android gibi eski cihazlarda dosya başına
isteklere (paralel) geri dönülür. Çoklu dosya gönderme de 4 bağlantıyla paralel gider.

Bonjour yayını/keşfi (`_qshare._tcp`: `NetService` + `NWBrowser`) ve arayüz Swift'te kalır; Swift bulunan cihazı `ip:port`
olarak Rust'a verir (`QuickShare.resolveAddress`). Rust tarafı da `cargo test` içinde 127.0.0.1 üzerinden uçtan uca denenir
(`qshare_core/tests/share_loopback.rs`).

### Android'le ortak çekirdek: `qshare_core/`

Paylaşım protokolü, alma sunucusu, dosya gönderme, klasör eşitleme ve Unicode (NFC/NFD) kodu **Android uygulaması
(MyLauncher) ile aynı** `qshare_core` crate'indedir; iki projede ayrı ayrı bakımı yapılan kopyalar kalmadı. Platforma
özgü farklar yapılandırmayla seçilir (`Config`, `Scope`); Plan varsayılanları kullanır (`Scope::link`: kalıcı silme,
gizli klasörler atlanır, `ad (2).uzantı`). `plan_qs_*` C ABI'si değişmedi, Swift tarafına dokunmak gerekmedi.

`qshare_core` iki repoda aynı dizinde (`qshare_core/`) durur. Tek kaynaktan yönetmek için git submodule yapılabilir:
`git submodule add <qshare_core-repo-adresi> qshare_core` (CI'da `actions/checkout` adımına `submodules: true` eklenir).

Testler: `cd qshare_core && cargo test` (protokol, eşitleme) ve `cd rust/plan_core && cargo test` (arama).
Unicode tabloları `qshare_core/tools/gen_unicode.py` ile üretilir.

## Derleme

```bash
./build.sh            # Xcode/Command Line Tools + Rust (rustup) gerekir; Rust'ı da kendisi derler
scripts/build_rust.sh # yalnızca Rust çekirdeği (swift build / swift test'ten ÖNCE bir kez)
swift test            # birim testleri
```

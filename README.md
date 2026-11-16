# Plan — macOS menü çubuğu: arama + not ekleme + paylaşım + Notlarım

Tek uygulama, iki parça:

1. **Menü çubuğu paneli** (Plan): arama, hızlı not/link ekleme, Hızlı Paylaş.
2. **Notlarım** : notlar ve linkler için tam pencere. Artık ayrı bir uygulama değil; panelin
   üstündeki **kalem** düğmesi bu uygulamanın içindeki Notlarım penceresini açar.

## Menü çubuğu paneli

- Üst çubuk: [Paylaş] [arama kutusu] [Kalem] [Kapat]. Kalem = **Notlarım penceresini** açar; Kapat (✕) = uygulamayı tamamen kapatır.
  Yazınca en çok 3 not + (sorgu · + · eklenen motorlar) satırı çıkar.
- Arama motoru ekle: Arama satırındaki + → ad ve adres (`%s` aranan kelimenin yerine geçer) yaz, Ekle. Yeni motor ilk harfiyle
  en sağda görünür (sağ tık → Sil).
- Enter / "Ekle": link ise .url, kısa metin not, 220 karakterden uzunsa .txt olarak kaydeder.
- Satırın üstüne gelince: Paylaş, Kopyala, Çöpe at. Linke tıkla = tarayıcıda açılır.
- Herhangi bir uygulamada metin seç → Hizmetler → **"Notlarıma Kaydet"** (ilk seferde Sistem Ayarları > Klavye >
  Klavye Kısayolları > Hizmetler'den açman gerekebilir). Link ise sayfa başlığı otomatik alınır.
- Hızlı Paylaş (Android'deki aynı protokol): soldaki anten düğmesi = ağdan dosya almayı aç/kapat (açıkken açık kırmızı "ON"),
  basılı tut = alınan dosyaların klasörü. Paylaşım ekranındaki "Alındı" satırına tıklayınca dosyanın kaydedildiği klasör açılır. Paylaşım açıkken altta açık cihazlar listelenir; klasör simgesiyle dosya gönderirsin.

- Menü çubuğu simgesine sağ tık: **Notlarım**, **Kayıt yeri** (paylaşımla gelen dosyaların klasörünü seç), **Notlarım klasörü** (~/Link'i Finder'da aç), Çık.

## Notlarım penceresi

Pencere 400 × 600 açılır ve ekranın sağ kenarına tutturulur. Açıkken uygulama Dock'ta ve menü çubuğunda (Notlarım menüsü,
⌘ kısayolları) görünür; pencere kapanınca yeniden yalnızca menü çubuğunda kalır.

- Notlar `~/Link` klasöründe; Android'deki Link klasörüyle aynı biçim. Klasörler, yeniden adlandırma, taşıma, sıralama.
- Satırın sağındaki ⋮: Düzenle / Taşı / Paylaş / Sil (birden çok seçiliyse hepsine); ⋮ basılı tutunca düzenleme modu.
- Sil = silmez; `~/.onemsiz` gizli klasörüne taşır. Araç çubuğundaki **çöp kutusu** (klasör ekle simgesinin yanında) onay sorup Link klasöründeki her şeyi macOS Çöp Kutusu'na gönderir.
- Araç çubuğu: başlığın hemen sağında klasör ekle, yenile, çöp kutusu, eşitle. Menü çubuğu paneli Notlarım açıkken pencereyi kapatmasın diye sola kayar.
- Kısa not satırına tıklamak metni panoya kopyalar; satıra uzun basmak kopyalar.
- `.txt` içinde arama (⌘F), eşleşmeler işaretli, ▲▼ ile gezinme.
- Eşitle (⇄, ⌘⇧S): aynı ağdaki açık Hızlı Paylaş cihazlarıyla `~/Link` içeriğini eşitler.
- Paylaş menüsü: Safari/Paylaş menüsünde **Notlarım** (uygulamanın içindeki `PlanShare.appex` eklentisi).
- Adres şeması: `plan://add?t=…` ve `plan://search?q=…`.
- Chrome eklentisi: `chrome-extension/` klasörü uygulamanın içine konur. Notlarım penceresi açıkken menü çubuğunda
  **Notlarım → Chrome Eklentisi Klasörünü Aç**. Kurulum: [chrome-extension/README.md](chrome-extension/README.md).

## Klasör yapısı

```
Package.swift            # Plan (uygulama) + PlanTests
Info.plist, version.env  # Tek Info.plist; sürüm numarası version.env'de
build.sh                 # Plan.app + Plan-macOS.zip (evrensel, ad-hoc imzalı)
scripts/build_share.sh   # Paylaş eklentisini derler (build.sh çağırır)
ShareExtension/          # Safari/Paylaş menüsü eklentisi (ayrı derlenir)
chrome-extension/        # Chrome eklentisi (uygulamanın içine konur)
Resources/               # Simgeler, tr/en ServicesMenu.strings
Sources/Plan/
├── App.swift            # Giriş: Notlarım penceresi (Window), menü çubuğu simgesi (StatusItemController), AppDelegate, Hizmetler
├── ContentView.swift    # Arama çubuğu (ekleme/arama Notlarım ile ortak: NotesStore.submit / searchAsync)
├── FloatingBar.swift    # Arama çubuğunu sağ alt köşeye sabitleyen yüzen panel; menü çubuğu simgesi göster/gizle
├── QuickShare.swift     # Hızlı Paylaş
└── Notlarim/            # Notlarım kodu (Models, Store, Services, ViewModel, Views, Support)
Tests/PlanTests/      # Notlarım depolama katmanı testleri
```

Notlarım kodundaki çakışan adlar yeniden adlandırıldı: `Store` → `NotesStore`, `Model` → `NotesModel`,
`ContentView` → `NotesContentView`.

## Derleme

```bash
./build.sh            # Xcode veya Command Line Tools gerekir
swift test            # birim testleri
```

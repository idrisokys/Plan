# NotMenu — macOS menü çubuğu: arama + not ekleme + paylaşım + Notlarım

Tek uygulama, iki parça:

1. **Menü çubuğu paneli** (NotMenu): arama, hızlı not/link ekleme, Hızlı Paylaş.
2. **Notlarım** (eski adıyla *Link Cepte*): notlar ve linkler için tam pencere. Artık ayrı bir uygulama değil; panelin
   üstündeki **kalem** düğmesi bu uygulamanın içindeki Notlarım penceresini açar.

## Menü çubuğu paneli

- Üst çubuk: [Paylaş] [arama kutusu] [Kalem] [Kapat]. Kalem = **Notlarım penceresini** açar; Kapat = uygulamadan çıkar.
  Yazınca en çok 3 not + (sorgu · + · eklenen motorlar) satırı çıkar.
- Arama motoru ekle: Arama satırındaki + → ad ve adres (`%s` aranan kelimenin yerine geçer) yaz, Ekle. Yeni motor ilk harfiyle
  en sağda görünür (sağ tık → Sil).
- Enter / "Ekle": link ise .url, kısa metin not, 220 karakterden uzunsa .txt olarak kaydeder.
- Satırın üstüne gelince: Paylaş, Kopyala, Çöpe at. Linke tıkla = tarayıcıda açılır.
- Herhangi bir uygulamada metin seç → Hizmetler → **"Notlarıma Kaydet"** (ilk seferde Sistem Ayarları > Klavye >
  Klavye Kısayolları > Hizmetler'den açman gerekebilir). Link ise sayfa başlığı otomatik alınır.
- Hızlı Paylaş (Android'deki aynı protokol): soldaki anten düğmesi = ağdan dosya almayı aç/kapat (açıkken açık kırmızı "ON"),
  basılı tut = alınan dosyaların klasörü. Paylaşım açıkken altta açık cihazlar listelenir; klasör simgesiyle dosya gönderirsin.

## Notlarım penceresi

Pencere 300 × 450 açılır ve ekranın sağ kenarına tutturulur. Açıkken uygulama Dock'ta ve menü çubuğunda (Notlarım menüsü,
⌘ kısayolları) görünür; pencere kapanınca yeniden yalnızca menü çubuğunda kalır.

- Notlar `~/Link` klasöründe; Android'deki Link klasörüyle aynı biçim. Klasörler, yeniden adlandırma, taşıma, sıralama.
- Satırın sağındaki ⋮: Taşı / Paylaş / Sil (birden çok seçiliyse hepsine); ⋮ basılı tutunca düzenleme modu.
- Sil = silmez; `~/.onemsiz` gizli klasörüne taşır. Bilgi (i) basılı tutulunca Link klasöründeki her şey oraya taşınır.
- Kısa not satırına tıklamak metni panoya kopyalar; satıra uzun basmak kopyalar.
- `.txt` içinde arama (⌘F), eşleşmeler işaretli, ▲▼ ile gezinme.
- Eşitle (⇄, ⌘⇧S): aynı ağdaki açık Hızlı Paylaş cihazlarıyla `~/Link` içeriğini eşitler.
- Paylaş menüsü: Safari/Paylaş menüsünde **Notlarım** (uygulamanın içindeki `NotlarimShare.appex` eklentisi).
- Adres şeması: `notlarim://add?t=…` ve `notlarim://search?q=…` (eski `linkcepte://` adresleri de çalışır).
- Chrome eklentisi: `chrome-extension/` klasörü uygulamanın içine konur. Notlarım penceresi açıkken menü çubuğunda
  **Notlarım → Chrome Eklentisi Klasörünü Aç**. Kurulum: [chrome-extension/README.md](chrome-extension/README.md).

## Klasör yapısı

```
Package.swift            # NotMenu (uygulama) + NotMenuTests
Info.plist, version.env  # Tek Info.plist; sürüm numarası version.env'de
build.sh                 # NotMenu.app + NotMenu-macOS.zip (evrensel, ad-hoc imzalı)
scripts/build_share.sh   # Paylaş eklentisini derler (build.sh çağırır)
ShareExtension/          # Safari/Paylaş menüsü eklentisi (ayrı derlenir)
chrome-extension/        # Chrome eklentisi (uygulamanın içine konur)
Resources/               # Simgeler, tr/en ServicesMenu.strings
Sources/NotMenu/
├── App.swift            # Giriş: MenuBarExtra + Notlarım penceresi (Window), AppDelegate, Hizmetler
├── ContentView.swift    # Menü çubuğu paneli
├── Store.swift          # Panelin hızlı ekleme/arama katmanı
├── QuickShare.swift     # Hızlı Paylaş
└── Notlarim/            # Eski Link Cepte kodu (Models, Store, Services, ViewModel, Views, Support)
Tests/NotMenuTests/      # Notlarım depolama katmanı testleri
```

Notlarım kodundaki çakışan adlar yeniden adlandırıldı: `Store` → `NotesStore`, `Model` → `NotesModel`,
`ContentView` → `NotesContentView`.

## Derleme

```bash
./build.sh            # Xcode veya Command Line Tools gerekir
swift test            # birim testleri
```

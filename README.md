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
- Enter / "Ekle": link ise `~/Link/Url` klasörüne .url (Notlarım'da başka bir alt klasörün içindeyken orada kalır), kısa metin not, 220 karakterden uzunsa .txt olarak kaydeder.
- Satırın üstüne gelince: Paylaş, Kopyala, Çöpe at. Linke tıkla = tarayıcıda açılır.
- Herhangi bir uygulamada metin seç → Hizmetler → **"Notlarıma Kaydet"** (ilk seferde Sistem Ayarları > Klavye >
  Klavye Kısayolları > Hizmetler'den açman gerekebilir). Link ise sayfa başlığı otomatik alınır.
- Hızlı Paylaş (Android'deki aynı protokol): soldaki anten düğmesi = ağdan dosya almayı aç/kapat (açıkken açık kırmızı "ON"),
  basılı tut = alınan dosyaların klasörü. Paylaşım ekranındaki "Alındı" satırına tıklayınca dosyanın kaydedildiği klasör açılır. Paylaşım açıkken altta açık cihazlar listelenir; klasör simgesiyle dosya gönderirsin.

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
- Eşitleme: Hızlı Paylaş açıkken cihaz listesinin üstündeki ⇄ simgesi; açılan pencerede cihazlar işaretlenir ve "Bu cihaza göre / Karşıdaki cihaza göre / İki cihazda aynı olsun" seçilir. `~/Link` içeriği (Android'deki `<ana dizin>/Link` ile) eşitlenir; silinenler Çöp Kutusu'na gider.
- Paylaş menüsü: Safari/Paylaş menüsünde **Notlarım** (uygulamanın içindeki `PlanShare.appex` eklentisi).
- Adres şeması: `plan://add?t=…` ve `plan://search?q=…`.
- Chrome eklentisi: `chrome-extension/` klasörü uygulamanın içine konur. Notlarım penceresi açıkken menü çubuğunda
  **Notlarım → Chrome Eklentisi Klasörünü Aç**. Kurulum: [chrome-extension/README.md](chrome-extension/README.md).

## Resim düzenleyici

Alt çubukta **✕**'in solundaki resim simgesi bir resim seçtirir ve düzenleyiciyi açar
(Android'deki Temel Düzenleyici'nin macOS karşılığı; kod `Sources/Plan/ImageEditor/`).

- **Filtre**: Siyah-Beyaz, Noir, Sepya, Klasik, Solgun, Chrome, Soğuk, Sıcak, Kontrast, Canlı, Parlak, Keskin, Vinyet, Negatif.
- **Kırp / Döndür**: serbest, 1:1, 4:3, 16:9, özel oran; sağa döndür, yatay / dikey çevir, yeniden boyutlandır.
- **Çiz**: renk, fırça boyutu, geri al (⌘Z tüm adımları geri alır).
- Kaydet menüsü: **Farklı kaydet…** (png / jpg / heic / tiff) ya da **Üzerine yaz** (onay sorar). Panoya kopyala düğmesi de var.


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
├── ImageEditor/         # Resim düzenleyici (model, arayüz, pencere)
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

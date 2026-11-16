# 🔗 Notlarım — Chrome eklentisi

**Türkçe** · [English](#english)

Chrome araç çubuğundaki simgeye tıklayınca açık sekmenin linki Mac'teki **Notlarım** uygulamasına kaydedilir.
Başlık otomatik alınır; link `~/Link` klasörüne `.url` dosyası olarak yazılır.

> Bu klasör **Notlarım Mac uygulamasının içinde** gelir. Notlarım penceresi açıkken üstteki menü çubuğunda **Notlarım → Chrome Eklentisi Klasörünü Aç**
> seçeneğine tıklayınca bu klasör Finder'da kendiliğinden açılır.

## Kurulum (yaklaşık 1 dakika)

**1. Uygulamayı hazırlayın**
Notlarım'ı (menü çubuğu uygulaması) **Uygulamalar** klasörüne taşıyıp bir kez açın. Linkler `~/Link` klasörüne kaydedilir.
(Bu adım, Chrome'un kullandığı `plan://` adresini sisteme tanıtır.)

**2. Eklenti klasörünü açın**
Menü çubuğundaki Notlarım simgesinde kalem düğmesiyle Notlarım penceresini açın; üstteki menü çubuğunda **Notlarım → Chrome Eklentisi Klasörünü Aç**'a tıklayın. Finder'da bu klasör açılır.

Klasör şu konumda durur:
`~/Library/Application Support/Notlarım/chrome-extension`

**3. Chrome'da Geliştirici modunu açın**
Chrome'un adres çubuğuna `chrome://extensions` yazıp Enter'a basın. Sağ üstteki **Geliştirici modu** düğmesini açın.

**4. Eklentiyi yükleyin**
**Paketlenmemiş öğe yükle** (Load unpacked) düğmesine basın. Açılan pencerede **⌘ ⇧ G** tuşlarına basıp
yukarıdaki yolu yapıştırın (`~/Library/Application Support/Notlarım/chrome-extension`), Enter'a basın ve
**Seç**'e tıklayın. Listede **Notlarım** görünür.

**5. Simgeyi araç çubuğuna sabitleyin**
Chrome araç çubuğundaki yapboz simgesine (Eklentiler) tıklayın, **Notlarım**'ın yanındaki iğneye basın.

## İlk kullanım

Bir sayfadayken Notlarım simgesine tıklayın. Chrome ilk seferde *"Notlarım'ı açmak istiyor musunuz?"* diye sorar.
**"Her zaman … bağlantıları ilişkili uygulamada açabilir"** kutusunu işaretleyip **Aç**'a basın; sonraki tıklamalarda sormaz.

Başarılı gönderimde simgede kısa süre **✓**, gönderilemeyen sayfalarda **!** görünür.

## Nasıl kullanılır

- **Araç çubuğu simgesi:** Açık sekmeyi gönderir.
- **Sağ tık menüsü:** Sayfaya sağ tıklayıp **Notlarım'a gönder**; bir linke sağ tıklayıp **Linki Notlarım'a gönder**.
- Yalnızca `http` ve `https` sayfaları gönderilir (`chrome://` gibi iç sayfalar gönderilemez, **!** görünür).
- Uygulama kapalıysa link gönderilirken uygulama menü çubuğunda açılır.

## Güncelleme

Notlarım uygulamasını yeni sürümle değiştirdikten sonra **Notlarım → Chrome Eklentisi Klasörünü Aç**'a bir kez daha tıklayın
(klasör güncellenir), sonra `chrome://extensions` sayfasında **Notlarım** kartındaki **↻ (yeniden yükle)** düğmesine basın.
Eklentiyi yeniden kurmanız gerekmez.

## Sorun giderme

| Sorun | Çözüm |
|---|---|
| Simgeye tıklayınca hiçbir şey olmuyor | Notlarım uygulamasını **Uygulamalar** klasöründen bir kez açın, sonra tekrar deneyin. |
| Chrome "Notlarım'ı açmak istiyor musunuz?" diye hep soruyor | Çıkan pencerede "her zaman izin ver" kutusunu işaretleyin. |
| `chrome://extensions` içinde "Paketlenmemiş öğe yükle" yok | Sağ üstten **Geliştirici modu**'nu açın. |
| Eklenti "Manifest dosyası eksik" diyor | Seçtiğiniz klasörün içinde `manifest.json` olmalı. Klasörü **içine girmeden** seçin (yol `…/chrome-extension` ile bitmeli). |

## Kaldırma

`chrome://extensions` sayfasında **Notlarım** kartındaki **Kaldır**'a basın. İsterseniz
`~/Library/Application Support/Notlarım/chrome-extension` klasörünü de silebilirsiniz (linkleriniz etkilenmez).

---

<a name="english"></a>

# 🔗 My Notes — Chrome extension (English)

Click the toolbar icon in Chrome to save the current tab's link to the **My Notes** Mac app. The page title is fetched
automatically and the link is written as a `.url` file into the `~/Link` folder.

> This folder is **bundled inside the My Notes Mac app**. Open the My Notes window, then choose **My Notes → Open Chrome Extension Folder** in the menu
> bar and this folder opens in Finder.

## Install (about 1 minute)

**1. Prepare the app**
Move My Notes to **Applications** and open it once (it runs in the menu bar). Links are saved to `~/Link`.
(This registers the `plan://` address Chrome uses.)

**2. Open the extension folder**
Open the My Notes window with the pencil button in the menu-bar popover, then in the top menu bar choose **My Notes → Open Chrome Extension Folder**. The folder opens in Finder. It lives at:
`~/Library/Application Support/My Notes/chrome-extension`

**3. Turn on Developer mode in Chrome**
Type `chrome://extensions` in the address bar and press Enter. Switch on **Developer mode** (top right).

**4. Load the extension**
Click **Load unpacked**. In the dialog press **⌘ ⇧ G**, paste the path above
(`~/Library/Application Support/My Notes/chrome-extension`), press Enter, then click **Select**.
**My Notes** now appears in the list.

**5. Pin the icon**
Click the puzzle-piece (Extensions) icon in Chrome's toolbar and pin **My Notes**.

## First use

Click the My Notes icon on any page. Chrome asks *"Open My Notes?"* the first time. Tick
**"Always allow … to open links of this type in the associated app"** and click **Open**; it won't ask again.

A **✓** appears briefly on the icon on success, and **!** if the page can't be sent.

## Usage

- **Toolbar icon:** sends the current tab.
- **Right-click menu:** right-click a page → **Send to My Notes**; right-click a link → **Send link to My Notes**.
- Only `http` and `https` pages can be sent (internal pages such as `chrome://` show **!**).
- If the app is closed it is launched with the link. 

## Updating

After replacing the My Notes app with a newer version, choose **My Notes → Open Chrome Extension Folder** once more (this refreshes the
folder), then press the **↻ (reload)** button on the **My Notes** card at `chrome://extensions`. No reinstall needed.

## Troubleshooting

| Problem | Fix |
|---|---|
| Nothing happens when I click the icon | Open My Notes once from the **Applications** folder, then try again. |
| Chrome keeps asking "Open My Notes?" | Tick the "always allow" box in the prompt. |
| No **Load unpacked** button | Turn on **Developer mode** at the top right of `chrome://extensions`. |
| "Manifest file is missing" | The selected folder must contain `manifest.json`. Select the folder itself (the path must end with `…/chrome-extension`). |

## Uninstall

Click **Remove** on the **My Notes** card at `chrome://extensions`. You may also delete
`~/Library/Application Support/My Notes/chrome-extension` (your links are not affected).

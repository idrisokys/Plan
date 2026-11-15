# NotMenu — macOS menü çubuğu: arama + not ekleme + paylaşım

- Üst çubuk (Android ile aynı): [Paylaş] [arama kutusu] [Ayarlar] [Notlarım]. Yazınca notlar + (sorgu · Yandex · Notlarım) satırı çıkar.
- Enter / "Ekle": link ise .url, kısa metin not, 220 karakterden uzunsa .txt olarak kaydeder (MyLauncher kuralı).
- Satırın üstüne gelince: Paylaş, Kopyala, Çöpe at. Linke tıkla = tarayıcıda açılır.
- Herhangi bir uygulamada metin seç → Hizmetler → "Notlarıma Kaydet" (ilk seferde Sistem Ayarları > Klavye > Klavye Kısayolları > Hizmetler'den açman gerekebilir).
- Notlar ~/Link klasöründe; Android'deki Link klasörüyle aynı biçim (iCloud Drive/Syncthing ile eşitlenebilir).
- Derleme: ./build.sh
- Hızlı Paylaş (Android'deki aynı protokol): soldaki anten düğmesi = ağdan dosya almayı aç/kapat (açıkken kırmızı), basılı tut = alınan dosyaların klasörü (varsayılan İndirilenler). Telefon/TV'de Hızlı Paylaş'tan Mac'i seçip gönder. İlk açılışta macOS "yerel ağ" ve güvenlik duvarı izni sorar; izin ver.

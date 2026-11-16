# NotMenu — macOS menü çubuğu: arama + not ekleme + paylaşım

- Üst çubuk: [Paylaş] [arama kutusu] [Kalem] [Kapat]. Kalem = Link Cepte uygulamasını (notlar ve linkler) pencere olarak açar; Kapat = uygulamadan çıkar. Yazınca en çok 3 not + (sorgu · Yandex · + · eklenen motorlar) satırı çıkar.
- Arama motoru ekle: Yandex'in yanındaki + → ad ve adres (`%s` aranan kelimenin yerine geçer) yaz, Ekle. Yeni motor ilk harfiyle en sağda görünür (sağ tık → Sil). Fare bölümün dışına çıkınca bölüm kapanır.
- Enter / "Ekle": link ise .url, kısa metin not, 220 karakterden uzunsa .txt olarak kaydeder (MyLauncher kuralı).
- Satırın üstüne gelince: Paylaş, Kopyala, Çöpe at. Linke tıkla = tarayıcıda açılır.
- Herhangi bir uygulamada metin seç → Hizmetler → "Notlarıma Kaydet" (ilk seferde Sistem Ayarları > Klavye > Klavye Kısayolları > Hizmetler'den açman gerekebilir).
- Notlar ~/Link klasöründe; Android'deki Link klasörüyle aynı biçim (iCloud Drive/Syncthing ile eşitlenebilir).
- Derleme: ./build.sh
- Hızlı Paylaş (Android'deki aynı protokol): soldaki anten düğmesi = ağdan dosya almayı aç/kapat (açıkken açık kırmızı "ON" simgesi), basılı tut = alınan dosyaların klasörü (varsayılan İndirilenler). Telefon/TV'de Hızlı Paylaş'tan Mac'i seçip gönder. İlk açılışta macOS "yerel ağ" ve güvenlik duvarı izni sorar; izin ver.
- Paylaşım açıkken altta o an açık cihazlar listelenir; sağdaki klasör simgesiyle dosya(lar) seçip o cihaza gönderirsin.
- Simgeler: Resources/AppIcon.png (ana simge), Resources/MenuIcon.png (menü çubuğu, küçüğü).

#!/bin/bash
# Kullanım: Terminal'de bu klasörde  ./build.sh   (Xcode veya Command Line Tools gerekir)
# Çıktı: Plan.app ve Plan-macOS.zip  (Notlarım dahil: tek uygulama)
set -euo pipefail
cd "$(dirname "$0")"
source version.env

APP=Plan.app
PLISTBUDDY=/usr/libexec/PlistBuddy

# Rust çekirdeği (tarama, arama, hash, küçük resim) önce derlenir
bash scripts/build_rust.sh

# Yalnızca Apple Silicon (arm64) derleme
swift build -c release --arch arm64
BIN="$(swift build -c release --arch arm64 --show-bin-path)/Plan"

rm -rf "$APP"; mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Plan"
cp Info.plist "$APP/Contents/Info.plist"
"$PLISTBUDDY" -c "Set :CFBundleShortVersionString $MARKETING_VERSION" "$APP/Contents/Info.plist"
"$PLISTBUDDY" -c "Set :CFBundleVersion $BUILD_NUMBER" "$APP/Contents/Info.plist"

# Dil klasörleri (Servisler menüsü başlığı için)
for l in tr en; do
  mkdir -p "$APP/Contents/Resources/$l.lproj"
  cp "Resources/$l.lproj/ServicesMenu.strings" "$APP/Contents/Resources/$l.lproj/"
done

# Uygulama simgesi (AppIcon.png → .icns) ve menü çubuğu simgesi
ICONSET="$(mktemp -d)/AppIcon.iconset"; mkdir -p "$ICONSET"
for s in 16 32 128 256 512; do
  sips -z $s $s Resources/AppIcon.png --out "$ICONSET/icon_${s}x${s}.png" >/dev/null
  sips -z $((s*2)) $((s*2)) Resources/AppIcon.png --out "$ICONSET/icon_${s}x${s}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"
cp Resources/MenuIcon.png "$APP/Contents/Resources/MenuIcon.png"

# Paylaş eklentisi (Safari Paylaş menüsü). Derlenemezse uygulama eklentisiz devam eder.
if bash scripts/build_share.sh "$APP"; then
  echo "Paylaş eklentisi eklendi"
else
  echo "UYARI: Paylaş eklentisi derlenemedi, uygulama eklentisiz hazırlanıyor"
  rm -rf "$APP/Contents/PlugIns"
fi

# Chrome eklentisi: uygulamanın içine konur (Notlarım → Chrome Eklentisi Klasörünü Aç bu klasörü açar)
ditto chrome-extension "$APP/Contents/Resources/chrome-extension"
find "$APP/Contents/Resources/chrome-extension" -name '.DS_Store' -delete

# Geçici (ad-hoc) imza: --deep yok, Paylaş eklentisinin kendi imzası korunur
codesign --force --sign - "$APP"

ditto -c -k --sequesterRsrc --keepParent "$APP" Plan-macOS.zip
echo "Hazır: $APP  →  Uygulamalar klasörüne sürükle ve aç."

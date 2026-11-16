#!/bin/bash
# Kullanım: Terminal'de bu klasörde  ./build.sh   (Xcode veya Command Line Tools gerekir)
set -e
swift build -c release
APP=NotMenu.app
rm -rf "$APP"; mkdir -p "$APP/Contents/MacOS"
cp .build/release/NotMenu "$APP/Contents/MacOS/NotMenu"
cp Info.plist "$APP/Contents/Info.plist"

# Uygulama simgesi (AppIcon.png → .icns) ve menü çubuğu simgesi (ana simgenin küçüğü)
mkdir -p "$APP/Contents/Resources"
ICONSET="$(mktemp -d)/AppIcon.iconset"; mkdir -p "$ICONSET"
for s in 16 32 128 256 512; do
  sips -z $s $s Resources/AppIcon.png --out "$ICONSET/icon_${s}x${s}.png" >/dev/null
  sips -z $((s*2)) $((s*2)) Resources/AppIcon.png --out "$ICONSET/icon_${s}x${s}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"
cp Resources/MenuIcon.png "$APP/Contents/Resources/MenuIcon.png"
codesign --force --deep --sign - "$APP"
echo "Hazır: $APP  →  Uygulamalar klasörüne sürükle ve aç."

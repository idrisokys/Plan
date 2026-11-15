#!/bin/bash
# Kullanım: Terminal'de bu klasörde  ./build.sh   (Xcode veya Command Line Tools gerekir)
set -e
swift build -c release
APP=NotMenu.app
rm -rf "$APP"; mkdir -p "$APP/Contents/MacOS"
cp .build/release/NotMenu "$APP/Contents/MacOS/NotMenu"
cp Info.plist "$APP/Contents/Info.plist"
codesign --force --deep --sign - "$APP"
echo "Hazır: $APP  →  Uygulamalar klasörüne sürükle ve aç."

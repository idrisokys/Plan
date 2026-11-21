#!/bin/bash
# Paylaş eklentisini derleyip uygulamanın içine koyar. Kullanım: build_share.sh <Plan.app>
# (build.sh tarafından çağrılır; yol proje köküne göredir.)
set -euo pipefail
cd "$(dirname "$0")/.."   # proje kökü

# shellcheck source=../version.env
source version.env

APP="$1"
X="$APP/Contents/PlugIns/PlanShare.appex"
mkdir -p "$X/Contents/MacOS" build

# Yalnızca Apple Silicon (arm64)
swiftc -parse-as-library -O -module-name PlanShare \
  -target arm64-apple-macos13.0 -framework AppKit \
  -Xlinker -e -Xlinker _NSExtensionMain \
  ShareExtension/ShareViewController.swift -o "$X/Contents/MacOS/PlanShare"
cp ShareExtension/Info.plist "$X/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $MARKETING_VERSION" "$X/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $BUILD_NUMBER" "$X/Contents/Info.plist"
codesign --force --sign - --entitlements ShareExtension/Share.entitlements "$X"

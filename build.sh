#!/bin/bash
# Brink — tek komutla derle, .app ve .dmg üret.
# Gereksinim: macOS 13+ ve Xcode Command Line Tools (xcode-select --install)
set -euo pipefail
cd "$(dirname "$0")"

APP_NAME="Brink"
BUNDLE_ID="com.semihtali.brink"
DIST="dist"
APP="$DIST/$APP_NAME.app"

echo "==> Swift derleniyor (release)..."
swift build -c release

echo "==> .app paketi oluşturuluyor..."
rm -rf "$DIST"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp ".build/release/$APP_NAME" "$APP/Contents/MacOS/$APP_NAME"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>$APP_NAME</string>
    <key>CFBundleDisplayName</key><string>$APP_NAME</string>
    <key>CFBundleIdentifier</key><string>$BUNDLE_ID</string>
    <key>CFBundleVersion</key><string>1.0</string>
    <key>CFBundleShortVersionString</key><string>1.0</string>
    <key>CFBundleExecutable</key><string>$APP_NAME</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>LSMinimumSystemVersion</key><string>13.0</string>
    <key>LSUIElement</key><true/>
    <key>NSHighResolutionCapable</key><true/>
    <key>NSAppTransportSecurity</key>
    <dict>
        <key>NSAllowsArbitraryLoads</key><false/>
    </dict>
</dict>
</plist>
PLIST

echo "==> Ad-hoc imzalanıyor..."
codesign --force --sign - "$APP"

echo "==> DMG oluşturuluyor..."
DMG_ROOT="$DIST/dmgroot"
mkdir -p "$DMG_ROOT"
cp -R "$APP" "$DMG_ROOT/"
ln -s /Applications "$DMG_ROOT/Applications"
hdiutil create -volname "$APP_NAME" -srcfolder "$DMG_ROOT" -ov -format UDZO "$DIST/$APP_NAME.dmg" >/dev/null
rm -rf "$DMG_ROOT"

echo ""
echo "✅ Bitti!"
echo "   Uygulama : $APP"
echo "   DMG      : $DIST/$APP_NAME.dmg"
echo ""
echo "Çalıştırmak için:  open $APP"
echo "veya DMG'yi açıp Brink'ı Applications klasörüne sürükleyin."

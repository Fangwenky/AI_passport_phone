#!/bin/zsh
set -e

PROJECT="$(cd "$(dirname "$0")/.." && pwd)"
APP="$PROJECT/dist/AI Passport Manager.app"
CONTENTS="$APP/Contents"
mkdir -p "$CONTENTS/MacOS" "$CONTENTS/Resources"
HELPER="$CONTENTS/Helpers/Passport Bluetooth.app"
mkdir -p "$HELPER/Contents/MacOS"

swiftc -parse-as-library -swift-version 5 -O \
  -framework SwiftUI -framework AppKit \
  "$PROJECT/mac/ManagerApp.swift" -o "$CONTENTS/MacOS/PassportManager"
cp "$PROJECT/android/app/src/main/res/drawable-nodpi/companion.png" "$CONTENTS/Resources/companion.png"
BRIDGE="$CONTENTS/Resources/bridge"
"$PROJECT/scripts/stage-bridge.sh"
cp -R "$PROJECT/.build/bridge/." "$BRIDGE/"

ICON_WORK="$(mktemp -d)"
trap 'rm -rf "$ICON_WORK"' EXIT
ICONSET="$ICON_WORK/AppIcon.iconset"
mkdir -p "$ICONSET"
for SIZE in 16 32 128 256 512; do
  sips -z "$SIZE" "$SIZE" "$PROJECT/mac/assets/app-icon.png" --out "$ICONSET/icon_${SIZE}x${SIZE}.png" >/dev/null
  DOUBLE=$((SIZE * 2))
  sips -z "$DOUBLE" "$DOUBLE" "$PROJECT/mac/assets/app-icon.png" --out "$ICONSET/icon_${SIZE}x${SIZE}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$CONTENTS/Resources/AppIcon.icns"

swiftc -O "$PROJECT/mac/ble.swift" -o "$HELPER/Contents/MacOS/PassportBluetooth"
cat > "$HELPER/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleIdentifier</key><string>dev.passport.redmi.bluetooth</string>
  <key>CFBundleName</key><string>Passport Bluetooth</string>
  <key>CFBundleExecutable</key><string>PassportBluetooth</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>0.4.0</string>
  <key>CFBundleVersion</key><string>6</string>
  <key>LSUIElement</key><true/>
  <key>NSBluetoothAlwaysUsageDescription</key><string>AI Passport uses Bluetooth to pair this Mac with the Redmi desk display.</string>
</dict></plist>
EOF
codesign --force --sign - "$HELPER" >/dev/null

cat > "$CONTENTS/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleIdentifier</key><string>dev.passport.redmi.manager</string>
  <key>CFBundleName</key><string>AI Passport Manager</string>
  <key>CFBundleDisplayName</key><string>AI Passport</string>
  <key>CFBundleExecutable</key><string>PassportManager</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>0.4.0</string>
  <key>CFBundleVersion</key><string>6</string>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSBluetoothAlwaysUsageDescription</key><string>AI Passport uses Bluetooth to pair this Mac with the Redmi desk display.</string>
  <key>NSAppTransportSecurity</key><dict><key>NSAllowsLocalNetworking</key><true/></dict>
</dict></plist>
EOF
codesign --force --sign - "$APP" >/dev/null
echo "$APP"

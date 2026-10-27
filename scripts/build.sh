#!/usr/bin/env bash
# Builds a universal (Apple Silicon + Intel) WindowPac.app. Run on a Mac.
set -euo pipefail
cd "$(dirname "$0")/.."

swift build -c release --arch arm64 --arch x86_64
BIN=".build/apple/Products/Release/WindowPac"

APP="build/WindowPac.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp "$BIN" "$APP/Contents/MacOS/WindowPac"
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleName</key><string>WindowPac</string>
  <key>CFBundleDisplayName</key><string>WindowPac</string>
  <key>CFBundleIdentifier</key><string>com.windowpac.app</string>
  <key>CFBundleExecutable</key><string>WindowPac</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>1.0</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
  <key>LSUIElement</key><true/>
</dict></plist>
PLIST

# A stable signature keeps the Accessibility grant across rebuilds better than ad-hoc;
# set SIGN_ID to a "Apple Development" identity if you have one.
codesign --force --deep --sign "${SIGN_ID:--}" "$APP"
lipo -archs "$APP/Contents/MacOS/WindowPac"
echo "Built $APP  →  cp -R $APP /Applications/"

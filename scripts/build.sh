#!/usr/bin/env bash
# Builds a universal (Apple Silicon + Intel) WindowPac.app. Run on a Mac.
set -euo pipefail
cd "$(dirname "$0")/.."

# Build each architecture separately (works with Command Line Tools only, no full Xcode),
# then merge into one universal binary.
for ARCH in arm64 x86_64; do
  swift build -c release --triple "$ARCH-apple-macosx13.0" --scratch-path ".build/$ARCH"
done
mkdir -p build
BIN="build/WindowPac-universal"
lipo -create -output "$BIN" \
  ".build/arm64/arm64-apple-macosx/release/WindowPac" \
  ".build/x86_64/x86_64-apple-macosx/release/WindowPac"

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

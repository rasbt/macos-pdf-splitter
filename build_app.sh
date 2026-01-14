#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"
PACKAGE_DIR="$ROOT_DIR/PDFSplitterMac"
APP_NAME="PDFSplitterMac"
DISPLAY_NAME="PDF Splitter"
DIST_DIR="$ROOT_DIR/dist"
APP_DIR="$DIST_DIR/${DISPLAY_NAME}.app"
BIN_PATH="$PACKAGE_DIR/.build/release/$APP_NAME"

mkdir -p "$DIST_DIR"

swift build -c release --package-path "$PACKAGE_DIR"

mkdir -p "$APP_DIR/Contents/MacOS"
mkdir -p "$APP_DIR/Contents/Resources"

cat > "$APP_DIR/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key>
  <string>${DISPLAY_NAME}</string>
  <key>CFBundleDisplayName</key>
  <string>${DISPLAY_NAME}</string>
  <key>CFBundleIdentifier</key>
  <string>com.local.pdfsplitter</string>
  <key>CFBundleVersion</key>
  <string>1</string>
  <key>CFBundleShortVersionString</key>
  <string>1.0</string>
  <key>CFBundleExecutable</key>
  <string>${APP_NAME}</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>LSMinimumSystemVersion</key>
  <string>12.0</string>
  <key>NSHighResolutionCapable</key>
  <true/>
</dict>
</plist>
EOF

cp "$BIN_PATH" "$APP_DIR/Contents/MacOS/$APP_NAME"

echo "Built app at: $APP_DIR"

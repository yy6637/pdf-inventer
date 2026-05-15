#!/bin/bash
set -e

cd "$(dirname "$0")/.."

APP_NAME="PDF 图片反转工具"
BUNDLE_DIR="build/$APP_NAME.app"
CONTENTS="$BUNDLE_DIR/Contents"
MACOS="$CONTENTS/MacOS"
RESOURCES="$CONTENTS/Resources"
BINARY="native/build/PDFInverter"

# 1. Compile Swift binary
echo "编译 Swift 二进制..."
swiftc -o "$BINARY" native/PDFInverter.swift -framework Cocoa -framework WebKit

# 2. Create .app bundle
echo "创建应用包..."
rm -rf "$BUNDLE_DIR"
mkdir -p "$MACOS" "$RESOURCES"

# 3. Copy binary
cp "$BINARY" "$MACOS/PDFInverter"

# 4. Create Info.plist
cat > "$CONTENTS/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleExecutable</key>
	<string>PDFInverter</string>
	<key>CFBundleIdentifier</key>
	<string>com.pdf-inverter.app</string>
	<key>CFBundleName</key>
	<string>PDF 图片反转工具</string>
	<key>CFBundleDisplayName</key>
	<string>PDF 图片反转工具</string>
	<key>CFBundleVersion</key>
	<string>1.0.0</string>
	<key>CFBundleShortVersionString</key>
	<string>1.0.0</string>
	<key>CFBundlePackageType</key>
	<string>APPL</string>
	<key>LSMinimumSystemVersion</key>
	<string>14.0</string>
	<key>NSHighResolutionCapable</key>
	<true/>
	<key>LSUIElement</key>
	<false/>
</dict>
</plist>
PLIST

# 5. Copy app icon (convert PNG to icns if possible)
if [ -f "build/icon.png" ]; then
  echo "生成图标..."
  ICON="$RESOURCES/icon.icns"
  ICONSET="$RESOURCES/icon.iconset"
  mkdir -p "$ICONSET"

  sips -z 16 16 "build/icon.png" --out "$ICONSET/icon_16x16.png" >/dev/null 2>&1
  sips -z 32 32 "build/icon.png" --out "$ICONSET/icon_16x16@2x.png" >/dev/null 2>&1
  sips -z 32 32 "build/icon.png" --out "$ICONSET/icon_32x32.png" >/dev/null 2>&1
  sips -z 64 64 "build/icon.png" --out "$ICONSET/icon_32x32@2x.png" >/dev/null 2>&1
  sips -z 128 128 "build/icon.png" --out "$ICONSET/icon_128x128.png" >/dev/null 2>&1
  sips -z 256 256 "build/icon.png" --out "$ICONSET/icon_128x128@2x.png" >/dev/null 2>&1
  sips -z 256 256 "build/icon.png" --out "$ICONSET/icon_256x256.png" >/dev/null 2>&1
  sips -z 512 512 "build/icon.png" --out "$ICONSET/icon_256x256@2x.png" >/dev/null 2>&1
  sips -z 512 512 "build/icon.png" --out "$ICONSET/icon_512x512.png" >/dev/null 2>&1
  sips -z 1024 1024 "build/icon.png" --out "$ICONSET/icon_512x512@2x.png" >/dev/null 2>&1

  iconutil -c icns "$ICONSET" -o "$ICON" 2>/dev/null && rm -rf "$ICONSET" || rm -rf "$ICONSET"
fi

echo ""
echo "✅ 构建完成: $BUNDLE_DIR"
echo "   双击 \"build/$APP_NAME.app\" 即可启动"

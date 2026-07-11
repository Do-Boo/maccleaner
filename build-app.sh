#!/bin/bash
# MacCleaner.app 번들 생성 스크립트
set -euo pipefail
cd "$(dirname "$0")"

APP_NAME="MacCleaner"
VERSION="${VERSION:-1.0.0}"
APP_DIR="build/$APP_NAME.app"
BIN_DIR="$(swift build -c release --arch arm64 --arch x86_64 --show-bin-path)"

echo "▸ 범용 릴리즈 빌드 중..."
swift build -c release --arch arm64 --arch x86_64

if [ ! -f "Resources/MacCleaner.icns" ]; then
    ./Scripts/build-icon.sh
fi

rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS"
mkdir -p "$APP_DIR/Contents/Resources"

cp "$BIN_DIR/$APP_NAME" "$APP_DIR/Contents/MacOS/$APP_NAME"
cp "Resources/MacCleaner.icns" "$APP_DIR/Contents/Resources/MacCleaner.icns"

cat > "$APP_DIR/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>
    <string>$APP_NAME</string>
    <key>CFBundleDisplayName</key>
    <string>$APP_NAME</string>
    <key>CFBundleIdentifier</key>
    <string>com.doyoukim.maccleaner</string>
    <key>CFBundleExecutable</key>
    <string>$APP_NAME</string>
    <key>CFBundleIconFile</key>
    <string>MacCleaner</string>
    <key>CFBundleVersion</key>
    <string>$VERSION</string>
    <key>CFBundleShortVersionString</key>
    <string>$VERSION</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSAppleEventsUsageDescription</key>
    <string>휴지통을 비우기 위해 Finder 제어 권한이 필요합니다.</string>
</dict>
</plist>
EOF

# 로컬 실행용 ad-hoc 서명
codesign --force --deep --sign - "$APP_DIR"

echo ""
echo "✅ 완료! 앱 위치: $APP_DIR"
echo "   실행: open \"$APP_DIR\""

#!/bin/bash
# 构建 PomodoroIsland 并组装成可双击运行的 .app（本地自签名）
set -euo pipefail

cd "$(dirname "$0")/.."

APP_NAME="PomodoroIsland"
BUNDLE_ID="com.danielduan.PomodoroIsland"
VERSION="1.0.0"
BUILD_DIR=".build/release"
APP_DIR="build/${APP_NAME}.app"

echo "==> swift build (release)"
swift build -c release

echo "==> 组装 ${APP_DIR}"
rm -rf "${APP_DIR}"
mkdir -p "${APP_DIR}/Contents/MacOS"

cp "${BUILD_DIR}/${APP_NAME}" "${APP_DIR}/Contents/MacOS/${APP_NAME}"

cat > "${APP_DIR}/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>
    <string>${APP_NAME}</string>
    <key>CFBundleDisplayName</key>
    <string>PomodoroIsland</string>
    <key>CFBundleExecutable</key>
    <string>${APP_NAME}</string>
    <key>CFBundleIdentifier</key>
    <string>${BUNDLE_ID}</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>${VERSION}</string>
    <key>CFBundleVersion</key>
    <string>${VERSION}</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSPrincipalClass</key>
    <string>NSApplication</string>
</dict>
</plist>
EOF

echo "==> ad-hoc 签名"
codesign --force --sign - "${APP_DIR}"

echo "==> 完成: ${APP_DIR}"
echo "    双击运行，或:  open ${APP_DIR}"

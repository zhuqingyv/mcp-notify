#!/usr/bin/env bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_NAME="MCPNotify"
BUNDLE_ID="com.mcp-notify.app"
APP_DIR="${SCRIPT_DIR}/${APP_NAME}.app"
INSTALL_DIR="${HOME}/Applications/${APP_NAME}.app"

echo "==> Building ${APP_NAME}.app"

# ── 1. Create bundle structure ────────────────────────────────────────────────
rm -rf "${APP_DIR}"
mkdir -p "${APP_DIR}/Contents/MacOS"
mkdir -p "${APP_DIR}/Contents/Resources"

# Copy notify-logo.png into Resources
NOTIFY_LOGO="${SCRIPT_DIR}/icons/notify-logo.png"
if [ -f "${NOTIFY_LOGO}" ]; then
  cp "${NOTIFY_LOGO}" "${APP_DIR}/Contents/Resources/notify-logo.png"
fi

# ── 2. Info.plist ─────────────────────────────────────────────────────────────
cat > "${APP_DIR}/Contents/Info.plist" << PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleIdentifier</key>
  <string>${BUNDLE_ID}</string>
  <key>CFBundleName</key>
  <string>${APP_NAME}</string>
  <key>CFBundleExecutable</key>
  <string>mcp-notify</string>
  <key>CFBundleVersion</key>
  <string>1.0</string>
  <key>CFBundleShortVersionString</key>
  <string>1.0</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleIconFile</key>
  <string>AppIcon</string>
  <key>NSPrincipalClass</key>
  <string>NSApplication</string>
  <key>LSUIElement</key>
  <true/>
  <key>NSUserNotificationAlertStyle</key>
  <string>alert</string>
</dict>
</plist>
PLIST

# ── 3. Compile Objective-C source ────────────────────────────────────────────
echo "==> Compiling Objective-C source..."
xcrun clang \
  -fobjc-arc \
  -O2 \
  -framework Foundation \
  -framework AppKit \
  -framework QuartzCore \
  -framework CoreGraphics \
  -o "${APP_DIR}/Contents/MacOS/mcp-notify" \
  "${SCRIPT_DIR}/Sources/main.m"

echo "==> Compiled OK"

# ── 4. Generate AppIcon.icns (uses Pillow to preserve aspect ratio) ───────────
ICON_PNG="${SCRIPT_DIR}/icons/app-icon.png"
if [ -f "${ICON_PNG}" ]; then
  echo "==> Generating AppIcon.icns from app-icon.png..."
  ICONSET_DIR="${SCRIPT_DIR}/AppIcon.iconset"
  rm -rf "${ICONSET_DIR}"
  mkdir -p "${ICONSET_DIR}"
  python3 -c "
from PIL import Image
import os
src = Image.open('${ICON_PNG}').convert('RGBA')
iconset = '${ICONSET_DIR}'
for name, sz in [('icon_16x16.png',16),('icon_16x16@2x.png',32),('icon_32x32.png',32),('icon_32x32@2x.png',64),('icon_128x128.png',128),('icon_128x128@2x.png',256),('icon_256x256.png',256),('icon_256x256@2x.png',512),('icon_512x512.png',512),('icon_512x512@2x.png',1024)]:
    src.resize((sz, sz), Image.LANCZOS).save(os.path.join(iconset, name))
"
  iconutil -c icns "${ICONSET_DIR}" -o "${APP_DIR}/Contents/Resources/AppIcon.icns"
  rm -rf "${ICONSET_DIR}"
  echo "==> AppIcon.icns generated"
else
  echo "==> Warning: ${ICON_PNG} not found, skipping AppIcon.icns"
fi

# ── 5. Code sign with correct bundle identifier ─────────────────────────────
echo "==> Signing binary..."
codesign --force --sign - --identifier "${BUNDLE_ID}" "${APP_DIR}/Contents/MacOS/mcp-notify"

# ── 6. Install to ~/Applications ─────────────────────────────────────────────
echo "==> Installing to ${INSTALL_DIR}..."
rm -rf "${INSTALL_DIR}"
cp -R "${APP_DIR}" "${INSTALL_DIR}"
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "${INSTALL_DIR}"

echo ""
echo "Done. App installed at: ${INSTALL_DIR}"
echo "Binary: ${INSTALL_DIR}/Contents/MacOS/mcp-notify"
echo ""
echo "First run will prompt for notification permission."
echo "Test: ${INSTALL_DIR}/Contents/MacOS/mcp-notify --title 'Test' --message 'Hello'"

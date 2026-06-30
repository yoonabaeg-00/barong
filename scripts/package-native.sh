#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
NATIVE_DIR="$ROOT/native/BarongNotch"
RESOURCE_DIR="$NATIVE_DIR/Sources/Resources"
OAUTH_RESOURCE="$RESOURCE_DIR/GoogleOAuth.json"
PACKAGE_DIR="$ROOT/dist/native"
PUBLIC_DOWNLOAD_DIR="$ROOT/public/downloads"
DIST_DOWNLOAD_DIR="$ROOT/dist/downloads"
APP_NAME="바롱이.app"
ZIP_NAME="barong-notch-macos.zip"
POC_ZIP_NAME="barong-notch-macos-poc.zip"

cleanup() {
  rm -f "$OAUTH_RESOURCE"
}
trap cleanup EXIT

node - "$ROOT/.env.local" "$OAUTH_RESOURCE" <<'NODE'
const fs = require('fs')
const [envPath, outPath] = process.argv.slice(2)

if (!fs.existsSync(envPath)) {
  throw new Error('.env.local is required to package the native app.')
}

const values = {}
for (const rawLine of fs.readFileSync(envPath, 'utf8').split('\n')) {
  const line = rawLine.trim()
  if (!line || line.startsWith('#') || !line.includes('=')) continue
  const [key, ...valueParts] = line.split('=')
  values[key] = valueParts.join('=').replace(/^["']|["']$/g, '')
}

if (!values.GOOGLE_CLIENT_ID || !values.GOOGLE_CLIENT_SECRET) {
  throw new Error('GOOGLE_CLIENT_ID and GOOGLE_CLIENT_SECRET are required in .env.local.')
}

fs.writeFileSync(outPath, JSON.stringify({
  clientId: values.GOOGLE_CLIENT_ID,
  clientSecret: values.GOOGLE_CLIENT_SECRET,
}, null, 2))
NODE

rm -rf "$PACKAGE_DIR"
mkdir -p "$PACKAGE_DIR" "$PUBLIC_DOWNLOAD_DIR" "$DIST_DOWNLOAD_DIR"

swift build --package-path "$NATIVE_DIR" -c release

SOURCE_APP="$NATIVE_DIR/.build/BarongNotch.app"
RELEASE_BINARY="$(find "$NATIVE_DIR/.build" -path "*/release/BarongNotch" -type f | head -n 1)"
if [ -z "$RELEASE_BINARY" ] || [ ! -f "$RELEASE_BINARY" ]; then
  echo "Native release binary was not produced." >&2
  exit 1
fi

rm -rf "$SOURCE_APP"
mkdir -p "$SOURCE_APP/Contents/MacOS" "$SOURCE_APP/Contents/Resources"
cp "$RELEASE_BINARY" "$SOURCE_APP/Contents/MacOS/BarongNotch"
chmod +x "$SOURCE_APP/Contents/MacOS/BarongNotch"
cat > "$SOURCE_APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDisplayName</key>
  <string>바롱이</string>
  <key>CFBundleExecutable</key>
  <string>BarongNotch</string>
  <key>CFBundleIdentifier</key>
  <string>local.barong.notch</string>
  <key>CFBundleName</key>
  <string>바롱이</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>0.1.0</string>
  <key>CFBundleVersion</key>
  <string>0.1.0</string>
  <key>LSUIElement</key>
  <true/>
</dict>
</plist>
PLIST

ditto "$SOURCE_APP" "$PACKAGE_DIR/$APP_NAME"
rm -rf "$PACKAGE_DIR/$APP_NAME/BarongNotch_BarongNotch.bundle"

RESOURCE_BUNDLE_SOURCE="$(find "$NATIVE_DIR/.build" -path "*/release/BarongNotch_BarongNotch.bundle" -type d | head -n 1)"
if [ -z "$RESOURCE_BUNDLE_SOURCE" ] || [ ! -d "$RESOURCE_BUNDLE_SOURCE" ]; then
  echo "Native resource bundle was not produced." >&2
  exit 1
fi

mkdir -p "$PACKAGE_DIR/$APP_NAME/Contents/Resources"
ditto "$RESOURCE_BUNDLE_SOURCE" "$PACKAGE_DIR/$APP_NAME/Contents/Resources/BarongNotch_BarongNotch.bundle"
cp "$OAUTH_RESOURCE" "$PACKAGE_DIR/$APP_NAME/Contents/Resources/GoogleOAuth.json"

if command -v codesign >/dev/null 2>&1; then
  codesign --force --deep --sign - "$PACKAGE_DIR/$APP_NAME"
fi

rm -f \
  "$PUBLIC_DOWNLOAD_DIR/$ZIP_NAME" \
  "$DIST_DOWNLOAD_DIR/$ZIP_NAME" \
  "$PUBLIC_DOWNLOAD_DIR/$POC_ZIP_NAME" \
  "$DIST_DOWNLOAD_DIR/$POC_ZIP_NAME"
(cd "$PACKAGE_DIR" && /usr/bin/zip -qry -X "$PUBLIC_DOWNLOAD_DIR/$ZIP_NAME" "$APP_NAME")
cp "$PUBLIC_DOWNLOAD_DIR/$ZIP_NAME" "$DIST_DOWNLOAD_DIR/$ZIP_NAME"
cp "$PUBLIC_DOWNLOAD_DIR/$ZIP_NAME" "$PUBLIC_DOWNLOAD_DIR/$POC_ZIP_NAME"
cp "$PUBLIC_DOWNLOAD_DIR/$ZIP_NAME" "$DIST_DOWNLOAD_DIR/$POC_ZIP_NAME"

echo "Packaged native app:"
echo "  $PUBLIC_DOWNLOAD_DIR/$ZIP_NAME"
echo "  $DIST_DOWNLOAD_DIR/$ZIP_NAME"
echo "  $PUBLIC_DOWNLOAD_DIR/$POC_ZIP_NAME"
echo "  $DIST_DOWNLOAD_DIR/$POC_ZIP_NAME"

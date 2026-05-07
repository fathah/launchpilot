#!/usr/bin/env bash
#
# scripts/notarize.sh — sign + notarize + staple launchpilot.app for distribution.
#
# Required environment variables:
#   DEVELOPER_ID_APPLICATION   Friendly name of the Developer ID cert in your keychain,
#                              e.g. "Developer ID Application: Your Name (WM6645CA5X)".
#                              Run `security find-identity -v -p codesigning` to copy it.
#   ASC_KEY_ID                 10-character Key ID from App Store Connect → Users and
#                              Access → Integrations → App Store Connect API.
#   ASC_ISSUER_ID              UUID issuer ID shown at the top of that same page.
#   ASC_KEY_PATH               Absolute path to the AuthKey_<KEY_ID>.p8 file you
#                              downloaded when the key was created.
#
# Optional overrides:
#   SCHEME (default: launchpilot)
#   CONFIGURATION (default: Release)
#   PROJECT (default: launchpilot.xcodeproj)
#   TEAM_ID (default: WM6645CA5X)
#   BUILD_DIR (default: build/notarize)
#
# Usage:
#   export DEVELOPER_ID_APPLICATION="Developer ID Application: Your Name (WM6645CA5X)"
#   export ASC_KEY_ID="ABC123XYZ4"
#   export ASC_ISSUER_ID="12345678-1234-1234-1234-123456789012"
#   export ASC_KEY_PATH="$HOME/keys/AuthKey_ABC123XYZ4.p8"
#   ./scripts/notarize.sh
#
# Output:
#   build/notarize/export/launchpilot.app   — signed, notarized, stapled
#   build/notarize/launchpilot.zip          — same app, zipped for distribution

set -euo pipefail

SCHEME="${SCHEME:-launchpilot}"
CONFIGURATION="${CONFIGURATION:-Release}"
PROJECT="${PROJECT:-launchpilot.xcodeproj}"
TEAM_ID="${TEAM_ID:-WM6645CA5X}"
BUILD_DIR="${BUILD_DIR:-build/notarize}"
ARCHIVE_PATH="$BUILD_DIR/launchpilot.xcarchive"
EXPORT_DIR="$BUILD_DIR/export"
EXPORT_PLIST="$BUILD_DIR/ExportOptions.plist"
APP_PATH="$EXPORT_DIR/launchpilot.app"
ZIP_PATH="$BUILD_DIR/launchpilot.zip"

require() {
  local var="$1"
  if [ -z "${!var:-}" ]; then
    echo "error: $var is not set. See header of this script for setup." >&2
    exit 1
  fi
}
require DEVELOPER_ID_APPLICATION
require ASC_KEY_ID
require ASC_ISSUER_ID
require ASC_KEY_PATH

if [ ! -f "$ASC_KEY_PATH" ]; then
  echo "error: ASC_KEY_PATH does not point to a file: $ASC_KEY_PATH" >&2
  exit 1
fi

if ! security find-identity -v -p codesigning | grep -qF "$DEVELOPER_ID_APPLICATION"; then
  echo "error: identity not found in keychain: $DEVELOPER_ID_APPLICATION" >&2
  echo "       run: security find-identity -v -p codesigning" >&2
  exit 1
fi

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO_ROOT"

mkdir -p "$BUILD_DIR"
rm -rf "$ARCHIVE_PATH" "$EXPORT_DIR" "$ZIP_PATH"

echo "==> Archiving $SCHEME ($CONFIGURATION) with Developer ID signing"
xcodebuild \
  -project "$PROJECT" \
  -scheme "$SCHEME" \
  -configuration "$CONFIGURATION" \
  -destination "generic/platform=macOS" \
  -archivePath "$ARCHIVE_PATH" \
  CODE_SIGN_STYLE=Manual \
  CODE_SIGN_IDENTITY="$DEVELOPER_ID_APPLICATION" \
  DEVELOPMENT_TEAM="$TEAM_ID" \
  archive

cat > "$EXPORT_PLIST" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>method</key>
    <string>developer-id</string>
    <key>teamID</key>
    <string>$TEAM_ID</string>
    <key>signingStyle</key>
    <string>manual</string>
    <key>signingCertificate</key>
    <string>Developer ID Application</string>
</dict>
</plist>
EOF

echo "==> Exporting signed .app"
xcodebuild \
  -exportArchive \
  -archivePath "$ARCHIVE_PATH" \
  -exportPath "$EXPORT_DIR" \
  -exportOptionsPlist "$EXPORT_PLIST"

if [ ! -d "$APP_PATH" ]; then
  echo "error: $APP_PATH not found after export" >&2
  exit 1
fi

echo "==> Zipping app for notarytool"
ditto -c -k --keepParent "$APP_PATH" "$ZIP_PATH"

echo "==> Submitting to Apple notarization service (this can take a few minutes)"
xcrun notarytool submit "$ZIP_PATH" \
  --key "$ASC_KEY_PATH" \
  --key-id "$ASC_KEY_ID" \
  --issuer "$ASC_ISSUER_ID" \
  --wait

echo "==> Stapling notarization ticket"
xcrun stapler staple "$APP_PATH"

echo "==> Verifying signature and notarization"
codesign -dv --verbose=4 "$APP_PATH" 2>&1 | head -20
spctl -a -t exec -vv "$APP_PATH"

echo
echo "Notarized app: $APP_PATH"
echo "Distributable zip: $ZIP_PATH"

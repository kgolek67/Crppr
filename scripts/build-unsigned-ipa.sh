#!/bin/bash
# Run on macOS with Xcode. GitHub Actions supplies both; no account or certificate is used.
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$PROJECT_ROOT"
BUILD_DIR="$PROJECT_ROOT/build"
IPA_PATH="$PROJECT_ROOT/dist/Crppr-unsigned.ipa"
mkdir -p "$BUILD_DIR" "$PROJECT_ROOT/dist"

xcodebuild -version
xcodebuild \
  -project Crppr.xcodeproj \
  -scheme Crppr \
  -configuration Release \
  -sdk iphoneos \
  -destination 'generic/platform=iOS' \
  -derivedDataPath "$BUILD_DIR/DerivedData" \
  ARCHS=arm64 \
  ONLY_ACTIVE_ARCH=NO \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGN_IDENTITY="" \
  build 2>&1 | tee "$BUILD_DIR/xcodebuild.log"

APP_PATH="$BUILD_DIR/DerivedData/Build/Products/Release-iphoneos/Crppr.app"
test -d "$APP_PATH"
xcrun lipo "$APP_PATH/Crppr" -verify_arch arm64
if codesign -d "$APP_PATH" > "$BUILD_DIR/signature-check.log" 2>&1; then
  echo 'Expected an unsigned app, but codesign found a signature.' >&2
  exit 1
fi

STAGING_DIR="$(mktemp -d "${TMPDIR:-/tmp}/crppr-payload.XXXXXX")"
trap 'rm -rf "$STAGING_DIR"' EXIT
mkdir -p "$STAGING_DIR/Payload"
ditto "$APP_PATH" "$STAGING_DIR/Payload/Crppr.app"
(
  cd "$STAGING_DIR"
  /usr/bin/zip -q -r -X "$STAGING_DIR/Crppr-unsigned.ipa" Payload
)
python3 scripts/validate-ipa.py "$STAGING_DIR/Crppr-unsigned.ipa"
mv -f "$STAGING_DIR/Crppr-unsigned.ipa" "$IPA_PATH"
echo "Unsigned IPA created: $IPA_PATH"

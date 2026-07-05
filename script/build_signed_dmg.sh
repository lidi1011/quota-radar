#!/usr/bin/env bash
set -euo pipefail

APP_NAME="QuotaRadar"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST_DIR="$ROOT_DIR/dist"
TMP_DIR="$ROOT_DIR/tmp"
APP_VERSION="$(sed -n 's/^APP_VERSION="\([^"]*\)"/\1/p' "$ROOT_DIR/script/build_and_run.sh")"
IDENTITY="${SIGN_IDENTITY:-}"
NOTARY_PROFILE="${NOTARY_PROFILE:-}"
DMG_NAME="$APP_NAME-$APP_VERSION-signed.dmg"
DMG_PATH="$DIST_DIR/$DMG_NAME"
STAGING_DIR="$TMP_DIR/dmg-signed-staging"
APP_BUNDLE="$DIST_DIR/$APP_NAME.app"

if [ -z "$APP_VERSION" ]; then
  echo "Could not read APP_VERSION from script/build_and_run.sh" >&2
  exit 1
fi

if [ -z "$IDENTITY" ]; then
  echo "SIGN_IDENTITY is required, for example:" >&2
  echo "  SIGN_IDENTITY=\"Developer ID Application: Your Name (TEAMID)\" $0" >&2
  exit 1
fi

cd "$ROOT_DIR"

"$ROOT_DIR/script/build_and_run.sh" --bundle

codesign \
  --force \
  --options runtime \
  --timestamp \
  --sign "$IDENTITY" \
  "$APP_BUNDLE"

codesign --verify --strict --verbose=2 "$APP_BUNDLE"
if ! spctl --assess --type execute --verbose=4 "$APP_BUNDLE"; then
  echo "Gatekeeper assessment failed before notarization; this is expected for an unnotarized Developer ID app."
fi

rm -rf "$STAGING_DIR"
mkdir -p "$STAGING_DIR" "$DIST_DIR"
cp -R "$APP_BUNDLE" "$STAGING_DIR/$APP_NAME.app"
ln -s /Applications "$STAGING_DIR/Applications"

rm -f "$DMG_PATH"
hdiutil create \
  -volname "额度雷达 $APP_VERSION" \
  -srcfolder "$STAGING_DIR" \
  -format UDZO \
  -ov \
  "$DMG_PATH"

codesign \
  --force \
  --timestamp \
  --sign "$IDENTITY" \
  "$DMG_PATH"

codesign --verify --verbose=2 "$DMG_PATH"
hdiutil verify "$DMG_PATH"

if [ -n "$NOTARY_PROFILE" ]; then
  xcrun notarytool submit "$DMG_PATH" --keychain-profile "$NOTARY_PROFILE" --wait
  xcrun stapler staple "$DMG_PATH"
  xcrun stapler validate "$DMG_PATH"
  spctl --assess --type open --context context:primary-signature --verbose=4 "$DMG_PATH"
else
  echo "Skipping notarization because NOTARY_PROFILE is not set."
  echo "To notarize later: NOTARY_PROFILE=<profile> $0"
fi

du -h "$DMG_PATH"

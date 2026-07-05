#!/usr/bin/env bash
set -euo pipefail

APP_NAME="QuotaRadar"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST_DIR="$ROOT_DIR/dist"
TMP_DIR="$ROOT_DIR/tmp"
APP_VERSION="$(sed -n 's/^APP_VERSION="\([^"]*\)"/\1/p' "$ROOT_DIR/script/build_and_run.sh")"
DMG_NAME="$APP_NAME-$APP_VERSION.dmg"
DMG_PATH="$DIST_DIR/$DMG_NAME"
STAGING_DIR="$TMP_DIR/dmg-staging"

if [ -z "$APP_VERSION" ]; then
  echo "Could not read APP_VERSION from script/build_and_run.sh" >&2
  exit 1
fi

cd "$ROOT_DIR"

"$ROOT_DIR/script/build_and_run.sh" --bundle

rm -rf "$STAGING_DIR"
mkdir -p "$STAGING_DIR" "$DIST_DIR"
cp -R "$DIST_DIR/$APP_NAME.app" "$STAGING_DIR/$APP_NAME.app"
ln -s /Applications "$STAGING_DIR/Applications"

rm -f "$DMG_PATH"
hdiutil create \
  -volname "额度雷达 $APP_VERSION" \
  -srcfolder "$STAGING_DIR" \
  -format UDZO \
  -ov \
  "$DMG_PATH"

hdiutil verify "$DMG_PATH"
du -h "$DMG_PATH"

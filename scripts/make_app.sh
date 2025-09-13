#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
DIST_DIR="$ROOT_DIR/dist"
APP_NAME="WattageBar"
APP_BUNDLE="$DIST_DIR/$APP_NAME.app"
INFO_PLIST_SRC="$ROOT_DIR/bundle/Info.plist"

echo "Building release binary..."
swift build -c release

BIN_PATH="$ROOT_DIR/.build/release/$APP_NAME"
if [[ ! -x "$BIN_PATH" ]]; then
  echo "Error: Built binary not found at $BIN_PATH" >&2
  exit 1
fi

echo "Creating app bundle at $APP_BUNDLE"
rm -rf "$APP_BUNDLE"
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"

cp "$INFO_PLIST_SRC" "$APP_BUNDLE/Contents/Info.plist"
cp "$BIN_PATH" "$APP_BUNDLE/Contents/MacOS/$APP_NAME"
chmod +x "$APP_BUNDLE/Contents/MacOS/$APP_NAME"

echo "Done: $APP_BUNDLE"
echo "Tip: Open with: open \"$APP_BUNDLE\""


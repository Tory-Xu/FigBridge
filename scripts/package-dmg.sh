#!/bin/zsh

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_NAME="FigBridge"
PRODUCT_NAME="FigBridge"
CONFIGURATION="release"
DIST_DIR="$ROOT_DIR/dist"
STAGE_DIR="$DIST_DIR/stage"
APP_DIR="$STAGE_DIR/$APP_NAME.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"
RESOURCE_BUNDLE_NAME="FigBridge_FigBridgeApp.bundle"
SOURCE_RESOURCES_DIR="$ROOT_DIR/Sources/FigBridgeApp/Resources"
DMG_PATH="$DIST_DIR/$APP_NAME.dmg"
VOLUME_NAME="$APP_NAME"

if ! command -v hdiutil >/dev/null 2>&1; then
  echo "error: hdiutil not found; this script must run on macOS" >&2
  exit 1
fi

echo "==> Building $PRODUCT_NAME ($CONFIGURATION)"
swift build -c "$CONFIGURATION" --product "$PRODUCT_NAME" --package-path "$ROOT_DIR"

EXECUTABLE_PATH="$(find "$ROOT_DIR/.build" -type f -path "*/$CONFIGURATION/$PRODUCT_NAME" -perm +111 | head -n 1)"
RESOURCE_BUNDLE_PATH="$(find "$ROOT_DIR/.build" -type d -path "*/$CONFIGURATION/$RESOURCE_BUNDLE_NAME" | head -n 1)"

if [[ -z "$EXECUTABLE_PATH" || ! -x "$EXECUTABLE_PATH" ]]; then
  echo "error: executable not found at $EXECUTABLE_PATH" >&2
  exit 1
fi

if [[ -z "$RESOURCE_BUNDLE_PATH" || ! -d "$RESOURCE_BUNDLE_PATH" ]]; then
  echo "error: resource bundle not found for $RESOURCE_BUNDLE_NAME" >&2
  exit 1
fi

echo "==> Preparing app bundle"
rm -rf "$STAGE_DIR"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR"

cp "$EXECUTABLE_PATH" "$MACOS_DIR/$APP_NAME"
cp "$SOURCE_RESOURCES_DIR/Info.plist" "$CONTENTS_DIR/Info.plist"
ditto "$SOURCE_RESOURCES_DIR" "$RESOURCES_DIR"
ditto "$RESOURCE_BUNDLE_PATH" "$APP_DIR/$RESOURCE_BUNDLE_NAME"

ln -s /Applications "$STAGE_DIR/Applications"

echo "==> Creating DMG"
rm -f "$DMG_PATH"
hdiutil create \
  -volname "$VOLUME_NAME" \
  -srcfolder "$STAGE_DIR" \
  -ov \
  -format UDZO \
  "$DMG_PATH" >/dev/null

echo "Created $DMG_PATH"

#!/bin/zsh

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_NAME="FigBridge"
PRODUCT_NAME="FigBridge"
CONFIGURATION="release"
DIST_DIR="$ROOT_DIR/dist"
TARGET_ARCH="${1:-arm64}"
STAGE_DIR="$DIST_DIR/stage-$TARGET_ARCH"
APP_DIR="$STAGE_DIR/$APP_NAME.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"
RESOURCE_BUNDLE_NAME="FigBridge_FigBridgeApp.bundle"
SOURCE_RESOURCES_DIR="$ROOT_DIR/Sources/FigBridgeApp/Resources"
VOLUME_NAME="$APP_NAME"

case "$TARGET_ARCH" in
  arm64|x86_64)
    ;;
  *)
    echo "error: unsupported architecture '$TARGET_ARCH'; expected arm64 or x86_64" >&2
    exit 1
    ;;
esac

DMG_PATH="$DIST_DIR/$APP_NAME-$TARGET_ARCH.dmg"

if ! command -v hdiutil >/dev/null 2>&1; then
  echo "error: hdiutil not found; this script must run on macOS" >&2
  exit 1
fi

echo "==> Building $PRODUCT_NAME ($CONFIGURATION, $TARGET_ARCH)"
swift build -c "$CONFIGURATION" --arch "$TARGET_ARCH" --product "$PRODUCT_NAME" --package-path "$ROOT_DIR"

EXECUTABLE_PATH="$(find "$ROOT_DIR/.build" -type f -path "*/$TARGET_ARCH-apple-macosx*/$CONFIGURATION/$PRODUCT_NAME" -perm +111 | head -n 1)"
RESOURCE_BUNDLE_PATH="$(find "$ROOT_DIR/.build" -type d -path "*/$CONFIGURATION/$RESOURCE_BUNDLE_NAME" | head -n 1)"

if [[ -z "$EXECUTABLE_PATH" || ! -x "$EXECUTABLE_PATH" ]]; then
  echo "error: executable not found at $EXECUTABLE_PATH" >&2
  exit 1
fi

if [[ -z "$RESOURCE_BUNDLE_PATH" || ! -d "$RESOURCE_BUNDLE_PATH" ]]; then
  echo "error: resource bundle not found for $RESOURCE_BUNDLE_NAME" >&2
  exit 1
fi

ARCH_INFO="$(lipo -info "$EXECUTABLE_PATH" 2>/dev/null || true)"
if [[ "$ARCH_INFO" != *"$TARGET_ARCH"* ]]; then
  echo "error: built executable architecture mismatch; expected $TARGET_ARCH, got: ${ARCH_INFO:-unknown}" >&2
  exit 1
fi

MIN_OS_VERSION="$(otool -l "$EXECUTABLE_PATH" | awk '
  $1 == "cmd" && $2 == "LC_BUILD_VERSION" { in_build_version = 1; next }
  in_build_version && $1 == "minos" { print $2; exit }
')"
if [[ "$MIN_OS_VERSION" != "12.0" ]]; then
  echo "error: minimum macOS version mismatch; expected 12.0, got: ${MIN_OS_VERSION:-unknown}" >&2
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

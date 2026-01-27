#!/usr/bin/env bash

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

APP_NAME="Overleaf Local Sync"
PRODUCT_EXECUTABLE="OverleafSyncMacApp"
DIST_DIR="$ROOT/dist"
APP_DIR="$DIST_DIR/$APP_NAME.app"

FORCE=false
for arg in "$@"; do
  case "$arg" in
    --force) FORCE=true ;;
    *)
      echo "Unknown argument: $arg" >&2
      echo "Usage: $0 [--force]" >&2
      exit 2
      ;;
  esac
done

mkdir -p "$DIST_DIR"

if [[ -e "$APP_DIR" && "$FORCE" != true ]]; then
  echo "Refusing to overwrite existing app bundle:" >&2
  echo "  $APP_DIR" >&2
  echo "" >&2
  echo "Re-run with --force to overwrite." >&2
  exit 1
fi

echo "Building (release)…"
cd "$ROOT"
swift build -c release

BIN_DIR="$(swift build -c release --show-bin-path)"
BIN_PATH="$BIN_DIR/$PRODUCT_EXECUTABLE"

if [[ ! -x "$BIN_PATH" ]]; then
  echo "Built executable not found:" >&2
  echo "  $BIN_PATH" >&2
  exit 1
fi

if [[ -e "$APP_DIR" ]]; then
  ts="$(date +"%Y%m%d-%H%M%S")"
  BACKUP_DIR="$DIST_DIR/backups"
  mkdir -p "$BACKUP_DIR"
  BACKUP_PATH="$BACKUP_DIR/$APP_NAME.app.$ts"
  echo "Existing app detected. Moving to backup:"
  echo "  $BACKUP_PATH"
  mv "$APP_DIR" "$BACKUP_PATH"
fi

mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"
cp "$BIN_PATH" "$APP_DIR/Contents/MacOS/$PRODUCT_EXECUTABLE"

ICON_SRC="$ROOT/Resources/AppIcon.icns"
if [[ -f "$ICON_SRC" ]]; then
  cp "$ICON_SRC" "$APP_DIR/Contents/Resources/AppIcon.icns"
fi

cat >"$APP_DIR/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key>
  <string>en</string>
  <key>CFBundleDisplayName</key>
  <string>Overleaf Local Sync</string>
  <key>CFBundleExecutable</key>
  <string>OverleafSyncMacApp</string>
  <key>CFBundleIdentifier</key>
  <string>com.qinferl.overleaflocalsync</string>
  <key>CFBundleIconFile</key>
  <string>AppIcon.icns</string>
  <key>CFBundleIconName</key>
  <string>AppIcon</string>
  <key>CFBundleInfoDictionaryVersion</key>
  <string>6.0</string>
  <key>CFBundleName</key>
  <string>Overleaf Local Sync</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>0.1.0</string>
  <key>CFBundleVersion</key>
  <string>1</string>
  <key>LSMinimumSystemVersion</key>
  <string>13.0</string>
  <key>NSHighResolutionCapable</key>
  <true/>
  <key>NSPrincipalClass</key>
  <string>NSApplication</string>
</dict>
</plist>
PLIST

echo ""
echo "✅ Built app bundle:"
echo "  $APP_DIR"
echo ""
echo "Install:"
echo "  open \"$DIST_DIR\""
echo "  then drag \"$APP_NAME.app\" into /Applications"

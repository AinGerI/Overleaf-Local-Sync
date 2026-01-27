#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SVG="$ROOT/Resources/AppIcon.svg"
OUT_ICNS="$ROOT/Resources/AppIcon.icns"

if [[ ! -f "$SVG" ]]; then
  echo "Missing $SVG" >&2
  exit 1
fi

if ! command -v qlmanage >/dev/null 2>&1 || ! command -v sips >/dev/null 2>&1 || ! command -v iconutil >/dev/null 2>&1; then
  echo "This script requires macOS tools: qlmanage, sips, iconutil" >&2
  exit 1
fi

tmp="$(mktemp -d "${TMPDIR:-/tmp}/olsync-icon.XXXXXX")"
trap 'rm -rf "$tmp"' EXIT

echo "Rendering SVG → PNG…"
qlmanage -t -s 1024 -o "$tmp" "$SVG" >/dev/null 2>&1

src_png="$tmp/$(basename "$SVG").png"
if [[ ! -f "$src_png" ]]; then
  # qlmanage output naming can vary; pick the first png.
  src_png="$(ls -1 "$tmp"/*.png 2>/dev/null | head -n 1 || true)"
fi
if [[ -z "${src_png:-}" || ! -f "$src_png" ]]; then
  echo "Failed to render PNG via qlmanage." >&2
  exit 1
fi

iconset="$tmp/AppIcon.iconset"
mkdir -p "$iconset"

make_png() {
  local size="$1"
  local name="$2"
  sips -z "$size" "$size" "$src_png" --out "$iconset/$name" >/dev/null 2>&1
}

make_png 16 icon_16x16.png
make_png 32 icon_16x16@2x.png
make_png 32 icon_32x32.png
make_png 64 icon_32x32@2x.png
make_png 128 icon_128x128.png
make_png 256 icon_128x128@2x.png
make_png 256 icon_256x256.png
make_png 512 icon_256x256@2x.png
make_png 512 icon_512x512.png
make_png 1024 icon_512x512@2x.png

echo "Building ICNS…"
iconutil -c icns "$iconset" -o "$OUT_ICNS"

echo "✅ Wrote $OUT_ICNS"


#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
ICON="${1:-$HOME/Downloads/HALO-AppIcon-1024.png}"
WORDMARK="${2:-$HOME/Downloads/HALO-Wordmark.png}"
ASSETS="$ROOT/HaloField/Assets.xcassets"
APPICON="$ASSETS/AppIcon.appiconset"
WORDMARKSET="$ASSETS/HALOWordmark.imageset"

if [[ ! -f "$ICON" ]]; then
  echo "Missing app icon: $ICON" >&2
  exit 1
fi

if [[ ! -f "$WORDMARK" ]]; then
  echo "Missing wordmark: $WORDMARK" >&2
  exit 1
fi

mkdir -p "$APPICON" "$WORDMARKSET"
cp "$ICON" "$APPICON/AppIcon-1024.png"
cp "$WORDMARK" "$WORDMARKSET/HALO-Wordmark.png"

cat > "$ASSETS/Contents.json" <<'JSON'
{
  "info" : {
    "author" : "xcode",
    "version" : 1
  }
}
JSON

cat > "$APPICON/Contents.json" <<'JSON'
{
  "images" : [
    {
      "filename" : "AppIcon-1024.png",
      "idiom" : "universal",
      "platform" : "ios",
      "size" : "1024x1024"
    }
  ],
  "info" : {
    "author" : "xcode",
    "version" : 1
  }
}
JSON

cat > "$WORDMARKSET/Contents.json" <<'JSON'
{
  "images" : [
    {
      "filename" : "HALO-Wordmark.png",
      "idiom" : "universal",
      "scale" : "1x"
    },
    {
      "idiom" : "universal",
      "scale" : "2x"
    },
    {
      "idiom" : "universal",
      "scale" : "3x"
    }
  ],
  "info" : {
    "author" : "xcode",
    "version" : 1
  }
}
JSON

echo "HALO iOS brand assets installed:"
echo "  $APPICON/AppIcon-1024.png"
echo "  $WORDMARKSET/HALO-Wordmark.png"

#!/usr/bin/env bash
# Install the UNMODIFIED original HALO wing PNG exported from the approved Figma file.
# Source: https://www.figma.com/design/tsF6XdJRXjS7gTiCGYt4v5
# Figma screen 73: Open Jobs · Map, original wing image layer (node 8:5).
set -Eeuo pipefail
source_png="${1:-}"
[[ -n "$source_png" && -f "$source_png" ]] || {
  echo "Usage: bash NativeiOS/install-figma-marketplace-wing.sh /path/to/original-HALO-wing.png" >&2
  exit 1
}
if ! file -b "$source_png" | grep -q 'PNG image data'; then
  echo "Expected the original unaltered Figma-exported PNG artwork" >&2
  exit 1
fi
root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
imageset="$root/HaloField/Assets.xcassets/HALOWing.imageset"
mkdir -p "$imageset"
cp -- "$source_png" "$imageset/HALO-Wing.png"
cat > "$imageset/Contents.json" <<'JSON'
{
  "images": [
    {
      "filename": "HALO-Wing.png",
      "idiom": "universal"
    }
  ],
  "info": {
    "author": "xcode",
    "version": 1
  }
}
JSON
echo "Installed original wing asset in $imageset. Regenerate NativeiOS/HaloField.xcodeproj with XcodeGen."

#!/usr/bin/env bash
# Generate the macOS AppIcon set from a single source PNG.
#
# Apple wants 10 PNG variants:
#   16x16, 16x16@2x (=32),  32x32, 32x32@2x (=64),
#   128x128, 128x128@2x (=256),  256x256, 256x256@2x (=512),
#   512x512, 512x512@2x (=1024)
#
# We use `sips` (built into macOS) to resample. For best edges, keep your
# source at 1024x1024 with a transparent background.
#
# Usage:  ./scripts/generate-icons.sh                    (default source)
#         ./scripts/generate-icons.sh path/to/source.png
#
# Default source: Erudite/icon-source.png — checked into git as the
# canonical icon master so anyone can regenerate without losing fidelity.
# (Lives outside the Xcode synchronized folder so actool won't try to
# bundle it as a stray asset.)
#
# Output: overwrites Erudite/Erudite/Assets.xcassets/AppIcon.appiconset/*.png
#         and rewrites Contents.json with explicit `filename` fields so
#         Xcode picks them up.

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SRC="${1:-${ROOT}/Erudite/icon-source.png}"
if [[ ! -f "$SRC" ]]; then
  echo "Source PNG not found: $SRC" >&2
  echo "Usage: $0 [source.png]   (default: Erudite/icon-source.png)" >&2
  exit 1
fi

ICONSET="${ROOT}/Erudite/Erudite/Assets.xcassets/AppIcon.appiconset"
[[ -d "$ICONSET" ]] || { echo "Iconset dir not found: $ICONSET" >&2; exit 1; }

echo "▶ Source: $SRC ($(sips -g pixelWidth -g pixelHeight "$SRC" | awk '/pixel/ {print $2}' | xargs))"
echo "▶ Target: $ICONSET"

# Each Contents.json entry needs its OWN filename — sharing names across
# entries causes Xcode's actool to deduplicate, dropping sizes from the
# compiled AppIcon.icns. We name files by their (size_pt, scale_x) pair
# so 16@2x and 32@1x get separate files even though both are 32px.
SPECS=(
  # size_pt scale  filename
  "16  1  icon_16x16.png"
  "16  2  icon_16x16@2x.png"
  "32  1  icon_32x32.png"
  "32  2  icon_32x32@2x.png"
  "128 1  icon_128x128.png"
  "128 2  icon_128x128@2x.png"
  "256 1  icon_256x256.png"
  "256 2  icon_256x256@2x.png"
  "512 1  icon_512x512.png"
  "512 2  icon_512x512@2x.png"
)

# Wipe stale PNGs, keep Contents.json (we'll rewrite it).
find "$ICONSET" -maxdepth 1 -name "*.png" -delete

for spec in "${SPECS[@]}"; do
  read -r pt scale name <<<"$spec"
  px=$(( pt * scale ))
  out="${ICONSET}/${name}"
  # Two passes for crisp downscale:
  #   1. resampleHeightWidth so we always hit the exact pixel target
  #   2. cropToHeightWidth to defeat any 1px rounding artifact
  sips -s format png \
       --resampleHeightWidth "$px" "$px" \
       --cropToHeightWidth "$px" "$px" \
       "$SRC" --out "$out" >/dev/null
  echo "  ✓ ${pt}x${pt}@${scale}x  →  ${name}  (${px}px)"
done

# Rewrite Contents.json. Filenames are unique per entry.
cat > "${ICONSET}/Contents.json" <<'JSON'
{
  "images" : [
    { "idiom" : "mac", "scale" : "1x", "size" : "16x16",   "filename" : "icon_16x16.png" },
    { "idiom" : "mac", "scale" : "2x", "size" : "16x16",   "filename" : "icon_16x16@2x.png" },
    { "idiom" : "mac", "scale" : "1x", "size" : "32x32",   "filename" : "icon_32x32.png" },
    { "idiom" : "mac", "scale" : "2x", "size" : "32x32",   "filename" : "icon_32x32@2x.png" },
    { "idiom" : "mac", "scale" : "1x", "size" : "128x128", "filename" : "icon_128x128.png" },
    { "idiom" : "mac", "scale" : "2x", "size" : "128x128", "filename" : "icon_128x128@2x.png" },
    { "idiom" : "mac", "scale" : "1x", "size" : "256x256", "filename" : "icon_256x256.png" },
    { "idiom" : "mac", "scale" : "2x", "size" : "256x256", "filename" : "icon_256x256@2x.png" },
    { "idiom" : "mac", "scale" : "1x", "size" : "512x512", "filename" : "icon_512x512.png" },
    { "idiom" : "mac", "scale" : "2x", "size" : "512x512", "filename" : "icon_512x512@2x.png" }
  ],
  "info" : {
    "author" : "xcode",
    "version" : 1
  }
}
JSON

echo
echo "✓ Iconset generated. Rebuild the app (Xcode ⌘R or scripts/build-dmg.sh)"
echo "  to see the new icon."

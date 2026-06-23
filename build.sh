#!/usr/bin/env bash
# Panic: Arena — HTML5/PWA build helper.
#
# Exports the "Web" preset headlessly, then copies the PWA shell (custom
# index.html, manifest, service worker, icons) over Godot's generated files.
#
# Prereqs:
#   - Godot 4.6.3 on PATH as `godot` (or set GODOT=/path/to/godot).
#   - Web export templates installed (Editor > Manage Export Templates).
#
# Usage:  ./build.sh           (release)
#         ./build.sh debug
set -euo pipefail

GODOT="${GODOT:-godot}"
MODE="${1:-release}"
OUT="build/html5"

mkdir -p "$OUT"

echo "==> Exporting Web preset ($MODE) with $GODOT"
if [ "$MODE" = "debug" ]; then
  "$GODOT" --headless --export-debug "Web" "$OUT/index.html"
else
  "$GODOT" --headless --export-release "Web" "$OUT/index.html"
fi

echo "==> Overlaying PWA shell"
cp pwa/manifest.json "$OUT/manifest.json"
cp pwa/service-worker.js "$OUT/service-worker.js"
mkdir -p "$OUT/icons"
cp -f pwa/icons/*.png "$OUT/icons/" 2>/dev/null || echo "    (no PNG icons yet — add pwa/icons/icon-192.png + icon-512.png)"
# Use the custom shell only if you have merged the Godot loader into it;
# otherwise keep Godot's generated index.html. See README "Export".
# cp pwa/index.html "$OUT/index.html"

echo "==> Build size:"
du -sh "$OUT" 2>/dev/null || true
echo "==> Done. Serve with:  python -m http.server 8000 --directory $OUT"

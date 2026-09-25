#!/usr/bin/env bash
# Fetch the official Fujifilm F-Log2 -> Film Simulation LUTs and place the ones
# this project uses into research/luts/official/ and ios/FilmSim/LUTs/.
#
# The 10 film-simulation LUTs are only shipped in the GFX ETERNA 55 package
# (the X100VI package contains ETERNA / ETERNA-BB / WDR only).
# Source page: https://www.fujifilm-x.com/global/support/download/lut/
#
# Usage: scripts/fetch_luts.sh [--force]
set -euo pipefail

ZIP_URL="https://dl.fujifilm-x.com/support/lut/gfx-eterna-55-3d-lut-v110.zip"
ZIP_SHA256="febfc7050999620651ca0cf162bf8b499970ef270b4da632765b61b958cf7940"
GRID="65grid"
LUTS=(
  "FLog2_to_PROVIA_${GRID}_V.1.00.cube"
  "FLog2_to_CLASSIC-CHROME_${GRID}_V.1.00.cube"
)

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DESTS=("$ROOT/research/luts/official" "$ROOT/ios/FilmSim/LUTs")
FORCE="${1:-}"

all_present=true
for d in "${DESTS[@]}"; do
  for f in "${LUTS[@]}"; do
    [[ -f "$d/$f" ]] || all_present=false
  done
done
if $all_present && [[ "$FORCE" != "--force" ]]; then
  echo "fetch_luts: LUTs already present (use --force to re-download)"
  exit 0
fi

command -v curl >/dev/null || { echo "fetch_luts: curl not found" >&2; exit 1; }
command -v unzip >/dev/null || { echo "fetch_luts: unzip not found" >&2; exit 1; }

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

echo "fetch_luts: downloading $ZIP_URL"
curl -fsSL --retry 3 -o "$TMP/luts.zip" "$ZIP_URL"

if command -v shasum >/dev/null; then
  actual="$(shasum -a 256 "$TMP/luts.zip" | cut -d' ' -f1)"
else
  actual="$(sha256sum "$TMP/luts.zip" | cut -d' ' -f1)"
fi
if [[ "$actual" != "$ZIP_SHA256" ]]; then
  echo "fetch_luts: checksum mismatch (expected $ZIP_SHA256, got $actual)." >&2
  echo "            Fujifilm may have republished the package; inspect it and update ZIP_SHA256." >&2
  exit 1
fi

unzip -q -o "$TMP/luts.zip" -d "$TMP/x"
for d in "${DESTS[@]}"; do
  mkdir -p "$d"
  for f in "${LUTS[@]}"; do
    src="$(find "$TMP/x" -name "$f" | head -n1)"
    [[ -n "$src" ]] || { echo "fetch_luts: $f not found in archive" >&2; exit 1; }
    cp "$src" "$d/$f"
    echo "fetch_luts: -> $d/$f"
  done
done
echo "fetch_luts: done"

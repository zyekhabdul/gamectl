#!/usr/bin/env bash
# ==============================================================================
# gamectl - Module LOC Budget & Legacy Ratchet Guard (Packet R3A)
# Pure Bash builtins only (safe under minimal-PATH lint checks).
# ==============================================================================
set -euo pipefail

REPO_ROOT="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
DEFAULT_MAX_LOC=600

declare -A LEGACY_CEILING=(
    ["src/tui/70_dashboard.sh"]=1020
    ["src/steam/31_manifests.sh"]=989
    ["src/steam/35_fixes.sh"]=981
    ["src/runners/41_proton_prefix.sh"]=980
    ["src/core/10_utils.sh"]=959
    ["src/tui/71_previews.sh"]=891
    ["src/runners/50_launcher.sh"]=795
    ["src/runners/40_wrappers.sh"]=723
    ["src/steam/32_steam_bridge.sh"]=694
    ["src/main.sh"]=605
)

shopt -s nullglob
files=("$REPO_ROOT"/src/*/*.sh "$REPO_ROOT"/src/main.sh)
shopt -u nullglob

if [ "${#files[@]}" -eq 0 ]; then
    printf '[FAIL] No source modules found under %s/src\n' "$REPO_ROOT" >&2
    exit 1
fi

checked=0
violations=0
for file in "${files[@]}"; do
    [ -f "$file" ] || continue
    rel="${file#"$REPO_ROOT/"}"
    mapfile -t _lines < "$file"
    loc="${#_lines[@]}"
    limit="${LEGACY_CEILING[$rel]:-$DEFAULT_MAX_LOC}"
    if [ "$loc" -gt "$limit" ]; then
        printf '[FAIL] LOC budget exceeded: %s (%d > %d)\n' "$rel" "$loc" "$limit" >&2
        violations=$((violations + 1))
    fi
    checked=$((checked + 1))
done

if [ "$checked" -eq 0 ]; then
    printf '[FAIL] No source modules found under %s/src\n' "$REPO_ROOT" >&2
    exit 1
fi

if [ "$violations" -gt 0 ]; then
    printf '[FAIL] %d module(s) exceeded LOC budget.\n' "$violations" >&2
    exit 1
fi

printf '[PASS] Module LOC budget verified (%d modules checked; new cap <= %d)\n' "$checked" "$DEFAULT_MAX_LOC"

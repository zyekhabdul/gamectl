#!/usr/bin/env bash
# ==============================================================================
# gamectl - TUI Ergonomics & I/O Optimization Contract Tests (Packet 26)
# ==============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
GAMECTL="$REPO_ROOT/bin/gamectl"

# Ensure binary exists
if [ ! -f "$GAMECTL" ]; then
    echo "[ERROR] Target binary $GAMECTL not found. Run ./scripts/build.sh" >&2
    exit 1
fi

echo "=== [TEST] TUI Ergonomics & O(1) Instant ACF Size Resolution ==="

test_preview_game_acf_instant_size_resolution() {
    local t_dir
    t_dir=$(mktemp -d "${TMPDIR:-/tmp}/gamectl_acf_sz_XXXXXX")
    local t_game="$t_dir/ACFGame"
    mkdir -p "$t_game"

    # 1. ACF manifest with SizeOnDisk = 5368709120 (5.0 GB)
    cat <<EOF > "$t_game/appmanifest_99999.acf"
"AppState"
{
    "appid" "99999"
    "SizeOnDisk" "5368709120"
}
EOF
    local out1
    out1=$("$GAMECTL" --preview "99999" "ACFGame" "STANDALONE" "$t_game" "game.exe")
    if ! grep -q "Disk Size.*5.0 GB" <<< "$out1"; then
        echo "[FAIL] Expected 5.0 GB from ACF SizeOnDisk. Got:" >&2
        echo "$out1" >&2
        rm -rf "$t_dir"
        return 1
    fi
    echo "[PASS] O(1) Instant ACF SizeOnDisk resolution verified (5.0 GB)."

    # 2. Savegame size cache mtime check
    mkdir -p "$t_game/saves"
    echo "test_save" > "$t_game/saves/save1.dat"
    local out2
    out2=$("$GAMECTL" --preview "99999" "ACFGame" "STANDALONE" "$t_game" "game.exe")
    if ! grep -q "Save Path.*./saves" <<< "$out2"; then
        echo "[FAIL] Save Path ./saves not reported in preview." >&2
        rm -rf "$t_dir"
        return 1
    fi
    if [ ! -f "$t_game/saves/.size_cache" ]; then
        echo "[FAIL] Expected .size_cache to be created in ./saves." >&2
        rm -rf "$t_dir"
        return 1
    fi
    echo "[PASS] Savegame mtime cache (.size_cache) verified."

    rm -rf "$t_dir"
    return 0
}

test_preview_game_acf_instant_size_resolution
echo "[VERIFIED] All TUI Ergonomics contracts passed with exit code 0."

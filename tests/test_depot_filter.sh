#!/usr/bin/env bash
# ==============================================================================
# gamectl - Platform-Specific Depot Filtering Contract Tests (Packet 27)
# ==============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
GAMECTL="$REPO_ROOT/bin/gamectl"

# Source required modules
source "$REPO_ROOT/src/core/10_utils.sh"
source "$REPO_ROOT/src/steam/20_discovery.sh"
source "$REPO_ROOT/src/steam/30_downloader.sh"

echo "=== [TEST] Platform-Specific Depot Filtering (Chunk 27.01) ==="

test_parse_depot_os_map_contract() {
    local t_dir
    t_dir=$(mktemp -d "${TMPDIR:-/tmp}/gamectl_test_os_map_XXXXXX")
    mkdir -p "$t_dir/sub"
    cat <<'EOF' > "$t_dir/sub/test.json"
{
    "depot": {
        "101": { "config": { "oslist": "windows" } },
        "102": { "config": { "oslist": "linux" } },
        "103": { "config": { "oslist": "macos" } },
        "baselanguages": "english"
    }
}
EOF
    local map_out
    map_out=$(parse_depot_os_map "$t_dir")
    rm -rf "$t_dir"

    echo "$map_out" | grep -q '101=windows' || { echo "[FAIL] Missing 101=windows" >&2; return 1; }
    echo "$map_out" | grep -q '102=linux' || { echo "[FAIL] Missing 102=linux" >&2; return 1; }
    echo "$map_out" | grep -q '103=macos' || { echo "[FAIL] Missing 103=macos" >&2; return 1; }
    echo "[PASS] parse_depot_os_map correctly extracts depot oslist."
    return 0
}

test_download_game_os_filter_contracts() {
    local t_root
    t_root=$(mktemp -d "${TMPDIR:-/tmp}/gamectl_dl_os_test_XXXXXX")
    local t_cfg="$t_root/config"
    local t_cache="$t_root/cache"
    local t_target="$t_root/games/OSTestTitle"
    mkdir -p "$t_cfg/SLSsteam" "$t_cache/gamectl/manifests" "$t_target"
    echo "AppIds: []" > "$t_cfg/SLSsteam/config.yaml"

    export XDG_CONFIG_HOME="$t_cfg"
    export XDG_CACHE_HOME="$t_cache"

    # Setup mock zip for AppID 88881 with Windows (101), Linux (102), MacOS (103)
    local mock_zip="$t_cache/gamectl/manifests/88881.zip"
    local stage_dir="$t_root/stage"
    mkdir -p "$stage_dir"
    printf "\xd0\x17\xf6\x71test_payload_101" > "$stage_dir/101_1.manifest"
    printf "\xd0\x17\xf6\x71test_payload_102" > "$stage_dir/102_2.manifest"
    printf "\xd0\x17\xf6\x71test_payload_103" > "$stage_dir/103_3.manifest"
    cat <<'LUA' > "$stage_dir/88881.lua"
addappid(101, 1, "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef")
addappid(102, 1, "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef")
addappid(103, 1, "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef")
LUA
    cat <<'JSON' > "$stage_dir/88881.json"
{
    "depot": {
        "101": { "config": { "oslist": "windows" } },
        "102": { "config": { "oslist": "linux" } },
        "103": { "config": { "oslist": "macos" } }
    }
}
JSON
    (cd "$stage_dir" && zip -q "$mock_zip" 101_1.manifest 102_2.manifest 103_3.manifest 88881.lua 88881.json)

    # Mock runner that records invoked arguments
    local mock_bin="$t_root/mock-depot-dl"
    cat <<'MOCK' > "$mock_bin"
#!/usr/bin/env bash
echo "$@" >> "$TEST_ARGS_LOG"
exit 0
MOCK
    chmod +x "$mock_bin"
    export GAMECTL_DEPOT_DL_BIN="$mock_bin"

    inject_game() { return 0; }

    # Case 1: --os linux (must only include depot 102)
    export TEST_ARGS_LOG="$t_root/args_linux.log"
    local out_linux
    out_linux=$(download_game "88881" "$t_target" "OSTestTitle" --engine standalone --os linux)
    local rc_linux=$?
    [ "$rc_linux" -eq 0 ] || { echo "[FAIL] Case 1 returned $rc_linux" >&2; rm -rf "$t_root"; return 1; }
    grep -q '102_2.manifest' "$TEST_ARGS_LOG" || { echo "[FAIL] Case 1 missing 102" >&2; rm -rf "$t_root"; return 1; }
    ! grep -q '101_1.manifest' "$TEST_ARGS_LOG" || { echo "[FAIL] Case 1 included 101" >&2; rm -rf "$t_root"; return 1; }
    ! grep -q '103_3.manifest' "$TEST_ARGS_LOG" || { echo "[FAIL] Case 1 included 103" >&2; rm -rf "$t_root"; return 1; }
    echo "[PASS] --os linux filter verified."

    # Case 2: --os windows (must only include depot 101)
    export TEST_ARGS_LOG="$t_root/args_windows.log"
    local out_win
    out_win=$(download_game "88881" "$t_target" "OSTestTitle" --engine standalone --os windows)
    local rc_win=$?
    [ "$rc_win" -eq 0 ] || { echo "[FAIL] Case 2 returned $rc_win" >&2; rm -rf "$t_root"; return 1; }
    grep -q '101_1.manifest' "$TEST_ARGS_LOG" || { echo "[FAIL] Case 2 missing 101" >&2; rm -rf "$t_root"; return 1; }
    ! grep -q '102_2.manifest' "$TEST_ARGS_LOG" || { echo "[FAIL] Case 2 included 102" >&2; rm -rf "$t_root"; return 1; }
    ! grep -q '103_3.manifest' "$TEST_ARGS_LOG" || { echo "[FAIL] Case 2 included 103" >&2; rm -rf "$t_root"; return 1; }
    echo "[PASS] --os windows filter verified."

    # Case 3: Default auto-detect on Linux host (must auto-select Linux depot 102)
    export TEST_ARGS_LOG="$t_root/args_auto.log"
    local out_auto
    out_auto=$(download_game "88881" "$t_target" "OSTestTitle" --engine standalone)
    local rc_auto=$?
    [ "$rc_auto" -eq 0 ] || { echo "[FAIL] Case 3 returned $rc_auto" >&2; rm -rf "$t_root"; return 1; }
    grep -q '102_2.manifest' "$TEST_ARGS_LOG" || { echo "[FAIL] Case 3 missing 102" >&2; rm -rf "$t_root"; return 1; }
    ! grep -q '101_1.manifest' "$TEST_ARGS_LOG" || { echo "[FAIL] Case 3 included 101" >&2; rm -rf "$t_root"; return 1; }
    echo "[PASS] Default auto-detect Linux depot verified."

    # Case 4: Circuit breaker when filter rejects all candidate depots
    local mock_zip_cb="$t_cache/gamectl/manifests/88882.zip"
    local stage_cb="$t_root/stage_cb"
    mkdir -p "$stage_cb"
    printf "\xd0\x17\xf6\x71test_payload_101" > "$stage_cb/101_1.manifest"
    echo 'addappid(101, 1, "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef")' > "$stage_cb/88882.lua"
    cat <<'JSON' > "$stage_cb/88882.json"
{ "depot": { "101": { "config": { "oslist": "windows" } } } }
JSON
    (cd "$stage_cb" && zip -q "$mock_zip_cb" 101_1.manifest 88882.lua 88882.json)

    local out_cb
    out_cb=$(download_game "88882" "$t_target" "CBTitle" --engine standalone --os macos 2>&1 || true)
    echo "$out_cb" | grep -q 'All candidate depots were filtered out by target OS' || { echo "[FAIL] Circuit breaker did not trigger: $out_cb" >&2; rm -rf "$t_root"; return 1; }
    echo "[PASS] Circuit breaker rejected empty depot filter safely."

    rm -rf "$t_root"
    unset XDG_CONFIG_HOME XDG_CACHE_HOME GAMECTL_DEPOT_DL_BIN TEST_ARGS_LOG
    return 0
}

test_parse_depot_os_map_contract
test_download_game_os_filter_contracts
echo "=== [PASS] All Chunk 27.01 contract tests passed successfully with Exit 0. ==="

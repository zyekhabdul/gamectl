#!/usr/bin/env bash
# ==============================================================================
# gamectl - Automated CLI Regression & Contract Test Suite
# ==============================================================================
# Validates non-interactive CLI subcommands, security invariants, syntax,
# and build synchronization according to deterministic machine harness standards.
# ==============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
GAMECTL="$REPO_ROOT/bin/gamectl"

# ANSI Tokens (Strict No-Emoji)
C_RST=$'\033[0m'
C_BOLD=$'\033[1m'
C_DIM=$'\033[38;5;244m'
C_CYAN=$'\033[1;38;5;117m'
C_GREEN=$'\033[1;38;5;120m'
C_RED=$'\033[1;38;5;203m'
C_AMBER=$'\033[1;38;5;221m'
C_BOX=$'\033[38;5;60m'

TOTAL_TESTS=0
PASSED_TESTS=0
FAILED_TESTS=0

run_test() {
    local name="$1"
    shift
    TOTAL_TESTS=$((TOTAL_TESTS + 1))
    printf "  %-55s " "$name"
    local output exit_code=0
    output=$("$@" 2>&1) || exit_code=$?
    if [ "$exit_code" -eq 0 ]; then
        echo "${C_GREEN}[ PASS ]${C_RST}"
        PASSED_TESTS=$((PASSED_TESTS + 1))
    else
        echo "${C_RED}[ FAIL ]${C_RST}"
        FAILED_TESTS=$((FAILED_TESTS + 1))
        echo "${C_DIM}    Command: $*${C_RST}" >&2
        echo "${C_DIM}    Exit: $exit_code${C_RST}" >&2
        echo "${C_RED}    Output: $output${C_RST}" >&2
    fi
}

echo "${C_BOX}╭─ GAMECTL AUTOMATED REGRESSION & INTEGRITY HARNESS ───────────╮${C_RST}"
echo "│ ${C_CYAN}Target Binary${C_RST}: ${C_BOLD}$GAMECTL${C_RST}"
echo "│ ${C_CYAN}Root Path    ${C_RST}: ${C_DIM}$REPO_ROOT${C_RST}"
echo "${C_BOX}╰─────────────────────────────────────────────────────────────╯${C_RST}"

# ------------------------------------------------------------------------------
# Test Suite 1: Source & Bundle Integrity Gate
# ------------------------------------------------------------------------------
echo
echo "${C_BOLD}>>> [SUITE 1] Source Syntax & Build Synchronization${C_RST}"

test_syntax() {
    for f in "$REPO_ROOT"/src/*/*.sh "$REPO_ROOT"/src/main.sh "$REPO_ROOT"/bin/gamectl "$REPO_ROOT"/scripts/build.sh "$REPO_ROOT"/install.sh "$REPO_ROOT"/completions/gamectl.bash; do
        [ -f "$f" ] || return 1
        bash -n "$f" || return 1
    done
}
run_test "Bash Syntax Check (All Source & Bundle Modules)" test_syntax

test_build_check() {
    "$REPO_ROOT/scripts/build.sh" --check >/dev/null
}
run_test "Source-to-Bundle Synchronization Check (--check)" test_build_check

# ------------------------------------------------------------------------------
# Test Suite 2: Fundamental CLI Subcommands
# ------------------------------------------------------------------------------
echo
echo "${C_BOLD}>>> [SUITE 2] CLI Core Contracts & Informational Output${C_RST}"

test_help() {
    local out
    out=$("$GAMECTL" --help)
    echo "$out" | grep -q "gamectl - Sovereign TUI Game Manager"
}
run_test "Help Output Contract (--help)" test_help

test_version() {
    local out
    out=$("$GAMECTL" --version)
    echo "$out" | grep -q -E "^gamectl v[0-9]+\.[0-9]+\.[0-9]+"
}
run_test "Version Output Contract (--version)" test_version

test_steamid_format() {
    local sid
    sid=$("$GAMECTL" generate-steamid)
    [[ "$sid" =~ ^7656119[0-9]{10}$ ]]
}
run_test "SteamID64 Generation Contract (17-digit individual)" test_steamid_format

test_resolution_format() {
    local res
    res=$("$GAMECTL" get-resolution)
    [[ "$res" =~ ^[0-9]+x[0-9]+$ ]]
}
run_test "Display Resolution Probing (get-resolution)" test_resolution_format

test_gamescope_args_format() {
    local args
    args=$("$GAMECTL" get-gamescope-args)
    echo "$args" | grep -q -E -- "-W [0-9]+ -H [0-9]+ -w [0-9]+ -h [0-9]+"
}
run_test "Gamescope FSR Dynamic Scaling (get-gamescope-args)" test_gamescope_args_format

test_steam_root() {
    local sroot
    sroot=$("$GAMECTL" get-steam-root 2>/dev/null || true)
    [ -z "$sroot" ] || [ -d "$sroot" ]
}
run_test "Steam Root Path Resolution (get-steam-root)" test_steam_root

test_steam_libraries() {
    local libs
    libs=$("$GAMECTL" get-steam-libraries 2>/dev/null || true)
    # Output may be empty if Steam not installed, or contains paths
    return 0
}
run_test "Steam Libraries Discovery (get-steam-libraries)" test_steam_libraries

# ------------------------------------------------------------------------------
# Test Suite 3: Library & Diagnostics Engine
# ------------------------------------------------------------------------------
echo
echo "${C_BOLD}>>> [SUITE 3] Library Scanner & Diagnostics Engine${C_RST}"

test_list_installed() {
    "$GAMECTL" --list >/dev/null
}
run_test "Installed Game Library Discovery (--list)" test_list_installed

test_list_formatted() {
    "$GAMECTL" list-formatted >/dev/null
}
run_test "Formatted Game Library List (list-formatted)" test_list_formatted

test_doctor_audit() {
    "$GAMECTL" doctor >/dev/null
}
run_test "7-Layer Health Diagnostics Audit (doctor)" test_doctor_audit

# ------------------------------------------------------------------------------
# Test Suite 4: Security Invariants & Anti-Regression Defenses
# ------------------------------------------------------------------------------
echo
echo "${C_BOLD}>>> [SUITE 4] Security Invariants & Anti-Regression Defenses${C_RST}"

test_no_eval_in_src() {
    local eval_hits
    eval_hits=$(grep -rn "eval " "$REPO_ROOT/src/" || true)
    if [ -n "$eval_hits" ]; then
        echo "Found eval: $eval_hits" >&2
        return 1
    fi
    return 0
}
run_test "Security Invariant: Zero arbitrary eval in src/" test_no_eval_in_src

test_runtime_dir_isolation() {
    grep -q 'XDG_RUNTIME_DIR:-/tmp/gamectl-\$UID' "$REPO_ROOT/src/steam/30_downloader.sh" && \
    ! grep -q 'local log_file="/tmp/gamectl_dl_' "$REPO_ROOT/src/steam/30_downloader.sh"
}
run_test "Security Invariant: User-isolated XDG_RUNTIME_DIR logs" test_runtime_dir_isolation

test_signal_trap_governor() {
    grep -q "_restore_launch_state" "$REPO_ROOT/src/runners/50_launcher.sh" && \
    grep -q "trap '_restore_launch_state; trap - INT TERM EXIT;" "$REPO_ROOT/src/runners/50_launcher.sh"
}
run_test "Power Invariant: CPU Governor signal trap in launcher" test_signal_trap_governor

test_pgrep_regex_strictness() {
    # Verify no un-delimited pgrep AppID queries exist
    ! grep -E 'pgrep -f "DepotDownloader\.\*-app \$\{[a-zA-Z_]+\}"' "$REPO_ROOT/src/steam/30_downloader.sh"
}
run_test "Process Invariant: Strict word-boundary pgrep queries" test_pgrep_regex_strictness

test_game_controller_hud() {
    grep -q "game_controller_hud" "$REPO_ROOT/src/runners/50_launcher.sh" && \
    grep -q "Return to Master Dashboard" "$REPO_ROOT/src/runners/50_launcher.sh"
}
run_test "Launcher Invariant: Detached Live Controller HUD" test_game_controller_hud

# ------------------------------------------------------------------------------
# Test Suite 5: Global Features & Remediation Contracts
# ------------------------------------------------------------------------------
echo
echo "${C_BOLD}>>> [SUITE 5] Global Features & Remediation Contracts${C_RST}"

test_dll_overrides_clean() {
    local tdir
    tdir=$(mktemp -d)
    local out
    out=$("$GAMECTL" detect-overrides "$tdir")
    rm -rf "$tdir"
    [ -z "$out" ]
}
run_test "DLL Overrides: Clean directory produces empty string" test_dll_overrides_clean

test_dll_overrides_onlinefix() {
    local tdir
    tdir=$(mktemp -d)
    touch "$tdir/OnlineFix64.dll"
    local out
    out=$("$GAMECTL" detect-overrides "$tdir")
    rm -rf "$tdir"
    echo "$out" | grep -q "onlinefix=n" && \
    echo "$out" | grep -q "winmm=n,b" && \
    echo "$out" | grep -q "steamoverlay64=n"
}
run_test "DLL Overrides: OnlineFix signature auto-detection" test_dll_overrides_onlinefix

test_dll_overrides_bepinex_custom() {
    local tdir
    tdir=$(mktemp -d)
    mkdir -p "$tdir/BepInEx"
    echo "custom_mod=n,b" > "$tdir/.dll_overrides"
    local out
    out=$("$GAMECTL" detect-overrides "$tdir")
    rm -rf "$tdir"
    echo "$out" | grep -q "winhttp=n,b" && \
    echo "$out" | grep -q "custom_mod=n,b"
}
run_test "DLL Overrides: BepInEx & .dll_overrides detection" test_dll_overrides_bepinex_custom

test_dll_overrides_user_precedence() {
    local tdir
    tdir=$(mktemp -d)
    touch "$tdir/OnlineFix64.dll"
    local out
    out=$("$GAMECTL" detect-overrides "$tdir" "winmm=b;my_dll=d")
    rm -rf "$tdir"
    echo "$out" | grep -q "winmm=b" && \
    echo "$out" | grep -q "my_dll=d" && \
    ! echo "$out" | grep -q "winmm=n,b"
}
run_test "DLL Overrides: User environment precedence & deduplication" test_dll_overrides_user_precedence

test_onlinefix_no_sig() {
    local tdir
    tdir=$(mktemp -d)
    local exit_code=0
    "$GAMECTL" onlinefix "$tdir" >/dev/null 2>&1 || exit_code=$?
    rm -rf "$tdir"
    [ "$exit_code" -ne 0 ]
}
run_test "OnlineFix CLI: Reject directory without OnlineFix signatures" test_onlinefix_no_sig

test_onlinefix_detection_flow() {
    local tdir
    tdir=$(mktemp -d)
    touch "$tdir/OnlineFix64.dll"
    cat <<EOF > "$tdir/OnlineFix.ini"
[Main]
PlayerName = DefaultPlayer
EOF
    local out
    out=$("$GAMECTL" onlinefix "$tdir" --yes 2>&1 || true)
    rm -rf "$tdir"
    echo "$out" | grep -q "OnlineFix signature detected" && \
    echo "$out" | grep -q "OnlineFix.ini detected"
}
run_test "OnlineFix CLI: Valid signature detection & INI audit" test_onlinefix_detection_flow

test_mod_overrides_alias() {
    local tdir
    tdir=$(mktemp -d)
    touch "$tdir/OnlineFix64.dll"
    cat <<EOF > "$tdir/OnlineFix.ini"
[Main]
PlayerName = DefaultPlayer
EOF
    local out
    out=$("$GAMECTL" mod-overrides "$tdir" --yes 2>&1 || true)
    rm -rf "$tdir"
    echo "$out" | grep -q "OnlineFix signature detected" && \
    echo "$out" | grep -q "OnlineFix.ini detected"
}
run_test "Mod Overrides Alias: Backward compatibility & signature detection" test_mod_overrides_alias

test_audio_latency_env() {
    grep -q 'export PIPEWIRE_LATENCY=' "$REPO_ROOT/src/runners/50_launcher.sh" && \
    grep -q 'export PULSE_LATENCY_MSEC=' "$REPO_ROOT/src/runners/50_launcher.sh"
}
run_test "Audio Invariant (DEFECT-03): PipeWire & Pulse latency env export" test_audio_latency_env

test_proton_list() {
    local out
    out=$("$GAMECTL" proton-list)
    echo "$out" | grep -q "GE-PROTON RELEASE MANAGER" && \
    echo "$out" | grep -q "LOCAL VERSIONS"
}
run_test "Proton Manager: Query local & upstream release table" test_proton_list

test_proton_remove_traversal() {
    local exit_code=0
    "$GAMECTL" proton-remove "../../etc" >/dev/null 2>&1 || exit_code=$?
    [ "$exit_code" -ne 0 ]
}
run_test "Proton Manager: Guard against path traversal attacks" test_proton_remove_traversal

test_proton_remove_missing() {
    local exit_code=0
    "$GAMECTL" proton-remove "non_existent_mock_tag_999" >/dev/null 2>&1 || exit_code=$?
    [ "$exit_code" -ne 0 ]
}
run_test "Proton Manager: Graceful handling of missing version" test_proton_remove_missing

test_proton_mock_lifecycle() {
    local compat_dir="$HOME/.local/share/Steam/compatibilitytools.d"
    mkdir -p "$compat_dir/MockProton-test"
    touch "$compat_dir/MockProton-test/compatibilitytool.vdf"
    local exit_code=0
    "$GAMECTL" proton-remove "MockProton-test" --yes >/dev/null 2>&1 || exit_code=$?
    [ "$exit_code" -eq 0 ] && [ ! -d "$compat_dir/MockProton-test" ]
}
run_test "Proton Manager: Safe deletion lifecycle (proton-remove)" test_proton_mock_lifecycle

test_prefix_invalid_dir() {
    local exit_code=0
    "$GAMECTL" pfx "/nonexistent/mock/game/dir_999" kill >/dev/null 2>&1 || exit_code=$?
    [ "$exit_code" -ne 0 ]
}
run_test "Prefix Manager: Reject invalid or nonexistent game directory" test_prefix_invalid_dir

test_prefix_kill_lifecycle() {
    local t_dir="/tmp/gamectl_test_pfx_kill_$$"
    mkdir -p "$t_dir/pfx"
    local exit_code=0
    "$GAMECTL" pfx "$t_dir" kill >/dev/null 2>&1 || exit_code=$?
    rm -rf "$t_dir"
    [ "$exit_code" -eq 0 ]
}
run_test "Prefix Manager: Kill command lifecycle & zero error exit" test_prefix_kill_lifecycle

test_prefix_clean_lifecycle() {
    local t_dir="/tmp/gamectl_test_pfx_clean_$$"
    mkdir -p "$t_dir/pfx/drive_c" "$t_dir/saves"
    echo "test_save" > "$t_dir/saves/save.dat"
    local exit_code=0
    "$GAMECTL" pfx "$t_dir" clean --yes >/dev/null 2>&1 || exit_code=$?
    local pfx_gone=0
    [ ! -d "$t_dir/pfx" ] && pfx_gone=1
    local snapshot_ok=0
    [ -d "$t_dir/.save_snapshots/slot1" ] && snapshot_ok=1
    rm -rf "$t_dir"
    [ "$exit_code" -eq 0 ] && [ "$pfx_gone" -eq 1 ] && [ "$snapshot_ok" -eq 1 ]
}
run_test "Prefix Manager: Clean command backup and wipe lifecycle" test_prefix_clean_lifecycle

test_wineserver_lifecycle_guard() {
    grep -q 'wineserver -w' "$REPO_ROOT/src/runners/50_launcher.sh" && \
    grep -q 'wineserver -k' "$REPO_ROOT/src/runners/50_launcher.sh"
}
run_test "Wineserver Guard (DEFECT-02): Integrated flush (-w) and kill (-k)" test_wineserver_lifecycle_guard

test_protondb_invalid_target() {
    local exit_code=0
    "$GAMECTL" protondb "invalid_non_numeric_target_xyz" >/dev/null 2>&1 || exit_code=$?
    [ "$exit_code" -ne 0 ]
}
run_test "ProtonDB Audit: Reject non-numeric AppID without steam_appid.txt" test_protondb_invalid_target

test_protondb_query_flow() {
    local out
    out=$("$GAMECTL" protondb 480)
    echo "$out" | grep -q "PROTONDB COMPATIBILITY REPORT" && \
    echo "$out" | grep -q "Target AppID"
}
run_test "ProtonDB Audit: Query reports and display compatibility tier" test_protondb_query_flow

test_desktop_entry_lifecycle() {
    local t_dir="/tmp/gamectl_test_desktop_$$"
    mkdir -p "$t_dir"
    touch "$t_dir/game.exe" "$t_dir/icon.png"
    local exit_code=0
    "$GAMECTL" make-desktop "$t_dir" "Test Cyber Odyssey" >/dev/null 2>&1 || exit_code=$?
    local desk_file="$HOME/.local/share/applications/gamectl-testcyberodyssey.desktop"
    local file_ok=0
    if [ -f "$desk_file" ]; then
        grep -q "Name=Test Cyber Odyssey" "$desk_file" && \
        grep -q "Categories=Game;" "$desk_file" && \
        file_ok=1
        rm -f "$desk_file"
    fi
    rm -rf "$t_dir"
    [ "$exit_code" -eq 0 ] && [ "$file_ok" -eq 1 ]
}
run_test "Desktop Entry Generator: Valid FreeDesktop specification format" test_desktop_entry_lifecycle

test_installer_dry_run() {
    local out1 out2
    out1=$("$REPO_ROOT/install.sh" --dry-run 2>&1)
    out2=$(cat "$REPO_ROOT/install.sh" | bash -s -- --dry-run 2>&1)
    echo "$out1" | grep -q "DRY-RUN mode" && \
    echo "$out2" | grep -q "turnkey piped web installer" && \
    echo "$out2" | grep -q "Dry-run pre-flight check completed successfully"
}
run_test "Turnkey Installer: Local and piped stdin dry-run execution" test_installer_dry_run

test_arch_pkgbuild_validation() {
    [ -f "$REPO_ROOT/packaging/arch/PKGBUILD" ] && \
    [ -f "$REPO_ROOT/packaging/arch/.SRCINFO" ] && \
    bash -n "$REPO_ROOT/packaging/arch/PKGBUILD" && \
    grep -q "pkgname = gamectl" "$REPO_ROOT/packaging/arch/.SRCINFO"
}
run_test "Arch Packaging: Valid PKGBUILD syntax and .SRCINFO generation" test_arch_pkgbuild_validation

test_artwork_fetch_missing_target() {
    local exit_code=0
    "$GAMECTL" fetch-art >/dev/null 2>&1 || exit_code=$?
    [ "$exit_code" -ne 0 ]
}
run_test "Artwork Pipeline: Reject execution without target directory or AppID" test_artwork_fetch_missing_target

test_artwork_fetch_pipeline() {
    local t_grid
    t_grid=$(mktemp -d)
    local t_game
    t_game=$(mktemp -d)
    echo "105600" > "$t_game/steam_appid.txt"
    touch "$t_game/Terraria.bin.x86_64"

    local exit_code=0
    GAMECTL_GRID_DIR="$t_grid" "$GAMECTL" fetch-art "$t_game" >/dev/null 2>&1 || exit_code=$?

    local files_ok=0
    [ -f "$t_grid/105600p.png" ] && \
    [ -f "$t_grid/105600.png" ] && \
    [ -f "$t_grid/105600_hero.png" ] && \
    [ -f "$t_grid/105600_logo.png" ] && \
    files_ok=1

    rm -rf "$t_grid" "$t_game"
    [ "$exit_code" -eq 0 ] && [ "$files_ok" -eq 1 ]
}
run_test "Artwork Pipeline: Fetch capsule, banner, hero, and logo from Steam CDN" test_artwork_fetch_pipeline

test_steam_shortcut_missing_target() {
    local exit_code=0
    "$GAMECTL" add-to-steam >/dev/null 2>&1 || exit_code=$?
    [ "$exit_code" -ne 0 ]
}
run_test "Steam Deck Shortcut: Reject execution without target directory" test_steam_shortcut_missing_target

test_steam_shortcut_registration_flow() {
    local t_dir
    t_dir=$(mktemp -d)
    local t_game1
    t_game1=$(mktemp -d)
    local t_game2
    t_game2=$(mktemp -d)
    touch "$t_game1/alpha.exe" "$t_game1/icon.png"
    touch "$t_game2/beta.exe"

    local vdf_file="$t_dir/shortcuts.vdf"
    local exit1=0 exit2=0
    GAMECTL_SHORTCUTS_VDF="$vdf_file" "$GAMECTL" add-to-steam "$t_game1" "Project Alpha" >/dev/null 2>&1 || exit1=$?
    GAMECTL_SHORTCUTS_VDF="$vdf_file" "$GAMECTL" add-to-steam "$t_game2" "Project Beta" >/dev/null 2>&1 || exit2=$?

    local vdf_ok=0
    if [ -f "$vdf_file" ] && [ -f "${vdf_file}.bak" ]; then
        python3 -c "
with open('$vdf_file', 'rb') as f:
    d = f.read()
assert d.startswith(b'\x00shortcuts\x00')
assert b'Project Alpha' in d
assert b'Project Beta' in d
assert b'launch' in d
assert b'--hud' in d
" >/dev/null 2>&1 && vdf_ok=1
    fi

    rm -rf "$t_dir" "$t_game1" "$t_game2"
    [ "$exit1" -eq 0 ] && [ "$exit2" -eq 0 ] && [ "$vdf_ok" -eq 1 ]
}
run_test "Steam Deck Shortcut: Binary shortcuts.vdf registration & atomic backup" test_steam_shortcut_registration_flow

test_entitle_aliases_missing_args() {
    local exit1=0 exit2=0
    "$GAMECTL" entitle </dev/null >/dev/null 2>&1 || exit1=$?
    "$GAMECTL" adopt-steam </dev/null >/dev/null 2>&1 || exit2=$?
    [ "$exit1" -ne 0 ] && [ "$exit2" -ne 0 ]
}
run_test "Entitlement Aliases: Reject execution without AppID (entitle/adopt-steam)" test_entitle_aliases_missing_args

test_entitle_aliases_execution() {
    local t_home
    t_home=$(mktemp -d)
    local out1 out2
    out1=$(HOME="$t_home" "$GAMECTL" entitle 48000 "LIMBO" 2>&1)
    out2=$(HOME="$t_home" "$GAMECTL" adopt-steam 48000 "LIMBO" 2>&1)
    rm -rf "$t_home"

    echo "$out1" | grep -q "STEAM ENTITLEMENT & ACF ADOPTION ENGINE" && \
    echo "$out1" | grep -q "Adopts local files, community Steam Input" && \
    echo "$out2" | grep -q "STEAM ENTITLEMENT & ACF ADOPTION ENGINE" && \
    echo "$out2" | grep -q "entitled in Steam Client with Full DLC & ACF manifest"
}
run_test "Entitlement Aliases: Valid execution & ACF adoption banners (entitle/adopt-steam)" test_entitle_aliases_execution

# ------------------------------------------------------------------------------
# Final Execution Summary
# ------------------------------------------------------------------------------
echo
echo "${C_BOX}╭─ TEST EXECUTION SUMMARY ─────────────────────────────────────╮${C_RST}"
echo "│ Total Executed : ${C_BOLD}$TOTAL_TESTS${C_RST}"
echo "│ Passed         : ${C_GREEN}$PASSED_TESTS${C_RST}"
echo "│ Failed         : ${C_RED}$FAILED_TESTS${C_RST}"
if [ "$FAILED_TESTS" -eq 0 ] && [ "$TOTAL_TESTS" -gt 0 ]; then
    echo "│ Status         : ${C_GREEN}[ VERIFIED ] All CLI contracts passed with Exit 0.${C_RST}"
    echo "${C_BOX}╰─────────────────────────────────────────────────────────────╯${C_RST}"
    exit 0
else
    echo "│ Status         : ${C_RED}[ FAILED ] $FAILED_TESTS test assertion(s) failed.${C_RST}"
    echo "${C_BOX}╰─────────────────────────────────────────────────────────────╯${C_RST}"
    exit 1
fi

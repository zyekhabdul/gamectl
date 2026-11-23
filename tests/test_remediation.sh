#!/bin/bash
# ==============================================================================
# gamectl Systemic Remediation & Architecture Regression Harness
# Chunk 1: Headless Engine Discipline & Subshell Execution Harness
# Chunk 2: Launcher Decoupling & In-Dashboard Process Management
# Chunk 3: Canonical TUI UI Primitives & Input Sanitization
# ==============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

C_RED=$'\033[1;31m'
C_GREEN=$'\033[1;32m'
C_BOLD=$'\033[1m'
C_RST=$'\033[0m'

TOTAL_TESTS=0
PASSED_TESTS=0
FAILED_TESTS=0

run_test() {
    local name="$1"
    shift
    TOTAL_TESTS=$((TOTAL_TESTS + 1))
    printf "  %-65s " "$name"
    local output exit_code=0
    output=$(eval "$@" 2>&1) || exit_code=$?
    if [ "$exit_code" -eq 0 ]; then
        echo "${C_GREEN}[ PASS ]${C_RST}"
        PASSED_TESTS=$((PASSED_TESTS + 1))
    else
        echo "${C_RED}[ FAIL ]${C_RST}"
        FAILED_TESTS=$((FAILED_TESTS + 1))
        echo "    Command: $*"
        echo "    Exit: $exit_code"
        [ -n "$output" ] && echo "    Output: $output"
    fi
}

echo "${C_BOLD}>>> [REMEDIATION HARNESS] Architecture Decoupling & Canonical Primitives${C_RST}"

test_launch_game_tui_silence_contract() {
    source "$REPO_ROOT/src/core/00_header.sh"
    source "$REPO_ROOT/src/core/10_utils.sh"
    source "$REPO_ROOT/src/steam/20_discovery.sh"
    source "$REPO_ROOT/src/runners/40_wrappers.sh"
    source "$REPO_ROOT/src/runners/50_launcher.sh"

    local t_dir="/tmp/test_tui_silence_$$"
    mkdir -p "$t_dir"
    cat <<'EOF' > "$t_dir/dummy.sh"
#!/bin/bash
sleep 2
EOF
    chmod +x "$t_dir/dummy.sh"

    local hud_called=0
    game_controller_hud() { hud_called=1; return 0; }

    local out
    out=$(GAMECTL_IN_ALT_SCREEN=1 launch_game "$t_dir" "dummy.sh" "TuiSilenceGame" 2>&1)
    local rc=$?

    pkill -f "$t_dir/dummy.sh" 2>/dev/null || true
    rm -rf "$t_dir"

    [ -z "$out" ] || return 1
    [ "$hud_called" -eq 0 ] || return 1
    [ "$rc" -eq 0 ] || return 1

    return 0
}
run_test "Launcher (Chunk 1): launch_game TUI stream silence and HUD bypass contract" test_launch_game_tui_silence_contract

test_tui_run_engine_contract() {
    source "$REPO_ROOT/src/core/00_header.sh"
    source "$REPO_ROOT/src/core/10_utils.sh"

    local log_file
    log_file="$(get_runtime_log_file)"
    mkdir -p "$(dirname "$log_file")"
    : > "$log_file"

    dummy_success() {
        echo "DUMMY_SUCCESS_STDOUT"
        return 0
    }

    local modal_flag="/tmp/modal_flag_$$"
    rm -f "$modal_flag"
    tui_modal_notice() { touch "$modal_flag"; return 0; }

    local out rc=0
    out=$(tui_run_engine "SuccessTask" dummy_success 2>&1) || rc=$?
    [ -z "$out" ] || { rm -f "$modal_flag"; return 1; }
    [ "$rc" -eq 0 ] || { rm -f "$modal_flag"; return 1; }
    grep -q "DUMMY_SUCCESS_STDOUT" "$log_file" || { rm -f "$modal_flag"; return 1; }

    dummy_fail() {
        echo "CRITICAL_FAIL_TRACE" >&2
        return 42
    }
    local fail_rc=0
    tui_run_engine "FailureTask" dummy_fail >/dev/null 2>&1 || fail_rc=$?
    [ "$fail_rc" -eq 42 ] || { rm -f "$modal_flag"; return 1; }
    [ -f "$modal_flag" ] || { rm -f "$modal_flag"; return 1; }

    rm -f "$modal_flag"
    return 0
}
run_test "Utils (Chunk 1): tui_run_engine isolated execution and error capture contract" test_tui_run_engine_contract

test_launcher_decoupling_contract() {
    source "$REPO_ROOT/src/core/00_header.sh"
    source "$REPO_ROOT/src/core/10_utils.sh"
    source "$REPO_ROOT/src/steam/20_discovery.sh"
    source "$REPO_ROOT/src/runners/40_wrappers.sh"
    source "$REPO_ROOT/src/runners/50_launcher.sh"
    source "$REPO_ROOT/src/tui/70_dashboard.sh"

    local orig_xdg="${XDG_RUNTIME_DIR:-}"
    local t_dir="/tmp/test_decouple_$$"
    mkdir -p "$t_dir/runtime"
    export XDG_RUNTIME_DIR="$t_dir/runtime"

    cat <<'EOF' > "$t_dir/dummy.sh"
#!/bin/bash
sleep 2
EOF
    chmod +x "$t_dir/dummy.sh"

    local hud_called=0
    game_controller_hud() { hud_called=1; return 0; }

    local rc=0
    GAMECTL_IN_ALT_SCREEN=0 launch_game "$t_dir" "dummy.sh" "DecoupleTestGame" >/dev/null 2>&1 || rc=$?
    if [ "$rc" -ne 0 ] || [ "$hud_called" -ne 0 ] || [ -z "${GAMECTL_LAST_LAUNCH_PID:-}" ]; then
        pkill -f "$t_dir/dummy.sh" 2>/dev/null || true
        rm -rf "$t_dir"
        [ -n "$orig_xdg" ] && export XDG_RUNTIME_DIR="$orig_xdg" || unset XDG_RUNTIME_DIR
        return 1
    fi

    local run_dir
    run_dir="$(get_runtime_dir)"
    if [ ! -f "$run_dir/active_games/${GAMECTL_LAST_LAUNCH_PID}.info" ]; then
        pkill -f "$t_dir/dummy.sh" 2>/dev/null || true
        rm -rf "$t_dir"
        [ -n "$orig_xdg" ] && export XDG_RUNTIME_DIR="$orig_xdg" || unset XDG_RUNTIME_DIR
        return 1
    fi

    manage_active_processes_interactive
    local hud_res=$hud_called

    pkill -f "$t_dir/dummy.sh" 2>/dev/null || true
    rm -rf "$t_dir"
    [ -n "$orig_xdg" ] && export XDG_RUNTIME_DIR="$orig_xdg" || unset XDG_RUNTIME_DIR

    [ "$hud_res" -eq 1 ] || return 1
    return 0
}
run_test "Launcher (Chunk 2): launch_game headless decoupling & process controller routing contract" test_launcher_decoupling_contract

test_canonical_tui_primitives_contract() {
    source "$REPO_ROOT/src/core/00_header.sh"
    source "$REPO_ROOT/src/core/10_utils.sh"

    local input_val
    input_val=$(tui_prompt_input "Title" "Header" "default_123" < /dev/null 2>/dev/null)
    [ "$input_val" = "default_123" ] || return 1

    local notice_out
    notice_out=$(tui_modal_notice "Alert" "Line 1\nLine %s %n\n-e -n done" < /dev/null 2>/dev/null)
    local notice_rc=$?
    [ "$notice_rc" -eq 0 ] || return 1
    echo "$notice_out" | grep -q "Line %s %n" || return 1

    local pal_rc=0
    tui_action_palette "Menu" "Header" "item1	opt1" < /dev/null 2>/dev/null || pal_rc=$?
    [ "$pal_rc" -ne 0 ] || return 1

    return 0
}
run_test "Utils (Chunk 3): canonical FZF dialog primitives and sanitization contract" test_canonical_tui_primitives_contract

test_resolve_game_drm_status_contract() {
    source "$REPO_ROOT/src/core/00_header.sh"
    source "$REPO_ROOT/src/core/10_utils.sh"

    local t_dir="/tmp/test_drm_$$"
    mkdir -p "$t_dir"

    # Test 1: Non-existent directory returns STANDALONE
    [ "$(resolve_game_drm_status "$t_dir/non_existent")" = "STANDALONE" ] || { rm -rf "$t_dir"; return 1; }

    # Test 2: Clean directory without Steam API returns STANDALONE
    local g_clean="$t_dir/clean_game"
    mkdir -p "$g_clean"
    touch "$g_clean/game.exe"
    [ "$(resolve_game_drm_status "$g_clean")" = "STANDALONE" ] || { rm -rf "$t_dir"; return 1; }

    # Test 3: Official Valve DLL without emulator artifacts returns VALVE_DLL
    local g_valvedll="$t_dir/valvedll_game"
    mkdir -p "$g_valvedll"
    head -c 100000 /dev/zero > "$g_valvedll/steam_api64.dll"
    [ "$(resolve_game_drm_status "$g_valvedll")" = "VALVE_DLL" ] || { rm -rf "$t_dir"; return 1; }

    # Test 4: Official Valve SO without emulator artifacts returns VALVE_SO
    local g_valveso="$t_dir/valveso_game"
    mkdir -p "$g_valveso"
    head -c 100000 /dev/zero > "$g_valveso/libsteam_api.so"
    [ "$(resolve_game_drm_status "$g_valveso")" = "VALVE_SO" ] || { rm -rf "$t_dir"; return 1; }

    # Test 5: Large GBE binary (>7MB) returns GBE_FORK
    local g_gbe_large="$t_dir/gbe_large_game"
    mkdir -p "$g_gbe_large"
    head -c 7500000 /dev/zero > "$g_gbe_large/libsteam_api.so"
    [ "$(resolve_game_drm_status "$g_gbe_large")" = "GBE_FORK" ] || { rm -rf "$t_dir"; return 1; }

    # Test 6: Small binary with steam_settings directory returns GBE_FORK
    local g_gbe_settings="$t_dir/gbe_settings_game"
    mkdir -p "$g_gbe_settings/steam_settings"
    head -c 100000 /dev/zero > "$g_gbe_settings/steam_api64.dll"
    [ "$(resolve_game_drm_status "$g_gbe_settings")" = "GBE_FORK" ] || { rm -rf "$t_dir"; return 1; }

    # Test 7: Small binary with .orig backup returns GBE_FORK
    local g_gbe_orig="$t_dir/gbe_orig_game"
    mkdir -p "$g_gbe_orig"
    head -c 100000 /dev/zero > "$g_gbe_orig/steam_api64.dll"
    head -c 100000 /dev/zero > "$g_gbe_orig/steam_api64.dll.orig"
    [ "$(resolve_game_drm_status "$g_gbe_orig")" = "GBE_FORK" ] || { rm -rf "$t_dir"; return 1; }

    rm -rf "$t_dir"
    return 0
}
run_test "Utils (Chunk 4): resolve_game_drm_status canonical SSoT contract" test_resolve_game_drm_status_contract

test_trap_scope_isolation_and_tui_guard_contract() {
    source "$REPO_ROOT/src/core/00_header.sh"
    source "$REPO_ROOT/src/core/10_utils.sh"
    source "$REPO_ROOT/src/steam/20_discovery.sh"
    source "$REPO_ROOT/src/runners/40_wrappers.sh"
    source "$REPO_ROOT/src/runners/50_launcher.sh"

    # 1. Static guard: launch_game cleanup path disarms via _disarm_launch_traps, not bare trap -
    grep -q '_disarm_launch_traps' "$REPO_ROOT/src/runners/50_launcher.sh" || return 1
    ! grep -B1 -A1 'export PATH="\$prev_path"' "$REPO_ROOT/src/runners/50_launcher.sh" | grep -q 'trap - INT TERM EXIT' || return 1

    # 2. TUI trap preservation across in-process launch_game
    local trap_check_rc=0
    (
        set +e
        local orig_xdg="${XDG_RUNTIME_DIR:-}"
        local t_dir="/tmp/test_trap_iso_$$"
        mkdir -p "$t_dir/runtime"
        export XDG_RUNTIME_DIR="$t_dir/runtime"
        cat <<'EOF' > "$t_dir/dummy.sh"
#!/bin/bash
sleep 2
EOF
        chmod +x "$t_dir/dummy.sh"

        export GAMECTL_IN_ALT_SCREEN=1
        GAMECTL_TUI_OWNER_PID="${BASHPID:-$$}"
        install_tui_screen_traps

        launch_game "$t_dir" "dummy.sh" "TrapIsoGame" >/dev/null 2>&1 || true

        local t_exit t_int t_term
        t_exit=$(trap -p EXIT)
        t_int=$(trap -p INT)
        t_term=$(trap -p TERM)

        pkill -f "$t_dir/dummy.sh" 2>/dev/null || true
        rm -rf "$t_dir"
        [ -n "$orig_xdg" ] && export XDG_RUNTIME_DIR="$orig_xdg" || unset XDG_RUNTIME_DIR
        trap - EXIT INT TERM

        [[ "$t_exit" == *exit_tui_screen* ]] || exit 1
        [[ "$t_int" == *exit_tui_screen* ]] || exit 1
        [[ "$t_term" == *exit_tui_screen* ]] || exit 1
        exit 0
    ) || trap_check_rc=$?
    [ "$trap_check_rc" -eq 0 ] || return 1

    # 3. Single-owner subshell isolation: subshell cannot reset parent alt-screen state
    local sub_out="" sub_rc=0
    export GAMECTL_IN_ALT_SCREEN=1
    GAMECTL_TUI_OWNER_PID="${BASHPID:-$$}"
    sub_out=$( ( exit_tui_screen ) ) || sub_rc=$?
    [ "$sub_rc" -eq 0 ] || return 1
    [ -z "$sub_out" ] || return 1
    [ "${GAMECTL_IN_ALT_SCREEN:-0}" -eq 1 ] || return 1

    # 4. Re-entrant / idempotent teardown on owner shell
    exit_tui_screen || return 1
    [ "${GAMECTL_IN_ALT_SCREEN:-0}" -eq 0 ] || return 1
    exit_tui_screen || return 1
    [ "${GAMECTL_IN_ALT_SCREEN:-0}" -eq 0 ] || return 1

    # 5. Exit code preservation under EXIT trap
    local code_rc=0
    (
        set +e
        export GAMECTL_IN_ALT_SCREEN=1
        GAMECTL_TUI_OWNER_PID="${BASHPID:-$$}"
        install_tui_screen_traps
        exit 42
    ) || code_rc=$?
    [ "$code_rc" -eq 42 ] || return 1

    return 0
}
run_test "Lifecycle (Chunk 5): trap scope isolation and re-entrant TUI screen restoration guard" test_trap_scope_isolation_and_tui_guard_contract

test_dual_mode_runtime_paths_contract() {
    source "$REPO_ROOT/src/core/00_header.sh"
    source "$REPO_ROOT/src/core/10_utils.sh"
    source "$REPO_ROOT/src/runners/40_wrappers.sh"

    local orig_xdg="${XDG_RUNTIME_DIR:-}"
    local exp_uid="${UID:-$(id -u 2>/dev/null || echo 1000)}"

    # 1. Verify unset XDG_RUNTIME_DIR divergence: desktop -> /run/user/<uid>, app -> /tmp/gamectl-<uid>
    local d_unset a_unset
    d_unset=$(unset XDG_RUNTIME_DIR; get_desktop_runtime_dir)
    a_unset=$(unset XDG_RUNTIME_DIR; get_runtime_dir)
    [ "$d_unset" = "/run/user/$exp_uid" ] || return 1
    [ "$a_unset" = "/tmp/gamectl-$exp_uid" ] || return 1

    # 2. Verify custom XDG_RUNTIME_DIR propagation
    local t_dir
    t_dir=$(mktemp -d "${TMPDIR:-/tmp}/gamectl_rt_contract_XXXXXX")
    export XDG_RUNTIME_DIR="$t_dir/custom_xdg"
    local d_set a_set
    d_set=$(get_desktop_runtime_dir)
    a_set=$(get_runtime_dir)
    if [ "$d_set" != "$t_dir/custom_xdg" ] || [ "$a_set" != "$t_dir/custom_xdg" ] || [ ! -d "$t_dir/custom_xdg" ]; then
        rm -rf "$t_dir"
        [ -n "$orig_xdg" ] && export XDG_RUNTIME_DIR="$orig_xdg" || unset XDG_RUNTIME_DIR
        return 1
    fi

    # 3. Verify zero hardcoded /run/user/ outside canonical resolver get_desktop_runtime_dir
    if grep -rn "/run/user/" "$REPO_ROOT/src/runners/40_wrappers.sh" "$REPO_ROOT/src/steam/30_downloader.sh" | grep -q .; then
        rm -rf "$t_dir"
        [ -n "$orig_xdg" ] && export XDG_RUNTIME_DIR="$orig_xdg" || unset XDG_RUNTIME_DIR
        return 1
    fi

    # 4. Verify build_sandbox_command consumes desktop & app runtime resolvers cleanly
    mkdir -p "$t_dir/bin" "$t_dir/game"
    printf '#!/bin/sh\nexit 0\n' > "$t_dir/bin/bwrap"
    chmod +x "$t_dir/bin/bwrap"
    local sb_ok=0
    if PATH="$t_dir/bin:$PATH" build_sandbox_command "$t_dir/game"; then
        printf '%s\n' "${GAMECTL_SANDBOX_PREFIX[@]}" | grep -q -- "$t_dir/custom_xdg/pipewire-0" && sb_ok=1
    fi

    rm -rf "$t_dir"
    [ -n "$orig_xdg" ] && export XDG_RUNTIME_DIR="$orig_xdg" || unset XDG_RUNTIME_DIR
    [ "$sb_ok" -eq 1 ] || return 1
    return 0
}
run_test "Runtime SSoT (Chunk 6): dual-mode get_desktop_runtime_dir vs get_runtime_dir contract" test_dual_mode_runtime_paths_contract

test_tui_exec_action_preserves_errexit_contract() {
    # Verify inside real PTY (which exercises lines 526-531 interactive tee path) AND non-TTY fast-path
    python3 - "$REPO_ROOT" <<'PYEOF'
import errno, os, pty, select, subprocess, sys, time

repo_root = sys.argv[1]

def run_in_pty(cmd_str):
    pid, fd = pty.fork()
    if pid == 0:
        env = dict(os.environ, TERM="xterm-256color")
        os.execvpe("bash", ["bash", "-c", cmd_str], env)
    out = bytearray()
    deadline = time.monotonic() + 8
    status = None
    sent_enter = False
    while time.monotonic() < deadline:
        if select.select([fd], [], [], 0.05)[0]:
            try:
                chunk = os.read(fd, 65536)
            except OSError as e:
                if e.errno != errno.EIO:
                    raise
                chunk = b""
            out.extend(chunk)
        if b"Press Enter or Esc" in out and not sent_enter:
            time.sleep(0.12)
            os.write(fd, b"\n")
            sent_enter = True
        done, st = os.waitpid(pid, os.WNOHANG)
        if done:
            status = st
            break
    os.close(fd)
    if status is None:
        os.kill(pid, 9)
        os.waitpid(pid, 0)
        return 124, out.decode(errors="replace")
    rc = os.waitstatus_to_exitcode(status)
    return rc, out.decode(errors="replace")

# Case 1: set +e before tui_exec_action must remain set +e afterwards (even after false runs)
c1 = f'''set +e
source "{repo_root}/src/core/00_header.sh"
source "{repo_root}/src/core/10_utils.sh"
set +e
tui_exec_action "TestAction" true
[[ $- == *e* ]] && exit 99
false
true
exit 0
'''
rc1, out1 = run_in_pty(c1)
if rc1 != 0:
    sys.stderr.write(f"Case 1 failed (rc={rc1}): {out1}\n")
    sys.exit(1)

# Case 2: set -e before tui_exec_action must remain set -e afterwards
c2 = f'''set -e
source "{repo_root}/src/core/00_header.sh"
source "{repo_root}/src/core/10_utils.sh"
set -e
tui_exec_action "TestAction2" true
[[ $- == *e* ]] || exit 98
exit 0
'''
rc2, out2 = run_in_pty(c2)
if rc2 != 0:
    sys.stderr.write(f"Case 2 failed (rc={rc2}): {out2}\n")
    sys.exit(1)
sys.exit(0)
PYEOF
}
run_test "Stability (Audit 1): tui_exec_action preserves caller errexit state under PTY" test_tui_exec_action_preserves_errexit_contract

test_zero_arbitrary_fzf_heights_contract() {
    local hits
    hits=$(grep -rn -- '--height=' "$REPO_ROOT/src/core/" "$REPO_ROOT/src/steam/" "$REPO_ROOT/src/runners/" "$REPO_ROOT/src/tui/" || true)
    if [ -n "$hits" ]; then
        echo "Found remaining --height= flags:" >&2
        echo "$hits" >&2
        return 1
    fi
    return 0
}
run_test "UI Consistency (Audit 4): zero arbitrary --height flags across FZF views" test_zero_arbitrary_fzf_heights_contract

test_watchdog_fd_and_layer_isolation_contract() {
    # 1. Watchdog in launch_game redirects stdin/stdout/stderr to /dev/null
    grep -q ') </dev/null >/dev/null 2>&1 &' "$REPO_ROOT/src/runners/50_launcher.sh" || return 1

    # 2. library_menu does not pass launch_rc from tui_run_engine into check_fzf_status
    ! grep -A3 'tui_run_engine "Launch \$sel_title"' "$REPO_ROOT/src/tui/70_dashboard.sh" | grep -q 'check_fzf_status "\$launch_rc"' || return 1
    return 0
}
run_test "Stability (Audit 2 & 3): watchdog FD isolation & engine vs FZF error decoupling" test_watchdog_fd_and_layer_isolation_contract

test_graphics_capability_and_renderer_contract() {
    source "$REPO_ROOT/src/core/00_header.sh"
    source "$REPO_ROOT/src/core/10_utils.sh"
    source "$REPO_ROOT/src/runners/40_wrappers.sh"

    # 1. Host capability probe returns valid canonical token
    local host_cap
    host_cap="$(detect_vulkan_capability)"
    case "$host_cap" in
        VULKAN_READY|VULKAN_LEGACY|OPENGL_ONLY) ;;
        *) return 1 ;;
    esac

    # 2. Capability x mode x prime matrix verification
    [ "$(GAMECTL_VULKAN_CAPABILITY=VULKAN_READY resolve_graphics_renderer auto 0)" = "dxvk" ] || return 1
    [ "$(GAMECTL_VULKAN_CAPABILITY=VULKAN_LEGACY resolve_graphics_renderer auto 0)" = "wined3d" ] || return 1
    [ "$(GAMECTL_VULKAN_CAPABILITY=OPENGL_ONLY resolve_graphics_renderer auto 0)" = "wined3d" ] || return 1
    [ "$(GAMECTL_VULKAN_CAPABILITY=VULKAN_LEGACY resolve_graphics_renderer auto 1)" = "dxvk" ] || return 1
    [ "$(GAMECTL_VULKAN_CAPABILITY=VULKAN_LEGACY resolve_graphics_renderer dxvk 0)" = "dxvk" ] || return 1
    [ "$(GAMECTL_VULKAN_CAPABILITY=VULKAN_READY resolve_graphics_renderer wined3d 0)" = "wined3d" ] || return 1

    # 3. build_wrapper_command CLI flags and per-game .wrappers override
    local t_dir
    t_dir=$(mktemp -d "${TMPDIR:-/tmp}/gamectl_rend_XXXXXX")
    printf 'renderer=wined3d\n' > "$t_dir/.wrappers"

    HOME="$t_dir" GAMECTL_VULKAN_CAPABILITY=VULKAN_READY build_wrapper_command "$t_dir"
    [ "$GAMECTL_ACTIVE_RENDERER" = "wined3d" ] || { rm -rf "$t_dir"; return 1; }

    HOME="$t_dir" GAMECTL_VULKAN_CAPABILITY=VULKAN_READY build_wrapper_command "$t_dir" --dxvk
    [ "$GAMECTL_ACTIVE_RENDERER" = "dxvk" ] || { rm -rf "$t_dir"; return 1; }

    HOME="$t_dir" GAMECTL_VULKAN_CAPABILITY=VULKAN_READY build_wrapper_command "$t_dir" --wined3d
    [ "$GAMECTL_ACTIVE_RENDERER" = "wined3d" ] || { rm -rf "$t_dir"; return 1; }

    HOME="$t_dir" GAMECTL_VULKAN_CAPABILITY=VULKAN_READY build_wrapper_command "$t_dir" --renderer=dxvk
    [ "$GAMECTL_ACTIVE_RENDERER" = "dxvk" ] || { rm -rf "$t_dir"; return 1; }

    rm -rf "$t_dir"
    return 0
}
run_test "Graphics SSoT (WP30 Packet A): detect_vulkan_capability & resolve_graphics_renderer contract" test_graphics_capability_and_renderer_contract

test_proton_env_contract() {
    source "$REPO_ROOT/src/core/00_header.sh"
    source "$REPO_ROOT/src/core/10_utils.sh"
    source "$REPO_ROOT/src/steam/20_discovery.sh"
    source "$REPO_ROOT/src/runners/40_wrappers.sh"
    source "$REPO_ROOT/src/runners/50_launcher.sh"

    local orig_xdg="${XDG_RUNTIME_DIR:-}"
    local orig_pfd_set=0 orig_pfd=""
    if [ -n "${PROTONFIXES_DISABLE+x}" ]; then
        orig_pfd_set=1
        orig_pfd="$PROTONFIXES_DISABLE"
    fi
    unset PROTONFIXES_DISABLE

    local t_dir
    t_dir=$(mktemp -d "${TMPDIR:-/tmp}/gamectl_proton_env_XXXXXX")
    local g_dir="$t_dir/StandaloneWinGame"
    mkdir -p "$t_dir/runtime" "$g_dir/steam_settings"
    export XDG_RUNTIME_DIR="$t_dir/runtime"

    # Dummy PE executable + GBE shield marker
    printf 'MZ' > "$g_dir/game.exe"
    printf 'fake_dll' > "$g_dir/steam_api64.dll"
    chmod +x "$g_dir/game.exe"

    cat <<EOF > "$t_dir/mock-proton"
#!/usr/bin/env bash
cat <<ENVEOF > "$t_dir/env.out"
STEAM_COMPAT_APP_ID=\${STEAM_COMPAT_APP_ID:-}
SteamAppId=\${SteamAppId:-}
SteamGameId=\${SteamGameId:-}
GAMEID=\${GAMEID:-}
PROTON_USE_WINED3D=\${PROTON_USE_WINED3D:-}
PROTONFIXES_DISABLE=\${PROTONFIXES_DISABLE-UNSET}
ENVEOF
sleep 0.2
EOF
    chmod +x "$t_dir/mock-proton"

    find_runner() { echo "$t_dir/mock-proton"; }
    backup_save() { :; }
    clean_stale_locks() { :; }
    detect_steamstub_drm() { return 1; }
    check_systemd_scope_support() { return 1; }

    _restore_proton_env_test() {
        pkill -f "$t_dir/mock-proton" 2>/dev/null || true
        rm -rf "$t_dir"
        [ -n "$orig_xdg" ] && export XDG_RUNTIME_DIR="$orig_xdg" || unset XDG_RUNTIME_DIR
        if [ "$orig_pfd_set" -eq 1 ]; then
            export PROTONFIXES_DISABLE="$orig_pfd"
        else
            unset PROTONFIXES_DISABLE
        fi
    }

    # Case 1: Valid AppID in steam_appid.txt + VULKAN_LEGACY -> AppID propagated, PROTON_USE_WINED3D=1, PROTONFIXES_DISABLE unset
    echo "360740" > "$g_dir/steam_appid.txt"
    rm -f "$t_dir/env.out"
    HOME="$t_dir" GAMECTL_IN_ALT_SCREEN=1 GAMECTL_VULKAN_CAPABILITY=VULKAN_LEGACY \
        launch_game "$g_dir" "game.exe" "DownwellTest" >/dev/null 2>&1 || { _restore_proton_env_test; return 1; }
    for _ in $(seq 1 40); do
        [ -s "$t_dir/env.out" ] && break
        sleep 0.05
    done
    [ -s "$t_dir/env.out" ] || { _restore_proton_env_test; return 1; }
    grep -qx "STEAM_COMPAT_APP_ID=360740" "$t_dir/env.out" || { _restore_proton_env_test; return 1; }
    grep -qx "SteamAppId=360740" "$t_dir/env.out" || { _restore_proton_env_test; return 1; }
    grep -qx "SteamGameId=360740" "$t_dir/env.out" || { _restore_proton_env_test; return 1; }
    grep -qx "GAMEID=umu-360740" "$t_dir/env.out" || { _restore_proton_env_test; return 1; }
    grep -qx "PROTON_USE_WINED3D=1" "$t_dir/env.out" || { _restore_proton_env_test; return 1; }
    grep -qx "PROTONFIXES_DISABLE=UNSET" "$t_dir/env.out" || { _restore_proton_env_test; return 1; }
    wait "${GAMECTL_LAST_LAUNCH_PID:-}" 2>/dev/null || true

    # Case 2: No steam_appid.txt (appid=0) + VULKAN_READY -> umu-default, PROTON_USE_WINED3D=0, PROTONFIXES_DISABLE=1
    rm -f "$g_dir/steam_appid.txt" "$t_dir/env.out"
    HOME="$t_dir" GAMECTL_IN_ALT_SCREEN=1 GAMECTL_VULKAN_CAPABILITY=VULKAN_READY \
        launch_game "$g_dir" "game.exe" "NoAppIdTest" >/dev/null 2>&1 || { _restore_proton_env_test; return 1; }
    for _ in $(seq 1 40); do
        [ -s "$t_dir/env.out" ] && break
        sleep 0.05
    done
    [ -s "$t_dir/env.out" ] || { _restore_proton_env_test; return 1; }
    grep -qx "STEAM_COMPAT_APP_ID=0" "$t_dir/env.out" || { _restore_proton_env_test; return 1; }
    grep -qx "SteamAppId=0" "$t_dir/env.out" || { _restore_proton_env_test; return 1; }
    grep -qx "SteamGameId=0" "$t_dir/env.out" || { _restore_proton_env_test; return 1; }
    grep -qx "GAMEID=umu-default" "$t_dir/env.out" || { _restore_proton_env_test; return 1; }
    grep -qx "PROTON_USE_WINED3D=0" "$t_dir/env.out" || { _restore_proton_env_test; return 1; }
    grep -qx "PROTONFIXES_DISABLE=1" "$t_dir/env.out" || { _restore_proton_env_test; return 1; }
    wait "${GAMECTL_LAST_LAUNCH_PID:-}" 2>/dev/null || true

    _restore_proton_env_test
    return 0
}
run_test "Proton Contract (WP30 Packet B): Proton/umu-run env normalization & protonfixes guard" test_proton_env_contract

# Test 13: WP30 Packet C — Doctor Vulkan/Multilib Audit, Crash Telemetry Hint & TUI Polish
test_doctor_multilib_and_tui_polish_contract() {
    local t_dir
    t_dir=$(mktemp -d "${TMPDIR:-/tmp}/gamectl_doc_tui_XXXXXX")
    mkdir -p "$t_dir/.config/gamectl" "$t_dir/game" "$t_dir/pfx" "$t_dir/runtime"
    (
        trap 'rm -rf "$t_dir"' EXIT
        export HOME="$t_dir"
        export XDG_RUNTIME_DIR="$t_dir/runtime"
        export GAMECTL_TEST_LIB="$t_dir/game"
        export GAMECTL_VULKAN_CAPABILITY="VULKAN_LEGACY"
        source "$REPO_ROOT/src/core/00_header.sh"
        source "$REPO_ROOT/src/core/10_utils.sh"
        source "$REPO_ROOT/src/steam/20_discovery.sh"
        source "$REPO_ROOT/src/steam/25_identity.sh"
        source "$REPO_ROOT/src/steam/30_downloader.sh"
        source "$REPO_ROOT/src/steam/35_fixes.sh"
        source "$REPO_ROOT/src/runners/40_wrappers.sh"
        source "$REPO_ROOT/src/runners/50_launcher.sh"
        source "$REPO_ROOT/src/diagnostics/60_doctor.sh"
        source "$REPO_ROOT/src/tui/70_dashboard.sh"

        # 1. Verify doctor_audit outputs generalized Vulkan Stack + Multilib 32-bit
        local doc_out
        doc_out=$(doctor_audit 2>&1 || true)
        echo "$doc_out" | grep -q "Vulkan Stack" || exit 1
        echo "$doc_out" | grep -q "VULKAN_LEGACY" || exit 1
        echo "$doc_out" | grep -q "WineD3D" || exit 1
        echo "$doc_out" | grep -q "Multilib 32-bit" || exit 1

        # 2. Verify inspect_game_log_hint detects DXGI/Vulkan & missing DLL hints
        local dx_log="$t_dir/runtime/game_gameexe.log"
        printf 'warn: MESA-INTEL: Haswell Vulkan support is incomplete\nWin32 function failed: HRESULT: 0x887a0002\n' > "$dx_log"
        local hint_dx
        hint_dx=$(inspect_game_log_hint "$dx_log")
        echo "$hint_dx" | grep -q "WineD3D" || exit 1

        local dll_log="$t_dir/runtime/dll.log"
        printf '0024:err:module:import_dll Library foo.dll not found\n' > "$dll_log"
        local hint_dll
        hint_dll=$(inspect_game_log_hint "$dll_log")
        echo "$hint_dll" | grep -q "Community Fixes" || exit 1

        # 3. Verify preview_game TUI polish: Community Fixes, Renderer, shortened Runner, active status, Log Hint
        printf '\x4d\x5a\x90\x00' > "$t_dir/game/game.exe"
        mkdir -p "$t_dir/.local/share/Steam/compatibilitytools.d/GE-Proton7-55"
        printf '#!/bin/sh\nexit 0\n' > "$t_dir/.local/share/Steam/compatibilitytools.d/GE-Proton7-55/proton"
        chmod +x "$t_dir/.local/share/Steam/compatibilitytools.d/GE-Proton7-55/proton"

        local active_dir
        active_dir="$(get_runtime_dir)/active_games"
        mkdir -p "$active_dir"
        cat <<EOF > "$active_dir/test.info"
PID=$$
DIR=$t_dir/game
LOG=$dx_log
EOF

        local prev_out
        prev_out=$(preview_game "360740" "DownwellTest" "[GBE_FORK]" "$t_dir/game" "game.exe" 2>&1)
        echo "$prev_out" | grep -q "Community Fixes" || exit 1
        if echo "$prev_out" | grep -qF "Ctrl-X (Fixes)"; then
            exit 1
        fi
        echo "$prev_out" | grep -q "(Active in background)" || exit 1
        echo "$prev_out" | grep -q "GE-Proton7-55" || exit 1
        echo "$prev_out" | grep -q "Renderer" || exit 1
        echo "$prev_out" | grep -q "Auto (WineD3D)" || exit 1
        echo "$prev_out" | grep -q "\[HINT\]" || exit 1
        echo "$prev_out" | grep -q "WineD3D" || exit 1
    )
}
run_test "Diagnostics & TUI Contract (WP30 Packet C): Vulkan/multilib doctor, log hints & TUI polish" test_doctor_multilib_and_tui_polish_contract

# Test 14: WP31 Packet 31A — Per-Device Vulkan Probe, PCI Uevent Fallback & ldconfig 32-bit Audit
test_vulkan_per_device_and_multilib_contract() {
    local t_dir
    t_dir=$(mktemp -d "${TMPDIR:-/tmp}/gamectl_wp31a_XXXXXX")
    mkdir -p "$t_dir/bin" "$t_dir/pci/dev0" "$t_dir/pci/dev1" "$t_dir/pci/dev2" "$t_dir/home" "$t_dir/runtime"
    (
        trap 'rm -rf "$t_dir"' EXIT
        export HOME="$t_dir/home"
        export XDG_RUNTIME_DIR="$t_dir/runtime"
        export PATH="$t_dir/bin:$PATH"
        source "$REPO_ROOT/src/core/00_header.sh"
        source "$REPO_ROOT/src/core/10_utils.sh"
        source "$REPO_ROOT/src/steam/20_discovery.sh"
        source "$REPO_ROOT/src/runners/40_wrappers.sh"
        source "$REPO_ROOT/src/diagnostics/60_doctor.sh"

        unset GAMECTL_VULKAN_CAPABILITY

        # Case 1: llvmpipe Vulkan 1.3 + Hardware GPU Vulkan 1.2 -> VULKAN_LEGACY
        cat <<'EOF' > "$t_dir/bin/vulkaninfo"
#!/usr/bin/env bash
cat <<'OUT'
Devices:
========
GPU0:
	apiVersion         = 1.2.289 (4202785)
	deviceType         = PHYSICAL_DEVICE_TYPE_INTEGRATED_GPU
	deviceName         = Intel(R) HD Graphics 4000
GPU1:
	apiVersion         = 1.3.289 (4206881)
	deviceType         = PHYSICAL_DEVICE_TYPE_CPU
	deviceName         = llvmpipe (LLVM 18.1.8, 256 bits)
OUT
EOF
        chmod +x "$t_dir/bin/vulkaninfo"
        [ "$(detect_vulkan_capability)" = "VULKAN_LEGACY" ] || exit 1

        # Case 2: stderr incomplete warning + single integrated GPU 1.3 -> VULKAN_LEGACY
        cat <<'EOF' > "$t_dir/bin/vulkaninfo"
#!/usr/bin/env bash
echo "MESA-INTEL: warning: Haswell Vulkan support is incomplete" >&2
cat <<'OUT'
GPU0:
	apiVersion         = 1.3.255
	deviceType         = PHYSICAL_DEVICE_TYPE_INTEGRATED_GPU
	deviceName         = Intel(R) HD Graphics 4600 (HSW GT2)
OUT
EOF
        chmod +x "$t_dir/bin/vulkaninfo"
        [ "$(detect_vulkan_capability)" = "VULKAN_LEGACY" ] || exit 1

        # Case 3: stderr incomplete on iGPU + discrete GPU 1.3 -> VULKAN_READY
        cat <<'EOF' > "$t_dir/bin/vulkaninfo"
#!/usr/bin/env bash
echo "MESA-INTEL: warning: Haswell Vulkan support is incomplete" >&2
cat <<'OUT'
GPU0:
	apiVersion         = 1.2.289
	deviceType         = PHYSICAL_DEVICE_TYPE_INTEGRATED_GPU
	deviceName         = Intel(R) HD Graphics 4600 (HSW GT2)
GPU1:
	apiVersion         = 1.3.289
	deviceType         = PHYSICAL_DEVICE_TYPE_DISCRETE_GPU
	deviceName         = AMD Radeon RX 6600
OUT
EOF
        chmod +x "$t_dir/bin/vulkaninfo"
        [ "$(detect_vulkan_capability)" = "VULKAN_READY" ] || exit 1

        # Case 4: CPU-only Vulkan 1.3 -> OPENGL_ONLY
        cat <<'EOF' > "$t_dir/bin/vulkaninfo"
#!/usr/bin/env bash
cat <<'OUT'
GPU0:
	apiVersion         = 1.3.289
	deviceType         = PHYSICAL_DEVICE_TYPE_CPU
	deviceName         = llvmpipe
OUT
EOF
        chmod +x "$t_dir/bin/vulkaninfo"
        [ "$(detect_vulkan_capability)" = "OPENGL_ONLY" ] || exit 1

        # Case 5: is_haswell_gpu via PCI uevent fallback
        printf 'PCI_CLASS=60000\nPCI_ID=8086:0C04\n' > "$t_dir/pci/dev0/uevent"
        printf 'PCI_CLASS=30000\nPCI_ID=10DE:2484\n' > "$t_dir/pci/dev1/uevent"
        ! GAMECTL_PCI_UEVENT_DIR="$t_dir/pci" is_haswell_gpu || exit 1
        printf 'PCI_CLASS=30000\nPCI_ID=8086:0416\n' > "$t_dir/pci/dev2/uevent"
        GAMECTL_PCI_UEVENT_DIR="$t_dir/pci" is_haswell_gpu || exit 1

        # Case 6: doctor_audit 32-bit multilib detection via ldconfig -p
        cat <<'EOF' > "$t_dir/bin/ldconfig"
#!/usr/bin/env bash
cat <<'OUT'
	libGL.so.1 (libc6,x86-64) => /usr/lib/libGL.so.1
	libGL.so.1 (libc6) => /opt/custom32/libGL.so.1
OUT
EOF
        chmod +x "$t_dir/bin/ldconfig"
        local doc_out
        doc_out=$(doctor_audit 2>&1 || true)
        echo "$doc_out" | grep -q "Multilib 32-bit" || exit 1
        echo "$doc_out" | grep -q "Multilib 32-bit:.*\[READY\]" || exit 1
        echo "$doc_out" | grep -q "/opt/custom32/libGL.so.1" || exit 1
    )
}
run_test "Hardware Probe (WP31 Packet 31A): per-device vulkaninfo, PCI uevent & ldconfig 32-bit audit" test_vulkan_per_device_and_multilib_contract

# Test 15: WP31 Packet 31B — Core SSoT Unification (AppID, Log Path, Wrappers Config & Runner Env)
test_ssot_unification_contract() {
    local t_dir
    t_dir=$(mktemp -d "${TMPDIR:-/tmp}/gamectl_wp31b_XXXXXX")
    mkdir -p "$t_dir/home/.config/gamectl" "$t_dir/runtime" "$t_dir/bin"
    mkdir -p "$t_dir/games/GameAlpha/steam_settings" "$t_dir/games/GameBeta" "$t_dir/games/GameGamma"
    (
        trap 'pkill -f "$t_dir/bin/proton" 2>/dev/null || true; rm -rf "$t_dir"' EXIT
        export HOME="$t_dir/home"
        export XDG_RUNTIME_DIR="$t_dir/runtime"
        export GAMECTL_VULKAN_CAPABILITY="VULKAN_LEGACY"
        source "$REPO_ROOT/src/core/00_header.sh"
        source "$REPO_ROOT/src/core/10_utils.sh"
        source "$REPO_ROOT/src/steam/20_discovery.sh"
        source "$REPO_ROOT/src/runners/40_wrappers.sh"
        source "$REPO_ROOT/src/runners/50_launcher.sh"

        # 1. resolve_game_appid priority: steam_appid.txt > steam_settings/steam_appid.txt > .gamectl_appid > default
        [ "$(resolve_game_appid "$t_dir/games/GameAlpha" "0")" = "0" ] || exit 1
        echo "333333" > "$t_dir/games/GameAlpha/.gamectl_appid"
        [ "$(resolve_game_appid "$t_dir/games/GameAlpha" "0")" = "333333" ] || exit 1
        echo "222222" > "$t_dir/games/GameAlpha/steam_settings/steam_appid.txt"
        [ "$(resolve_game_appid "$t_dir/games/GameAlpha" "0")" = "222222" ] || exit 1
        echo "111111" > "$t_dir/games/GameAlpha/steam_appid.txt"
        [ "$(resolve_game_appid "$t_dir/games/GameAlpha" "0")" = "111111" ] || exit 1

        # 2. get_game_log_file collision prevention for identical executable names
        local log_a log_b
        log_a="$(get_game_log_file "$t_dir/games/GameAlpha" "game.exe")"
        log_b="$(get_game_log_file "$t_dir/games/GameBeta" "game.exe")"
        [ -n "$log_a" ] && [ -n "$log_b" ] && [ "$log_a" != "$log_b" ] || exit 1

        # 3. load_wrapper_config trims quotes/spaces, applies per-game overrides & selective env
        printf 'gamemode = 1\nhud = "0"\nrenderer = "dxvk"\n' > "$HOME/.config/gamectl/wrappers"
        printf 'hud = 1\nsandbox = "1"\n' > "$t_dir/games/GameGamma/.wrappers"
        GAMECTL_RENDERER="wined3d" load_wrapper_config "$t_dir/games/GameGamma" 0
        [ "$GAMECTL_CFG_GM" = "1" ] && [ "$GAMECTL_CFG_HUD" = "1" ] && [ "$GAMECTL_CFG_SANDBOX" = "1" ] || exit 1
        [ "$GAMECTL_CFG_RENDERER" = "dxvk" ] || exit 1
        GAMECTL_RENDERER="wined3d" load_wrapper_config "$t_dir/games/GameGamma" 1
        [ "$GAMECTL_CFG_RENDERER" = "wined3d" ] || exit 1

        # 4. manage_prefix & launch_game share identical Windows runner env contract (including .gamectl_appid fallback)
        cat <<EOF > "$t_dir/bin/proton"
#!/usr/bin/env bash
cat <<ENVOUT > "$t_dir/pfx_env.out"
ARGS=\$*
GAMEID=\${GAMEID:-}
STEAM_COMPAT_APP_ID=\${STEAM_COMPAT_APP_ID:-}
SteamAppId=\${SteamAppId:-}
SteamGameId=\${SteamGameId:-}
PROTON_USE_WINED3D=\${PROTON_USE_WINED3D:-}
PROTONFIXES_DISABLE=\${PROTONFIXES_DISABLE-UNSET}
ENVOUT
EOF
        chmod +x "$t_dir/bin/proton"
        find_runner() { echo "$t_dir/bin/proton"; }
        backup_save() { :; }
        clean_stale_locks() { :; }
        detect_steamstub_drm() { return 1; }
        check_systemd_scope_support() { return 1; }

        # 4a. manage_prefix with empty AppID -> appid=0, GAMEID=umu-default, PROTONFIXES_DISABLE=1
        unset PROTONFIXES_DISABLE
        manage_prefix "$t_dir/games/GameBeta" winecfg >/dev/null 2>&1 || exit 1
        grep -qx "GAMEID=umu-default" "$t_dir/pfx_env.out" || exit 1
        grep -qx "SteamAppId=0" "$t_dir/pfx_env.out" || exit 1
        grep -qx "SteamGameId=0" "$t_dir/pfx_env.out" || exit 1
        grep -qx "PROTON_USE_WINED3D=1" "$t_dir/pfx_env.out" || exit 1
        grep -qx "PROTONFIXES_DISABLE=1" "$t_dir/pfx_env.out" || exit 1

        # 4b. manage_prefix with only .gamectl_appid -> GAMEID=umu-444555, PROTONFIXES_DISABLE=UNSET
        echo "444555" > "$t_dir/games/GameBeta/.gamectl_appid"
        rm -f "$t_dir/pfx_env.out"
        manage_prefix "$t_dir/games/GameBeta" cmd >/dev/null 2>&1 || exit 1
        grep -qx "ARGS=run cmd.exe" "$t_dir/pfx_env.out" || exit 1
        grep -qx "GAMEID=umu-444555" "$t_dir/pfx_env.out" || exit 1
        grep -qx "SteamAppId=444555" "$t_dir/pfx_env.out" || exit 1
        grep -qx "PROTONFIXES_DISABLE=UNSET" "$t_dir/pfx_env.out" || exit 1

        # 4c. launch_game on GameBeta (only .gamectl_appid) propagates 444555 + writes anti-collision log
        printf 'MZ' > "$t_dir/games/GameBeta/game.exe"
        printf 'fake_dll' > "$t_dir/games/GameBeta/steam_api64.dll"
        mkdir -p "$t_dir/games/GameBeta/steam_settings"
        chmod +x "$t_dir/games/GameBeta/game.exe"
        rm -f "$t_dir/pfx_env.out"
        GAMECTL_IN_ALT_SCREEN=1 launch_game "$t_dir/games/GameBeta" "game.exe" "BetaTitle" >/dev/null 2>&1 || exit 1
        for _ in $(seq 1 40); do
            [ -s "$t_dir/pfx_env.out" ] && break
            sleep 0.05
        done
        grep -qx "GAMEID=umu-444555" "$t_dir/pfx_env.out" || exit 1
        grep -qx "SteamAppId=444555" "$t_dir/pfx_env.out" || exit 1
        [ -f "$log_b" ] || exit 1
    )
}
run_test "SSoT Unification (WP31 Packet 31B): AppID, anti-collision log, wrapper config & runner env" test_ssot_unification_contract

echo
if [ "$FAILED_TESTS" -eq 0 ] && [ "$TOTAL_TESTS" -gt 0 ]; then
    echo "${C_GREEN}[ VERIFIED ] All remediation contracts passed with Exit 0 ($PASSED_TESTS/$TOTAL_TESTS).${C_RST}"
    exit 0
else
    echo "${C_RED}[ FAILED ] $FAILED_TESTS test assertion(s) failed.${C_RST}"
    exit 1
fi

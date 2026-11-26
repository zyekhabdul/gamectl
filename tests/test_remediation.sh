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
        if [ -n "$output" ]; then echo "    Output: $output"; fi
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
    if grep -rn "/run/user/" "$REPO_ROOT"/src/runners/4*.sh "$REPO_ROOT"/src/steam/3[01234]_*.sh | grep -q .; then
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

    # Dummy PE executable + local GBE template/shield fixture (deterministic offline verification)
    mkdir -p "$t_dir/.local/share/gbe-fork/windows/release/regular/x64"
    printf 'fake_dll' > "$t_dir/.local/share/gbe-fork/windows/release/regular/x64/steam_api64.dll"
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
        mkdir -p "$t_dir/home/.local/share/gbe-fork/windows/release/regular/x64"
        printf 'fake_dll' > "$t_dir/home/.local/share/gbe-fork/windows/release/regular/x64/steam_api64.dll"
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

# Test 16: WP31 Packet 31C — Detection Integrity, Standalone XDG Runners & Child Env Hygiene
test_detection_integrity_runners_and_env_hygiene_contract() {
    local t_dir
    t_dir=$(mktemp -d "${TMPDIR:-/tmp}/gamectl_wp31c_XXXXXX")
    mkdir -p "$t_dir/home/.local/share/Steam/compatibilitytools.d/GE-Proton8-1" \
             "$t_dir/xdg_data/gamectl/runners/GE-Proton9-99" \
             "$t_dir/runtime" \
             "$t_dir/games/StrippedGbeGame" \
             "$t_dir/games/MarkerGbeGame" \
             "$t_dir/games/StockValveGame" \
             "$t_dir/games/EnvHygieneGame"
    (
        trap 'rm -rf "$t_dir"' EXIT
        export HOME="$t_dir/home"
        export XDG_DATA_HOME="$t_dir/xdg_data"
        export XDG_RUNTIME_DIR="$t_dir/runtime"
        export GAMECTL_GBE_DIR="$t_dir/empty_gbe"
        source "$REPO_ROOT/src/core/00_header.sh"
        source "$REPO_ROOT/src/core/10_utils.sh"
        source "$REPO_ROOT/src/steam/20_discovery.sh"
        source "$REPO_ROOT/src/runners/40_wrappers.sh"
        source "$REPO_ROOT/src/runners/50_launcher.sh"

        # 1. Stripped small GBE DLL (<7MB) with embedded signature or .gamectl_gbe -> GBE_FORK
        printf 'MZ\x00goldberg\x00steam_settings/configs.user.ini\x00' > "$t_dir/games/StrippedGbeGame/steam_api64.dll"
        printf 'MZ\x00' > "$t_dir/games/StrippedGbeGame/game.exe"
        [ "$(resolve_game_drm_status "$t_dir/games/StrippedGbeGame" "game.exe")" = "GBE_FORK" ] || exit 1

        printf 'MZ\x00valve_original_stub\x00' > "$t_dir/games/MarkerGbeGame/steam_api64.dll"
        printf 'MZ\x00' > "$t_dir/games/MarkerGbeGame/game.exe"
        touch "$t_dir/games/MarkerGbeGame/.gamectl_gbe"
        [ "$(resolve_game_drm_status "$t_dir/games/MarkerGbeGame" "game.exe")" = "GBE_FORK" ] || exit 1

        printf 'MZ\x00valve_original_stub\x00' > "$t_dir/games/StockValveGame/steam_api64.dll"
        printf 'MZ\x00' > "$t_dir/games/StockValveGame/game.exe"
        [ "$(resolve_game_drm_status "$t_dir/games/StockValveGame" "game.exe")" = "VALVE_DLL" ] || exit 1

        # 2. Standalone XDG runner in XDG_DATA_HOME/gamectl/runners takes precedence over Steam compat dir
        printf '#!/bin/sh\nexit 0\n' > "$t_dir/xdg_data/gamectl/runners/GE-Proton9-99/proton"
        printf '#!/bin/sh\nexit 0\n' > "$t_dir/home/.local/share/Steam/compatibilitytools.d/GE-Proton8-1/proton"
        chmod +x "$t_dir/xdg_data/gamectl/runners/GE-Proton9-99/proton" \
                 "$t_dir/home/.local/share/Steam/compatibilitytools.d/GE-Proton8-1/proton"
        (
            command() {
                if [ "${1:-}" = "-v" ] && [ "${2:-}" = "umu-run" ]; then
                    return 1
                fi
                builtin command "$@"
            }
            local found_runner
            found_runner="$(find_runner "$t_dir/games/StockValveGame")"
            [ "$found_runner" = "$t_dir/xdg_data/gamectl/runners/GE-Proton9-99/proton" ] || exit 1
        ) || exit 1

        # 3. Child process launched via launch_game receives zero BASH_FUNC_* pollution
        dummy_leak_check_fn() { echo "leak"; }
        export -f dummy_leak_check_fn
        env | grep -q '^BASH_FUNC_' || exit 1

        cat <<EOF > "$t_dir/games/EnvHygieneGame/game.sh"
#!/usr/bin/env bash
env | grep -E '^BASH_FUNC_' > "$t_dir/child_funcs.out" || true
touch "$t_dir/child_done"
EOF
        chmod +x "$t_dir/games/EnvHygieneGame/game.sh"
        backup_save() { :; }
        clean_stale_locks() { :; }
        detect_steamstub_drm() { return 1; }
        check_systemd_scope_support() { return 1; }

        GAMECTL_IN_ALT_SCREEN=1 launch_game "$t_dir/games/EnvHygieneGame" "game.sh" "EnvHygiene" >/dev/null 2>&1 || exit 1
        for _ in $(seq 1 40); do
            [ -f "$t_dir/child_done" ] && break
            sleep 0.05
        done
        [ -f "$t_dir/child_done" ] || exit 1
        [ ! -s "$t_dir/child_funcs.out" ] || exit 1

        # 4. Hygiene & dashboard optional bridge labeling
        grep -q 'src/gamectl.egg-info' "$REPO_ROOT/Makefile" || exit 1
        grep -q 'src/gamectl_runner/bin' "$REPO_ROOT/Makefile" || exit 1
        grep -q 'Bridge (Opt)' "$REPO_ROOT/src/tui/71_previews.sh" || exit 1
    )
}
run_test "Detection & Hygiene (WP31 Packet 31C): GBE markers, XDG runners, child env & Makefile clean" test_detection_integrity_runners_and_env_hygiene_contract

# Test 17: WP32 Packet 32A — Atomic KV/Prepend Mutations & Safe latest.json
test_atomic_mutations_and_json_safety_contract() {
    local t_dir
    t_dir=$(mktemp -d "${TMPDIR:-/tmp}/gamectl_wp32a_XXXXXX")
    mkdir -p "$t_dir/home/.config/gamectl" "$t_dir/game/steam_settings" "$t_dir/runtime" "$t_dir/bin"
    (
        trap 'rm -rf "$t_dir"' EXIT
        export HOME="$t_dir/home"
        export XDG_RUNTIME_DIR="$t_dir/runtime"
        source "$REPO_ROOT/src/core/00_header.sh"
        source "$REPO_ROOT/src/core/10_utils.sh"
        source "$REPO_ROOT/src/steam/25_identity.sh"
        source "$REPO_ROOT/src/runners/50_launcher.sh"
        source "$REPO_ROOT/src/steam/35_fixes.sh"

        # 1. Zero sed -i across modular sources
        if grep -rn "sed -i" "$REPO_ROOT/src/core" "$REPO_ROOT/src/steam" "$REPO_ROOT/src/runners" "$REPO_ROOT/src/diagnostics" "$REPO_ROOT/src/tui" "$REPO_ROOT/src/main.sh" | grep -q .; then
            echo "Found forbidden sed -i in src/" >&2
            exit 1
        fi

        # 2. Special characters in atomic_set_kv_file without backslash/delimiter mangling
        local special_val='foo/bar|baz&qux\n\1"quote'\'''
        printf 'other_key=keep_me\ntarget=old\n' > "$t_dir/test.kv"
        atomic_set_kv_file "$t_dir/test.kv" "target" "$special_val" "="
        [ "$(grep -F 'other_key=keep_me' "$t_dir/test.kv")" = "other_key=keep_me" ] || exit 1
        [ "$(grep -E '^target=' "$t_dir/test.kv")" = "target=$special_val" ] || exit 1

        # 3. atomic_prepend_line on 0-byte and non-empty file
        : > "$t_dir/empty.lua"
        atomic_prepend_line "$t_dir/empty.lua" "addappid(12345)"
        [ "$(cat "$t_dir/empty.lua")" = "addappid(12345)" ] || exit 1
        printf 'line2\n' > "$t_dir/nonempty.lua"
        atomic_prepend_line "$t_dir/nonempty.lua" "line1"
        [ "$(head -n 1 "$t_dir/nonempty.lua")" = "line1" ] && [ "$(tail -n 1 "$t_dir/nonempty.lua")" = "line2" ] || exit 1

        # 4. set_id and setup_onlinefix preserve / | & \ literally
        local persona_special='Player/One|Two&Three\Four'
        cat <<'EOF' > "$t_dir/game/steam_settings/configs.user.ini"
[user::general]
account_name=old
account_steamid=76561198000000000
EOF
        set_id "$persona_special" "76561198000000123" "$t_dir/game" >/dev/null || exit 1
        [ "$(grep -E '^account_name=' "$t_dir/game/steam_settings/configs.user.ini")" = "account_name=$persona_special" ] || exit 1

        cat <<'EOF' > "$t_dir/home/.config/gamectl/persona"
account_name=Player/One|Two&Three\Four
EOF
        printf '[Main]\nPlayerName = OldName\n' > "$t_dir/game/OnlineFix.ini"
        printf 'MZ\x00' > "$t_dir/game/OnlineFix64.dll"
        setup_onlinefix "$t_dir/game" --yes >/dev/null || exit 1
        [ "$(grep -E '^PlayerName' "$t_dir/game/OnlineFix.ini")" = "PlayerName = $persona_special" ] || exit 1

        # 5. install_game_fix produces valid JSON even when fix_title has quotes and backslashes
        local fix_src="$t_dir/fix_src"
        mkdir -p "$fix_src"
        printf 'payload\n' > "$fix_src/fix.txt"
        (cd "$fix_src" && zip -q "$t_dir/fix_payload.zip" fix.txt)
        get_valid_luatools_token() { echo "dummy_token"; }
        resolve_game_install_dir() { echo "$t_dir/game"; }
        audit_proton_compatibility() { :; }
        detect_fix_custom_launcher() { :; }
        curl() {
            local out_file="" url=""
            while [ $# -gt 0 ]; do
                case "$1" in
                    -o) shift; out_file="${1:-}" ;;
                    https://*|http://*) url="$1" ;;
                esac
                shift || true
            done
            case "$url" in
                *fixes?appid=*)
                    printf '{"fixes":[{"id":"fix-1","title":"Fix \\"Alpha\\" \\\\ Beta","fixFilename":"fix.zip","hasFix":true}]}'
                    ;;
                *download?fix=*)
                    printf '{"url":"https://example.invalid/fix.zip"}'
                    ;;
                *fix.zip*)
                    cp -f "$t_dir/fix_payload.zip" "$out_file"
                    ;;
            esac
        }
        install_game_fix "12345" "$t_dir/game" --yes >/dev/null || exit 1
        jq -e '.fix_title == "Fix \"Alpha\" \\ Beta"' "$t_dir/game/.gamectl_fix_backup/latest.json" >/dev/null || exit 1
    )
}
run_test "Atomic Safety (WP32 Packet 32A): atomic KV/prepend & injection-safe latest.json" test_atomic_mutations_and_json_safety_contract

# Test 18: WP32 Packet 32B — Supply-Chain & Archive Security Hardening
test_archive_security_and_staged_proton_contract() {
    local t_dir
    t_dir=$(mktemp -d "${TMPDIR:-/tmp}/gamectl_wp32b_XXXXXX")
    mkdir -p "$t_dir/home/.local/share/Steam/compatibilitytools.d" "$t_dir/runtime" "$t_dir/stage_clean" "$t_dir/stage_sym" "$t_dir/stage_trav/sub"
    (
        trap 'rm -rf "$t_dir"' EXIT
        export HOME="$t_dir/home"
        export XDG_RUNTIME_DIR="$t_dir/runtime"
        source "$REPO_ROOT/src/core/00_header.sh"
        source "$REPO_ROOT/src/core/10_utils.sh"
        source "$REPO_ROOT/src/steam/30_downloader.sh"
        source "$REPO_ROOT/src/runners/40_wrappers.sh"

        # 1. audit_zip_safety: clean passes, symlink fails, traversal fails
        printf '\xd0\x17\xf6\x71payload' > "$t_dir/stage_clean/100_1.manifest"
        (cd "$t_dir/stage_clean" && zip -q "$t_dir/clean.zip" 100_1.manifest)
        audit_zip_safety "$t_dir/clean.zip" || exit 1

        ln -s /etc/passwd "$t_dir/stage_sym/evil_link.manifest"
        (cd "$t_dir/stage_sym" && zip -qy "$t_dir/symlink.zip" evil_link.manifest)
        ! audit_zip_safety "$t_dir/symlink.zip" 2>/dev/null || exit 1
        ! validate_manifest_zip "$t_dir/symlink.zip" "100" 2>/dev/null || exit 1

        python3 - "$t_dir/trav.zip" <<'PY'
import sys, zipfile
with zipfile.ZipFile(sys.argv[1], "w") as zf:
    zf.writestr("../escape.txt", "bad")
PY
        ! audit_zip_safety "$t_dir/trav.zip" 2>/dev/null || exit 1

        # 2. Staged proton_install: valid SHA-512 succeeds, mismatch & traversal fail atomically
        local compat_dir
        compat_dir="$(get_compat_dir)"
        mkdir -p "$compat_dir"
        local arch_sfx="x86_64"
        [ "$(uname -m 2>/dev/null || echo x86_64)" = "aarch64" ] && arch_sfx="aarch64"

        mkdir -p "$t_dir/tar_ok/GE-Proton9-99"
        printf '"compatibilitytools"\n{}\n' > "$t_dir/tar_ok/GE-Proton9-99/compatibilitytool.vdf"
        printf '#!/bin/sh\nexit 0\n' > "$t_dir/tar_ok/GE-Proton9-99/proton"
        tar -czf "$t_dir/GE-Proton9-99-${arch_sfx}.tar.gz" -C "$t_dir/tar_ok" GE-Proton9-99
        local good_hash
        good_hash=$(sha512sum "$t_dir/GE-Proton9-99-${arch_sfx}.tar.gz" | awk '{print $1}')
        printf '%s  GE-Proton9-99-%s.tar.gz\n' "$good_hash" "$arch_sfx" > "$t_dir/good.sha512sum"
        printf '%0128d  GE-Proton9-99-%s.tar.gz\n' 0 "$arch_sfx" > "$t_dir/bad.sha512sum"

        python3 - "$t_dir/evil.tar.gz" <<'PY'
import io, sys, tarfile
with tarfile.open(sys.argv[1], "w:gz") as tf:
    info = tarfile.TarInfo("../evil_proton")
    data = b"bad"
    info.size = len(data)
    tf.addfile(info, io.BytesIO(data))
PY

        export TEST_SUM_MODE="good" TEST_TAR_MODE="good"
        curl() {
            local out_file="" url=""
            while [ $# -gt 0 ]; do
                case "$1" in
                    -o) shift; out_file="${1:-}" ;;
                    https://*|http://*) url="$1" ;;
                esac
                shift || true
            done
            case "$url" in
                *api.github.com*)
                    printf '{"tag_name":"GE-Proton9-99","assets":[{"name":"GE-Proton9-99-%s.tar.gz","browser_download_url":"https://example.invalid/GE-Proton9-99-%s.tar.gz"},{"name":"GE-Proton9-99.sha512sum","browser_download_url":"https://example.invalid/GE-Proton9-99.sha512sum"}]}' "$arch_sfx" "$arch_sfx"
                    ;;
                *.sha512sum)
                    if [ "$TEST_SUM_MODE" = "good" ]; then
                        cp -f "$t_dir/good.sha512sum" "$out_file"
                    else
                        cp -f "$t_dir/bad.sha512sum" "$out_file"
                    fi
                    ;;
                *.tar.gz)
                    if [ "$TEST_TAR_MODE" = "good" ]; then
                        cp -f "$t_dir/GE-Proton9-99-${arch_sfx}.tar.gz" "$out_file"
                    else
                        cp -f "$t_dir/evil.tar.gz" "$out_file"
                    fi
                    ;;
            esac
        }

        # Bad SHA-512 must fail and leave zero installed/stage directories
        TEST_SUM_MODE="bad"
        ! proton_install "GE-Proton9-99" --yes >/dev/null 2>&1 || exit 1
        [ ! -d "$compat_dir/GE-Proton9-99" ] || exit 1
        ! find "$compat_dir" -maxdepth 1 -name '.proton_stage.*' | grep -q . || exit 1

        # Path traversal tarball must fail and leave zero installed/stage directories
        TEST_SUM_MODE="good"
        TEST_TAR_MODE="evil"
        rm -f "$t_dir/good.sha512sum"
        printf '%s  GE-Proton9-99-%s.tar.gz\n' "$(sha512sum "$t_dir/evil.tar.gz" | awk '{print $1}')" "$arch_sfx" > "$t_dir/good.sha512sum"
        ! proton_install "GE-Proton9-99" --yes >/dev/null 2>&1 || exit 1
        [ ! -d "$compat_dir/GE-Proton9-99" ] || exit 1
        ! find "$compat_dir" -maxdepth 1 -name '.proton_stage.*' | grep -q . || exit 1

        # Valid SHA-512 + clean tarball succeeds atomically
        TEST_TAR_MODE="good"
        printf '%s  GE-Proton9-99-%s.tar.gz\n' "$good_hash" "$arch_sfx" > "$t_dir/good.sha512sum"
        proton_install "GE-Proton9-99" --yes >/dev/null || exit 1
        [ -f "$compat_dir/GE-Proton9-99/compatibilitytool.vdf" ] && [ -x "$compat_dir/GE-Proton9-99/proton" ] || exit 1
        ! find "$compat_dir" -maxdepth 1 -name '.proton_stage.*' | grep -q . || exit 1
    )
}
run_test "Archive & Supply-Chain (WP32 Packet 32B): audit_zip_safety & staged proton_install" test_archive_security_and_staged_proton_contract

# Test 19: WP32 Packet 32C — Runner Directory SSoT, Timeout Guards & Downloader Dedup
test_runner_ssot_timeouts_and_downloader_dedup_contract() {
    local t_dir
    t_dir=$(mktemp -d "${TMPDIR:-/tmp}/gamectl_wp32c_XXXXXX")
    mkdir -p "$t_dir/home/.local/share/Steam/compatibilitytools.d" \
             "$t_dir/xdg_data/gamectl/runners/GE-Proton-XDG" \
             "$t_dir/runtime"
    (
        trap 'rm -rf "$t_dir"' EXIT
        export HOME="$t_dir/home"
        export XDG_DATA_HOME="$t_dir/xdg_data"
        export XDG_RUNTIME_DIR="$t_dir/runtime"

        # 1. Standalone sourcing of 30_downloader.sh without pre-sourcing 10_utils.sh
        (
            source "$REPO_ROOT/src/steam/30_downloader.sh"
            declare -F get_runtime_dir >/dev/null 2>&1 || exit 1
            declare -F audit_zip_safety >/dev/null 2>&1 || exit 1
            declare -F atomic_prepend_line >/dev/null 2>&1 || exit 1
            [ "$(get_runtime_dir)" = "$t_dir/runtime" ] || exit 1
        ) || exit 1

        source "$REPO_ROOT/src/core/00_header.sh"
        source "$REPO_ROOT/src/core/10_utils.sh"
        source "$REPO_ROOT/src/steam/20_discovery.sh"
        source "$REPO_ROOT/src/runners/40_wrappers.sh"
        source "$REPO_ROOT/src/diagnostics/60_doctor.sh"

        # 2. list_runner_dirs starts with XDG runners and deduplicates Steam dirs
        local dirs_out
        dirs_out=$(list_runner_dirs)
        [ "$(echo "$dirs_out" | head -n 1)" = "$t_dir/xdg_data/gamectl/runners" ] || exit 1
        [ "$(echo "$dirs_out" | wc -l)" -eq "$(echo "$dirs_out" | sort -u | wc -l)" ] || exit 1

        # 3. proton_list, doctor_audit, and proton_remove see standalone XDG runner
        printf '#!/bin/sh\nexit 0\n' > "$t_dir/xdg_data/gamectl/runners/GE-Proton-XDG/proton"
        chmod +x "$t_dir/xdg_data/gamectl/runners/GE-Proton-XDG/proton"
        curl() { return 1; }
        local list_out doc_out
        list_out=$(proton_list) || exit 1
        printf '%s\n' "$list_out" | grep -q 'GE-Proton-XDG' || exit 1
        doc_out=$(doctor_audit || true)
        printf '%s\n' "$doc_out" | grep -q 'GE-Proton-XDG/proton' || exit 1
        proton_remove "GE-Proton-XDG" --yes >/dev/null || exit 1
        [ ! -d "$t_dir/xdg_data/gamectl/runners/GE-Proton-XDG" ] || exit 1

        # 4. Store search curl calls enforce --max-time 15
        [ "$(cat "$REPO_ROOT"/src/tui/*.sh | grep -c -- '--max-time 15.*storesearch')" -eq 2 ] || exit 1
        grep -q -- '--max-time 15.*storesearch' "$REPO_ROOT/src/steam/32_steam_bridge.sh" || exit 1
    )
}
run_test "Runner SSoT & Network Guard (WP32 Packet 32C): list_runner_dirs, proton_remove XDG, timeouts & dedup" test_runner_ssot_timeouts_and_downloader_dedup_contract

# Test 20: WP32.1 Hardening — Newline Guard, Multi-Arch SHA512, Tarball Symlink Audit & List Priority
test_wp32_1_hardening_contracts() {
    local t_dir
    t_dir=$(mktemp -d "${TMPDIR:-/tmp}/gamectl_wp32_1_XXXXXX")
    mkdir -p "$t_dir/home/.local/share/Steam/compatibilitytools.d/GE-Proton-Dup" \
             "$t_dir/xdg_data/gamectl/runners/GE-Proton-Dup" \
             "$t_dir/game" \
             "$t_dir/runtime"
    (
        trap 'rm -rf "$t_dir"' EXIT
        export HOME="$t_dir/home"
        export XDG_DATA_HOME="$t_dir/xdg_data"
        export XDG_RUNTIME_DIR="$t_dir/runtime"
        source "$REPO_ROOT/src/core/00_header.sh"
        source "$REPO_ROOT/src/core/10_utils.sh"
        source "$REPO_ROOT/src/steam/20_discovery.sh"
        source "$REPO_ROOT/src/runners/40_wrappers.sh"
        source "$REPO_ROOT/src/runners/50_launcher.sh"

        # 1. Reject embedded newline/CR in atomic_set_kv_file & atomic_prepend_line
        printf 'key=safe\n' > "$t_dir/kv.ini"
        local nl_val=$'bad\ninjected=1'
        ! atomic_set_kv_file "$t_dir/kv.ini" "key" "$nl_val" "=" 2>/dev/null || exit 1
        [ "$(cat "$t_dir/kv.ini")" = "key=safe" ] || exit 1
        ! atomic_prepend_line "$t_dir/kv.ini" $'line1\nline2' 2>/dev/null || exit 1
        [ "$(cat "$t_dir/kv.ini")" = "key=safe" ] || exit 1

        # 2. setup_onlinefix propagates failure when atomic_set_kv_file fails
        printf '[Main]\nPlayerName = Old\n' > "$t_dir/game/OnlineFix.ini"
        printf 'MZ\x00' > "$t_dir/game/OnlineFix64.dll"
        atomic_set_kv_file() { return 1; }
        local of_out="" of_rc=0
        of_out=$(setup_onlinefix "$t_dir/game" --yes 2>&1) || of_rc=$?
        [ "$of_rc" -ne 0 ] || exit 1
        ! printf '%s\n' "$of_out" | grep -q '\[SUCCESS\]' || exit 1
        unset -f atomic_set_kv_file

        # 3. proton_install selects arch-matching .sha512sum when opposite arch is listed first
        local compat_dir
        compat_dir="$(get_compat_dir)"
        mkdir -p "$compat_dir"
        local arch_sfx="x86_64" other_sfx="aarch64"
        if [ "$(uname -m 2>/dev/null || echo x86_64)" = "aarch64" ]; then
            arch_sfx="aarch64"; other_sfx="x86_64"
        fi
        mkdir -p "$t_dir/tar_ok/GE-Proton9-99/files/lib" "$t_dir/tar_ok/GE-Proton9-99/files/share"
        printf '"compatibilitytools"\n{}\n' > "$t_dir/tar_ok/GE-Proton9-99/compatibilitytool.vdf"
        printf '#!/bin/sh\nexit 0\n' > "$t_dir/tar_ok/GE-Proton9-99/proton"
        printf 'shared\n' > "$t_dir/tar_ok/GE-Proton9-99/files/share/b"
        ln -s '../share/b' "$t_dir/tar_ok/GE-Proton9-99/files/lib/a"
        tar -czf "$t_dir/GE-Proton9-99-${arch_sfx}.tar.gz" -C "$t_dir/tar_ok" GE-Proton9-99
        local ok_hash
        ok_hash=$(sha512sum "$t_dir/GE-Proton9-99-${arch_sfx}.tar.gz" | awk '{print $1}')
        printf '%s  GE-Proton9-99-%s.tar.gz\n' "$ok_hash" "$arch_sfx" > "$t_dir/ok.sha512sum"
        printf '%0128d  GE-Proton9-99-%s.tar.gz\n' 0 "$other_sfx" > "$t_dir/other.sha512sum"

        # Build tarball with escaping symlink (GE-Proton9-99/evil -> ../../etc/passwd)
        python3 - "$t_dir/sym_escape.tar.gz" <<'PY'
import sys, tarfile
with tarfile.open(sys.argv[1], "w:gz") as tf:
    ti = tarfile.TarInfo("GE-Proton9-99/evil")
    ti.type = tarfile.SYMTYPE
    ti.linkname = "../../etc/passwd"
    tf.addfile(ti)
PY
        local sym_escape_hash
        sym_escape_hash=$(sha512sum "$t_dir/sym_escape.tar.gz" | awk '{print $1}')
        printf '%s  GE-Proton9-99-%s.tar.gz\n' "$sym_escape_hash" "$arch_sfx" > "$t_dir/sym_escape.sha512sum"

        export TEST_TAR_VARIANT="ok"
        curl() {
            local out_file="" url=""
            while [ $# -gt 0 ]; do
                case "$1" in
                    -o) shift; out_file="${1:-}" ;;
                    https://*|http://*) url="$1" ;;
                esac
                shift || true
            done
            case "$url" in
                *api.github.com*)
                    printf '{"tag_name":"GE-Proton9-99","assets":[{"name":"GE-Proton9-99-%s.sha512sum","browser_download_url":"https://example.invalid/other.sha512sum"},{"name":"GE-Proton9-99-%s.tar.gz","browser_download_url":"https://example.invalid/GE-Proton9-99-%s.tar.gz"},{"name":"GE-Proton9-99-%s.sha512sum","browser_download_url":"https://example.invalid/ok.sha512sum"}]}' "$other_sfx" "$arch_sfx" "$arch_sfx" "$arch_sfx"
                    ;;
                *other.sha512sum)
                    cp -f "$t_dir/other.sha512sum" "$out_file"
                    ;;
                *ok.sha512sum)
                    if [ "$TEST_TAR_VARIANT" = "ok" ]; then
                        cp -f "$t_dir/ok.sha512sum" "$out_file"
                    else
                        cp -f "$t_dir/sym_escape.sha512sum" "$out_file"
                    fi
                    ;;
                *.tar.gz)
                    if [ "$TEST_TAR_VARIANT" = "ok" ]; then
                        cp -f "$t_dir/GE-Proton9-99-${arch_sfx}.tar.gz" "$out_file"
                    else
                        cp -f "$t_dir/sym_escape.tar.gz" "$out_file"
                    fi
                    ;;
            esac
        }

        # Escaping symlink tarball must be rejected with zero installed/stage residue
        TEST_TAR_VARIANT="escape"
        ! proton_install "GE-Proton9-99" --yes >/dev/null 2>&1 || exit 1
        [ ! -d "$compat_dir/GE-Proton9-99" ] || exit 1
        ! find "$compat_dir" -maxdepth 1 -name '.proton_stage.*' | grep -q . || exit 1

        # Multi-arch checksum + internal relative symlink succeeds cleanly
        TEST_TAR_VARIANT="ok"
        proton_install "GE-Proton9-99" --yes >/dev/null || exit 1
        [ -L "$compat_dir/GE-Proton9-99/files/lib/a" ] || exit 1
        ! find "$compat_dir" -maxdepth 1 -name '.proton_stage.*' | grep -q . || exit 1

        # 4. proton_list preserves XDG priority over Steam on duplicate tag name
        local list_out
        list_out=$(proton_list) || exit 1
        printf '%s\n' "$list_out" | grep 'GE-Proton-Dup' | grep -q "$t_dir/xdg_data/gamectl/runners/GE-Proton-Dup" || exit 1
    )
}
run_test "Hardening (WP32.1): newline guard, multi-arch SHA512, tarball symlink audit & list priority" test_wp32_1_hardening_contracts

# Test 21: WP33 Packet 33A — Remote Save Sync Hardening & Active-Game Save Guard
test_remote_sync_and_active_game_guard_contract() {
    local t_dir
    t_dir=$(mktemp -d "${TMPDIR:-/tmp}/gamectl_wp33a_XXXXXX")
    local gdir="$t_dir/ext/My \"Test\" Game"
    local dry_gdir="$t_dir/ext/Dry \"Only\" Game"
    mkdir -p "$t_dir/home" "$t_dir/remote_home" "$t_dir/mock_bin" "$t_dir/runtime/active_games" \
             "$gdir/saves" "$gdir/.save_snapshots/slot1" "$dry_gdir"
    printf 'local_save_v1\n' > "$gdir/saves/slot.dat"
    printf 'snap_save_v0\n' > "$gdir/.save_snapshots/slot1/slot.dat"

    cat <<'EOF' > "$t_dir/mock_bin/ssh"
#!/usr/bin/env bash
while [ $# -gt 0 ]; do
    case "$1" in
        -q|-n|-T|-N|-x|-v|-Y|-A|-a|-C|-f|-g|-k|-M|-O|-s|-t|-V|-X)
            shift ;;
        -o|-l|-p|-i|-F|-J|-W|-b|-c|-D|-E|-e|-I|-L|-m|-Q|-R|-S|-w)
            shift 2 ;;
        --)
            shift; break ;;
        -*)
            shift ;;
        *)
            break ;;
    esac
done
shift || true
if [ "${MOCK_SSH_FAIL_MKDIR:-0}" = "1" ] && [[ "$*" == *"mkdir -p"* ]]; then
    exit 42
fi
export HOME="$MOCK_REMOTE_HOME"
if [ "${1:-}" = "rsync" ]; then
    exec "$@"
fi
exec /bin/sh -c "$*"
EOF
    chmod +x "$t_dir/mock_bin/ssh"

    local bg_pid=""
    (
        trap ' [ -n "$bg_pid" ] && kill "$bg_pid" 2>/dev/null || true; rm -rf "$t_dir"' EXIT
        export HOME="$t_dir/home"
        export MOCK_REMOTE_HOME="$t_dir/remote_home"
        export XDG_RUNTIME_DIR="$t_dir/runtime"
        export PATH="$t_dir/mock_bin:$PATH"
        source "$REPO_ROOT/src/core/00_header.sh"
        source "$REPO_ROOT/src/core/10_utils.sh"
        source "$REPO_ROOT/src/runners/50_launcher.sh"

        # 1. sync_save_remote handles spaces & double quotes and resolves remote $HOME
        local out="" rc=0
        out=$(sync_save_remote "$gdir" 'My "Test" Game' "mockhost" 2>&1) || rc=$?
        [ "$rc" -eq 0 ] || exit 1
        printf '%s\n' "$out" | grep -q '\[VERIFIED\]' || exit 1
        [ "$(cat "$t_dir/remote_home/Games/My \"Test\" Game/saves/slot.dat")" = "local_save_v1" ] || exit 1

        # 2. pull_save_remote --dry-run does NOT create local saves/ directory
        mkdir -p "$t_dir/remote_home/Games/Dry \"Only\" Game/saves"
        printf 'remote_dry\n' > "$t_dir/remote_home/Games/Dry \"Only\" Game/saves/slot.dat"
        out=$(pull_save_remote "$dry_gdir" 'Dry "Only" Game' "mockhost" --dry-run 2>&1) || exit 1
        [ ! -d "$dry_gdir/saves" ] || exit 1

        # 3. pull_save_remote (real) pulls remote save
        printf 'remote_v2\n' > "$t_dir/remote_home/Games/My \"Test\" Game/saves/slot.dat"
        out=$(pull_save_remote "$gdir" 'My "Test" Game' "mockhost" 2>&1) || exit 1
        printf '%s\n' "$out" | grep -q '\[VERIFIED\]' || exit 1
        [ "$(cat "$gdir/saves/slot.dat")" = "remote_v2" ] || exit 1

        # 4. ssh mkdir failure and rsync exit 23 propagate non-zero and emit ZERO [VERIFIED]
        out=$(MOCK_SSH_FAIL_MKDIR=1 sync_save_remote "$gdir" 'My "Test" Game' "mockhost" 2>&1) && rc=0 || rc=$?
        [ "$rc" -ne 0 ] || exit 1
        ! printf '%s\n' "$out" | grep -q '\[VERIFIED\]' || exit 1

        rsync() { return 23; }
        out=$(sync_save_remote "$gdir" 'My "Test" Game' "mockhost" 2>&1) && rc=0 || rc=$?
        [ "$rc" -ne 0 ] || exit 1
        ! printf '%s\n' "$out" | grep -q '\[VERIFIED\]' || exit 1

        out=$(pull_save_remote "$gdir" 'My "Test" Game' "mockhost" 2>&1) && rc=0 || rc=$?
        [ "$rc" -ne 0 ] || exit 1
        ! printf '%s\n' "$out" | grep -q '\[VERIFIED\]' || exit 1
        unset -f rsync

        # 5. Active-game save guard blocks restore_save, pull_save_remote, and sync_save_remote (without --force)
        sleep 30 &
        bg_pid=$!
        printf 'PID=%s\nDIR=%s\n' "$bg_pid" "$gdir" > "$t_dir/runtime/active_games/${bg_pid}.info"
        [ "$(is_game_active_for_dir "$gdir")" = "$bg_pid" ] || exit 1

        ! restore_save "$gdir" 1 false >/dev/null 2>&1 || exit 1
        [ "$(cat "$gdir/saves/slot.dat")" = "remote_v2" ] || exit 1
        ! pull_save_remote "$gdir" 'My "Test" Game' "mockhost" >/dev/null 2>&1 || exit 1
        ! sync_save_remote "$gdir" 'My "Test" Game' "mockhost" >/dev/null 2>&1 || exit 1
        sync_save_remote "$gdir" 'My "Test" Game' "mockhost" --force >/dev/null 2>&1 || exit 1
    )
}
run_test "Remote Sync & Active Guard (WP33 Packet 33A): quoting, error propagation, dry-run & active PID guard" test_remote_sync_and_active_game_guard_contract

# Test 22: WP33 Packet 33B — Packaging Architecture Integrity & Freshness Gate
test_packaging_arch_and_freshness_gate_contract() {
    local t_dir
    t_dir=$(mktemp -d "${TMPDIR:-/tmp}/gamectl_wp33b_XXXXXX")
    mkdir -p "$t_dir/scripts" "$t_dir/crates/depot-dl/src" "$t_dir/bin"
    (
        trap 'rm -rf "$t_dir"' EXIT
        cp -f "$REPO_ROOT/scripts/build-depot-dl.sh" "$t_dir/scripts/build-depot-dl.sh"
        printf '[package]\nname = "depot-dl"\n' > "$t_dir/crates/depot-dl/Cargo.toml"
        printf '# lock\n' > "$t_dir/crates/depot-dl/Cargo.lock"
        printf 'fn main() {}\n' > "$t_dir/crates/depot-dl/src/main.rs"
        printf '#!/bin/sh\nexit 0\n' > "$t_dir/bin/gamectl-depot-dl"
        chmod +x "$t_dir/bin/gamectl-depot-dl"

        # 1. Fresh binary passes --check; stale binary (newer Rust source) fails --check
        touch -d "2026-01-01 00:00:00" "$t_dir/crates/depot-dl/Cargo.toml" "$t_dir/crates/depot-dl/Cargo.lock" "$t_dir/crates/depot-dl/src/main.rs"
        touch -d "2026-01-02 00:00:00" "$t_dir/bin/gamectl-depot-dl"
        bash "$t_dir/scripts/build-depot-dl.sh" --check >/dev/null 2>&1 || exit 1

        touch -d "2026-01-03 00:00:00" "$t_dir/crates/depot-dl/src/main.rs"
        local stale_out="" stale_rc=0
        stale_out=$(bash "$t_dir/scripts/build-depot-dl.sh" --check 2>&1) || stale_rc=$?
        [ "$stale_rc" -ne 0 ] || exit 1
        printf '%s\n' "$stale_out" | grep -q 'stale' || exit 1

        # 2. Pure Python wheel excludes native ELF
        grep -qx 'include src/gamectl_runner/bin/gamectl' "$REPO_ROOT/MANIFEST.in" || exit 1
        ! grep -q 'recursive-include src/gamectl_runner/bin' "$REPO_ROOT/MANIFEST.in" || exit 1
        [ ! -e "$REPO_ROOT/src/gamectl_runner/bin/gamectl-depot-dl" ] || exit 1

        # 3. Arch .SRCINFO files reflect x86_64 instead of any
        grep -q 'arch = x86_64' "$REPO_ROOT/packaging/arch/.SRCINFO" || exit 1
        ! grep -q 'arch = any' "$REPO_ROOT/packaging/arch/.SRCINFO" || exit 1
        grep -q 'arch = x86_64' "$REPO_ROOT/packaging/aur-git/.SRCINFO" || exit 1
        ! grep -q 'arch = any' "$REPO_ROOT/packaging/aur-git/.SRCINFO" || exit 1

        # 4. Debian package carries native arch matching ELF and declares zip dependency
        local deb_pkg deb_info
        deb_pkg=$(ls "$REPO_ROOT/packaging/debian"/gamectl_*_amd64.deb 2>/dev/null | head -n 1)
        [ -n "$deb_pkg" ] && [ -f "$deb_pkg" ] || exit 1
        deb_info=$(dpkg-deb -I "$deb_pkg") || exit 1
        printf '%s\n' "$deb_info" | grep -q 'Architecture: amd64' || exit 1
        printf '%s\n' "$deb_info" | grep -qE 'Depends:.*\bzip\b' || exit 1
    )
}
run_test "Packaging & Freshness (WP33 Packet 33B): .deb arch/zip, .SRCINFO x86_64, pure wheel & depot-dl freshness" test_packaging_arch_and_freshness_gate_contract

# Test 23: WP33 Packet 33C — Standalone-First get_compat_dir() & Optional/Strict shellcheck Lint
test_standalone_compat_dir_and_lint_gate_contract() {
    local t_dir
    t_dir=$(mktemp -d "${TMPDIR:-/tmp}/gamectl_wp33c_XXXXXX")
    mkdir -p "$t_dir/home" "$t_dir/xdg_data" "$t_dir/no_sc_bin"
    (
        trap 'rm -rf "$t_dir"' EXIT
        export HOME="$t_dir/home"
        export XDG_DATA_HOME="$t_dir/xdg_data"
        unset STEAM_ROOT GAMECTL_RUNNER_DIR
        source "$REPO_ROOT/src/core/00_header.sh"
        source "$REPO_ROOT/src/core/10_utils.sh"
        source "$REPO_ROOT/src/steam/20_discovery.sh"
        source "$REPO_ROOT/src/runners/40_wrappers.sh"

        # 1. Standalone machine without Steam falls back to XDG_DATA_HOME/gamectl/runners
        [ "$(get_compat_dir)" = "$t_dir/xdg_data/gamectl/runners" ] || exit 1

        # 2. Explicit GAMECTL_RUNNER_DIR override takes priority in both get_compat_dir and list_runner_dirs
        export GAMECTL_RUNNER_DIR="$t_dir/custom_runners"
        [ "$(get_compat_dir)" = "$t_dir/custom_runners" ] || exit 1
        [ "$(list_runner_dirs | head -n 1)" = "$t_dir/custom_runners" ] || exit 1

        # 3. make lint passes without shellcheck; STRICT_LINT=1 make lint fails deterministically
        local cmd_tool tool_path
        for cmd_tool in bash sh make dirname basename; do
            tool_path="$(command -v "$cmd_tool" 2>/dev/null || true)"
            [ -n "$tool_path" ] && ln -sf "$tool_path" "$t_dir/no_sc_bin/$cmd_tool"
        done
        local lint_out="" lint_rc=0
        lint_out=$(PATH="$t_dir/no_sc_bin" make -C "$REPO_ROOT" lint 2>&1) || lint_rc=$?
        [ "$lint_rc" -eq 0 ] || exit 1
        printf '%s\n' "$lint_out" | grep -q 'shellcheck not found' || exit 1

        local strict_rc=0
        PATH="$t_dir/no_sc_bin" STRICT_LINT=1 make -C "$REPO_ROOT" lint >/dev/null 2>&1 || strict_rc=$?
        [ "$strict_rc" -ne 0 ] || exit 1
    )
}
run_test "Standalone Runner & Lint (WP33 Packet 33C): XDG get_compat_dir fallback & STRICT_LINT gate" test_standalone_compat_dir_and_lint_gate_contract

# Test 24: WP34 Packet 34A — Multiline & Read-Only tui_modal_notice (Real PTY) + 3-Tier tui_run_engine Capture
test_wp34a_tui_primitives_and_engine_capture_contract() {
    local t_dir
    t_dir=$(mktemp -d "${TMPDIR:-/tmp}/gamectl_wp34a_XXXXXX")
    mkdir -p "$t_dir/runtime"
    (
        trap 'rm -rf "$t_dir"' EXIT
        export XDG_RUNTIME_DIR="$t_dir/runtime"
        source "$REPO_ROOT/src/core/00_header.sh"
        source "$REPO_ROOT/src/core/10_utils.sh"

        # 1. Non-TTY tui_modal_notice expands literal \n and preserves %s/%n and -e/-n verbatim
        local non_tty_out
        non_tty_out=$(tui_modal_notice "Alert" 'Line 1\nLine %s %n\n-e -n done' < /dev/null 2>/dev/null) || exit 1
        [ "$(printf '%s\n' "$non_tty_out" | wc -l)" -eq 4 ] || exit 1
        printf '%s\n' "$non_tty_out" | grep -Fq 'Line %s %n' || exit 1
        printf '%s\n' "$non_tty_out" | grep -Fq -- '-e -n done' || exit 1
        ! printf '%s\n' "$non_tty_out" | grep -Fq '\n' || exit 1
        local log_file
        log_file="$(get_runtime_log_file)"
        [ "$(grep -c '\[UI[ ]*\].*\[Alert\]' "$log_file")" -eq 1 ] || exit 1
        grep -q '\[Alert\] Line 1 | Line %s %n | -e -n done' "$log_file" || exit 1

        # 2. Real PTY + real fzf render verifies multiline layout without literal \n
        python3 - "$REPO_ROOT" "$t_dir/runtime" <<'PY' || exit 1
import errno, fcntl, os, pty, re, select, signal, struct, termios, time, sys

repo_root, runtime_dir = sys.argv[1], sys.argv[2]
pid, fd = pty.fork()
if pid == 0:
    os.environ["XDG_RUNTIME_DIR"] = runtime_dir
    os.environ["TERM"] = "xterm-256color"
    os.execvp("bash", [
        "bash", "-c",
        'source "$1/src/core/00_header.sh"; source "$1/src/core/10_utils.sh"; '
        'tui_modal_notice "Sync Test" "Line Alpha\\nLine Beta %s\\nLine Gamma"',
        "_", repo_root,
    ])

fcntl.ioctl(fd, termios.TIOCSWINSZ, struct.pack("HHHH", 24, 80, 0, 0))
output = bytearray()
sent_enter = False
status = None
try:
    deadline = time.monotonic() + 8.0
    while time.monotonic() < deadline:
        if select.select([fd], [], [], 0.05)[0]:
            try:
                chunk = os.read(fd, 65536)
            except OSError as err:
                if err.errno != errno.EIO:
                    raise
                chunk = b""
            output.extend(chunk)
            if b"\x1b[6n" in chunk:
                os.write(fd, b"\x1b[1;1R")
            if not sent_enter and b"Line Alpha" in output:
                os.write(fd, b"\r")
                sent_enter = True
        done, status_now = os.waitpid(pid, os.WNOHANG)
        if done:
            status = status_now
            while select.select([fd], [], [], 0)[0]:
                try:
                    chunk = os.read(fd, 65536)
                except OSError as err:
                    if err.errno != errno.EIO:
                        raise
                    break
                if not chunk:
                    break
                output.extend(chunk)
            break
finally:
    if status is None:
        os.killpg(pid, signal.SIGKILL)
        os.waitpid(pid, 0)
    os.close(fd)

assert status is not None, f"tui_modal_notice timed out in PTY: {bytes(output)!r}"
rc = os.waitstatus_to_exitcode(status)
text = re.sub(r"\x1b\[[0-9;?]*[ -/]*[@-~]", "", bytes(output).decode("utf-8", errors="replace"))
assert rc == 0, f"fzf rc={rc}, output={text!r}"
assert sent_enter, f"fzf did not render Line Alpha before exit: {text!r}"
assert "Line Alpha" in text, f"missing Line Alpha in {text!r}"
assert "Line Beta %s" in text, f"missing Line Beta %s in {text!r}"
assert "Line Gamma" in text, f"missing Line Gamma in {text!r}"
assert "\\n" not in text, f"literal \\n leaked in {text!r}"
PY

        # 3. tui_run_engine 3-tier error capture (stderr -> stdout fallback -> silent sentinel)
        local captured_msg=""
        tui_modal_notice() { captured_msg="$2"; return 0; }

        fail_stderr() { echo "STDERR_TRACE_LINE" >&2; echo "STDOUT_BACKGROUND_INFO"; return 11; }
        captured_msg=""
        ! tui_run_engine "ErrTask" fail_stderr >/dev/null 2>&1 || exit 1
        printf '%s\n' "$captured_msg" | grep -Fq 'STDERR_TRACE_LINE' || exit 1
        grep -Fq 'STDOUT_BACKGROUND_INFO' "$log_file" || exit 1

        fail_stdout_only() { echo "STDOUT_ONLY_REASON"; return 12; }
        captured_msg=""
        ! tui_run_engine "OutTask" fail_stdout_only >/dev/null 2>&1 || exit 1
        printf '%s\n' "$captured_msg" | grep -Fq 'STDOUT_ONLY_REASON' || exit 1
        grep -Fq 'STDOUT_ONLY_REASON' "$log_file" || exit 1

        fail_silent() { return 13; }
        captured_msg=""
        ! tui_run_engine "SilentTask" fail_silent >/dev/null 2>&1 || exit 1
        printf '%s\n' "$captured_msg" | grep -Fq 'No diagnostic output emitted.' || exit 1
    )
}
run_test "TUI Primitives (WP34 Packet 34A): real PTY multiline tui_modal_notice & 3-tier tui_run_engine capture" test_wp34a_tui_primitives_and_engine_capture_contract

# Test 25: WP34 Packet 34B — Engine Failure/Warning Stream Discipline (stderr >&2)
test_wp34b_engine_stderr_stream_discipline_contract() {
    local t_dir
    t_dir=$(mktemp -d "${TMPDIR:-/tmp}/gamectl_wp34b_XXXXXX")
    mkdir -p "$t_dir/home" "$t_dir/runtime" "$t_dir/no_saves_game" "$t_dir/game/saves"
    (
        trap 'rm -rf "$t_dir"' EXIT
        export HOME="$t_dir/home"
        export XDG_RUNTIME_DIR="$t_dir/runtime"
        unset GAMECTL_REMOTE_HOST GAMECTL_COMPANION_HOST GAMECTL_SYNC_HOST GAMECTL_TUF_HOST

        # 1. Zero echo [ERROR] lines without >&2 across src/
        if grep -rn 'echo.*\[ERROR\]' "$REPO_ROOT/src/" | grep -v '>&2' | grep -q .; then
            echo "Found echo [ERROR] without >&2 in src/" >&2
            exit 1
        fi

        source "$REPO_ROOT/src/core/00_header.sh"
        source "$REPO_ROOT/src/core/10_utils.sh"
        source "$REPO_ROOT/src/runners/50_launcher.sh"

        local out_f="$t_dir/stdout.txt" err_f="$t_dir/stderr.txt" rc=0

        # 2a. sync_save_remote missing saves/ emits [ERROR] to stderr only
        sync_save_remote "$t_dir/no_saves_game" "TestTitle" >"$out_f" 2>"$err_f" && rc=0 || rc=$?
        [ "$rc" -ne 0 ] || exit 1
        grep -Fq '[ERROR] Portable saves directory not found' "$err_f" || exit 1
        ! grep -qE '\[(ERROR|WARN)\]' "$out_f" || exit 1

        # 2b. sync_save_remote unconfigured host emits [WARN] to stderr only
        sync_save_remote "$t_dir/game" "TestTitle" >"$out_f" 2>"$err_f" && rc=0 || rc=$?
        [ "$rc" -ne 0 ] || exit 1
        grep -Fq '[WARN] Target remote host not configured.' "$err_f" || exit 1
        grep -Fq 'remote_host' "$err_f" || exit 1
        ! grep -qE '\[(ERROR|WARN)\]' "$out_f" || exit 1

        # 2c. sync_save_remote unreachable host emits [WARN] to stderr only
        ssh() { return 255; }
        sync_save_remote "$t_dir/game" "TestTitle" "unreachable_host" >"$out_f" 2>"$err_f" && rc=0 || rc=$?
        [ "$rc" -ne 0 ] || exit 1
        grep -q '\[WARN\] Remote host .* offline or unreachable' "$err_f" || exit 1
        ! grep -qE '\[(ERROR|WARN)\]' "$out_f" || exit 1
        unset -f ssh

        # 3. tui_run_engine surfaces sync_save_remote stderr directly into modal
        local modal_body=""
        tui_modal_notice() { modal_body="$2"; return 0; }
        ! tui_run_engine "Remote Sync" sync_save_remote "$t_dir/game" "TestTitle" >/dev/null 2>&1 || exit 1
        printf '%s\n' "$modal_body" | grep -Fq 'Target remote host not configured.' || exit 1
    )
}
run_test "Engine Stream Discipline (WP34 Packet 34B): stderr routing on sync_save_remote & fixes" test_wp34b_engine_stderr_stream_discipline_contract

# Test 26: WP34 Packet 34C — TUI Engine Routing Unification (9 Call Sites -> tui_run_engine)
test_wp34c_tui_engine_routing_unification_contract() {
    local t_dir
    t_dir=$(mktemp -d "${TMPDIR:-/tmp}/gamectl_wp34c_XXXXXX")
    mkdir -p "$t_dir/home" "$t_dir/runtime" "$t_dir/game/saves" "$t_dir/mock_bin"
    touch "$t_dir/game/game.exe"
    (
        trap 'rm -rf "$t_dir"' EXIT

        # 1. Static invariants: zero naked engine calls or launch_rc check_fzf_status violations in TUI
        if grep -nE 'if (create_desktop_entry|inject_game|sync_save_remote|pull_save_remote|backup_save|restore_save) ' "$REPO_ROOT/src/tui/70_dashboard.sh" | grep -q .; then
            echo "Found unrouted engine call in 70_dashboard.sh" >&2
            exit 1
        fi
        if grep -n 'launch_game ' "$REPO_ROOT/src/tui/70_dashboard.sh" | grep -v 'tui_run_engine' | grep -q .; then
            echo "Found bare launch_game call in 70_dashboard.sh" >&2
            exit 1
        fi
        if grep -n 'check_fzf_status "\$launch_rc"' "$REPO_ROOT/src/tui/70_dashboard.sh" | grep -q .; then
            echo "Found launch_rc check_fzf_status layer violation in 70_dashboard.sh" >&2
            exit 1
        fi
        if grep -nE 'if (revert_game_fix|install_game_fix) ' "$REPO_ROOT"/src/steam/3[58]_*.sh | grep -q .; then
            echo "Found unrouted fix engine call in src/steam/3[58]_*.sh" >&2
            exit 1
        fi

        # 2. Behavioral end-to-end: library_menu Ctrl-S routes through remote_sync_interactive -> tui_run_engine & surfaces real remote_host trace
        cat <<'EOF' > "$t_dir/mock_bin/fzf"
#!/usr/bin/env bash
cat >/dev/null
cnt_file="$HOME/fzf_cnt"
idx=0
[ -f "$cnt_file" ] && idx=$(cat "$cnt_file")
echo $((idx + 1)) > "$cnt_file"
if [ "$idx" -eq 0 ]; then
    printf 'ctrl-s\n%s\n' "$TEST_ROW"
    exit 0
elif [ "$idx" -eq 1 ]; then
    printf 'push\tPush Saves\n'
    exit 0
fi
exit 130
EOF
        chmod +x "$t_dir/mock_bin/fzf"

        python3 - "$REPO_ROOT" "$t_dir" <<'PY' || exit 1
import errno, os, pty, select, signal, sys, time

repo_root, t_dir = sys.argv[1], sys.argv[2]
row = f"105600\tTerraria\tSTANDALONE\t{t_dir}/game\tgame.exe"
pid, fd = pty.fork()
if pid == 0:
    os.environ["HOME"] = f"{t_dir}/home"
    os.environ["XDG_RUNTIME_DIR"] = f"{t_dir}/runtime"
    os.environ["PATH"] = f"{t_dir}/mock_bin:" + os.environ.get("PATH", "")
    os.environ["TEST_ROW"] = row
    os.environ["TEST_OUT_DIR"] = t_dir
    for k in ("GAMECTL_REMOTE_HOST", "GAMECTL_COMPANION_HOST", "GAMECTL_SYNC_HOST", "GAMECTL_TUF_HOST"):
        os.environ.pop(k, None)
    script = '''
source "$1/src/core/00_header.sh"
source "$1/src/core/10_utils.sh"
source "$1/src/steam/20_discovery.sh"
source "$1/src/runners/40_wrappers.sh"
source "$1/src/runners/50_launcher.sh"
source "$1/src/tui/70_dashboard.sh"
clean_stale_locks() { :; }
invalidate_scan_cache() { :; }
scan_installed_games() { printf '%s\\n' "$TEST_ROW"; }
tui_modal_notice() {
    printf '%s' "$1" > "$TEST_OUT_DIR/notice_title"
    printf '%s' "$2" > "$TEST_OUT_DIR/notice_body"
    return 0
}
library_menu
'''
    os.execvp("bash", ["bash", "-c", script, "_", repo_root])

output = bytearray()
status = None
try:
    deadline = time.monotonic() + 8.0
    while time.monotonic() < deadline:
        if select.select([fd], [], [], 0.05)[0]:
            try:
                chunk = os.read(fd, 65536)
            except OSError as err:
                if err.errno != errno.EIO:
                    raise
                chunk = b""
            output.extend(chunk)
        done, status_now = os.waitpid(pid, os.WNOHANG)
        if done:
            status = status_now
            break
finally:
    if status is None:
        os.killpg(pid, signal.SIGKILL)
        os.waitpid(pid, 0)
    os.close(fd)

assert status is not None and os.waitstatus_to_exitcode(status) == 0, f"library_menu failed: {bytes(output)!r}"
assert b"Target remote host not configured." not in output, f"raw stderr leaked to PTY: {bytes(output)!r}"
PY

        [ "$(cat "$t_dir/notice_title")" = "Remote Sync Error" ] || exit 1
        grep -Fq 'Target remote host not configured.' "$t_dir/notice_body" || exit 1

        # 3. Behavioral: tui_run_engine --fail-title preserves domain title on revert_game_fix failure
        export HOME="$t_dir/home"
        export XDG_RUNTIME_DIR="$t_dir/runtime"
        source "$REPO_ROOT/src/core/00_header.sh"
        source "$REPO_ROOT/src/core/10_utils.sh"
        source "$REPO_ROOT/src/steam/35_fixes.sh"
        tui_modal_notice() {
            printf '%s' "$1" > "$t_dir/revert_title"
            printf '%s' "$2" > "$t_dir/revert_body"
            return 0
        }
        ! tui_run_engine --fail-title "Revert Error" "Revert Test" revert_game_fix "$t_dir/game" >/dev/null 2>&1 || exit 1
        [ "$(cat "$t_dir/revert_title")" = "Revert Error" ] || exit 1
        grep -Fq 'No backup snapshots found in:' "$t_dir/revert_body" || exit 1
    )
}
run_test "TUI Engine Unification (WP34 Packet 34C): 9 call sites routed through tui_run_engine" test_wp34c_tui_engine_routing_unification_contract

# Test 27: WP34 Packet 34D — Unified Ctrl-S Remote Sync Palette (Push, Pull, Pull Dry-Run, Configure Host)
test_wp34d_ctrl_s_remote_sync_palette_contract() {
    local t_dir
    t_dir=$(mktemp -d "${TMPDIR:-/tmp}/gamectl_wp34d_XXXXXX")
    mkdir -p "$t_dir/home" "$t_dir/runtime" "$t_dir/game/saves" "$t_dir/mock_bin" "$t_dir/captures"
    touch "$t_dir/game/game.exe"
    (
        trap 'rm -rf "$t_dir"' EXIT

        # 1. Static invariants: definition, export, ctrl-s routing, and zero bare sync calls in 70_dashboard.sh
        grep -q '^remote_sync_interactive()' "$REPO_ROOT/src/tui/70_dashboard.sh" || exit 1
        grep -q 'export -f .*remote_sync_interactive' "$REPO_ROOT/src/main.sh" || exit 1
        grep -q 'remote_sync_interactive "\$sel_dir" "\$sel_title"' "$REPO_ROOT/src/tui/70_dashboard.sh" || exit 1
        if grep -nE '(sync_save_remote|pull_save_remote) ' "$REPO_ROOT/src/tui/70_dashboard.sh" | grep -v 'tui_run_engine' | grep -q .; then
            echo "Found unrouted sync_save_remote/pull_save_remote call in 70_dashboard.sh" >&2
            exit 1
        fi

        # Mock fzf scripted per call index using FZF_SCRIPT_FILE
        cat <<'EOF' > "$t_dir/mock_bin/fzf"
#!/usr/bin/env bash
cnt_file="$HOME/fzf_cnt"
idx=0
[ -f "$cnt_file" ] && idx=$(cat "$cnt_file")
echo $((idx + 1)) > "$cnt_file"
cat > "$TEST_CAP_DIR/stdin_${idx}.txt"
printf '%s\n' "$*" > "$TEST_CAP_DIR/args_${idx}.txt"
line=$(sed -n "$((idx + 1))p" "$FZF_SCRIPT_FILE" 2>/dev/null || true)
[ -z "$line" ] && exit 130
kind="${line%%|*}"
payload="${line#*|}"
case "$kind" in
    OUT)
        printf '%b\n' "$payload"
        exit 0
        ;;
    EXIT)
        exit "${payload:-130}"
        ;;
    *)
        exit 130
        ;;
esac
EOF
        chmod +x "$t_dir/mock_bin/fzf"

        # 2. Behavioral PTY test A: Palette options + Config flow (save, reject leading dash, Esc cancel, clear with '-')
        cat <<'EOF' > "$t_dir/script_config.txt"
OUT|config\tConfigure Remote Host - Set or clear SSH host (Current: Not configured)
OUT|companion-box
OUT|config\tConfigure Remote Host - Set or clear SSH host (Current: companion-box)
OUT|-oProxyCommand=bad
OUT|config\tConfigure Remote Host - Set or clear SSH host (Current: companion-box)
EXIT|130
OUT|config\tConfigure Remote Host - Set or clear SSH host (Current: companion-box)
OUT|-
EXIT|130
EOF

        python3 - "$REPO_ROOT" "$t_dir" <<'PY' || exit 1
import errno, os, pty, select, signal, sys, time

repo_root, t_dir = sys.argv[1], sys.argv[2]
pid, fd = pty.fork()
if pid == 0:
    os.environ["HOME"] = f"{t_dir}/home"
    os.environ["XDG_RUNTIME_DIR"] = f"{t_dir}/runtime"
    os.environ["PATH"] = f"{t_dir}/mock_bin:" + os.environ.get("PATH", "")
    os.environ["TEST_CAP_DIR"] = f"{t_dir}/captures"
    os.environ["FZF_SCRIPT_FILE"] = f"{t_dir}/script_config.txt"
    os.environ["TEST_OUT_DIR"] = t_dir
    for k in ("GAMECTL_REMOTE_HOST", "GAMECTL_COMPANION_HOST", "GAMECTL_SYNC_HOST", "GAMECTL_TUF_HOST"):
        os.environ.pop(k, None)
    script = '''
source "$1/src/core/00_header.sh"
source "$1/src/core/10_utils.sh"
source "$1/src/steam/20_discovery.sh"
source "$1/src/runners/40_wrappers.sh"
source "$1/src/runners/50_launcher.sh"
source "$1/src/tui/70_dashboard.sh"
tui_modal_notice() {
    printf '%s|%s\\n' "$1" "$2" >> "$TEST_OUT_DIR/notices.log"
    return 0
}
remote_sync_interactive "$TEST_OUT_DIR/game" "Terraria"
if [ -f "$HOME/.config/gamectl/remote_host" ]; then
    echo "STILL_EXISTS" > "$TEST_OUT_DIR/after_clear"
else
    echo "CLEARED" > "$TEST_OUT_DIR/after_clear"
fi
'''
    os.execvp("bash", ["bash", "-c", script, "_", repo_root])

output = bytearray()
status = None
try:
    deadline = time.monotonic() + 8.0
    while time.monotonic() < deadline:
        if select.select([fd], [], [], 0.05)[0]:
            try:
                chunk = os.read(fd, 65536)
            except OSError as err:
                if err.errno != errno.EIO:
                    raise
                chunk = b""
            output.extend(chunk)
        done, status_now = os.waitpid(pid, os.WNOHANG)
        if done:
            status = status_now
            break
finally:
    if status is None:
        os.killpg(pid, signal.SIGKILL)
        os.waitpid(pid, 0)
    os.close(fd)

assert status is not None and os.waitstatus_to_exitcode(status) == 0, f"config flow failed: {bytes(output)!r}"
with open(f"{t_dir}/captures/stdin_0.txt") as f:
    pal0 = f.read()
for label in ("Push Saves", "Pull Saves", "Pull Dry-Run", "Configure Remote Host"):
    assert label in pal0, f"Missing palette option {label!r} in:\n{pal0}"
with open(f"{t_dir}/captures/args_2.txt") as f:
    args2 = f.read()
assert "Host: companion-box" in args2, f"Expected refreshed host in palette header: {args2!r}"
with open(f"{t_dir}/notices.log") as f:
    notices = f.read()
assert "Remote Companion Host|Saved remote companion host:" in notices, f"Missing save notice: {notices!r}"
assert "Invalid Remote Host|Remote host cannot start with '-':" in notices, f"Missing invalid-host notice: {notices!r}"
assert "Remote Companion Host|Cleared remote companion host." in notices, f"Missing clear notice: {notices!r}"
with open(f"{t_dir}/after_clear") as f:
    assert f.read().strip() == "CLEARED"
PY

        # 3. Behavioral PTY test B: push, pull, pull-dry success & failure routing via tui_run_engine
        rm -rf "$t_dir/captures"/* "$t_dir/notices.log" "$t_dir/home/fzf_cnt"
        cat <<'EOF' > "$t_dir/script_actions.txt"
OUT|push\tPush Saves
OUT|pull\tPull Saves
OUT|pull-dry\tPull Dry-Run
OUT|push\tPush Saves
OUT|pull\tPull Saves
OUT|pull-dry\tPull Dry-Run
EXIT|130
EOF

        python3 - "$REPO_ROOT" "$t_dir" <<'PY' || exit 1
import errno, os, pty, select, signal, sys, time

repo_root, t_dir = sys.argv[1], sys.argv[2]
pid, fd = pty.fork()
if pid == 0:
    os.environ["HOME"] = f"{t_dir}/home"
    os.environ["XDG_RUNTIME_DIR"] = f"{t_dir}/runtime"
    os.environ["PATH"] = f"{t_dir}/mock_bin:" + os.environ.get("PATH", "")
    os.environ["TEST_CAP_DIR"] = f"{t_dir}/captures"
    os.environ["FZF_SCRIPT_FILE"] = f"{t_dir}/script_actions.txt"
    os.environ["TEST_OUT_DIR"] = t_dir
    os.environ["GAMECTL_REMOTE_HOST"] = "tuf-box"
    script = '''
source "$1/src/core/00_header.sh"
source "$1/src/core/10_utils.sh"
source "$1/src/steam/20_discovery.sh"
source "$1/src/runners/40_wrappers.sh"
source "$1/src/runners/50_launcher.sh"
source "$1/src/tui/70_dashboard.sh"
CALL_IDX_FILE="$TEST_OUT_DIR/call_idx"
sync_save_remote() {
    local c=0
    [ -f "$CALL_IDX_FILE" ] && c=$(cat "$CALL_IDX_FILE")
    echo $((c + 1)) > "$CALL_IDX_FILE"
    printf 'PUSH|%s|%s|%s\\n' "${GAMECTL_ENGINE_ISOLATED:-0}" "$1" "$2" >> "$TEST_OUT_DIR/calls.log"
    if [ "$c" -ge 3 ]; then
        echo "[ERROR] Simulated push failure on stderr" >&2
        return 1
    fi
    echo "[VERIFIED] Push ok"
    return 0
}
pull_save_remote() {
    local c=0
    [ -f "$CALL_IDX_FILE" ] && c=$(cat "$CALL_IDX_FILE")
    echo $((c + 1)) > "$CALL_IDX_FILE"
    printf 'PULL|%s|%s|%s|%s\\n' "${GAMECTL_ENGINE_ISOLATED:-0}" "$1" "$2" "${3:-}" >> "$TEST_OUT_DIR/calls.log"
    if [ "$c" -ge 3 ]; then
        echo "[ERROR] Simulated pull failure ${3:-real} on stderr" >&2
        return 1
    fi
    echo "[VERIFIED] Pull ok"
    return 0
}
tui_modal_notice() {
    printf 'NOTICE:%s::%s\\n---\\n' "$1" "${2//$'\n'/ | }" >> "$TEST_OUT_DIR/actions_notices.log"
    return 0
}
remote_sync_interactive "$TEST_OUT_DIR/game" "Terraria"
'''
    os.execvp("bash", ["bash", "-c", script, "_", repo_root])

output = bytearray()
status = None
try:
    deadline = time.monotonic() + 8.0
    while time.monotonic() < deadline:
        if select.select([fd], [], [], 0.05)[0]:
            try:
                chunk = os.read(fd, 65536)
            except OSError as err:
                if err.errno != errno.EIO:
                    raise
                chunk = b""
            output.extend(chunk)
        done, status_now = os.waitpid(pid, os.WNOHANG)
        if done:
            status = status_now
            break
finally:
    if status is None:
        os.killpg(pid, signal.SIGKILL)
        os.waitpid(pid, 0)
    os.close(fd)

assert status is not None and os.waitstatus_to_exitcode(status) == 0, f"actions flow failed: {bytes(output)!r}"
assert b"Simulated push failure on stderr" not in output, f"raw stderr leaked to PTY: {bytes(output)!r}"
assert b"Simulated pull failure" not in output, f"raw stderr leaked to PTY: {bytes(output)!r}"

with open(f"{t_dir}/calls.log") as f:
    calls = [line.strip() for line in f if line.strip()]
expected_calls = [
    f"PUSH|1|{t_dir}/game|Terraria",
    f"PULL|1|{t_dir}/game|Terraria|",
    f"PULL|1|{t_dir}/game|Terraria|--dry-run",
    f"PUSH|1|{t_dir}/game|Terraria",
    f"PULL|1|{t_dir}/game|Terraria|",
    f"PULL|1|{t_dir}/game|Terraria|--dry-run",
]
assert calls == expected_calls, f"Unexpected calls: {calls!r}"

with open(f"{t_dir}/actions_notices.log") as f:
    notices = f.read()
for expected_notice in (
    "NOTICE:Remote Sync (Push)::Savegames pushed to tuf-box",
    "NOTICE:Remote Sync (Pull)::Savegames pulled from tuf-box",
    "NOTICE:Remote Pull (Dry-Run)::Dry-run pull simulation completed from tuf-box",
    "NOTICE:Remote Sync Error::Operation returned Exit Code 1.",
    "Simulated push failure on stderr",
    "NOTICE:Remote Pull Error::Operation returned Exit Code 1.",
    "Simulated pull failure real on stderr",
    "NOTICE:Remote Pull Dry-Run Error::Operation returned Exit Code 1.",
    "Simulated pull failure --dry-run on stderr",
):
    assert expected_notice in notices, f"Missing {expected_notice!r} in:\n{notices}"
PY
    )
}
run_test "Unified Ctrl-S Remote Sync Palette (WP34 Packet 34D): Push, Pull, Dry-Run & Config routing" test_wp34d_ctrl_s_remote_sync_palette_contract

# Test 28: WP35 — Remote Sync Resolver, Honest SSH Diagnostics, Custom SSH Paths & Rclone Backend
test_wp35_remote_sync_resolver_ssh_diagnostics_and_rclone_contract() {
    local t_dir
    t_dir=$(mktemp -d "${TMPDIR:-/tmp}/gamectl_wp35_XXXXXX")
    mkdir -p "$t_dir/home" "$t_dir/remote_home" "$t_dir/rclone_store" "$t_dir/runtime/active_games" \
             "$t_dir/mock_bin" "$t_dir/captures" "$t_dir/MyGame/saves" "$t_dir/DryGame"
    printf 'save_local_v1\n' > "$t_dir/MyGame/saves/data.sav"

    # Mock ssh: logs args, optionally returns targeted auth/hostkey/dns errors, or runs sh -c against MOCK_REMOTE_HOME
    cat <<'EOF' > "$t_dir/mock_bin/ssh"
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$MOCK_SSH_ARGS_LOG"
case "${MOCK_SSH_MODE:-ok}" in
    auth)
        echo "aomiqaza@100.101.15.31: Permission denied (publickey)." >&2
        exit 255
        ;;
    hostkey)
        echo "Host key verification failed." >&2
        exit 255
        ;;
    dns)
        echo "ssh: Could not resolve hostname badhost: Name or service not known" >&2
        exit 255
        ;;
esac
while [ $# -gt 0 ]; do
    case "$1" in
        -q|-n|-T|-N|-x|-v|-Y|-A|-a|-C|-f|-g|-k|-M|-O|-s|-t|-V|-X)
            shift ;;
        -o|-l|-p|-i|-F|-J|-W|-b|-c|-D|-E|-e|-I|-L|-m|-Q|-R|-S|-w)
            shift 2 ;;
        --)
            shift; break ;;
        -*)
            shift ;;
        *)
            break ;;
    esac
done
shift || true
export HOME="$MOCK_REMOTE_HOME"
if [ "${1:-}" = "rsync" ]; then
    exec "$@"
fi
exec /bin/sh -c "$*"
EOF
    chmod +x "$t_dir/mock_bin/ssh"

    # Mock rclone backed by $MOCK_RCLONE_STORE
    cat <<'EOF' > "$t_dir/mock_bin/rclone"
#!/usr/bin/env bash
sub="${1:-}"
shift || true
case "$sub" in
    listremotes)
        printf 'gdrive:\nproton:\n'
        exit 0
        ;;
    lsf)
        while [ $# -gt 0 ]; do
            [ "$1" = "--" ] && { shift; break; }
            shift
        done
        target="${1:-}"
        rel="${target#*:}"
        rel="${rel#/}"
        real_dir="$MOCK_RCLONE_STORE/${target%%:*}/$rel"
        if [ ! -d "$real_dir" ]; then
            echo "ERROR : error listing: directory not found" >&2
            exit 3
        fi
        ls -1 "$real_dir"
        exit 0
        ;;
    copy)
        is_dry=false
        while [ $# -gt 0 ]; do
            case "$1" in
                --dry-run) is_dry=true; shift ;;
                --) shift; break ;;
                --exclude|--contimeout|--timeout|--retries|--low-level-retries) shift 2 ;;
                *) shift ;;
            esac
        done
        src="${1:-}"
        dst="${2:-}"
        map_path() {
            local p="$1"
            if [[ "$p" == *:* ]]; then
                local r="${p%%:*}"
                local rel="${p#*:}"
                rel="${rel#/}"
                printf '%s/%s/%s' "$MOCK_RCLONE_STORE" "$r" "$rel"
            else
                printf '%s' "$p"
            fi
        }
        src_fs=$(map_path "$src")
        dst_fs=$(map_path "$dst")
        if [ ! -d "$src_fs" ]; then
            echo "ERROR : source directory not found: $src" >&2
            exit 3
        fi
        if [ "$is_dry" = true ]; then
            echo "NOTICE: dry-run simulated copy $src -> $dst"
            exit 0
        fi
        mkdir -p "$dst_fs"
        cp -a "$src_fs/." "$dst_fs/"
        exit 0
        ;;
esac
exit 1
EOF
    chmod +x "$t_dir/mock_bin/rclone"

    local bg_pid=""
    (
        trap '[ -n "$bg_pid" ] && kill "$bg_pid" 2>/dev/null || true; rm -rf "$t_dir"' EXIT
        export HOME="$t_dir/home"
        export MOCK_REMOTE_HOME="$t_dir/remote_home"
        export MOCK_RCLONE_STORE="$t_dir/rclone_store"
        export MOCK_SSH_ARGS_LOG="$t_dir/ssh_args.log"
        export XDG_RUNTIME_DIR="$t_dir/runtime"
        export PATH="$t_dir/mock_bin:$PATH"
        unset GAMECTL_REMOTE_HOST GAMECTL_COMPANION_HOST GAMECTL_SYNC_HOST GAMECTL_TUF_HOST GAMECTL_SSH_TIMEOUT

        source "$REPO_ROOT/src/core/00_header.sh"
        source "$REPO_ROOT/src/core/10_utils.sh"
        source "$REPO_ROOT/src/runners/50_launcher.sh"
        source "$REPO_ROOT/src/tui/70_dashboard.sh"

        local out_f="$t_dir/out.txt" err_f="$t_dir/err.txt" rc=0

        # 1. Honest SSH diagnostics + ConnectTimeout default 5s and override
        MOCK_SSH_MODE=auth sync_save_remote "$t_dir/MyGame" "MyGame" "serv" >"$out_f" 2>"$err_f" && rc=0 || rc=$?
        [ "$rc" -ne 0 ] || exit 1
        grep -Fq '[ERROR] SSH authentication failed' "$err_f" || exit 1
        grep -Fq 'ssh-add' "$err_f" || exit 1
        ! grep -Fq 'offline or unreachable' "$err_f" || exit 1
        grep -Fq 'ConnectTimeout=5' "$MOCK_SSH_ARGS_LOG" || exit 1

        : > "$MOCK_SSH_ARGS_LOG"
        GAMECTL_SSH_TIMEOUT=9 MOCK_SSH_MODE=hostkey sync_save_remote "$t_dir/MyGame" "MyGame" "serv" >"$out_f" 2>"$err_f" && rc=0 || rc=$?
        [ "$rc" -ne 0 ] || exit 1
        grep -Fq '[ERROR] SSH host key verification failed' "$err_f" || exit 1
        grep -Fq 'ConnectTimeout=9' "$MOCK_SSH_ARGS_LOG" || exit 1

        MOCK_SSH_MODE=dns sync_save_remote "$t_dir/MyGame" "MyGame" "badhost" >"$out_f" 2>"$err_f" && rc=0 || rc=$?
        [ "$rc" -ne 0 ] || exit 1
        grep -Fq '[ERROR] SSH hostname' "$err_f" || exit 1

        # 2. SSH custom base path (mockhost:~/Trash/gamectl-testing & user@mockhost:~/Trash/gamectl-testing)
        export MOCK_SSH_MODE=ok
        sync_save_remote "$t_dir/MyGame" "MyGame" "mockhost:~/Trash/gamectl-testing" >"$out_f" 2>"$err_f" || exit 1
        [ "$(cat "$t_dir/remote_home/Trash/gamectl-testing/MyGame/saves/data.sav")" = "save_local_v1" ] || exit 1

        printf 'save_remote_v2\n' > "$t_dir/remote_home/Trash/gamectl-testing/MyGame/saves/data.sav"
        mkdir -p "$t_dir/remote_home/Trash/gamectl-testing/DryGame/saves"
        printf 'dry_val\n' > "$t_dir/remote_home/Trash/gamectl-testing/DryGame/saves/data.sav"
        pull_save_remote "$t_dir/DryGame" "DryGame" "aomiqaza@mockhost:~/Trash/gamectl-testing" --dry-run >"$out_f" 2>"$err_f" || exit 1
        [ ! -d "$t_dir/DryGame/saves" ] || exit 1

        pull_save_remote "$t_dir/MyGame" "MyGame" "aomiqaza@mockhost:~/Trash/gamectl-testing" >"$out_f" 2>"$err_f" || exit 1
        [ "$(cat "$t_dir/MyGame/saves/data.sav")" = "save_remote_v2" ] || exit 1
        [ "$(cat "$t_dir/MyGame/.save_snapshots/slot1/data.sav")" = "save_local_v1" ] || exit 1

        # Path traversal guard on SSH custom path
        ! sync_save_remote "$t_dir/MyGame" "MyGame" "mockhost:~/../etc" >"$out_f" 2>"$err_f" || exit 1
        grep -Fq 'path traversal' "$err_f" || exit 1

        # 3. rclone backend: default path (gdrive:), custom prefix (gdrive:Trash/gamectl-testing), explicit rclone:gdrive:sub/dir
        sync_save_remote "$t_dir/MyGame" "MyGame" "gdrive:" >"$out_f" 2>"$err_f" || exit 1
        [ "$(cat "$t_dir/rclone_store/gdrive/gamectl-saves/MyGame/saves/data.sav")" = "save_remote_v2" ] || exit 1

        sync_save_remote "$t_dir/MyGame" "MyGame" "gdrive:Trash/gamectl-testing" >"$out_f" 2>"$err_f" || exit 1
        [ "$(cat "$t_dir/rclone_store/gdrive/Trash/gamectl-testing/MyGame/saves/data.sav")" = "save_remote_v2" ] || exit 1

        sync_save_remote "$t_dir/MyGame" "MyGame" "rclone:gdrive:sub/dir" >"$out_f" 2>"$err_f" || exit 1
        [ "$(cat "$t_dir/rclone_store/gdrive/sub/dir/MyGame/saves/data.sav")" = "save_remote_v2" ] || exit 1

        # rclone pull --dry-run must NOT create DryGame/saves; missing remote dir must fail to stderr without [VERIFIED]
        mkdir -p "$t_dir/rclone_store/gdrive/Trash/gamectl-testing/DryGame/saves"
        printf 'rclone_dry\n' > "$t_dir/rclone_store/gdrive/Trash/gamectl-testing/DryGame/saves/data.sav"
        pull_save_remote "$t_dir/DryGame" "DryGame" "gdrive:Trash/gamectl-testing" --dry-run >"$out_f" 2>"$err_f" || exit 1
        [ ! -d "$t_dir/DryGame/saves" ] || exit 1

        ! pull_save_remote "$t_dir/DryGame" "DryGame" "gdrive:missing-prefix" >"$out_f" 2>"$err_f" || exit 1
        grep -Fq '[ERROR] Remote saves directory not found or inaccessible' "$err_f" || exit 1
        ! grep -Fq '[VERIFIED]' "$out_f" || exit 1

        # rclone real pull creates pre-pull backup snapshot and pulls remote state
        printf 'rclone_v3\n' > "$t_dir/rclone_store/gdrive/Trash/gamectl-testing/MyGame/saves/data.sav"
        pull_save_remote "$t_dir/MyGame" "MyGame" "gdrive:Trash/gamectl-testing" >"$out_f" 2>"$err_f" || exit 1
        [ "$(cat "$t_dir/MyGame/saves/data.sav")" = "rclone_v3" ] || exit 1
        [ "$(cat "$t_dir/MyGame/.save_snapshots/slot1/data.sav")" = "save_remote_v2" ] || exit 1

        # rclone rejects unknown remote and '~' prefix
        ! sync_save_remote "$t_dir/MyGame" "MyGame" "nonexistent:" >"$out_f" 2>"$err_f" || exit 1
        grep -Fq 'not found' "$err_f" || exit 1
        ! sync_save_remote "$t_dir/MyGame" "MyGame" "gdrive:~/bad" >"$out_f" 2>"$err_f" || exit 1
        grep -Fq "cannot start with '~'" "$err_f" || exit 1

        # Active-game guard blocks rclone push (unless --force) and pull
        sleep 30 &
        bg_pid=$!
        printf 'PID=%s\nDIR=%s\n' "$bg_pid" "$t_dir/MyGame" > "$t_dir/runtime/active_games/${bg_pid}.info"
        ! sync_save_remote "$t_dir/MyGame" "MyGame" "gdrive:Trash/gamectl-testing" >/dev/null 2>&1 || exit 1
        ! pull_save_remote "$t_dir/MyGame" "MyGame" "gdrive:Trash/gamectl-testing" >/dev/null 2>&1 || exit 1
        sync_save_remote "$t_dir/MyGame" "MyGame" "gdrive:Trash/gamectl-testing" --force >/dev/null 2>&1 || exit 1
        kill "$bg_pid" 2>/dev/null || true
        wait "$bg_pid" 2>/dev/null || true
        bg_pid=""

        # 4. TUI config validation rejects unknown_remote: and saves serv:~/Trash/gamectl-testing & gdrive:Trash/gamectl-testing
        cat <<'EOF' > "$t_dir/mock_bin/fzf"
#!/usr/bin/env bash
cat >/dev/null
cnt_file="$HOME/fzf_wp35_cnt"
idx=0
[ -f "$cnt_file" ] && idx=$(cat "$cnt_file")
echo $((idx + 1)) > "$cnt_file"
case "$idx" in
    0) printf 'config\tConfigure Remote Host\n'; exit 0 ;;
    1) printf 'serv:~/Trash/gamectl-testing\n'; exit 0 ;;
    2) printf 'config\tConfigure Remote Host\n'; exit 0 ;;
    3) printf 'unknown_remote:\n'; exit 0 ;;
    4) printf 'config\tConfigure Remote Host\n'; exit 0 ;;
    5) printf 'gdrive:Trash/gamectl-testing\n'; exit 0 ;;
    *) exit 130 ;;
esac
EOF
        chmod +x "$t_dir/mock_bin/fzf"

        python3 - "$REPO_ROOT" "$t_dir" <<'PY' || exit 1
import errno, os, pty, select, signal, sys, time

repo_root, t_dir = sys.argv[1], sys.argv[2]
pid, fd = pty.fork()
if pid == 0:
    os.environ["HOME"] = f"{t_dir}/home"
    os.environ["XDG_RUNTIME_DIR"] = f"{t_dir}/runtime"
    os.environ["PATH"] = f"{t_dir}/mock_bin:" + os.environ.get("PATH", "")
    os.environ["TEST_OUT_DIR"] = t_dir
    script = '''
source "$1/src/core/00_header.sh"
source "$1/src/core/10_utils.sh"
source "$1/src/steam/20_discovery.sh"
source "$1/src/runners/40_wrappers.sh"
source "$1/src/runners/50_launcher.sh"
source "$1/src/tui/70_dashboard.sh"
tui_modal_notice() {
    printf '%s|%s\\n' "$1" "${2//$'\n'/ }" >> "$TEST_OUT_DIR/wp35_notices.log"
    return 0
}
remote_sync_interactive "$TEST_OUT_DIR/MyGame" "MyGame"
'''
    os.execvp("bash", ["bash", "-c", script, "_", repo_root])

output = bytearray()
status = None
try:
    deadline = time.monotonic() + 8.0
    while time.monotonic() < deadline:
        if select.select([fd], [], [], 0.05)[0]:
            try:
                chunk = os.read(fd, 65536)
            except OSError as err:
                if err.errno != errno.EIO:
                    raise
                chunk = b""
            output.extend(chunk)
        done, status_now = os.waitpid(pid, os.WNOHANG)
        if done:
            status = status_now
            break
finally:
    if status is None:
        os.killpg(pid, signal.SIGKILL)
        os.waitpid(pid, 0)
    os.close(fd)

assert status is not None and os.waitstatus_to_exitcode(status) == 0, f"TUI config validation failed: {bytes(output)!r}"
with open(f"{t_dir}/wp35_notices.log") as f:
    notices = f.read()
assert "Remote Companion Host|Saved remote companion host:\\nserv:~/Trash/gamectl-testing" in notices, notices
assert "Invalid Remote Target|" in notices and "unknown_remote:" in notices, notices
assert "Remote Companion Host|Saved remote companion host:\\ngdrive:Trash/gamectl-testing" in notices, notices
with open(f"{t_dir}/home/.config/gamectl/remote_host") as f:
    assert f.read().strip() == "gdrive:Trash/gamectl-testing"
PY
    )
}
run_test "Remote Sync Resolver, SSH Diagnostics & Rclone (WP35)" test_wp35_remote_sync_resolver_ssh_diagnostics_and_rclone_contract

# Test 29: WP36B Wine prefix save auto-locate, noise/escape guards, and backup/restore roundtrip
test_wp36b_prefix_save_auto_locate_contract() {
    local t_dir
    t_dir=$(mktemp -d "/tmp/gamectl_wp36b_test.XXXXXX")
    local bg_pid=""

    (
        trap '[ -n "$bg_pid" ] && kill "$bg_pid" 2>/dev/null || true; rm -rf "$t_dir"' EXIT
        export HOME="$t_dir/home"
        export XDG_RUNTIME_DIR="$t_dir/runtime"
        mkdir -p -m 700 "$HOME" "$XDG_RUNTIME_DIR/active_games"

        local gdir="$t_dir/MyPrefixGame"
        local users="$gdir/pfx/drive_c/users"
        local udir="$users/steamuser"
        mkdir -p \
            "$udir/AppData/Local/StudioA" \
            "$udir/AppData/Roaming/GameB" \
            "$udir/Documents/My Games/GameC" \
            "$udir/Saved Games/GameD" \
            "$udir/AppData/Local/Microsoft" \
            "$udir/AppData/Local/Temp" \
            "$udir/AppData/Local/NVIDIA" \
            "$udir/AppData/Roaming/Goldberg SteamEmu Saves" \
            "$udir/AppData/Local/EmptyMod" \
            "$udir/AppData/Roaming/BadGame" \
            "$t_dir/outside_secret"

        printf 'v1_local\n' > "$udir/AppData/Local/StudioA/save1.dat"
        printf 'v1_roaming\n' > "$udir/AppData/Roaming/GameB/profile.bin"
        printf 'v1_docs\n' > "$udir/Documents/My Games/GameC/slot.sav"
        printf 'v1_saved\n' > "$udir/Saved Games/GameD/world.dat"
        printf 'noise\n' > "$udir/AppData/Local/Microsoft/noise.dat"
        printf 'noise\n' > "$udir/AppData/Local/Temp/tmp.dat"
        printf 'noise\n' > "$udir/AppData/Local/NVIDIA/shader.bin"
        printf 'gbe\n' > "$udir/AppData/Roaming/Goldberg SteamEmu Saves/gbe.dat"
        printf 'secret\n' > "$t_dir/outside_secret/secret.txt"
        printf 'ok\n' > "$udir/AppData/Roaming/BadGame/normal.dat"

        ln -s "$udir/Documents" "$udir/My Documents"
        ln -s "$t_dir/outside_secret" "$udir/AppData/Local/EscapeDir"
        ln -s "$t_dir/outside_secret/secret.txt" "$udir/AppData/Roaming/BadGame/escape.dat"

        source "$REPO_ROOT/src/core/00_header.sh"
        source "$REPO_ROOT/src/core/10_utils.sh"

        local disc_out err_f="$t_dir/err.txt"
        disc_out=$(discover_prefix_saves "$gdir" 2>"$err_f") || exit 1
        local expected
        expected=$(printf '%s\n' \
            "steamuser/AppData/Local/StudioA" \
            "steamuser/AppData/Roaming/GameB" \
            "steamuser/Documents/My Games/GameC" \
            "steamuser/Saved Games/GameD")
        [ "$disc_out" = "$expected" ] || { echo "Unexpected discovery: $disc_out"; exit 1; }
        grep -Fq 'Rejected escaping prefix save' "$err_f" || exit 1
        [ ! -e "$gdir/saves" ] || exit 1

        # Active-game guard blocks collect & restore
        sleep 30 &
        bg_pid=$!
        printf 'PID=%s\nDIR=%s\n' "$bg_pid" "$gdir" > "$XDG_RUNTIME_DIR/active_games/${bg_pid}.info"
        ! collect_prefix_saves "$gdir" true 2>/dev/null || exit 1
        ! restore_prefix_saves "$gdir" true 2>/dev/null || exit 1
        kill "$bg_pid" 2>/dev/null || true
        wait "$bg_pid" 2>/dev/null || true
        bg_pid=""

        # Collect -> backup -> overwrite -> restore -> restore_prefix_saves roundtrip
        collect_prefix_saves "$gdir" true || exit 1
        [ "$(cat "$gdir/saves/_prefix_saves/steamuser/AppData/Local/StudioA/save1.dat")" = "v1_local" ] || exit 1
        [ ! -e "$gdir/saves/_prefix_saves/steamuser/AppData/Local/EscapeDir" ] || exit 1

        backup_save "$gdir" true || exit 1
        printf 'corrupted\n' > "$udir/AppData/Local/StudioA/save1.dat"
        restore_save "$gdir" 1 true || exit 1
        restore_prefix_saves "$gdir" true || exit 1
        [ "$(cat "$udir/AppData/Local/StudioA/save1.dat")" = "v1_local" ] || exit 1

        # CLI entrypoint parity via compiled bin/gamectl
        "$REPO_ROOT/scripts/build.sh" >/dev/null
        local cli_out
        cli_out=$("$REPO_ROOT/bin/gamectl" scan-saves "$gdir" 2>/dev/null) || exit 1
        [ "$cli_out" = "$expected" ] || exit 1
        rm -rf "$gdir/saves/_prefix_saves"
        "$REPO_ROOT/bin/gamectl" collect-saves "$gdir" >/dev/null || exit 1
        [ "$(cat "$gdir/saves/_prefix_saves/steamuser/Saved Games/GameD/world.dat")" = "v1_saved" ] || exit 1
    )
}
run_test "Wine Prefix Save Auto-Locate & Safety Contracts (WP36B)" test_wp36b_prefix_save_auto_locate_contract

# Test 30: WP36C Game Developer Mode & Engine Profiler contracts
test_wp36c_dev_profiler_contract() {
    local t_dir
    t_dir=$(mktemp -d "/tmp/gamectl_wp36c_test.XXXXXX")

    (
        trap 'rm -rf "$t_dir"' EXIT
        export HOME="$t_dir/home"
        export XDG_RUNTIME_DIR="$t_dir/runtime"
        mkdir -p -m 700 "$HOME/.config/gamectl" "$XDG_RUNTIME_DIR"
        unset WINEDEBUG VK_LOADER_DEBUG GAMECTL_DEV_WINEDEBUG GAMECTL_DEV_VK_DEBUG GAMECTL_DEV_GBE_LOG

        local gdir="$t_dir/DevGame"
        mkdir -p "$gdir"
        printf 'gamemode=1\n' > "$gdir/.wrappers"

        cat <<'EOF' > "$gdir/devprobe.sh"
#!/usr/bin/env bash
printf 'CHILD_WINEDEBUG=%s\nCHILD_VK=%s\nCHILD_GBE=%s\n' \
    "${WINEDEBUG:-UNSET}" "${VK_LOADER_DEBUG:-UNSET}" "${GAMECTL_GBE_LOG:-0}"
sleep 0.2
EOF
        chmod +x "$gdir/devprobe.sh"

        source "$REPO_ROOT/src/core/00_header.sh"
        source "$REPO_ROOT/src/core/10_utils.sh"
        source "$REPO_ROOT/src/steam/20_discovery.sh"
        source "$REPO_ROOT/src/steam/25_identity.sh"
        source "$REPO_ROOT/src/steam/30_downloader.sh"
        source "$REPO_ROOT/src/runners/40_wrappers.sh"
        source "$REPO_ROOT/src/runners/50_launcher.sh"

        # 1. Default OFF: zero env pollution, no trace dir
        resolve_dev_profiler_env "$gdir" 1
        [ "$GAMECTL_DEV_ACTIVE" -eq 0 ] || exit 1
        [ -z "$GAMECTL_DEV_RESOLVED_WINEDEBUG" ] || exit 1
        [ -z "$GAMECTL_DEV_RESOLVED_VK_DEBUG" ] || exit 1
        [ "$GAMECTL_DEV_RESOLVED_GBE_LOG" -eq 0 ] || exit 1
        [ -z "$GAMECTL_DEV_TRACE_LOG" ] || exit 1
        [ ! -d "$(get_runtime_dir)/dev_traces" ] || exit 1
        [ -z "${WINEDEBUG+x}" ] || exit 1
        [ -z "${VK_LOADER_DEBUG+x}" ] || exit 1

        # 2. CLI persistence basic/full/status/off preserves unrelated keys
        "$REPO_ROOT/scripts/build.sh" >/dev/null
        "$REPO_ROOT/bin/gamectl" dev-profile "$gdir" basic >/dev/null || exit 1
        grep -q '^gamemode=1$' "$gdir/.wrappers" || exit 1
        resolve_dev_profiler_env "$gdir" 1
        [ "$GAMECTL_DEV_ACTIVE" -eq 1 ] || exit 1
        [ "$GAMECTL_DEV_RESOLVED_WINEDEBUG" = "+loaddll,+seh" ] || exit 1
        [ -z "$GAMECTL_DEV_RESOLVED_VK_DEBUG" ] || exit 1
        [ "$GAMECTL_DEV_RESOLVED_GBE_LOG" -eq 1 ] || exit 1
        [[ "$GAMECTL_DEV_TRACE_LOG" == "$(get_runtime_dir)/dev_traces/"*.log ]] || exit 1

        "$REPO_ROOT/bin/gamectl" dev-profile "$gdir" full >/dev/null || exit 1
        resolve_dev_profiler_env "$gdir" 1
        [ "$GAMECTL_DEV_RESOLVED_WINEDEBUG" = "+relay,+seh,+loaddll" ] || exit 1
        [ "$GAMECTL_DEV_RESOLVED_VK_DEBUG" = "all" ] || exit 1
        [ "$GAMECTL_DEV_RESOLVED_GBE_LOG" -eq 1 ] || exit 1

        local status_out
        status_out=$("$REPO_ROOT/bin/gamectl" dev-profile "$gdir" status) || exit 1
        echo "$status_out" | grep -Fq 'resolved_winedebug=+relay,+seh,+loaddll' || exit 1
        echo "$status_out" | grep -Fq 'resolved_vk_debug=all' || exit 1

        # 3. Respect explicit user WINEDEBUG / VK_LOADER_DEBUG
        WINEDEBUG="+err" VK_LOADER_DEBUG="error" resolve_dev_profiler_env "$gdir" 1
        [ -z "$GAMECTL_DEV_RESOLVED_WINEDEBUG" ] || exit 1
        [ "$GAMECTL_DEV_RESPECTED_USER_WINEDEBUG" -eq 1 ] || exit 1
        [ -z "$GAMECTL_DEV_RESOLVED_VK_DEBUG" ] || exit 1
        [ "$GAMECTL_DEV_RESPECTED_USER_VK_DEBUG" -eq 1 ] || exit 1

        # 4. Custom WINEDEBUG sanitization
        GAMECTL_DEV_WINEDEBUG='+heap;rm -rf' resolve_dev_profiler_env "$gdir" 1
        [ "$GAMECTL_DEV_RESOLVED_WINEDEBUG" = "+heaprm-rf" ] || exit 1

        # 5. Launch integration exports only into child and creates trace log
        launch_game "$gdir" "devprobe.sh" "DevProbe" --no-scope >/dev/null || exit 1
        local gpid="$GAMECTL_LAST_LAUNCH_PID"
        local glog="$GAMECTL_LAST_LOG_FILE"
        local tlog="$GAMECTL_DEV_TRACE_LOG"
        [ -z "${WINEDEBUG+x}" ] || exit 1
        [ -z "${VK_LOADER_DEBUG+x}" ] || exit 1
        for _ in $(seq 1 30); do
            kill -0 "$gpid" 2>/dev/null || break
            sleep 0.1
        done
        sleep 0.3
        grep -Fq 'CHILD_WINEDEBUG=+relay,+seh,+loaddll' "$glog" || exit 1
        grep -Fq 'CHILD_VK=all' "$glog" || exit 1
        grep -Fq 'CHILD_GBE=1' "$glog" || exit 1
        grep -Fq 'CHILD_WINEDEBUG=+relay,+seh,+loaddll' "$tlog" || exit 1

        # 6. Turning off leaves child env clean
        "$REPO_ROOT/bin/gamectl" dev-profile "$gdir" off >/dev/null || exit 1
        launch_game "$gdir" "devprobe.sh" "DevProbeOff" --no-scope >/dev/null || exit 1
        gpid="$GAMECTL_LAST_LAUNCH_PID"
        glog="$GAMECTL_LAST_LOG_FILE"
        for _ in $(seq 1 30); do
            kill -0 "$gpid" 2>/dev/null || break
            sleep 0.1
        done
        grep -Fq 'CHILD_WINEDEBUG=UNSET' "$glog" || exit 1
        grep -Fq 'CHILD_VK=UNSET' "$glog" || exit 1
        grep -Fq 'CHILD_GBE=0' "$glog" || exit 1
    )
}
run_test "Game Developer Mode & Engine Profiler (WP36C)" test_wp36c_dev_profiler_contract

test_cli_alias_and_ci_gates_contract() {
    local main_sh="$REPO_ROOT/src/main.sh"
    local makefile="$REPO_ROOT/Makefile"
    local ci_yml="$REPO_ROOT/.github/workflows/ci.yml"
    local bin_gamectl="$REPO_ROOT/bin/gamectl"

    # 1. No duplicate add-steam case branch pattern in src/main.sh
    local branch_matches
    branch_matches=$(grep -cE '^[[:space:]]*[^#]*add-steam[^#]*\)$' "$main_sh" || true)
    [ "$branch_matches" -eq 1 ] || return 1

    local unlock_branch
    unlock_branch=$(grep -E '^[[:space:]]*unlock\|' "$main_sh" || true)
    [ -n "$unlock_branch" ] || return 1
    case "$unlock_branch" in
        *add-steam*) return 1 ;;
    esac

    # 2. ShellCheck SC2221/SC2222 clean on src/main.sh
    if command -v shellcheck >/dev/null 2>&1; then
        shellcheck -s bash -i SC2221,SC2222 "$main_sh" >/dev/null || return 1
    fi

    # 3. Runtime CLI dispatch on bundled bin/gamectl
    local t_home
    t_home="$(mktemp -d "${TMPDIR:-/tmp}/gamectl_alias_test.XXXXXX")"
    (
        trap 'rm -rf "$t_home"' EXIT
        local out rc

        out=$(HOME="$t_home" "$bin_gamectl" add-steam < /dev/null 2>&1) && rc=0 || rc=$?
        [ "$rc" -ne 0 ] || exit 1
        printf '%s\n' "$out" | grep -Fq 'Usage: gamectl add-to-steam' || exit 1

        local cmd_alias
        for cmd_alias in entitle unlock; do
            out=$(HOME="$t_home" "$bin_gamectl" "$cmd_alias" < /dev/null 2>&1) && rc=0 || rc=$?
            [ "$rc" -ne 0 ] || exit 1
            printf '%s\n' "$out" | grep -Fq 'Usage: gamectl entitle' || exit 1
        done
    ) || return 1

    # 4. Makefile test recipe includes test_depot_filter.sh
    awk '/^test:/{flag=1;next} /^[^ \t]/{flag=0} flag' "$makefile" | grep -Fq './tests/test_depot_filter.sh' || return 1

    # 5. CI workflow enforces build-depot-dl.sh --force and test_depot_filter.sh
    grep -Fq './scripts/build-depot-dl.sh --force' "$ci_yml" || return 1
    grep -Fq './tests/test_depot_filter.sh' "$ci_yml" || return 1
}
run_test "CLI Alias Collision & CI Test Gates Contract" test_cli_alias_and_ci_gates_contract

# Test 31: WP38A/38B — Unified Store Interface & Built-in Steam Adapter
test_wp38_store_interface_and_steam_adapter_contract() {
    local t_dir
    t_dir=$(mktemp -d "${TMPDIR:-/tmp}/gamectl_wp38_store_XXXXXX")
    mkdir -p "$t_dir/home/.config/gamectl" "$t_dir/home/.local/share/gbe-fork/regular/x64" \
             "$t_dir/home/.local/share/gbe-fork/windows/release/regular/x64" \
             "$t_dir/runtime" "$t_dir/cache" "$t_dir/game"
    (
        trap 'rm -rf "$t_dir"' EXIT
        export HOME="$t_dir/home"
        export XDG_CONFIG_HOME="$t_dir/home/.config"
        export XDG_CACHE_HOME="$t_dir/cache"
        export XDG_RUNTIME_DIR="$t_dir/runtime"

        touch "$t_dir/home/.local/share/gbe-fork/regular/x64/libsteam_api.so"
        touch "$t_dir/home/.local/share/gbe-fork/windows/release/regular/x64/steam_api64.dll"

        source "$REPO_ROOT/src/core/10_utils.sh"
        source "$REPO_ROOT/src/steam/20_discovery.sh"
        source "$REPO_ROOT/src/steam/30_downloader.sh"
        source "$REPO_ROOT/src/steam/31_manifests.sh"
        source "$REPO_ROOT/src/stores/00_store_interface.sh"

        # 1. Sibling loader & registry contracts
        declare -F store_steam_available >/dev/null || exit 1
        store_list_registered | grep -Fxq "steam" || exit 1
        store_list_available | grep -Fxq "steam" || exit 1

        # 2. store_dispatch rejects unknown store, invalid identifier, and unknown op
        local err_out rc
        err_out=$(store_dispatch "bogus" "status" 2>&1) && rc=0 || rc=$?
        [ "$rc" -ne 0 ] || exit 1
        printf '%s' "$err_out" | grep -Fq '[ERROR]' || exit 1

        err_out=$(store_dispatch "bad!store" "status" 2>&1) && rc=0 || rc=$?
        [ "$rc" -ne 0 ] || exit 1

        err_out=$(store_dispatch "steam" "explode" 2>&1) && rc=0 || rc=$?
        [ "$rc" -ne 0 ] || exit 1
        printf '%s' "$err_out" | grep -Fq '[ERROR]' || exit 1

        # 3. Offline-safe store_steam_status never invokes network
        curl() { touch "$t_dir/net_called"; return 99; }
        local st_out
        st_out=$(store_dispatch "steam" "status") || exit 1
        [ ! -e "$t_dir/net_called" ] || exit 1
        printf '%s\n' "$st_out" | grep -Fq 'store=steam' || exit 1
        printf '%s\n' "$st_out" | grep -Fq 'gbe_fork : ready' || exit 1

        # 4. store_steam_search TSV format & validate_tui_fields separator rejection
        scan_installed_games() { printf '105600\tTerraria\t[STANDALONE]\t/tmp/t\tgame.bin\tSTANDALONE\n'; }
        curl() {
            printf '%s' '{"items":[{"id":105600,"name":"Terraria","platforms":{"linux":true,"windows":true,"mac":false}},{"id":48000,"name":"LIMBO","platforms":{"linux":true,"windows":true}}]}'
        }
        local s_out
        s_out=$(store_dispatch "steam" "search" "Terraria") || exit 1
        printf '%s\n' "$s_out" | grep -Fq $'STEAM\t105600\tTerraria\tlinux,windows\tINSTALLED' || exit 1
        printf '%s\n' "$s_out" | grep -Fq $'STEAM\t48000\tLIMBO\tlinux,windows\tAVAILABLE' || exit 1

        curl() { printf '%s' '{"items":[{"id":999,"name":"Evil\tTabTitle","platforms":{"linux":true}}]}'; }
        err_out=$(store_dispatch "steam" "search" "Evil" 2>&1) && rc=0 || rc=$?
        [ "$rc" -ne 0 ] || exit 1
        printf '%s' "$err_out" | grep -Fq '[ERROR]' || exit 1
        unset -f scan_installed_games

        # 5. store_steam_sync offline DLC generation without Steam Client or network
        fetch_cached_json() { return 1; }
        curl() { return 1; }
        printf 'addappid(999105)\naddappid(999106)\n' > "$t_dir/game/999105.lua"
        store_dispatch "steam" "sync" "999105" "$t_dir/game" >/dev/null || exit 1
        grep -Fq '999106=DLC_999106' "$t_dir/game/steam_settings/DLC.txt" || exit 1
        unset -f fetch_cached_json curl

        # 6. Bundled CLI `gamectl stores [list|status]`
        "$REPO_ROOT/scripts/build.sh" >/dev/null
        local cli_list cli_status
        cli_list=$("$REPO_ROOT/bin/gamectl" stores list) || exit 1
        printf '%s\n' "$cli_list" | grep -Eq '^steam[[:space:]]+\[AVAILABLE\]' || exit 1
        cli_status=$("$REPO_ROOT/bin/gamectl" stores status) || exit 1
        printf '%s\n' "$cli_status" | grep -Fq 'store=steam' || exit 1
        "$REPO_ROOT/bin/gamectl" stores invalid >/dev/null 2>&1 && exit 1 || true
    )
}
run_test "Multi-Store Interface & Steam Adapter (WP38A/38B)" test_wp38_store_interface_and_steam_adapter_contract

# Test 32: WP38C/38D — Scanner v3 6-Column Schema, Legacy Cache Refresh & TUI Store Switcher
test_wp38_scanner_v3_and_store_switcher_contract() {
    local t_dir
    t_dir=$(mktemp -d "${TMPDIR:-/tmp}/gamectl_wp38_scan_XXXXXX")
    mkdir -p "$t_dir/home/Games/SoloTitle" "$t_dir/steam/steamapps/common/SteamTitle" \
             "$t_dir/runtime" "$t_dir/bin"
    (
        trap 'rm -rf "$t_dir"' EXIT
        export HOME="$t_dir/home"
        export STEAM_ROOT="$t_dir/steam"
        export XDG_RUNTIME_DIR="$t_dir/runtime"

        touch "$t_dir/steam/steamapps/common/SteamTitle/steamgame.bin"
        chmod +x "$t_dir/steam/steamapps/common/SteamTitle/steamgame.bin"
        cat <<'EOF' > "$t_dir/steam/steamapps/appmanifest_99881.acf"
"AppState"
{
    "appid" "99881"
    "name" "SteamTitle"
    "installdir" "SteamTitle"
}
EOF
        touch "$t_dir/home/Games/SoloTitle/sologame.bin"
        chmod +x "$t_dir/home/Games/SoloTitle/sologame.bin"

        # Seed legacy v2 cache that MUST be rejected and refreshed to v3
        printf '# gamectl scanner v2\n1\tStaleV2\t[STANDALONE]\t/stale/legacy/path\tstale.bin\n' > "$t_dir/runtime/scancache.tab"

        source "$REPO_ROOT/src/core/10_utils.sh"
        source "$REPO_ROOT/src/steam/20_discovery.sh"

        # 1. Scanner v3 invalidates v2 cache and writes 6-column v3 cache
        local all_out
        all_out=$(scan_installed_games) || exit 1
        [ "$(head -n 1 "$t_dir/runtime/scancache.tab")" = "# gamectl scanner v3" ] || exit 1
        ! printf '%s\n' "$all_out" | grep -Fq 'StaleV2' || exit 1
        printf '%s\n' "$all_out" | awk -F'\t' '$2 ~ /SteamTitle/ && NF == 6 && $6 == "STEAM" { found=1 } END { exit !found }' || exit 1
        printf '%s\n' "$all_out" | awk -F'\t' '$2 ~ /SoloTitle/ && NF == 6 && $6 == "STANDALONE" { found=1 } END { exit !found }' || exit 1

        # 2. Backward compatibility for 5-column cut consumers
        printf '%s\n' "$all_out" | cut -f1-5 | grep -Fq 'SteamTitle' || exit 1
        printf '%s\n' "$all_out" | cut -f1-5 | grep -Fq 'SoloTitle' || exit 1

        # 3. Store filtering (--store STEAM / --store STANDALONE)
        local steam_only solo_only
        steam_only=$(scan_installed_games --store STEAM) || exit 1
        printf '%s\n' "$steam_only" | grep -Fq 'SteamTitle' || exit 1
        ! printf '%s\n' "$steam_only" | grep -Fq 'SoloTitle' || exit 1

        solo_only=$(scan_installed_games --store STANDALONE) || exit 1
        printf '%s\n' "$solo_only" | grep -Fq 'SoloTitle' || exit 1
        ! printf '%s\n' "$solo_only" | grep -Fq 'SteamTitle' || exit 1

        # 4. TUI zero-key-collision checks: ctrl-s stays Remote Sync; tab & alt-s in --expect
        grep -q -- '--expect=ctrl-f,ctrl-d,ctrl-l,ctrl-o,ctrl-p,ctrl-i,ctrl-s,ctrl-b,ctrl-r,ctrl-x,tab,alt-s' "$REPO_ROOT/src/tui/70_dashboard.sh" || exit 1
        grep -A3 'ctrl-s)' "$REPO_ROOT/src/tui/70_dashboard.sh" | grep -Fq 'remote_sync_interactive' || exit 1

        # 5. Live library_menu Tab cycling under PTY + stub fzf
        cat <<'EOF' > "$t_dir/bin/fzf"
#!/usr/bin/env python3
import os, pathlib, sys
log = pathlib.Path(os.environ["FZF_ARG_LOG"])
cnt_p = pathlib.Path(os.environ["FZF_CNT"])
idx = int(cnt_p.read_text()) if cnt_p.exists() else 0
cnt_p.write_text(str(idx + 1))
with log.open("a") as fh:
    fh.write(" ".join(sys.argv[1:]) + "\n")
sys.stdin.read()
if idx < 5:
    sys.stdout.write("tab\n")
    sys.exit(0)
sys.exit(130)
EOF
        chmod +x "$t_dir/bin/fzf"
        export FZF_ARG_LOG="$t_dir/fzf_args.log"
        export FZF_CNT="$t_dir/fzf_cnt"
        export PATH="$t_dir/bin:$PATH"

        python3 - "$REPO_ROOT/bin/gamectl" <<'PY' || exit 1
import os, pty, select, sys
pid, fd = pty.fork()
if pid == 0:
    os.execvpe("bash", ["bash", "-c", f'source "{sys.argv[1]}"; clean_stale_locks() {{ :; }}; library_menu'], os.environ)
out = bytearray()
while True:
    if select.select([fd], [], [], 5)[0]:
        try:
            chunk = os.read(fd, 4096)
        except OSError:
            chunk = b""
        if not chunk:
            break
        out.extend(chunk)
    else:
        break
_, status = os.waitpid(pid, 0)
os.close(fd)
assert os.waitstatus_to_exitcode(status) == 0, f"library_menu exited non-zero: {bytes(out)!r}"
PY
        grep -Fq '[Store: ALL]' "$t_dir/fzf_args.log" || exit 1
        grep -Fq '[Store: STEAM]' "$t_dir/fzf_args.log" || exit 1
        grep -Fq '[Store: GOG]' "$t_dir/fzf_args.log" || exit 1
        grep -Fq '[Store: EPIC]' "$t_dir/fzf_args.log" || exit 1
        grep -Fq '[Store: AMAZON]' "$t_dir/fzf_args.log" || exit 1
        grep -Fq '[Store: STANDALONE]' "$t_dir/fzf_args.log" || exit 1
    )
}
run_test "Scanner v3 & TUI Store Switcher (WP38C/38D)" test_wp38_scanner_v3_and_store_switcher_contract

# Test 33: WP39A/39C — Optional GOG Adapter, Offline Status, Search/Sync Contracts & CLI
test_wp39_gog_adapter_and_cli_contract() {
    local t_dir
    t_dir=$(mktemp -d "${TMPDIR:-/tmp}/gamectl_wp39_gog_XXXXXX")
    mkdir -p "$t_dir/home/.config/gamectl" "$t_dir/home/.config/gogdl" "$t_dir/home/.local/share/gbe-fork/regular/x64" \
             "$t_dir/home/.local/share/gbe-fork/windows/release/regular/x64" "$t_dir/runtime" "$t_dir/game/saves" \
             "$t_dir/no_gog_bin" "$t_dir/gog_bin"
    (
        trap 'rm -rf "$t_dir"' EXIT
        export HOME="$t_dir/home" XDG_CONFIG_HOME="$t_dir/home/.config" XDG_RUNTIME_DIR="$t_dir/runtime"
        touch "$t_dir/home/.local/share/gbe-fork/regular/x64/libsteam_api.so" \
              "$t_dir/home/.local/share/gbe-fork/windows/release/regular/x64/steam_api64.dll"
        echo "save_data" > "$t_dir/game/saves/slot.dat"

        local cmd_tool tool_path
        for cmd_tool in bash sh env cat mkdir rm cp mv grep awk sed jq curl file zip unzip rsync ssh python3 fzf dirname basename readlink head tail date stat touch tr wc cut find chmod mktemp uname pgrep id; do
            tool_path="$(command -v "$cmd_tool" 2>/dev/null || true)"
            [ -n "$tool_path" ] && ln -sf "$tool_path" "$t_dir/no_gog_bin/$cmd_tool"
        done

        PATH="$t_dir/no_gog_bin" bash -c '
            set -e
            source "$1/src/core/10_utils.sh"
            source "$1/src/core/14_saves.sh"
            source "$1/src/steam/20_discovery.sh"
            source "$1/src/runners/40_wrappers.sh"
            source "$1/src/stores/00_store_interface.sh"
            source "$1/src/diagnostics/60_doctor.sh"

            declare -F store_gog_available >/dev/null
            store_list_registered | grep -Fxq "gog"
            ! store_gog_available
            curl() { touch "$2/net_hit"; return 99; }
            st=$(store_dispatch gog status)
            [ ! -e "$2/net_hit" ]
            printf "%s\n" "$st" | grep -Fq "store=gog"
            printf "%s\n" "$st" | grep -Fq "missing"
            [ ! -e "$HOME/.config/gamectl/gog_token" ]

            err=$(store_dispatch gog search "witcher" 2>&1) && exit 1 || true
            printf "%s" "$err" | grep -Fq "[ERROR]"
            err=$(store_dispatch gog download 1207658924 "$2/dl" 2>&1) && exit 1 || true
            printf "%s" "$err" | grep -Fq "[ERROR]"

            doc_out=$(doctor_audit || true)
            printf "%s\n" "$doc_out" | grep -Fq "GOG Store CLI"
            printf "%s\n" "$doc_out" | grep -Fq "[OPT]"
        ' _ "$REPO_ROOT" "$t_dir" || exit 1

        cat <<'EOF' > "$t_dir/gog_bin/gogdl"
#!/usr/bin/env bash
case "$1" in
    search)
        if [ "${GOG_EVIL:-0}" = "1" ]; then
            printf '[{"id":99,"title":"Bad\\tTitle","worksOn":{"Linux":true}}]\n'
        else
            printf '[{"id":1207658924,"title":"The Witcher 3","worksOn":{"Linux":true,"Windows":true}}]\n'
        fi ;;
    download)
        mkdir -p "$4"
        printf 'downloaded %s\n' "$2" > "$4/gog.ok" ;;
    save-sync)
        printf 'synced %s %s\n' "$2" "$3" > "$2/sync.ok" ;;
esac
EOF
        chmod +x "$t_dir/gog_bin/gogdl"
        printf '{"access_token":"dummy"}\n' > "$t_dir/home/.config/gogdl/auth.json"
        "$REPO_ROOT/scripts/build.sh" >/dev/null

        PATH="$t_dir/gog_bin:$PATH" bash -c '
            set -e
            source "$1/src/core/10_utils.sh"
            source "$1/src/core/14_saves.sh"
            source "$1/src/steam/20_discovery.sh"
            source "$1/src/stores/00_store_interface.sh"

            store_gog_available
            store_list_available | grep -Fxq "gog"
            store_dispatch gog status | grep -Fq "session present"
            store_dispatch gog search "" 2>/dev/null && exit 1 || true

            s_out=$(store_dispatch gog search "witcher")
            printf "%s\n" "$s_out" | grep -Fq $'\''GOG\t1207658924\tThe Witcher 3\tlinux,windows\tAVAILABLE'\''
            GOG_EVIL=1 store_dispatch gog search "evil" 2>/dev/null && exit 1 || true

            store_dispatch gog download 1207658924 "$2/dl_game" >/dev/null
            grep -Fq "downloaded 1207658924" "$2/dl_game/gog.ok"

            store_dispatch gog sync 1207658924 "$2/game" >/dev/null
            [ -d "$2/game/.save_snapshots/slot1" ]
            grep -Fq "synced $2/game 1207658924" "$2/game/sync.ok"

            "$1/bin/gamectl" gog --help | grep -Fq "gamectl gog"
            "$1/bin/gamectl" gog status | grep -Fq "ready (gogdl:"
            "$1/bin/gamectl" gog search "witcher" | grep -Fq "1207658924"
            "$1/bin/gamectl" gog bogus 2>/dev/null && exit 1 || true
            "$1/bin/gamectl" stores list | grep -Eq "^gog[[:space:]]+\[AVAILABLE\]"
        ' _ "$REPO_ROOT" "$t_dir" || exit 1
    )
}
run_test "Optional GOG Adapter & CLI Contracts (WP39A/39C)" test_wp39_gog_adapter_and_cli_contract

# Test 34: WP39B/39C — GOG Local Discovery (goggame-*.info), Validation & TUI Filter
test_wp39_gog_discovery_and_tui_filter_contract() {
    local t_dir
    t_dir=$(mktemp -d "${TMPDIR:-/tmp}/gamectl_wp39_disc_XXXXXX")
    mkdir -p "$t_dir/home/GOG Games/Witcher3" "$t_dir/home/Games/SoloTitle" \
             "$t_dir/home/Games/BadGog" "$t_dir/steam/steamapps/common/SteamTitle" "$t_dir/runtime"
    (
        trap 'rm -rf "$t_dir"' EXIT
        export HOME="$t_dir/home" STEAM_ROOT="$t_dir/steam" XDG_RUNTIME_DIR="$t_dir/runtime"

        for b in "$t_dir/home/GOG Games/Witcher3/witcher.sh" "$t_dir/home/Games/SoloTitle/solo.bin" \
                 "$t_dir/home/Games/BadGog/bad.bin" "$t_dir/steam/steamapps/common/SteamTitle/steam.bin"; do
            printf '#!/bin/sh\nexit 0\n' > "$b"
            chmod +x "$b"
        done
        printf '{"gameId":"1207658924","name":"The Witcher 3"}\n' > "$t_dir/home/GOG Games/Witcher3/goggame-1207658924.info"
        printf '{"gameId":"999","name":"Bad\\tGogName"}\n' > "$t_dir/home/Games/BadGog/goggame-999.info"
        printf '"AppState"\n{\n  "appid" "99881"\n  "name" "SteamTitle"\n  "installdir" "SteamTitle"\n}\n' \
            > "$t_dir/steam/steamapps/appmanifest_99881.acf"

        source "$REPO_ROOT/src/core/10_utils.sh"
        source "$REPO_ROOT/src/steam/20_discovery.sh"
        source "$REPO_ROOT/src/stores/00_store_interface.sh"

        local all_out gog_out solo_out err_log="$t_dir/scan.err"
        all_out=$(scan_installed_games --refresh 2>"$err_log") || exit 1
        [ "$(head -n 1 "$t_dir/runtime/scancache.tab")" = "# gamectl scanner v3" ] || exit 1
        grep -Fq '[ERROR]' "$err_log" || exit 1
        ! printf '%s\n' "$all_out" | grep -Fq 'BadGog' || exit 1

        printf '%s\n' "$all_out" | awk -F'\t' '$1 ~ /^1207658924/ && $2 ~ /The Witcher 3/ && $3 ~ /^\[GOG\]/ && NF == 6 && $6 == "GOG" { ok=1 } END { exit !ok }' || exit 1
        printf '%s\n' "$all_out" | awk -F'\t' '$2 ~ /SoloTitle/ && $6 == "STANDALONE" { ok=1 } END { exit !ok }' || exit 1
        printf '%s\n' "$all_out" | awk -F'\t' '$2 ~ /SteamTitle/ && $6 == "STEAM" { ok=1 } END { exit !ok }' || exit 1

        gog_out=$(scan_installed_games --store GOG) || exit 1
        printf '%s\n' "$gog_out" | grep -Fq 'The Witcher 3' || exit 1
        ! printf '%s\n' "$gog_out" | grep -Fq 'SoloTitle' || exit 1
        store_dispatch gog list_installed | grep -Fq '1207658924' || exit 1

        solo_out=$(scan_installed_games --store STANDALONE) || exit 1
        printf '%s\n' "$solo_out" | grep -Fq 'SoloTitle' || exit 1
        ! printf '%s\n' "$solo_out" | grep -Fq 'The Witcher 3' || exit 1

        grep -Fq 'GOG\tGOG Library' "$REPO_ROOT/src/tui/70_dashboard.sh" || exit 1
        grep -A3 'ctrl-s)' "$REPO_ROOT/src/tui/70_dashboard.sh" | grep -Fq 'remote_sync_interactive' || exit 1
        grep -Fq 'gog)' "$REPO_ROOT/completions/gamectl.bash" || exit 1
    )
}
run_test "GOG Discovery & TUI Store Filter (WP39B/39C)" test_wp39_gog_discovery_and_tui_filter_contract

# Test 35: WP40A/40C — Optional Epic Adapter (legendary), Offline Status, Search/Sync & CLI
test_wp40_epic_adapter_and_cli_contract() {
    local t_dir
    t_dir=$(mktemp -d "${TMPDIR:-/tmp}/gamectl_wp40_epic_XXXXXX")
    mkdir -p "$t_dir/home/.config/gamectl" "$t_dir/home/.config/legendary" "$t_dir/home/.local/share/gbe-fork/regular/x64" \
             "$t_dir/home/.local/share/gbe-fork/windows/release/regular/x64" "$t_dir/runtime" "$t_dir/game/saves" \
             "$t_dir/no_epic_bin" "$t_dir/epic_bin"
    (
        trap 'rm -rf "$t_dir"' EXIT
        export HOME="$t_dir/home" XDG_CONFIG_HOME="$t_dir/home/.config" XDG_RUNTIME_DIR="$t_dir/runtime"
        export LEGENDARY_CONFIG_PATH="$t_dir/home/.config/legendary"
        touch "$t_dir/home/.local/share/gbe-fork/regular/x64/libsteam_api.so" \
              "$t_dir/home/.local/share/gbe-fork/windows/release/regular/x64/steam_api64.dll"
        echo "epic_save" > "$t_dir/game/saves/slot.dat"

        local cmd_tool tool_path
        for cmd_tool in bash sh env cat mkdir rm cp mv grep awk sed jq curl file zip unzip rsync ssh python3 fzf dirname basename readlink head tail date stat touch tr wc cut find chmod mktemp uname pgrep id realpath; do
            tool_path="$(command -v "$cmd_tool" 2>/dev/null || true)"
            [ -n "$tool_path" ] && ln -sf "$tool_path" "$t_dir/no_epic_bin/$cmd_tool"
        done

        PATH="$t_dir/no_epic_bin" bash -c '
            set -e
            source "$1/src/core/10_utils.sh"
            source "$1/src/core/14_saves.sh"
            source "$1/src/steam/20_discovery.sh"
            source "$1/src/runners/40_wrappers.sh"
            source "$1/src/stores/00_store_interface.sh"
            source "$1/src/diagnostics/60_doctor.sh"

            declare -F store_epic_available >/dev/null
            store_list_registered | grep -Fxq "epic"
            ! store_epic_available
            curl() { touch "$2/net_hit"; return 99; }
            st=$(store_dispatch epic status)
            [ ! -e "$2/net_hit" ]
            printf "%s\n" "$st" | grep -Fq "store=epic"
            printf "%s\n" "$st" | grep -Fq "missing"
            printf "%s\n" "$st" | grep -Fq "unconfigured"

            err=$(store_dispatch epic search "alan" 2>&1) && exit 1 || true
            printf "%s" "$err" | grep -Fq "[ERROR]"
            err=$(store_dispatch epic download "AlanWake" "$2/dl" 2>&1) && exit 1 || true
            printf "%s" "$err" | grep -Fq "[ERROR]"

            doc_out=$(doctor_audit || true)
            printf "%s\n" "$doc_out" | grep -Fq "Epic Store CLI"
            printf "%s\n" "$doc_out" | grep -Fq "[OPT]"
        ' _ "$REPO_ROOT" "$t_dir" || exit 1

        cat <<'EOF' > "$t_dir/epic_bin/legendary"
#!/usr/bin/env bash
case "$1" in
    list)
        if [ "${EPIC_MODE:-ok}" = "bad_json" ]; then
            printf 'EPIC\tNOT_JSON\tBroken\twindows\n'
        elif [ "${EPIC_MODE:-ok}" = "evil_tab" ]; then
            printf '[{"app_name":"BadApp","app_title":"Evil\\tTitle","asset_infos":{"Windows":{}}}]\n'
        else
            printf '[{"app_name":"Sugar","app_title":"Rocket League","asset_infos":{"Windows":{}}},{"app_name":"CelesteApp","app_title":"Celeste","asset_infos":{"Linux":{},"Windows":{}}}]\n'
        fi ;;
    install)
        app="$2"; shift 2; gdir=""
        while [ $# -gt 0 ]; do [ "$1" = "--game-folder" ] && { gdir="$2"; shift 2; continue; }; shift; done
        mkdir -p "$gdir"; printf 'installed %s\n' "$app" > "$gdir/epic.ok" ;;
    sync-saves)
        app="$2"; shift 2; spath=""
        while [ $# -gt 0 ]; do [ "$1" = "--save-path" ] && { spath="$2"; shift 2; continue; }; shift; done
        printf 'synced %s %s\n' "$app" "$spath" > "$spath/../sync.ok" ;;
    launch)
        printf 'launched %s\n' "$2" ;;
esac
EOF
        chmod +x "$t_dir/epic_bin/legendary"
        printf '{"access_token":"TOPSECRET_EPIC_TOKEN"}\n' > "$t_dir/home/.config/legendary/user.json"
        "$REPO_ROOT/scripts/build.sh" >/dev/null

        PATH="$t_dir/epic_bin:$PATH" bash -c '
            set -e
            source "$1/src/core/10_utils.sh"
            source "$1/src/core/14_saves.sh"
            source "$1/src/steam/20_discovery.sh"
            source "$1/src/stores/00_store_interface.sh"

            store_epic_available
            store_list_available | grep -Fxq "epic"
            st_out=$(store_dispatch epic status)
            printf "%s\n" "$st_out" | grep -Fq "session present"
            ! printf "%s\n" "$st_out" | grep -Fq "TOPSECRET_EPIC_TOKEN"
            store_dispatch epic search "" 2>/dev/null && exit 1 || true

            s_out=$(store_dispatch epic search "celeste")
            printf "%s\n" "$s_out" | grep -Fq $'\''EPIC\tCelesteApp\tCeleste\tlinux,windows\tAVAILABLE'\''
            EPIC_MODE=bad_json store_dispatch epic search "broken" 2>/dev/null && exit 1 || true
            EPIC_MODE=evil_tab store_dispatch epic search "evil" 2>/dev/null && exit 1 || true

            store_dispatch epic download "CelesteApp" "$2/dl_epic" >/dev/null
            grep -Fq "installed CelesteApp" "$2/dl_epic/epic.ok"

            store_dispatch epic sync "CelesteApp" "$2/game" >/dev/null
            [ -d "$2/game/.save_snapshots/slot1" ]
            grep -Fq "synced CelesteApp $2/game/saves" "$2/game/sync.ok"

            "$1/bin/gamectl" epic --help | grep -Fq "gamectl epic"
            "$1/bin/gamectl" epic status | grep -Fq "ready (legendary:"
            "$1/bin/gamectl" epic search "rocket" | grep -Fq "Sugar"
            "$1/bin/gamectl" epic launch "Sugar" | grep -Fq "launched Sugar"
            "$1/bin/gamectl" epic bogus 2>/dev/null && exit 1 || true
            "$1/bin/gamectl" stores list | grep -Eq "^epic[[:space:]]+\[AVAILABLE\]"
        ' _ "$REPO_ROOT" "$t_dir" || exit 1
    )
}
run_test "Optional Epic Adapter & CLI Contracts (WP40A/40C)" test_wp40_epic_adapter_and_cli_contract

# Test 36: WP40B/40C — Epic installed.json Discovery, Deduplication, Validation & TUI Filter
test_wp40_epic_discovery_and_tui_filter_contract() {
    local t_dir
    t_dir=$(mktemp -d "${TMPDIR:-/tmp}/gamectl_wp40_disc_XXXXXX")
    mkdir -p "$t_dir/home/Games/CelesteEpic" "$t_dir/home/Games/SoloTitle" \
             "$t_dir/home/Epic/BadEpic" "$t_dir/home/.config/legendary" "$t_dir/runtime"
    (
        trap 'rm -rf "$t_dir"' EXIT
        export HOME="$t_dir/home" XDG_CONFIG_HOME="$t_dir/home/.config" XDG_RUNTIME_DIR="$t_dir/runtime"
        export LEGENDARY_CONFIG_PATH="$t_dir/home/.config/legendary"

        for b in "$t_dir/home/Games/CelesteEpic/Celeste.bin.x86_64" "$t_dir/home/Games/SoloTitle/solo.bin" \
                 "$t_dir/home/Epic/BadEpic/bad.bin"; do
            printf '#!/bin/sh\nexit 0\n' > "$b"
            chmod +x "$b"
        done

        cat <<EOF > "$LEGENDARY_CONFIG_PATH/installed.json"
{
  "CelesteApp": {
    "app_name": "CelesteApp",
    "title": "Celeste Epic",
    "install_path": "$t_dir/home/Games/CelesteEpic",
    "executable": "Celeste.bin.x86_64"
  },
  "BadTab": {
    "app_name": "BadTab",
    "title": "Bad\\tEpicTitle",
    "install_path": "$t_dir/home/Epic/BadEpic",
    "executable": "bad.bin"
  }
}
EOF

        source "$REPO_ROOT/src/core/00_header.sh"
        source "$REPO_ROOT/src/core/10_utils.sh"
        source "$REPO_ROOT/src/steam/20_discovery.sh"
        source "$REPO_ROOT/src/stores/00_store_interface.sh"

        local all_out epic_out solo_out fmt_out err_log="$t_dir/scan.err"
        all_out=$(scan_installed_games --refresh 2>"$err_log") || exit 1
        [ "$(head -n 1 "$t_dir/runtime/scancache.tab")" = "# gamectl scanner v3" ] || exit 1
        grep -Fq '[ERROR]' "$err_log" || exit 1
        ! printf '%s\n' "$all_out" | grep -Fq 'BadEpic' || exit 1

        # Epic game in ~/Games/ is indexed once as EPIC and NOT duplicated as STANDALONE
        [ "$(printf '%s\n' "$all_out" | grep -c 'CelesteEpic')" -eq 1 ] || exit 1
        printf '%s\n' "$all_out" | awk -F'\t' '$1 ~ /^CelesteApp/ && $2 ~ /Celeste Epic/ && $3 ~ /^\[EPIC\]/ && NF == 6 && $6 == "EPIC" { ok=1 } END { exit !ok }' || exit 1
        printf '%s\n' "$all_out" | awk -F'\t' '$2 ~ /SoloTitle/ && $6 == "STANDALONE" { ok=1 } END { exit !ok }' || exit 1

        epic_out=$(scan_installed_games --store EPIC) || exit 1
        printf '%s\n' "$epic_out" | grep -Fq 'Celeste Epic' || exit 1
        ! printf '%s\n' "$epic_out" | grep -Fq 'SoloTitle' || exit 1
        store_dispatch epic list_installed | grep -Fq 'CelesteApp' || exit 1

        solo_out=$(scan_installed_games --store STANDALONE) || exit 1
        printf '%s\n' "$solo_out" | grep -Fq 'SoloTitle' || exit 1
        ! printf '%s\n' "$solo_out" | grep -Fq 'Celeste Epic' || exit 1

        fmt_out=$(scan_installed_games --formatted --store EPIC) || exit 1
        printf '%s\n' "$fmt_out" | grep -Fq '[EPIC]' || exit 1

        # Cache invalidation when installed.json mtime becomes newer than scancache.tab
        sleep 1
        cat <<EOF > "$LEGENDARY_CONFIG_PATH/installed.json"
{
  "CelesteApp": {
    "app_name": "CelesteApp",
    "title": "Celeste Updated",
    "install_path": "$t_dir/home/Games/CelesteEpic",
    "executable": "Celeste.bin.x86_64"
  }
}
EOF
        scan_installed_games --store EPIC | grep -Fq 'Celeste Updated' || exit 1

        grep -Fq 'EPIC\tEpic Games Library' "$REPO_ROOT/src/tui/70_dashboard.sh" || exit 1
        grep -A3 'ctrl-s)' "$REPO_ROOT/src/tui/70_dashboard.sh" | grep -Fq 'remote_sync_interactive' || exit 1
        grep -Fq 'epic)' "$REPO_ROOT/completions/gamectl.bash" || exit 1
    )
}
run_test "Epic Discovery, Deduplication & TUI Filter (WP40B/40C)" test_wp40_epic_discovery_and_tui_filter_contract

# Test 37: Remediation Packet 2 (R2A/R2B) — Steam App-Type SSoT, Badges, Filter & Redirect
test_r2_steam_app_type_ssot_and_tui_contracts() {
    local t_dir
    t_dir=$(mktemp -d "${TMPDIR:-/tmp}/gamectl_r2_ssot_XXXXXX")
    mkdir -p "$t_dir/home/.cache/gamectl" "$t_dir/home/Games" "$t_dir/bin" "$t_dir/runtime"

    (
        trap 'rm -rf "$t_dir"' EXIT
        export HOME="$t_dir/home"
        export XDG_CACHE_HOME="$t_dir/home/.cache"
        export XDG_RUNTIME_DIR="$t_dir/runtime"

        source "$REPO_ROOT/src/core/00_header.sh"
        source "$REPO_ROOT/src/core/10_utils.sh"
        source "$REPO_ROOT/src/core/12_tui_primitives.sh"
        source "$REPO_ROOT/src/steam/20_discovery.sh"
        source "$REPO_ROOT/src/steam/30_downloader.sh"
        source "$REPO_ROOT/src/steam/31_manifests.sh"
        source "$REPO_ROOT/src/steam/32_steam_bridge.sh"
        source "$REPO_ROOT/src/tui/70_dashboard.sh"
        source "$REPO_ROOT/src/tui/71_previews.sh"

        # 1. Closed 7-token canonical taxonomy and badge formatting
        [ "$(normalize_steam_app_type 0)" = "GAME" ] || exit 1
        [ "$(normalize_steam_app_type game)" = "GAME" ] || exit 1
        [ "$(normalize_steam_app_type 4)" = "DLC" ] || exit 1
        [ "$(normalize_steam_app_type dlc)" = "DLC" ] || exit 1
        [ "$(normalize_steam_app_type 1)" = "DEMO" ] || exit 1
        [ "$(normalize_steam_app_type 2)" = "MOD" ] || exit 1
        [ "$(normalize_steam_app_type 11)" = "SOUNDTRACK" ] || exit 1
        [ "$(normalize_steam_app_type music)" = "SOUNDTRACK" ] || exit 1
        [ "$(normalize_steam_app_type 3)" = "TOOL" ] || exit 1
        [ "$(normalize_steam_app_type 6)" = "APP" ] || exit 1
        [ "$(normalize_steam_app_type unknown)" = "APP" ] || exit 1

        local b_game b_dlc b_ost
        b_game=$(format_app_type_badge GAME | sed -r 's/\x1B\[[0-9;]*[mK]//g')
        b_dlc=$(format_app_type_badge 4 | sed -r 's/\x1B\[[0-9;]*[mK]//g')
        b_ost=$(format_app_type_badge music | sed -r 's/\x1B\[[0-9;]*[mK]//g')
        [ "$b_game" = "[GAME]" ] || exit 1
        [ "$b_dlc" = "[DLC]" ] || exit 1
        [ "$b_ost" = "[OST]" ] || exit 1

        # 2. Single-batch classify_steam_app_types + offline fallback + separator rejection
        : > "$t_dir/batch.calls"
        curl() {
            local url="${@: -1}"
            if [[ "$url" == *IStoreBrowseService/GetItems* ]]; then
                printf '1\n' >> "$t_dir/batch.calls"
                printf '%s' '{"response":{"store_items":[{"appid":1245620,"type":0},{"appid":2778580,"type":4,"related_items":{"parent_appid":1245620}},{"appid":1001,"type":1},{"appid":1002,"type":2},{"appid":1003,"type":11},{"appid":1004,"type":6}]}}'
                return 0
            fi
            return 1
        }

        local cls_out
        cls_out=$(classify_steam_app_types 1245620 2778580 1001 1002 1003 1004 99999 1245620) || exit 1
        [ "$(wc -l < "$t_dir/batch.calls")" -eq 1 ] || exit 1
        [ "$(printf '%s\n' "$cls_out" | wc -l)" -eq 7 ] || exit 1
        printf '%s\n' "$cls_out" | grep -Fxq $'1245620\tGAME\t' || exit 1
        printf '%s\n' "$cls_out" | grep -Fxq $'2778580\tDLC\t1245620' || exit 1
        printf '%s\n' "$cls_out" | grep -Fxq $'1001\tDEMO\t' || exit 1
        printf '%s\n' "$cls_out" | grep -Fxq $'1002\tMOD\t' || exit 1
        printf '%s\n' "$cls_out" | grep -Fxq $'1003\tSOUNDTRACK\t' || exit 1
        printf '%s\n' "$cls_out" | grep -Fxq $'1004\tAPP\t' || exit 1
        printf '%s\n' "$cls_out" | grep -Fxq $'99999\tAPP\t' || exit 1

        # Malformed/tab-injected batch response degrades safely to APP
        curl() { printf '%s' '{"response":{"store_items":[{"appid":777,"type":"bad\tval"}]}}'; }
        [ "$(classify_steam_app_types 777)" = $'777\tAPP\t' ] || exit 1
        curl() { return 1; }
        [ "$(classify_steam_app_types 1245620 2778580)" = $'1245620\tAPP\t\n2778580\tAPP\t' ] || exit 1

        # 3. parse_steam_app_type_json, fetch_steam_app_details & resolve_steam_app_type (zero-network for cached fixtures)
        [ "$(parse_steam_app_type_json '{"type":"game","name":"ELDEN RING"}')" = $'1\tGAME\t\t' ] || exit 1
        [ "$(parse_steam_app_type_json '{"type":"dlc","fullgame":{"appid":"1245620","name":"ELDEN RING"}}')" = $'1\tDLC\t1245620\tELDEN RING' ] || exit 1
        [ "$(parse_steam_app_type_json '{"platforms":{"windows":true}}')" = $'0\tAPP\t\t' ] || exit 1
        [ "$(parse_steam_app_type_json '{"type":"dlc","fullgame":{"appid":"1245620","name":"ELDEN\tRING"}}')" = $'1\tDLC\t1245620\tELDEN RING' ] || exit 1

        cat <<'EOF' > "$XDG_CACHE_HOME/gamectl/steam_details_1245620.json"
{"1245620":{"success":true,"data":{"type":"game","name":"ELDEN RING","platforms":{"windows":true,"linux":false},"genres":[{"description":"Action"}]}}}
EOF
        cat <<'EOF' > "$XDG_CACHE_HOME/gamectl/steam_details_2778580.json"
{"2778580":{"success":true,"data":{"type":"dlc","name":"Shadow of the Erdtree","fullgame":{"appid":"1245620","name":"ELDEN RING"},"platforms":{"windows":true,"linux":false},"genres":[{"description":"RPG"}]}}}
EOF
        cat <<'EOF' > "$XDG_CACHE_HOME/gamectl/steam_details_555555.json"
{"555555":{"success":true,"data":{"platforms":{"windows":true,"linux":true},"genres":[{"description":"Indie"}]}}}
EOF

        curl() { touch "$t_dir/unexpected_net"; return 1; }
        [ "$(resolve_steam_app_type 1245620)" = $'GAME\t\t' ] || exit 1
        [ "$(resolve_steam_app_type 2778580)" = $'DLC\t1245620\tELDEN RING' ] || exit 1
        [ "$(resolve_steam_app_type 555555)" = $'APP\t\t' ] || exit 1
        [ ! -e "$t_dir/unexpected_net" ] || exit 1
        curl() { return 1; }

        # 4. preview_search_game renders Type for GAME and DLC Base info
        local prev_game prev_dlc
        prev_game=$(preview_search_game 1245620 "ELDEN RING" "[NOT INSTALLED]" | sed -r 's/\x1B\[[0-9;]*[mK]//g')
        prev_dlc=$(preview_search_game 2778580 "Shadow of the Erdtree" "[NOT INSTALLED]" | sed -r 's/\x1B\[[0-9;]*[mK]//g')
        grep -Fq "Type        : [GAME]" <<< "$prev_game" || exit 1
        grep -Fq "Type        : [DLC] (Base: ELDEN RING • 1245620)" <<< "$prev_dlc" || exit 1

        # 5. search_steam Tab filter + DLC redirect + unlock_interactive classification (offline PTY mock)
        local dl_log="$t_dir/dl.calls"
        cat <<'MOCK_FZF' > "$t_dir/bin/fzf"
#!/usr/bin/env bash
step_file="${FZF_STEP_FILE}"
idx=0
[ -f "${step_file}.idx" ] && idx=$(cat "${step_file}.idx")
echo $((idx + 1)) > "${step_file}.idx"
input_data=$(cat)
printf '%s\n' "$input_data" > "${FZF_DUMP_DIR}/dump_${idx}.tsv"
case "$idx" in
    0)
        printf 'tab\n'
        exit 0
        ;;
    1)
        printf 'tab\n'
        exit 0
        ;;
    2)
        printf 'ctrl-a\n'
        printf '%s\n' "$input_data" | grep -F '2778580' | head -n 1
        exit 0
        ;;
    3)
        printf 'base\tDownload Base Game\n'
        exit 0
        ;;
    4)
        printf 'ctrl-a\n'
        printf '%s\n' "$input_data" | grep -F '2778580' | head -n 1
        exit 0
        ;;
    5)
        printf 'dlc\tDownload DLC Only\n'
        exit 0
        ;;
    6)
        printf 'ctrl-a\n'
        printf '%s\n' "$input_data" | grep -F '2778580' | head -n 1
        exit 0
        ;;
    7)
        printf 'cancel\tCancel / Return\n'
        exit 0
        ;;
    *)
        exit 130
        ;;
esac
MOCK_FZF
        chmod +x "$t_dir/bin/fzf"
        export PATH="$t_dir/bin:$PATH"
        export FZF_STEP_FILE="$t_dir/fzf_step"
        export FZF_DUMP_DIR="$t_dir"
        export REPO_ROOT dl_log

        cat <<'PTY_SEARCH' > "$t_dir/pty_search.sh"
#!/usr/bin/env bash
source "$REPO_ROOT/src/core/00_header.sh"
source "$REPO_ROOT/src/core/10_utils.sh"
source "$REPO_ROOT/src/core/12_tui_primitives.sh"
source "$REPO_ROOT/src/steam/20_discovery.sh"
source "$REPO_ROOT/src/steam/30_downloader.sh"
source "$REPO_ROOT/src/steam/31_manifests.sh"
source "$REPO_ROOT/src/steam/32_steam_bridge.sh"
source "$REPO_ROOT/src/tui/70_dashboard.sh"
source "$REPO_ROOT/src/tui/71_previews.sh"
curl() {
    local u="${@: -1}"
    if [[ "$u" == *storesearch* ]]; then
        printf '%s' '{"items":[{"id":1245620,"name":"ELDEN RING"},{"id":2778580,"name":"Shadow of the Erdtree"}]}'
    elif [[ "$u" == *IStoreBrowseService/GetItems* ]]; then
        printf '%s' '{"response":{"store_items":[{"appid":1245620,"type":0},{"appid":2778580,"type":4,"related_items":{"parent_appid":1245620}}]}}'
    fi
}
scan_installed_games() { return 0; }
tui_exec_action() { shift; "$@"; }
download_game() { printf '%s\n' "$*" >> "$dl_log"; }
flush_tty_input() { :; }
search_steam "elden" false
PTY_SEARCH
        chmod +x "$t_dir/pty_search.sh"

        python3 - "$t_dir/pty_search.sh" <<'PY_PTY' >/dev/null 2>&1 || true
import os, pty, select, subprocess, sys
m, s = pty.openpty()
p = subprocess.Popen(["bash", sys.argv[1]], stdin=s, stdout=s, stderr=s, close_fds=True)
os.close(s)
while True:
    r, _, _ = select.select([m], [], [], 1.0)
    if r:
        try:
            if not os.read(m, 4096):
                break
        except OSError:
            break
    elif p.poll() is not None:
        break
os.close(m)
p.wait()
PY_PTY

        # dump_0 = ALL (both 1245620 and 2778580), dump_1 = GAME (only 1245620), dump_2 = DLC (only 2778580)
        awk -F'\t' '$1 == "1245620" {ok=1} END {exit !ok}' "$t_dir/dump_0.tsv" || exit 1
        awk -F'\t' '$1 == "2778580" {ok=1} END {exit !ok}' "$t_dir/dump_0.tsv" || exit 1
        awk -F'\t' '$1 == "1245620" {ok=1} END {exit !ok}' "$t_dir/dump_1.tsv" || exit 1
        awk -F'\t' '$1 == "2778580" {bad=1} END {exit bad}' "$t_dir/dump_1.tsv" || exit 1
        awk -F'\t' '$1 == "2778580" {ok=1} END {exit !ok}' "$t_dir/dump_2.tsv" || exit 1
        awk -F'\t' '$1 == "1245620" {bad=1} END {exit bad}' "$t_dir/dump_2.tsv" || exit 1
        # Redirected DLC 2778580 -> Base Game 1245620 (branch 1), --allow-dlc (branch 2), cancel (branch 3)
        [ "$(wc -l < "$dl_log")" -eq 2 ] || exit 1
        sed -n '1p' "$dl_log" | grep -Fq '1245620 ' || exit 1
        ! sed -n '1p' "$dl_log" | grep -Fq -- '--allow-dlc' || exit 1
        sed -n '2p' "$dl_log" | grep -Fq '2778580 ' || exit 1
        sed -n '2p' "$dl_log" | grep -Fq -- '--allow-dlc' || exit 1

        # Verify unlock_interactive enriches picker rows with classify_steam_app_types badges
        rm -f "${FZF_STEP_FILE}.idx"
        cat <<'MOCK_FZF_ADOPT' > "$t_dir/bin/fzf"
#!/usr/bin/env bash
step_file="${FZF_STEP_FILE}"
idx=0
[ -f "${step_file}.idx" ] && idx=$(cat "${step_file}.idx")
echo $((idx + 1)) > "${step_file}.idx"
input_data=$(cat)
printf '%s\n' "$input_data" > "${FZF_DUMP_DIR}/adopt_${idx}.tsv"
case "$idx" in
    0) printf 'elden\n'; exit 0 ;;
    1) printf '%s\n' "$input_data" | grep -F '1245620' | head -n 1; exit 0 ;;
    *) exit 130 ;;
esac
MOCK_FZF_ADOPT
        chmod +x "$t_dir/bin/fzf"

        cat <<'PTY_ADOPT' > "$t_dir/pty_adopt.sh"
#!/usr/bin/env bash
source "$REPO_ROOT/src/core/00_header.sh"
source "$REPO_ROOT/src/core/10_utils.sh"
source "$REPO_ROOT/src/core/12_tui_primitives.sh"
source "$REPO_ROOT/src/steam/20_discovery.sh"
source "$REPO_ROOT/src/steam/30_downloader.sh"
source "$REPO_ROOT/src/steam/31_manifests.sh"
source "$REPO_ROOT/src/steam/32_steam_bridge.sh"
curl() {
    local u="${@: -1}"
    if [[ "$u" == *storesearch* ]]; then
        printf '%s' '{"items":[{"id":1245620,"name":"ELDEN RING"},{"id":2778580,"name":"Shadow of the Erdtree"}]}'
    elif [[ "$u" == *IStoreBrowseService/GetItems* ]]; then
        printf '%s' '{"response":{"store_items":[{"appid":1245620,"type":0},{"appid":2778580,"type":4,"related_items":{"parent_appid":1245620}}]}}'
    fi
}
scan_installed_games() { return 0; }
flush_tty_input() { :; }
unlock_interactive
PTY_ADOPT
        chmod +x "$t_dir/pty_adopt.sh"

        python3 - "$t_dir/pty_adopt.sh" <<'PY_PTY' >/dev/null 2>&1 || true
import os, pty, select, subprocess, sys
m, s = pty.openpty()
p = subprocess.Popen(["bash", sys.argv[1]], stdin=s, stdout=s, stderr=s, close_fds=True)
os.close(s)
while True:
    r, _, _ = select.select([m], [], [], 1.0)
    if r:
        try:
            if not os.read(m, 4096):
                break
        except OSError:
            break
    elif p.poll() is not None:
        break
os.close(m)
p.wait()
PY_PTY
        grep -Fq '[GAME]' "$t_dir/adopt_1.tsv" || exit 1
        grep -Fq '[DLC]' "$t_dir/adopt_1.tsv" || exit 1
    )
}
run_test "Steam App-Type SSoT, Preview, Filter & DLC Redirect (R2A/R2B)" test_r2_steam_app_type_ssot_and_tui_contracts

# Test 38: Remediation Packet 2 (R2C) — Engine-Level DLC Guard in download_game()
test_r2_engine_level_dlc_guard_contract() {
    local t_dir
    t_dir=$(mktemp -d "${TMPDIR:-/tmp}/gamectl_r2_dlc_guard_XXXXXX")
    mkdir -p "$t_dir/home/.cache/gamectl/manifests" "$t_dir/game" "$t_dir/runtime"

    (
        trap 'rm -rf "$t_dir"' EXIT
        export HOME="$t_dir/home"
        export XDG_CACHE_HOME="$t_dir/home/.cache"
        export XDG_RUNTIME_DIR="$t_dir/runtime"

        source "$REPO_ROOT/src/core/00_header.sh"
        source "$REPO_ROOT/src/core/10_utils.sh"
        source "$REPO_ROOT/src/steam/20_discovery.sh"
        source "$REPO_ROOT/src/steam/30_downloader.sh"
        source "$REPO_ROOT/src/steam/31_manifests.sh"

        local mock_dl="$t_dir/mock_depot_dl"
        cat <<'EOF' > "$mock_dl"
#!/usr/bin/env bash
touch "${HOME}/depot_dl.invoked"
exit 0
EOF
        chmod +x "$mock_dl"
        export GAMECTL_DEPOT_DL_BIN="$mock_dl"

        cat <<'EOF' > "$XDG_CACHE_HOME/gamectl/steam_details_2778580.json"
{"2778580":{"success":true,"data":{"type":"dlc","name":"Shadow of the Erdtree","fullgame":{"appid":"1245620","name":"ELDEN RING"}}}}
EOF
        cat <<'EOF' > "$XDG_CACHE_HOME/gamectl/steam_details_1245620.json"
{"1245620":{"success":true,"data":{"type":"game","name":"ELDEN RING"}}}
EOF
        cat <<'EOF' > "$XDG_CACHE_HOME/gamectl/steam_details_555555.json"
{"555555":{"success":true,"data":{"platforms":{"windows":true,"linux":true}}}}
EOF

        local manifest_called=0
        fetch_manifest() {
            manifest_called=$((manifest_called + 1))
            local aid="$1"
            local stage="$t_dir/stage_$aid"
            mkdir -p "$stage"
            printf '\xd0\x17\xf6\x71' > "$stage/${aid}_1.manifest"
            printf 'addappid(%s, 1, "%064d")\n' "$aid" 0 > "$stage/${aid}.lua"
            local out_zip="$t_dir/m_${aid}.zip"
            (cd "$stage" && zip -q -0 "$out_zip" "${aid}_1.manifest" "${aid}.lua")
            printf '%s\n' "$out_zip"
        }
        harvest_dlc_manifests() { :; }
        inject_game() { :; }

        # 1. DLC rejected by default before fetch_manifest / depot-dl
        local err_out rc=0
        err_out=$(download_game 2778580 "$t_dir/game" "Shadow of the Erdtree" 2>&1) || rc=$?
        [ "$rc" -ne 0 ] || exit 1
        grep -Fq 'gamectl download 1245620' <<< "$err_out" || exit 1
        grep -Fq -- '--allow-dlc' <<< "$err_out" || exit 1
        [ "$manifest_called" -eq 0 ] || exit 1
        [ ! -e "$HOME/depot_dl.invoked" ] || exit 1

        # 2. Same DLC succeeds with explicit --allow-dlc
        rc=0
        download_game 2778580 "$t_dir/game" "Shadow of the Erdtree" --allow-dlc --raw >/dev/null 2>&1 || rc=$?
        [ "$rc" -eq 0 ] || exit 1
        [ -f "$HOME/depot_dl.invoked" ] || exit 1

        # 3. GAME, legacy cache without type, and offline uncached AppID are NOT blocked
        rm -f "$HOME/depot_dl.invoked"
        download_game 1245620 "$t_dir/game" "ELDEN RING" --raw >/dev/null 2>&1 || exit 1
        [ -f "$HOME/depot_dl.invoked" ] || exit 1

        rm -f "$HOME/depot_dl.invoked"
        download_game 555555 "$t_dir/game" "LegacyCached" --raw >/dev/null 2>&1 || exit 1
        [ -f "$HOME/depot_dl.invoked" ] || exit 1

        rm -f "$HOME/depot_dl.invoked"
        curl() { return 1; }
        download_game 888999 "$t_dir/game" "OfflineUncached" --raw >/dev/null 2>&1 || exit 1
        [ -f "$HOME/depot_dl.invoked" ] || exit 1

        # 4. SSoT preflight_manifest_source offline checks & deduplication + completion sync
        curl() { touch "$t_dir/preflight_net"; return 90; }
        get_valid_luatools_token() { return 1; }
        get_hubcap_api_key() { echo ""; }
        ! preflight_manifest_source 999999 luatools true 2>/dev/null || exit 1
        ! preflight_manifest_source 999999 hubcap true 2>/dev/null || exit 1
        preflight_manifest_source 999999 auto true || exit 1
        [ ! -e "$t_dir/preflight_net" ] || exit 1
        ! grep -Fq 'manifests/${appid}.zip' "$REPO_ROOT/src/steam/30_downloader.sh" || exit 1

        local comp_dl_opts
        comp_dl_opts=$(grep -F 'download_opts=' "$REPO_ROOT/completions/gamectl.bash")
        grep -Fq -- '--allow-dlc' <<< "$comp_dl_opts" || exit 1
        grep -Fq -- '--os' <<< "$comp_dl_opts" || exit 1
    )
}
run_test "Engine-Level DLC Guard in download_game() (R2C)" test_r2_engine_level_dlc_guard_contract

# Test 39: WP41A/41B — Optional Amazon Adapter (nile), Discovery, Deduplication & TUI Filter
test_wp41_amazon_adapter_and_discovery_contract() {
    local t_dir
    t_dir=$(mktemp -d "${TMPDIR:-/tmp}/gamectl_wp41_amazon_XXXXXX")
    mkdir -p "$t_dir/home/.config/gamectl" "$t_dir/home/.config/nile" "$t_dir/home/Games/AmzGame" \
             "$t_dir/home/Games/SoloAmz" "$t_dir/home/AmzBad" "$t_dir/runtime" "$t_dir/game/saves" \
             "$t_dir/no_amz_bin" "$t_dir/amz_bin"
    (
        trap 'rm -rf "$t_dir"' EXIT
        export HOME="$t_dir/home" XDG_CONFIG_HOME="$t_dir/home/.config" XDG_RUNTIME_DIR="$t_dir/runtime"
        export NILE_CONFIG_PATH="$t_dir/home/.config/nile"
        echo "amz_save" > "$t_dir/game/saves/slot.dat"
        local cmd_tool tool_path
        for cmd_tool in bash sh env cat mkdir rm cp mv grep awk sed jq curl file zip unzip rsync ssh python3 fzf dirname basename readlink head tail date stat touch tr wc cut find chmod mktemp uname pgrep id realpath; do
            tool_path="$(command -v "$cmd_tool" 2>/dev/null || true)"
            [ -n "$tool_path" ] && ln -sf "$tool_path" "$t_dir/no_amz_bin/$cmd_tool"
        done

        PATH="$t_dir/no_amz_bin" bash -c '
            set -e
            source "$1/src/core/10_utils.sh"; source "$1/src/core/14_saves.sh"; source "$1/src/steam/20_discovery.sh"
            source "$1/src/runners/40_wrappers.sh"; source "$1/src/stores/00_store_interface.sh"; source "$1/src/diagnostics/60_doctor.sh"
            store_list_registered | grep -Fxq "amazon"
            ! store_amazon_available
            curl() { touch "$2/net_hit"; return 99; }
            st=$(store_dispatch amazon status); [ ! -e "$2/net_hit" ]
            printf "%s\n" "$st" | grep -Fq "store=amazon"
            printf "%s\n" "$st" | grep -Fq "missing"
            store_dispatch amazon search "control" 2>/dev/null && exit 1 || true
            store_dispatch amazon download "Amz1" "$2/dl" 2>/dev/null && exit 1 || true
            doc_out=$(doctor_audit || true)
            printf "%s\n" "$doc_out" | grep -Fq "Amazon Store CLI"
            printf "%s\n" "$doc_out" | grep -Fq "[OPT]"
        ' _ "$REPO_ROOT" "$t_dir" || exit 1

        cat <<'EOF' > "$t_dir/amz_bin/nile"
#!/usr/bin/env bash
case "$1" in
    library|list-games)
        [ "${AMZ_MODE:-ok}" = "bad_json" ] && { printf 'NOT_JSON\n'; exit 0; }
        [ "${AMZ_MODE:-ok}" = "evil_tab" ] && { printf '[{"id":"BadId","title":"Evil\\tTitle"}]\n'; exit 0; }
        printf '[{"product":{"id":"AmzCtrl","title":"Control Ultimate"},"platforms":["windows"]},{"product":{"id":"AmzInd","title":"Indie Gem"}}]\n' ;;
    install)
        id="$2"; shift 2; p=""
        while [ $# -gt 0 ]; do [ "$1" = "--path" ] && { p="$2"; shift 2; continue; }; shift; done
        mkdir -p "$p"; printf 'installed %s\n' "$id" > "$p/amz.ok" ;;
    verify)
        id="$2"; shift 2; p=""
        while [ $# -gt 0 ]; do [ "$1" = "--path" ] && { p="$2"; shift 2; continue; }; shift; done
        printf 'verified %s %s\n' "$id" "$p" > "$p/verify.ok" ;;
    auth) printf 'nile auth ok\n' ;;
esac
EOF
        chmod +x "$t_dir/amz_bin/nile"
        printf '{"token":"SECRET_AMZ_TOKEN"}\n' > "$t_dir/home/.config/nile/user.json"
        for b in "$t_dir/home/Games/AmzGame/game.exe" "$t_dir/home/Games/SoloAmz/solo.bin" "$t_dir/home/AmzBad/bad.bin"; do
            printf '\x7fELF' > "$b"; chmod +x "$b"
        done
        cat <<EOF > "$t_dir/home/.config/nile/installed.json"
[
  {"id":"AmzCtrl","title":"Control Ultimate","path":"$t_dir/home/Games/AmzGame","executable":"game.exe"},
  {"id":"AmzBad","title":"Bad\\tTitle","path":"$t_dir/home/AmzBad","executable":"bad.bin"}
]
EOF
        PATH="$t_dir/amz_bin:$PATH" bash -c '
            set -e
            source "$1/src/core/10_utils.sh"; source "$1/src/core/14_saves.sh"; source "$1/src/steam/20_discovery.sh"; source "$1/src/stores/00_store_interface.sh"
            store_amazon_available
            st_out=$(store_dispatch amazon status)
            printf "%s\n" "$st_out" | grep -Fq "session present"
            ! printf "%s\n" "$st_out" | grep -Fq "SECRET_AMZ_TOKEN"
            store_dispatch amazon search "" 2>/dev/null && exit 1 || true
            s_out=$(store_dispatch amazon search "control")
            printf "%s\n" "$s_out" | grep -Fq $'\''AMAZON\tAmzCtrl\tControl Ultimate\twindows\tINSTALLED'\''
            AMZ_MODE=bad_json store_dispatch amazon search "x" 2>/dev/null && exit 1 || true
            AMZ_MODE=evil_tab store_dispatch amazon search "x" 2>/dev/null && exit 1 || true
            store_dispatch amazon download "AmzInd" "$2/dl_amz" >/dev/null
            grep -Fq "installed AmzInd" "$2/dl_amz/amz.ok"
            store_dispatch amazon sync "AmzCtrl" "$2/game" >/dev/null
            [ -d "$2/game/.save_snapshots/slot1" ]
            grep -Fq "verified AmzCtrl $2/game" "$2/game/verify.ok"

            err_log="$2/scan.err"; all_out=$(scan_installed_games --refresh 2>"$err_log")
            grep -Fq "[ERROR]" "$err_log"
            ! printf "%s\n" "$all_out" | grep -Fq "AmzBad"
            [ "$(printf "%s\n" "$all_out" | grep -c "AmzGame")" -eq 1 ]
            printf "%s\n" "$all_out" | awk -F"\t" '\''$1 ~ /^AmzCtrl/ && $6 == "AMAZON" {ok=1} END {exit !ok}'\''
            store_dispatch amazon list_installed | grep -Fq "AmzCtrl"
            scan_installed_games --formatted --store AMAZON | grep -Fq "[AMAZON]"
            ! scan_installed_games --store STANDALONE | grep -Fq "Control Ultimate"
            grep -Fq "AMAZON\tAmazon Games Library" "$1/src/tui/70_dashboard.sh"
            grep -Fq "amazon)" "$1/completions/gamectl.bash"
            "$1/bin/gamectl" amazon --help | grep -Fq "gamectl amazon"
            "$1/bin/gamectl" amazon status | grep -Fq "ready (nile:"
            "$1/bin/gamectl" amazon search "indie" | grep -Fq "AmzInd"
            "$1/bin/gamectl" amazon auth | grep -Fq "nile auth ok"
            "$1/bin/gamectl" amazon bogus 2>/dev/null && exit 1 || true
        ' _ "$REPO_ROOT" "$t_dir" || exit 1
    )
}
run_test "Optional Amazon Adapter, Discovery & CLI (WP41A/41B)" test_wp41_amazon_adapter_and_discovery_contract

# Test 40: WP41C — Unified Auth Hub (gamectl auth) & Cross-Store Search (search_stores)
test_wp41_auth_hub_and_cross_store_search_contract() {
    local t_dir
    t_dir=$(mktemp -d "${TMPDIR:-/tmp}/gamectl_wp41_auth_search_XXXXXX")
    mkdir -p "$t_dir/home/.config/gamectl" "$t_dir/home/.config/gogdl" "$t_dir/home/.config/legendary" \
             "$t_dir/home/.config/nile" "$t_dir/runtime" "$t_dir/bin"
    (
        trap 'rm -rf "$t_dir"' EXIT
        export HOME="$t_dir/home" XDG_CONFIG_HOME="$t_dir/home/.config" XDG_RUNTIME_DIR="$t_dir/runtime"
        export LEGENDARY_CONFIG_PATH="$t_dir/home/.config/legendary" NILE_CONFIG_PATH="$t_dir/home/.config/nile"
        printf '{"refresh_token":"SECRET_LUA_TOK"}\n' > "$t_dir/home/.config/gamectl/lua_tools_auth.json"
        printf '{"access_token":"SECRET_GOG_TOK"}\n' > "$t_dir/home/.config/gogdl/auth.json"
        printf '{"access_token":"SECRET_EPIC_TOK"}\n' > "$t_dir/home/.config/legendary/user.json"
        printf '{"token":"SECRET_AMZ_TOK"}\n' > "$t_dir/home/.config/nile/user.json"

        cat <<'EOF' > "$t_dir/bin/gogdl"
#!/usr/bin/env bash
case "$1" in auth) echo "gog auth ok";; search) printf '[{"id":"111","title":"Witcher","worksOn":{"Linux":true}}]\n';; esac
EOF
        cat <<'EOF' > "$t_dir/bin/legendary"
#!/usr/bin/env bash
case "$1" in auth) echo "epic auth ok";; list) printf '[{"app_name":"Ep1","app_title":"Witcher Epic","asset_infos":{"Windows":{}}}]\n';; esac
EOF
        cat <<'EOF' > "$t_dir/bin/nile"
#!/usr/bin/env bash
case "$1" in auth) echo "amz auth ok";; library|list-games) printf '[{"product":{"id":"Am1","title":"Witcher Amazon"},"platforms":["windows"]}]\n';; esac
EOF
        chmod +x "$t_dir/bin/gogdl" "$t_dir/bin/legendary" "$t_dir/bin/nile"

        PATH="$t_dir/bin:$PATH" bash -c '
            set -e
            source "$1/src/core/10_utils.sh"; source "$1/src/steam/20_discovery.sh"; source "$1/src/steam/30_downloader.sh"
            source "$1/src/steam/31_manifests.sh"; source "$1/src/stores/00_store_interface.sh"

            net_hit="$2/auth_net_hit"
            batch_log="$2/batch.calls"
            curl() { touch "$net_hit"; return 99; }
            auth_st=$(auth_hub_cli status)
            [ ! -e "$net_hit" ]
            for tok in SECRET_LUA_TOK SECRET_GOG_TOK SECRET_EPIC_TOK SECRET_AMZ_TOK; do
                ! printf "%s\n" "$auth_st" | grep -Fq "$tok"
            done
            printf "%s\n" "$auth_st" | grep -Fq "store=steam"
            printf "%s\n" "$auth_st" | grep -Fq "store=gog"
            printf "%s\n" "$auth_st" | grep -Fq "store=epic"
            printf "%s\n" "$auth_st" | grep -Fq "store=amazon"

            [ "$(auth_hub_cli gog)" = "gog auth ok" ]
            [ "$(auth_hub_cli epic)" = "epic auth ok" ]
            [ "$(auth_hub_cli amazon)" = "amz auth ok" ]
            login_luatools() { echo "lua auth $1"; }
            [ "$(auth_hub_cli luatools ABCDEF)" = "lua auth ABCDEF" ]
            auth_hub_cli bogus 2>/dev/null && exit 1 || true

            : > "$batch_log"
            curl() {
                local u="${@: -1}"
                if [[ "$u" == *storesearch* ]]; then
                    printf "%s" "{\"items\":[{\"id\":1245620,\"name\":\"Witcher Base\",\"platforms\":{\"windows\":true}},{\"id\":2778580,\"name\":\"Witcher DLC\",\"platforms\":{\"windows\":true}}]}"
                elif [[ "$u" == *IStoreBrowseService/GetItems* ]]; then
                    printf "1\n" >> "$batch_log"
                    printf "%s" "{\"response\":{\"store_items\":[{\"appid\":1245620,\"type\":0},{\"appid\":2778580,\"type\":4,\"related_items\":{\"parent_appid\":1245620}}]}}"
                fi
            }
            all_res=$(store_search_all "witcher")
            [ "$(wc -l < "$batch_log")" -eq 1 ]
            printf "%s\n" "$all_res" | awk -F"\t" "NF != 7 {exit 1}"
            printf "%s\n" "$all_res" | grep -Fxq $'\''STEAM\t1245620\tWitcher Base\twindows\tAVAILABLE\tGAME\t'\''
            printf "%s\n" "$all_res" | grep -Fxq $'\''STEAM\t2778580\tWitcher DLC\twindows\tAVAILABLE\tDLC\t1245620'\''
            printf "%s\n" "$all_res" | grep -Fxq $'\''GOG\t111\tWitcher\tlinux\tAVAILABLE\tGAME\t'\''
            printf "%s\n" "$all_res" | grep -Fxq $'\''EPIC\tEp1\tWitcher Epic\twindows\tAVAILABLE\tGAME\t'\''
            printf "%s\n" "$all_res" | grep -Fxq $'\''AMAZON\tAm1\tWitcher Amazon\twindows\tAVAILABLE\tGAME\t'\''

            # Store filter + offline Steam batch fallback to APP + 5-col store_*_search intact
            [ "$(store_search_all "witcher" --store gog | wc -l)" -eq 1 ]
            curl() {
                local u="${@: -1}"
                [[ "$u" == *storesearch* ]] && printf "%s" "{\"items\":[{\"id\":1245620,\"name\":\"Witcher Base\",\"platforms\":{\"windows\":true}}]}" || return 1
            }
            store_search_all "witcher" --store steam | grep -Fxq $'\''STEAM\t1245620\tWitcher Base\twindows\tAVAILABLE\tAPP\t'\''
            store_gog_search "witcher" | awk -F"\t" "NF != 5 {exit 1}"
            grep -Fq "search_stores_interactive" "$1"/src/tui/*.sh
            grep -Fq "search-stores|search_stores)" "$1/completions/gamectl.bash"
            "$1/bin/gamectl" auth status | grep -Fq "store=amazon"
            "$1/bin/gamectl" search-stores --help | grep -Fq "gamectl search-stores"
        ' _ "$REPO_ROOT" "$t_dir" || exit 1
    )
}
run_test "Unified Auth Hub & Cross-Store Search (WP41C)" test_wp41_auth_hub_and_cross_store_search_contract

# Test 41: Work Packet 3 (R3A-R3D) — Module LOC Budget Guard & Submodule Auto-Loaders
test_r3_loc_budget_and_submodule_autoloader_contract() {
    local t_dir
    t_dir=$(mktemp -d "${TMPDIR:-/tmp}/gamectl_r3_loc_XXXXXX")
    mkdir -p "$t_dir/src/core"
    (
        trap 'rm -rf "$t_dir"' EXIT
        bash "$REPO_ROOT/scripts/check_loc_budget.sh" "$REPO_ROOT" >/dev/null || exit 1

        # New module <= 600 passes; > 600 fails; legacy ceiling exceeded fails; empty src fails
        printf '# ok\n' > "$t_dir/src/core/ok.sh"
        bash "$REPO_ROOT/scripts/check_loc_budget.sh" "$t_dir" >/dev/null || exit 1
        python3 -c 'print("\n".join(["# x"]*601))' > "$t_dir/src/core/over.sh"
        ! bash "$REPO_ROOT/scripts/check_loc_budget.sh" "$t_dir" 2>/dev/null || exit 1
        rm -f "$t_dir/src/core/over.sh"
        python3 -c 'print("\n".join(["# x"]*606))' > "$t_dir/src/main.sh"
        ! bash "$REPO_ROOT/scripts/check_loc_budget.sh" "$t_dir" 2>/dev/null || exit 1
        rm -rf "$t_dir/src" && mkdir -p "$t_dir/src"
        ! bash "$REPO_ROOT/scripts/check_loc_budget.sh" "$t_dir" 2>/dev/null || exit 1

        # Unbundled sibling auto-loaders load 21_shortcuts_artwork.sh, 33/34, 36/37, 38, 43, and 72/73
        bash -c '
            set -e
            unset GAMECTL_BUNDLED
            source "$1/src/core/00_header.sh"
            source "$1/src/core/10_utils.sh"
            source "$1/src/steam/20_discovery.sh"
            declare -F create_desktop_entry >/dev/null
            declare -F fetch_steam_artwork >/dev/null
            declare -F add_steam_shortcut >/dev/null
            source "$1/src/steam/30_downloader.sh"
            declare -F list_downloads >/dev/null
            declare -F preview_download >/dev/null
            declare -F list_downloads_interactive >/dev/null
            source "$1/src/steam/31_manifests.sh"
            declare -F get_valid_luatools_token >/dev/null
            declare -F classify_steam_app_types >/dev/null
            source "$1/src/steam/35_fixes.sh"
            declare -F restart_steam_client >/dev/null
            declare -F preview_fix_entry >/dev/null
            declare -F manage_game_fixes_interactive >/dev/null
            source "$1/src/runners/41_proton_prefix.sh"
            declare -F list_runner_dirs >/dev/null
            declare -F find_runner >/dev/null
            declare -F proton_list >/dev/null
            declare -F proton_install >/dev/null
            declare -F proton_remove >/dev/null
            source "$1/src/tui/70_dashboard.sh"
            declare -F search_steam >/dev/null
            declare -F search_stores_interactive >/dev/null
        ' _ "$REPO_ROOT" || exit 1

        grep -Fq '_scan_json_store_entries' "$REPO_ROOT/src/steam/20_discovery.sh" || exit 1
        ! grep -Fq 'src/steam/20_discovery.sh' "$REPO_ROOT/scripts/check_loc_budget.sh" || exit 1
        ! grep -Fq 'src/steam/30_downloader.sh' "$REPO_ROOT/scripts/check_loc_budget.sh" || exit 1
        ! grep -Fq 'src/steam/31_manifests.sh' "$REPO_ROOT/scripts/check_loc_budget.sh" || exit 1
        ! grep -Fq 'src/steam/35_fixes.sh' "$REPO_ROOT/scripts/check_loc_budget.sh" || exit 1
        ! grep -Fq 'src/runners/41_proton_prefix.sh' "$REPO_ROOT/scripts/check_loc_budget.sh" || exit 1
        ! grep -Fq 'src/tui/70_dashboard.sh' "$REPO_ROOT/scripts/check_loc_budget.sh" || exit 1
        local f f_loc
        for f in "$REPO_ROOT"/src/*/*.sh; do
            f_loc=$(wc -l < "$f")
            [ "$f_loc" -le 900 ] || exit 1
        done
    )
}
run_test "Module LOC Budget & Submodule Auto-Loaders (R3A-R3D)" test_r3_loc_budget_and_submodule_autoloader_contract

# Test 42: Linux Shebang/Arch Binary Detection, Running List Badges & Startup Crash Probe
test_process_runtime_binary_and_ux_contract() {
    local t_dir
    t_dir=$(mktemp -d "${TMPDIR:-/tmp}/gamectl_proc_ux_XXXXXX")
    (
        trap 'rm -rf "$t_dir"' EXIT
        export HOME="$t_dir/home"
        export XDG_RUNTIME_DIR="$t_dir/runtime"
        export XDG_CACHE_HOME="$t_dir/cache"
        mkdir -p "$HOME/Games" "$XDG_RUNTIME_DIR/active_games" "$XDG_CACHE_HOME/gamectl"
        unset GAMECTL_BUNDLED
        source "$REPO_ROOT/src/core/00_header.sh"
        source "$REPO_ROOT/src/core/10_utils.sh"
        source "$REPO_ROOT/src/steam/20_discovery.sh"
        source "$REPO_ROOT/src/steam/25_identity.sh"
        source "$REPO_ROOT/src/steam/30_downloader.sh"
        source "$REPO_ROOT/src/runners/40_wrappers.sh"
        source "$REPO_ROOT/src/runners/42_graphics_isolation.sh"
        source "$REPO_ROOT/src/tui/71_previews.sh"

        # 1. ensure_linux_binaries_executable +x on #! script and ELF, leaves .txt/.pak alone
        local d_perm="$t_dir/perm_check"
        mkdir -p "$d_perm"
        printf '#!/bin/bash\nexec true\n' > "$d_perm/Celeste"
        printf '\x7f\x45\x4c\x46dummy' > "$d_perm/game.x86_64"
        printf 'notes' > "$d_perm/readme.txt"
        chmod 644 "$d_perm/Celeste" "$d_perm/game.x86_64" "$d_perm/readme.txt"
        ensure_linux_binaries_executable "$d_perm" 2>/dev/null
        [ -x "$d_perm/Celeste" ] && [ -x "$d_perm/game.x86_64" ] && [ ! -x "$d_perm/readme.txt" ] || exit 1

        # 2. find_game_binary: prefers #! wrapper Celeste (auto-+x), else x86_64 over x86 and .exe
        local d_cel="$HOME/Games/Celeste"
        mkdir -p "$d_cel"
        printf '#!/bin/bash\nexit 0\n' > "$d_cel/Celeste"
        chmod 644 "$d_cel/Celeste"
        printf '\x7f\x45\x4c\x46\x01\x01\x01' > "$d_cel/Celeste.bin.x86"
        printf '\x7f\x45\x4c\x46\x02\x01\x01' > "$d_cel/Celeste.bin.x86_64"
        printf 'MZ' > "$d_cel/Celeste.exe"
        chmod 755 "$d_cel/Celeste.bin.x86" "$d_cel/Celeste.bin.x86_64" "$d_cel/Celeste.exe"
        [ "$(find_game_binary "$d_cel")" = "Celeste" ] && [ -x "$d_cel/Celeste" ] || exit 1

        if [ "$(uname -m)" = "x86_64" ]; then
            rm -f "$d_cel/Celeste"
            [ "$(find_game_binary "$d_cel")" = "Celeste.bin.x86_64" ] || exit 1
        fi
        printf '#!/bin/bash\nexit 0\n' > "$d_cel/Celeste"
        chmod 755 "$d_cel/Celeste"

        # 32-bit-only and Windows-only fallbacks remain intact (even with +x 0-byte pfx.lock)
        local d_32="$HOME/Games/Teleglitch" d_win="$HOME/Games/Downwell"
        mkdir -p "$d_32" "$d_win"
        printf '\x7f\x45\x4c\x46\x01\x01\x01' > "$d_32/teleglitch32"
        chmod 755 "$d_32/teleglitch32"
        : > "$d_win/pfx.lock"
        chmod 755 "$d_win/pfx.lock"
        printf 'MZ' > "$d_win/Downwell.exe"
        [ "$(find_game_binary "$d_32")" = "teleglitch32" ] || exit 1
        [ "$(find_game_binary "$d_win")" = "Downwell.exe" ] || exit 1

        # 3. inspect_game_log_hint recognizes DllNotFoundException & Exec format error
        local l_dll="$t_dir/dll.log" l_exec="$t_dir/exec.log"
        printf 'System.DllNotFoundException: libFNA3D.so.0\n' > "$l_dll"
        printf 'bash: ./game: Exec format error\n' > "$l_exec"
        inspect_game_log_hint "$l_dll" | grep -Fq 'Missing runtime DLL/library' || exit 1
        inspect_game_log_hint "$l_exec" | grep -Fq 'Executable architecture or permission mismatch' || exit 1

        # 4. Active process SSoT, stale pruning, [RUNNING] formatted row, and preview label
        sleep 5 &
        local live_pid=$!
        trap 'kill "$live_pid" 2>/dev/null || true; rm -rf "$t_dir"' EXIT
        local live_log="$XDG_RUNTIME_DIR/celeste_live.log"
        printf 'ok running\n' > "$live_log"
        printf 'PID=%s\nTITLE=Celeste\nDIR=%s\nBIN=Celeste\nLOG=%s\nSCOPE_UNIT=\n' "$live_pid" "$d_cel" "$live_log" > "$XDG_RUNTIME_DIR/active_games/${live_pid}.info"
        printf 'PID=999999\nTITLE=StaleGame\nDIR=/tmp/nonexistent_stale\nBIN=x\nLOG=/tmp/x.log\n' > "$XDG_RUNTIME_DIR/active_games/999999.info"

        local active_out
        active_out=$(list_active_games)
        grep -Fq "$live_pid" <<< "$active_out" || exit 1
        [ ! -e "$XDG_RUNTIME_DIR/active_games/999999.info" ] || exit 1
        [ "$(get_active_games_summary)" = $'1\x1fCeleste' ] || exit 1

        local fmt_rows
        fmt_rows=$(scan_installed_games --refresh --formatted)
        grep -F 'Celeste' <<< "$fmt_rows" | grep -Fq '[RUNNING]' || exit 1
        ! grep -F 'Downwell' <<< "$fmt_rows" | grep -Fq '[RUNNING]' || exit 1

        local prev_out
        prev_out=$(preview_game "504230" "Celeste" "[GBE_FORK]" "$d_cel" "Celeste" 2>/dev/null)
        grep -Fq "[RUNNING PID:$live_pid]" <<< "$prev_out" || exit 1
        grep -Fq "Manage Running Game" <<< "$prev_out" || exit 1

        # 5. verify_launched_game_startup: pass on live process, fail + summarize on early exit
        GAMECTL_LAUNCH_PROBE_TICKS=2 verify_launched_game_startup "$d_cel" "Celeste" "Celeste" || exit 1
        [ "$GAMECTL_VERIFY_PID" = "$live_pid" ] || exit 1

        kill "$live_pid" 2>/dev/null || true
        wait "$live_pid" 2>/dev/null || true
        local d_crash="$HOME/Games/CrashApp"
        mkdir -p "$d_crash"
        local c_log
        c_log="$(get_game_log_file "$d_crash" "CrashApp.bin")"
        printf 'System.DllNotFoundException: libFNA3D.so.0\n' > "$c_log"
        printf 'PID=999998\nTITLE=CrashApp\nDIR=%s\nBIN=CrashApp.bin\nLOG=%s\n' "$d_crash" "$c_log" > "$XDG_RUNTIME_DIR/active_games/999998.info"
        if GAMECTL_LAUNCH_PROBE_TICKS=2 verify_launched_game_startup "$d_crash" "CrashApp.bin" "CrashApp"; then
            exit 1
        fi
        [ ! -e "$XDG_RUNTIME_DIR/active_games/999998.info" ] || exit 1
        grep -Fq '[HINT] Missing runtime DLL/library' <<< "$GAMECTL_VERIFY_SUMMARY" || exit 1
        grep -Fq 'System.DllNotFoundException: libFNA3D.so.0' <<< "$GAMECTL_VERIFY_SUMMARY" || exit 1

        # 6. tui_modal_notice --wrap=word & list_missing_elf_libs ldd diagnostics (with ':' path & dedup)
        grep -Fq -- '--wrap=word' <(sed -n '/^tui_modal_notice()/,/^}/p' "$REPO_ROOT/src/core/12_tui_primitives.sh") || exit 1
        ! list_missing_elf_libs "$d_win" "Downwell.exe" >/dev/null 2>&1 || exit 1

        local d_colon="$HOME/Games/Game: Special Edition" stub_bin="$t_dir/ldd_stub_bin"
        mkdir -p "$d_colon" "$stub_bin"
        printf '\x7f\x45\x4c\x46\x01\x01\x01' > "$d_colon/game32"
        chmod 755 "$d_colon/game32"
        cat <<'EOF_LDD' > "$stub_bin/ldd"
#!/usr/bin/env bash
case ":$LD_LIBRARY_PATH:" in
    *":.:"*|".:"*) ;;
    *) echo "BAD_LD_PATH=$LD_LIBRARY_PATH" >&2; exit 1 ;;
esac
printf '\tlibGLU.so.1 => not found\n\tlibSDL2-2.0.so.0 => not found\n\tlibGLU.so.1 => not found\n\tlibopenal.so.1 => not found\n\tlibsteam_api.so => ./libsteam_api.so (0xf7000000)\n'
EOF_LDD
        chmod +x "$stub_bin/ldd"

        local ldd_info="" ldd_log=""
        ldd_info=$(PATH="$stub_bin:$PATH" list_missing_elf_libs "$d_colon" "game32") || exit 1
        [ "$ldd_info" = $'32-bit\x1flibGLU.so.1, libSDL2-2.0.so.0, libopenal.so.1' ] || exit 1

        ldd_log="$(get_game_log_file "$d_colon" "game32")"
        printf './game32: error while loading shared libraries: libGLU.so.1: cannot open shared object file\n' > "$ldd_log"
        printf 'PID=999997\nTITLE=Special32\nDIR=%s\nBIN=game32\nLOG=%s\n' "$d_colon" "$ldd_log" > "$XDG_RUNTIME_DIR/active_games/999997.info"
        if PATH="$stub_bin:$PATH" GAMECTL_LAUNCH_PROBE_TICKS=2 verify_launched_game_startup "$d_colon" "game32" "Special32"; then
            exit 1
        fi
        grep -Fq 'Missing Shared Libraries (32-bit):' <<< "$GAMECTL_VERIFY_SUMMARY" || exit 1
        grep -Fq 'libGLU.so.1, libSDL2-2.0.so.0, libopenal.so.1' <<< "$GAMECTL_VERIFY_SUMMARY" || exit 1
    )
}
run_test "Runtime Binary Detection, Running List Badges & Startup Probe" test_process_runtime_binary_and_ux_contract

echo
if [ "$FAILED_TESTS" -eq 0 ] && [ "$TOTAL_TESTS" -gt 0 ]; then
    echo "${C_GREEN}[ VERIFIED ] All remediation contracts passed with Exit 0 ($PASSED_TESTS/$TOTAL_TESTS).${C_RST}"
    exit 0
else
    echo "${C_RED}[ FAILED ] $FAILED_TESTS test assertion(s) failed.${C_RST}"
    exit 1
fi

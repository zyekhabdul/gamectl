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

echo
if [ "$FAILED_TESTS" -eq 0 ] && [ "$TOTAL_TESTS" -gt 0 ]; then
    echo "${C_GREEN}[ VERIFIED ] All remediation contracts passed with Exit 0 ($PASSED_TESTS/$TOTAL_TESTS).${C_RST}"
    exit 0
else
    echo "${C_RED}[ FAILED ] $FAILED_TESTS test assertion(s) failed.${C_RST}"
    exit 1
fi

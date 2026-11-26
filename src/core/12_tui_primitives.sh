# Flush pending keyboard input to prevent ghost keypress propagation across TUI views
flush_tty_input() {
    if [ -t 0 ]; then
        while read -r -t 0.01 -n 10000 _ 2>/dev/null; do
            :
        done
    elif [ -r /dev/tty ]; then
        while read -r -t 0.01 -n 10000 _ < /dev/tty 2>/dev/null; do
            :
        done
    fi
    return 0
}

# Terminal Screen Lifecycle Management (Alternate Screen Buffer)
export GAMECTL_IN_ALT_SCREEN=0
GAMECTL_TUI_OWNER_PID=""
GAMECTL_TUI_EXITING=0
GAMECTL_SAVED_STTY=""

# Canonical TUI signal trap installer (Single Authoritative Owner)
install_tui_screen_traps() {
    if [ "${GAMECTL_IN_ALT_SCREEN:-0}" -eq 1 ] && [ "${BASHPID:-$$}" = "${GAMECTL_TUI_OWNER_PID:-}" ]; then
        trap '_gamectl_tui_rc=$?; trap - EXIT INT TERM; exit_tui_screen; exit "$_gamectl_tui_rc"' EXIT
        trap 'trap - EXIT INT TERM; exit_tui_screen; exit 130' INT
        trap 'trap - EXIT INT TERM; exit_tui_screen; exit 143' TERM
    fi
    return 0
}

enter_tui_screen() {
    if [ -t 1 ] && [ "${TERM:-}" != "dumb" ] && [ "${GAMECTL_IN_ALT_SCREEN:-0}" -eq 0 ]; then
        if [ -t 0 ]; then
            GAMECTL_SAVED_STTY=$(stty -g 2>/dev/null || echo "")
        fi
        tput smcup 2>/dev/null || printf '\033[?1049h'
        printf '\033[2J\033[H' 2>/dev/null || true
        export GAMECTL_IN_ALT_SCREEN=1
        GAMECTL_TUI_OWNER_PID="${BASHPID:-$$}"
        GAMECTL_TUI_EXITING=0
        install_tui_screen_traps
    fi
    return 0
}

exit_tui_screen() {
    # Re-entrant & single-owner guard: idempotent under concurrent signals or repeated calls
    if [ "${GAMECTL_TUI_EXITING:-0}" -eq 1 ]; then
        return 0
    fi
    if [ "${GAMECTL_IN_ALT_SCREEN:-0}" -ne 1 ]; then
        return 0
    fi
    if [ -n "${GAMECTL_TUI_OWNER_PID:-}" ] && [ "${BASHPID:-$$}" != "${GAMECTL_TUI_OWNER_PID}" ]; then
        return 0
    fi

    GAMECTL_TUI_EXITING=1
    export GAMECTL_IN_ALT_SCREEN=0

    if [ -t 1 ]; then
        printf '\033[2J\033[H' 2>/dev/null || true
        tput rmcup 2>/dev/null || printf '\033[?1049l'
        tput cnorm 2>/dev/null || printf '\033[?25h'
    fi
    if [ -t 0 ]; then
        if [ -n "${GAMECTL_SAVED_STTY:-}" ]; then
            stty "$GAMECTL_SAVED_STTY" 2>/dev/null || stty echo icanon 2>/dev/null || true
            GAMECTL_SAVED_STTY=""
        else
            stty echo icanon 2>/dev/null || true
        fi
    elif [ -t 1 ]; then
        stty echo icanon 2>/dev/null || true
    fi

    trap - EXIT INT TERM 2>/dev/null || true
    GAMECTL_TUI_OWNER_PID=""
    GAMECTL_TUI_EXITING=0
    return 0
}

# Clean FZF Modal Notification Dialog (Zero-Flicker)
tui_modal_notice() {
    local title="${1:-Notice}"
    local msg="${2:-}"
    local rendered="${msg//\\n/$'\n'}"

    if [ ! -t 0 ] || [ ! -t 1 ]; then
        log_msg "INFO" "UI" "[$title] ${rendered//$'\n'/ | }"
        printf '[%s]\n%s\n' "$title" "$rendered"
        return 0
    fi
    require_tui "$title" || return $?
    flush_tty_input

    local fzf_rc=0
    printf '%s\n' "$rendered" | fzf \
        --disabled \
        --no-info \
        --no-sort \
        --wrap=word \
        --pointer=' ' \
        --prompt='' \
        --border-label="  ╢ $title ╟  " \
        --border-label-pos=2 \
        --header="NOTICE (Enter or Esc: Dismiss)" \
        --reverse 2>/dev/null || fzf_rc=$?
    check_fzf_status "$fzf_rc" || return $?
    return 0
}

# Canonical Free-Text Input Dialog (Zero-Flicker FZF Wrapper)
tui_prompt_input() {
    local title="${1:-Input}"
    local header="${2:-Enter text (Enter: Confirm │ Esc: Cancel)}"
    local default_val="${3:-}"
    local prompt_str="${4:-Input > }"

    if [ ! -t 0 ]; then
        log_msg "INFO" "UI" "[$title] Non-interactive input fallback: '$default_val'"
        echo "$default_val"
        return 0
    fi
    if ! command -v fzf >/dev/null 2>&1; then
        echo "[ERROR] fzf is required for $title." >&2
        return 127
    fi

    flush_tty_input
    local input_raw="" fzf_rc=0
    input_raw=$(: | fzf \
        --print-query \
        --query="$default_val" \
        --border-label="  ╢ $title ╟  " \
        --border-label-pos=2 \
        --header="$header" \
        --prompt="$prompt_str" \
        --reverse 2>/dev/null) || fzf_rc=$?

    check_fzf_status "$fzf_rc" || return $?
    [ "$fzf_rc" -eq 130 ] && return 130

    local cleaned
    cleaned=$(echo "$input_raw" | head -n 1 | tr -d '\r\n')
    echo "$cleaned"
    return 0
}

# Canonical Action Selection Palette (Zero-Flicker FZF Wrapper)
tui_action_palette() {
    local title="${1:-Menu}"
    local header="${2:-Select Option (Enter: Select │ Esc: Cancel)}"
    local options_tsv="${3:-}"
    local preview_cmd="${4:-}"
    local prompt_str="${5:-Select > }"

    if [ ! -t 0 ]; then
        echo "[ERROR] Interactive palette requires a terminal (TTY)." >&2
        return 1
    fi
    if ! command -v fzf >/dev/null 2>&1; then
        echo "[ERROR] fzf is required for $title." >&2
        return 127
    fi

    flush_tty_input
    local fzf_cmd=(
        fzf
        --delimiter=$'\t'
        --with-nth=1,2
        --border-label="  ╢ $title ╟  "
        --border-label-pos=2
        --header="$header"
        --prompt="$prompt_str"
        --reverse
    )
    if [ -n "$preview_cmd" ]; then
        fzf_cmd+=(--preview="$preview_cmd" --preview-window=down:40%:border-rounded:wrap)
    fi

    local sel="" fzf_rc=0
    sel=$(printf "%s" "$options_tsv" | "${fzf_cmd[@]}" 2>/dev/null) || fzf_rc=$?

    check_fzf_status "$fzf_rc" || return $?
    [ "$fzf_rc" -eq 130 ] && return 130

    echo "$sel"
    return 0
}

# Execute headless engine command with isolated subshell and deterministic error capture
tui_run_engine() {
    local fail_title=""
    if [ "${1:-}" = "--fail-title" ]; then
        fail_title="${2:-}"
        shift 2
    fi
    local action_name="$1"
    shift
    [ -n "$fail_title" ] || fail_title="Engine Failure ($action_name)"
    local cmd=("$@")
    local run_dir run_log out_log err_log
    run_dir="$(get_runtime_dir)"
    run_log="$(get_runtime_log_file)"
    out_log=$(mktemp "$run_dir/out_${$}.XXXXXX") || return 1
    err_log=$(mktemp "$run_dir/err_${$}.XXXXXX") || { rm -f "$out_log" 2>/dev/null || true; return 1; }

    local rc=0
    # Execute inside isolated subshell with stdin disconnected (< /dev/null)
    # Capture stdout & stderr per invocation, append stdout to runtime log, and fall back to stdout on silent stderr
    ( export GAMECTL_ENGINE_ISOLATED=1; "${cmd[@]}" ) < /dev/null > "$out_log" 2> "$err_log" || rc=$?
    if [ -s "$out_log" ]; then
        cat "$out_log" >> "$run_log" 2>/dev/null || true
    fi

    if [ "$rc" -ne 0 ]; then
        local err_summary=""
        if [ -s "$err_log" ]; then
            err_summary=$(tail -n 12 "$err_log" 2>/dev/null || true)
        elif [ -s "$out_log" ]; then
            err_summary=$(tail -n 12 "$out_log" 2>/dev/null || true)
        fi
        if [ -z "${err_summary//[[:space:]]/}" ]; then
            err_summary="No diagnostic output emitted."
        fi
        log_msg "ERROR" "ENGINE" "$action_name failed (exit code $rc)"
        tui_modal_notice "$fail_title" "Operation returned Exit Code $rc.\n\nError Traces:\n$err_summary\n\nFull log:\n$run_log"
    fi
    rm -f "$out_log" "$err_log" 2>/dev/null || true
    return "$rc"
}

# Execute command with live interactive terminal streaming and zero raw leaks
tui_exec_action() {
    local action_title="$1"
    shift
    local cmd=("$@")

    if [ ! -t 0 ] || [ ! -t 1 ]; then
        "${cmd[@]}"
        return $?
    fi

    local run_dir
    run_dir="$(get_runtime_dir)"
    local tmp_log="$run_dir/action_review_$$.log"
    : > "$tmp_log"

    # Clean the full alternate screen to guarantee zero ghost lines from previous menus
    printf '\033[2J\033[H'
    printf '\033[1;35m╭── ╢ gamectl :: Live Action Stream ╟────────────────────────────────────────────\033[0m\n'
    printf '\033[1;36m│ Target : %s\033[0m\n' "$action_title"
    printf '\033[38;5;244m│ Stream : Real-time live execution (Ctrl+C to abort)\033[0m\n'
    printf '\033[1;35m╰───────────────────────────────────────────────────────────────────────────────\033[0m\n\n'

    echo "[INFO] Running: $action_title..." >> "$tmp_log"

    # Shield parent shell from SIGINT termination so child process handles abort cleanly
    trap '' INT

    local rc=0 _had_errexit=0
    [[ $- == *e* ]] && _had_errexit=1
    set +e
    "${cmd[@]}" 2>&1 | tee -a "$tmp_log"
    rc="${PIPESTATUS[0]}"
    [ "$_had_errexit" -eq 1 ] && set -e

    if [ "${GAMECTL_IN_ALT_SCREEN:-0}" -eq 1 ] && [ "${BASHPID:-$$}" = "${GAMECTL_TUI_OWNER_PID:-}" ]; then
        install_tui_screen_traps
    else
        trap - INT
    fi

    printf '\n'
    if [ "$rc" -eq 0 ]; then
        printf '\033[1;32m╭── ╢ [SUCCESS] %s completed successfully ╟─────────────────────────\033[0m\n' "$action_title"
    elif [ "$rc" -eq 130 ]; then
        printf '\033[1;33m╭── ╢ [CANCELLED] %s was aborted by user ╟─────────────────────────\033[0m\n' "$action_title"
    else
        printf '\033[1;31m╭── ╢ [FAILED (Exit %d)] %s encountered an error ╟──────────────────\033[0m\n' "$rc" "$action_title"
    fi
    printf '\033[38;5;244m╰── Press Enter or Esc to return to Dashboard ──────────────────────────────────\033[0m\n'

    flush_tty_input
    local key=""
    IFS= read -r -s -n 1 key 2>/dev/null || true
    if [ "$key" = $'\e' ]; then
        read -r -s -n 2 -t 0.05 _ || true
    fi
    flush_tty_input

    # Clean the screen completely before handing back control to caller TUI
    printf '\033[2J\033[H'

    rm -f "$tmp_log" 2>/dev/null || true
    return "$rc"
}

require_tui() {
    if [ ! -t 0 ] || [ ! -t 1 ]; then
        echo "[ERROR] ${1:-Interactive mode} requires a terminal (TTY)." >&2
        return 1
    fi
    if ! command -v fzf >/dev/null 2>&1; then
        echo "[ERROR] fzf is required for ${1:-interactive mode}." >&2
        return 127
    fi
}

check_fzf_status() {
    case "$1" in
        0|1|130) return 0 ;;
        *) echo "[ERROR] Interactive selection failed (fzf exit code $1)." >&2; return "$1" ;;
    esac
}

validate_tui_fields() {
    local field
    for field in "$@"; do
        if [[ "$field" == *[$'\t\r\n']* ]]; then
            printf '[ERROR] TUI fields cannot contain TAB, CR or newline: %q\n' "$field" >&2
            return 1
        fi
    done
}

store_search_items() {
    jq -r 'if any(.items[]?; (.id | tostring | test("[\\t\\r\\n]")) or (.name | test("[\\t\\r\\n]")))
        then error("TUI catalog contains TAB, CR or newline")
        else .items[]? | "\(.id)\t\(.name)" end'
}


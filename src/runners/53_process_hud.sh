# ==============================================================================
# Running Process Controller HUD & Log Context Preview (Split from 50_launcher.sh)
# ==============================================================================

# Preview pane generator for Process HUD Log context (3 lines before and 3 lines after)
preview_process_log() {
    local lfile="$1"
    local lnum="${2:-1}"
    [ -f "$lfile" ] || return 0
    [[ "$lnum" =~ ^[0-9]+$ ]] || lnum=1

    local total_lines
    total_lines=$(wc -l < "$lfile" 2>/dev/null || echo 1)
    local start_line=$(( lnum > 3 ? lnum - 3 : 1 ))
    local end_line=$(( lnum + 3 < total_lines ? lnum + 3 : total_lines ))

    echo "${UI_BOX}╭─ PROCESS LOG CONTEXT (Lines $start_line..$end_line of $total_lines) ────────────────╮${UI_RST}"
    local cur=1
    while IFS= read -r line || [ -n "$line" ]; do
        if [ "$cur" -ge "$start_line" ] && [ "$cur" -le "$end_line" ]; then
            if [ "$cur" -eq "$lnum" ]; then
                printf "  ${UI_GREEN}-> [%3d]${UI_RST} ${UI_BOLD}${UI_CYAN}%s${UI_RST}\n" "$cur" "$line"
            else
                printf "     ${UI_DIM}[%3d] %s${UI_RST}\n" "$cur" "$line"
            fi
        fi
        cur=$((cur + 1))
        [ "$cur" -gt "$end_line" ] && break
    done < "$lfile"
    echo "${UI_BOX}╰─────────────────────────────────────────────────────────────────────╯${UI_RST}"
}

# Interactive Live HUD for running game process (Zero-Flicker FZF Modal)
game_controller_hud() {
    if [ ! -t 0 ] || [ ! -t 1 ]; then
        echo "[ERROR] Process HUD requires a terminal (TTY)." >&2
        return 1
    fi
    if ! command -v fzf >/dev/null 2>&1; then
        echo "[ERROR] fzf is required for Process HUD but was not found in PATH." >&2
        return 127
    fi

    local game_pid="$1"
    local title="$2"
    local log_file="$3"
    local gdir="$4"
    local gbin="$5"
    local info_file="$6"
    local run_type="$7"

    flush_tty_input

    while true; do
        local is_alive=0
        is_pid_running "$game_pid" && is_alive=1

        local status_badge="[TERMINATED / EXITED]"
        local status_color="\033[38;5;111m"
        if [ "$is_alive" -eq 1 ]; then
            status_badge="[RUNNING]"
            status_color="\033[38;5;120m"
        fi

        local hud_palette
        if [ "$is_alive" -eq 1 ]; then
            hud_palette=$(cat <<EOF
1	Return to Game Library	Keep process $game_pid active in background
2	Return to Master Dashboard	Keep process $game_pid active in background
3	Live Game Log Stream	View recent process output & runtime traces
4	Stop Game (SIGTERM)	Send graceful shutdown signal to process
5	Force Kill Game (SIGKILL)	Emergency teardown & terminate wineserver
EOF
)
        else
            hud_palette=$(cat <<EOF
1	Return to Game Library	Game process has exited
2	Return to Master Dashboard	Game process has exited
3	View Recent Logs	Inspect final process stdout & error logs
EOF
)
        fi

        local log_hint
        log_hint=$(inspect_game_log_hint "$log_file" 2>/dev/null || true)

        export GAMECTL_HUD_TITLE="$title"
        export GAMECTL_HUD_PID="$game_pid"
        export GAMECTL_HUD_RUN_TYPE="$run_type"
        export GAMECTL_HUD_COLOR="$status_color"
        export GAMECTL_HUD_BADGE="$status_badge"
        export GAMECTL_HUD_LOG="$log_file"
        export GAMECTL_HUD_HINT="$log_hint"

        local preview_cmd
        preview_cmd='printf "\033[38;5;60m╭─ PROCESS STATUS ────────────────────────────────────╮\033[0m\n  Target Game : \033[1m%s\033[0m\n  Process PID : \033[1m%s\033[0m (%s)\n  Status      : %b%s\033[0m\n  Log File    : %s\n\033[38;5;60m╰─────────────────────────────────────────────────────╯\033[0m\n" "$GAMECTL_HUD_TITLE" "$GAMECTL_HUD_PID" "$GAMECTL_HUD_RUN_TYPE" "$GAMECTL_HUD_COLOR" "$GAMECTL_HUD_BADGE" "$GAMECTL_HUD_LOG"; if [ -n "$GAMECTL_HUD_HINT" ]; then printf "  \033[38;5;214m[HINT]\033[0m %s\n" "$GAMECTL_HUD_HINT"; fi; printf "\033[38;5;60m╭─ RECENT LOG TAIL (Last 15 lines) ──────────────────╮\033[0m\n"; if [ -n "$GAMECTL_HUD_LOG" ] && [ -f "$GAMECTL_HUD_LOG" ]; then tail -n 15 "$GAMECTL_HUD_LOG" 2>/dev/null; else echo "  (No logs recorded)"; fi'

        local hud_sel fzf_rc=0
        hud_sel=$(echo "$hud_palette" | fzf \
            --delimiter=$'\t' \
            --with-nth=1,2 \
            --border-label="  ╢ gamectl :: Process Controller :: $title ╟  " \
            --border-label-pos=2 \
            --header="Enter: Execute │ Esc: Return to Library" \
            --prompt="HUD > " \
            --preview="$preview_cmd" \
            --preview-window=down:55%:border-rounded:wrap \
            --reverse 2>/dev/null) || fzf_rc=$?

        if [ "$fzf_rc" -eq 130 ]; then
            return 0
        fi
        if [ "$fzf_rc" -ne 0 ] && [ "$fzf_rc" -ne 1 ]; then
            echo "[ERROR] Process HUD failed (fzf exit code $fzf_rc)." >&2
            return "$fzf_rc"
        fi
        [ -z "$hud_sel" ] && return 0

        local opt
        opt=$(echo "$hud_sel" | awk -F'\t' '{print $1}')

        case "$opt" in
            1)
                return 0
                ;;
            2)
                return 10
                ;;
            3)
                if [ -s "$log_file" ]; then
                    export GAMECTL_LOG_FILE="$log_file"
                    export GAMECTL_PREVIEW_BIN="$SELF_BIN"
                    local log_fzf_rc=0
                    awk '{printf "%d\t%s\n", NR, $0}' "$log_file" 2>/dev/null | (command -v tac >/dev/null 2>&1 && tac || sed -e '1!G;h;$!d') | fzf \
                        --delimiter=$'\t' \
                        --with-nth=1,2 \
                        --border-label="  ╢ Logs :: $title (PID: $game_pid) ╟  " \
                        --border-label-pos=2 \
                        --header="PROCESS LOGS (Esc / Enter: Return)" \
                        --prompt="Log > " \
                        --preview='"$GAMECTL_PREVIEW_BIN" --preview-process-log "$GAMECTL_LOG_FILE" {1}' \
                        --preview-window=down:35%:border-rounded:wrap \
                        --reverse 2>/dev/null || log_fzf_rc=$?

                    if [ "$log_fzf_rc" -ne 0 ] && [ "$log_fzf_rc" -ne 1 ] && [ "$log_fzf_rc" -ne 130 ]; then
                        echo "[ERROR] Process log viewer failed (fzf exit code $log_fzf_rc)." >&2
                        return "$log_fzf_rc"
                    fi
                else
                    tui_modal_notice "Log Stream" "Log file is currently empty or does not exist:\n$log_file" || return $?
                fi
                ;;
            4)
                local s_unit=""
                [ -f "$info_file" ] && s_unit=$(grep -E '^SCOPE_UNIT=' "$info_file" 2>/dev/null | cut -d'=' -f2- || true)
                log_msg "INFO" "LAUNCH" "Sending SIGTERM to process PID $game_pid ($title)..."
                if [ -n "$s_unit" ]; then
                    systemctl --user stop --no-block "$s_unit.scope" 2>/dev/null || true
                fi
                kill "$game_pid" 2>/dev/null || true
                local wait_cnt=0
                while is_pid_running "$game_pid" && [ "$wait_cnt" -lt 6 ]; do
                    sleep 0.2
                    wait_cnt=$((wait_cnt + 1))
                done
                if [ -d "$gdir/pfx" ]; then
                    local ws_bin
                    ws_bin="$(get_wineserver_bin "$(find_runner "$gdir" 2>/dev/null || true)" 2>/dev/null || true)"
                    [ -n "$ws_bin" ] && WINEPREFIX="$gdir/pfx" "$ws_bin" -w 2>/dev/null || true # wineserver -w
                fi
                if ! is_pid_running "$game_pid"; then
                    rm -f "$info_file" 2>/dev/null || true; record_game_exit_event "$game_pid" "$title" "$gdir" "$log_file"; notify_tui_listeners
                    log_msg "INFO" "LAUNCH" "Game '$title' (PID $game_pid) terminated gracefully"
                    tui_modal_notice "Game Stopped" "Game '$title' (PID $game_pid) terminated gracefully." || return $?
                else
                    tui_modal_notice "Process Still Alive" "Process did not respond to SIGTERM. Select 'Force Kill' (Option 5) for immediate teardown." || return $?
                fi
                ;;
            5)
                local s_unit=""
                [ -f "$info_file" ] && s_unit=$(grep -E '^SCOPE_UNIT=' "$info_file" 2>/dev/null | cut -d'=' -f2- || true)
                log_msg "WARN" "LAUNCH" "Sending SIGKILL to process PID $game_pid ($title)..."
                if [ -n "$s_unit" ]; then
                    systemctl --user kill -s SIGKILL "$s_unit.scope" 2>/dev/null || true
                    systemctl --user stop --no-block "$s_unit.scope" 2>/dev/null || true
                fi
                kill -9 "$game_pid" 2>/dev/null || true
                if [ -d "$gdir/pfx" ]; then
                    local ws_bin
                    ws_bin="$(get_wineserver_bin "$(find_runner "$gdir" 2>/dev/null || true)" 2>/dev/null || true)"
                    [ -n "$ws_bin" ] && WINEPREFIX="$gdir/pfx" "$ws_bin" -k 2>/dev/null || true # wineserver -k
                fi
                rm -f "$info_file" 2>/dev/null || true; record_game_exit_event "$game_pid" "$title" "$gdir" "$log_file"; notify_tui_listeners
                log_msg "WARN" "LAUNCH" "Game '$title' (PID $game_pid) force-killed"
                tui_modal_notice "Force Terminated" "Game '$title' (PID $game_pid) force-killed via SIGKILL." || return $?
                ;;
            *)
                return 0
                ;;
        esac
    done
}

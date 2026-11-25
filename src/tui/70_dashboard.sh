# Interactive Centralized Activity & Runtime Log Viewer
view_logs_interactive() {
    if [ ! -t 0 ] || [ ! -t 1 ]; then
        echo "[ERROR] Interactive log viewer requires a terminal (TTY)." >&2
        return 1
    fi
    if ! command -v fzf >/dev/null 2>&1; then
        echo "[ERROR] fzf is required for interactive mode but was not found in PATH." >&2
        return 127
    fi

    flush_tty_input
    local log_file
    log_file="$(get_runtime_log_file)"

    if [ ! -s "$log_file" ]; then
        log_msg "INFO" "SYSTEM" "Log file initialized"
    fi

    local fzf_rc=0
    export GAMECTL_LOG_FILE="$log_file"
    export GAMECTL_PREVIEW_BIN="$SELF_BIN"
    if command -v tac >/dev/null 2>&1; then
        tac "$log_file" 2>/dev/null
    else
        sed -e '1!G;h;$!d' "$log_file" 2>/dev/null
    fi | fzf \
        --border-label="  ╢ gamectl :: Activity & Runtime Logs ╟  " \
        --border-label-pos=2 \
        --header="Ctrl-X: Clear Log │ Esc: Return" \
        --prompt="Logs > " \
        --preview='"$GAMECTL_PREVIEW_BIN" --preview-log {}' \
        --preview-window=down:35%:border-rounded:wrap \
        --bind='ctrl-x:execute(: > "$GAMECTL_LOG_FILE")+reload(command -v tac >/dev/null 2>&1 && tac "$GAMECTL_LOG_FILE" 2>/dev/null || sed -e "1!G;h;\$!d" "$GAMECTL_LOG_FILE" 2>/dev/null)' \
        --reverse 2>/dev/null || fzf_rc=$?

    flush_tty_input
    if [ "$fzf_rc" -eq 130 ]; then
        return 0
    fi
    if [ "$fzf_rc" -ne 0 ] && [ "$fzf_rc" -ne 1 ]; then
        echo "[ERROR] Activity log viewer failed (fzf exit code $fzf_rc)." >&2
        return "$fzf_rc"
    fi
    return 0
}

# In-Dashboard Process Management & Cockpit Controller
manage_active_processes_interactive() {
    local run_dir
    run_dir="$(get_runtime_dir)"
    if [ ! -d "$run_dir/active_games" ]; then
        tui_modal_notice "Process Controller" "No games currently running."
        return 0
    fi

    local running_list=""
    local count=0
    for inf in "$run_dir/active_games"/*.info; do
        [ -f "$inf" ] || continue
        local p_pid p_title p_dir p_bin p_log
        p_pid=$(grep -E '^PID=' "$inf" 2>/dev/null | head -n 1 | cut -d'=' -f2-)
        p_title=$(grep -E '^TITLE=' "$inf" 2>/dev/null | head -n 1 | cut -d'=' -f2-)
        p_dir=$(grep -E '^DIR=' "$inf" 2>/dev/null | head -n 1 | cut -d'=' -f2-)
        p_bin=$(grep -E '^BIN=' "$inf" 2>/dev/null | head -n 1 | cut -d'=' -f2-)
        p_log=$(grep -E '^LOG=' "$inf" 2>/dev/null | head -n 1 | cut -d'=' -f2-)
        if [ -n "$p_pid" ] && kill -0 "$p_pid" 2>/dev/null; then
            count=$((count + 1))
            running_list+="${p_pid}\t${p_title}\t${p_dir}\t${p_bin}\t${p_log}\t${inf}\n"
        else
            rm -f "$inf" 2>/dev/null || true
        fi
    done

    if [ "$count" -eq 0 ] || [ -z "$running_list" ]; then
        tui_modal_notice "Process Controller" "No games currently running."
        return 0
    fi

    # If only 1 game is running, open its controller HUD directly
    if [ "$count" -eq 1 ]; then
        local s_pid s_title s_dir s_bin s_log s_inf
        s_pid=$(printf '%b' "$running_list" | head -n 1 | cut -f1)
        s_title=$(printf '%b' "$running_list" | head -n 1 | cut -f2)
        s_dir=$(printf '%b' "$running_list" | head -n 1 | cut -f3)
        s_bin=$(printf '%b' "$running_list" | head -n 1 | cut -f4)
        s_log=$(printf '%b' "$running_list" | head -n 1 | cut -f5)
        s_inf=$(printf '%b' "$running_list" | head -n 1 | cut -f6)
        game_controller_hud "$s_pid" "$s_title" "$s_log" "$s_dir" "$s_bin" "$s_inf" "Active Game"
        return 0
    fi

    # If multiple games are running, let the user select which one to manage
    local pick p_rc=0
    pick=$(tui_action_palette "Running Games ($count Active)" "Select Game Process to Manage (Enter: Select │ Esc: Return)" "$(printf '%b' "$running_list")" "" "Process > ") || p_rc=$?
    [ "$p_rc" -eq 130 ] && return 0
    [ "$p_rc" -ne 0 ] && return "$p_rc"
    [ -z "$pick" ] && return 0
    local c_pid c_title c_dir c_bin c_log c_inf
    c_pid=$(echo "$pick" | cut -f1)
    c_title=$(echo "$pick" | cut -f2)
    c_dir=$(echo "$pick" | cut -f3)
    c_bin=$(echo "$pick" | cut -f4)
    c_log=$(echo "$pick" | cut -f5)
    c_inf=$(echo "$pick" | cut -f6)
    game_controller_hud "$c_pid" "$c_title" "$c_log" "$c_dir" "$c_bin" "$c_inf" "Active Game"
    return 0
}

# Master Dashboard Hub (Two-Panel Interactive TUI)
dashboard_menu() {
    if [ ! -t 0 ] || [ ! -t 1 ]; then
        echo "[ERROR] Master Dashboard requires a terminal (TTY)." >&2
        return 1
    fi
    if ! command -v fzf >/dev/null 2>&1; then
        echo "[ERROR] fzf is required for Master Dashboard but was not found in PATH." >&2
        return 127
    fi

    enter_tui_screen
    clean_stale_locks

    local initial_count
    initial_count=$(scan_installed_games 2>/dev/null | wc -l || echo "0")
    log_msg "INFO" "DASHBOARD" "Cockpit active ($initial_count titles indexed)"

    export GAMECTL_PREVIEW_BIN="$SELF_BIN"

    while true; do
        flush_tty_input
        local game_count
        game_count=$(scan_installed_games 2>/dev/null | wc -l || echo "0")
        export GAMECTL_GAME_COUNT="$game_count"

        local menu_entries
        menu_entries=$(cat <<EOF
1	${UI_PURPLE}[01]${UI_RST} ${UI_BOLD}GAME LIBRARY${UI_RST}	${UI_DIM}Browse, inject and launch installed games${UI_RST}
2	${UI_PURPLE}[02]${UI_RST} ${UI_BOLD}STEAM STORE SEARCH${UI_RST}	${UI_DIM}Search games & check ProtonDB compatibility${UI_RST}
3	${UI_PURPLE}[03]${UI_RST} ${UI_BOLD}DOWNLOAD MONITOR${UI_RST}	${UI_DIM}Track Steam native downloads & ACF telemetry${UI_RST}
4	${UI_PURPLE}[04]${UI_RST} ${UI_BOLD}STEAM ACF ADOPTION & ASSET MANAGER${UI_RST}	${UI_DIM}Adopt physical files, shaders & bridge downloads${UI_RST}
5	${UI_PURPLE}[05]${UI_RST} ${UI_BOLD}GLOBAL SETTINGS${UI_RST}	${UI_DIM}Configure LAN persona, default wrappers & remote host${UI_RST}
6	${UI_PURPLE}[06]${UI_RST} ${UI_BOLD}SYSTEM DIAGNOSTICS${UI_RST}	${UI_DIM}Audit 7-layer dependencies, runners & GPU health${UI_RST}
7	${UI_PURPLE}[07]${UI_RST} ${UI_BOLD}ACTIVITY LOGS${UI_RST}	${UI_DIM}Inspect operational events, runner traces & error history${UI_RST}
EOF
)

        local fzf_out fzf_rc=0
        fzf_out=$(echo "$menu_entries" | fzf \
            --delimiter=$'\t' \
            --with-nth=2,3 \
            --expect=ctrl-l,ctrl-p \
            --border-label="  ╢ gamectl :: Master Dashboard Hub ╟  " \
            --border-label-pos=2 \
            --header="Enter: Open │ 1-7: Quick Select │ Ctrl-P: Process Controller │ Ctrl-L: Logs │ Esc: Exit" \
            --prompt="Dashboard > " \
            --preview='"$GAMECTL_PREVIEW_BIN" --preview-dashboard {1} "$GAMECTL_GAME_COUNT"' \
            --preview-window=right:55%:border-rounded:wrap \
        ) || fzf_rc=$?

        [ "$fzf_rc" -eq 130 ] && break
        if [ "$fzf_rc" -ne 0 ] && [ "$fzf_rc" -ne 1 ]; then
            echo "[ERROR] Master Dashboard menu failed (fzf exit code $fzf_rc)." >&2
            return "$fzf_rc"
        fi
        [ -z "$fzf_out" ] && continue

        local trigger_key selection
        trigger_key=$(echo "$fzf_out" | head -n 1)
        selection=$(echo "$fzf_out" | sed -n '2p')

        if [ "$trigger_key" = "ctrl-l" ]; then
            view_logs_interactive || return $?
            continue
        elif [ "$trigger_key" = "ctrl-p" ]; then
            manage_active_processes_interactive || return $?
            continue
        fi

        [ -z "$selection" ] && continue

        local sel_key
        sel_key=$(echo "$selection" | awk -F'\t' '{print $1}')

        local sub_rc=0
        case "$sel_key" in
            1)
                library_menu false || sub_rc=$?
                ;;
            2)
                search_steam "" false || sub_rc=$?
                ;;
            3)
                list_downloads_interactive || sub_rc=$?
                ;;
            4)
                unlock_interactive || sub_rc=$?
                ;;
            5)
                configure_global || sub_rc=$?
                ;;
            6)
                flush_tty_input
                local audit_rc=0
                doctor_audit 2>&1 | fzf \
                    --ansi \
                    --no-sort \
                    --border-label="  ╢ gamectl :: System Diagnostics Audit ╟  " \
                    --border-label-pos=2 \
                    --header="Esc / Enter / q: Return to Dashboard" \
                    --prompt="Audit > " \
                    --bind="q:abort" \
                    --reverse 2>/dev/null || audit_rc=$?
                check_fzf_status "$audit_rc" || sub_rc=$?
                ;;
            7)
                view_logs_interactive || sub_rc=$?
                ;;
            *)
                break
                ;;
        esac
        if [ "$sub_rc" -ne 0 ] && [ "$sub_rc" -ne 1 ] && [ "$sub_rc" -ne 130 ]; then
            return "$sub_rc"
        fi
        flush_tty_input
    done
    exit_tui_screen
}

# Unified Remote Save Sync Palette (Push, Pull, Dry-Run, Configure Host)
remote_sync_interactive() {
    local sel_dir="$1"
    local sel_title="${2:-$sel_dir}"

    while true; do
        local rhost="" host_display=""
        rhost=$(get_remote_host 2>/dev/null || true)
        host_display="${rhost:-Not configured}"

        local sync_entries
        sync_entries=$(printf 'push\tPush Saves - Send local saves to %s\npull\tPull Saves - Download remote saves from %s (auto pre-pull backup)\npull-dry\tPull Dry-Run - Simulate remote pull without modifying local files\nconfig\tConfigure Remote Host - Set SSH host (serv, host:~/path) or rclone (gdrive:path) (Current: %s)\n' \
            "$host_display" "$host_display" "$host_display")

        local pal_rc=0 sel=""
        sel=$(tui_action_palette \
            "Remote Save Sync :: ${sel_title:-$sel_dir}" \
            "Host: $host_display │ Select Sync Action (Enter: Run │ Esc: Return)" \
            "$sync_entries" \
            "" \
            "Sync > ") || pal_rc=$?
        [ "$pal_rc" -eq 130 ] && return 0
        [ "$pal_rc" -ne 0 ] && return "$pal_rc"
        [ -z "$sel" ] && continue

        local action="${sel%%$'\t'*}"
        case "$action" in
            push)
                if tui_run_engine --fail-title "Remote Sync Error" "Remote Push (${sel_title:-$sel_dir})" sync_save_remote "$sel_dir" "$sel_title"; then
                    tui_modal_notice "Remote Sync (Push)" "Savegames pushed to ${rhost:-remote host} for:\n${sel_title:-$sel_dir}" || return $?
                fi
                ;;
            pull)
                if tui_run_engine --fail-title "Remote Pull Error" "Remote Pull (${sel_title:-$sel_dir})" pull_save_remote "$sel_dir" "$sel_title"; then
                    tui_modal_notice "Remote Sync (Pull)" "Savegames pulled from ${rhost:-remote host} for:\n${sel_title:-$sel_dir}\n\nPre-pull local snapshot saved to .save_snapshots/ when local saves existed." || return $?
                fi
                ;;
            pull-dry)
                if tui_run_engine --fail-title "Remote Pull Dry-Run Error" "Remote Pull Dry-Run (${sel_title:-$sel_dir})" pull_save_remote "$sel_dir" "$sel_title" --dry-run; then
                    tui_modal_notice "Remote Pull (Dry-Run)" "Dry-run pull simulation completed from ${rhost:-remote host} for:\n${sel_title:-$sel_dir}\n\nNo local files were modified.\nSimulation log:\n$(get_runtime_log_file)" || return $?
                fi
                ;;
            config)
                local new_rhost="" cfg_rc=0
                new_rhost=$(tui_prompt_input "Remote Companion Host" "Enter SSH host (serv, host:~/path), rclone (gdrive:path), or '-' to clear (Current: $host_display │ Enter: Save │ Esc: Cancel)" "$rhost" "Remote Target > ") || cfg_rc=$?
                [ "$cfg_rc" -eq 130 ] && continue
                [ "$cfg_rc" -ne 0 ] && return "$cfg_rc"
                new_rhost=$(printf '%s' "$new_rhost" | tr -d '[:space:]')
                local env_rhost="${GAMECTL_REMOTE_HOST:-${GAMECTL_COMPANION_HOST:-${GAMECTL_SYNC_HOST:-${GAMECTL_TUF_HOST:-}}}}"

                if [ "$new_rhost" = "-" ]; then
                    rm -f "$HOME/.config/gamectl/remote_host"
                    log_msg "INFO" "CONFIG" "Cleared remote companion host"
                    if [ -n "$env_rhost" ]; then
                        tui_modal_notice "Remote Companion Host" "Cleared saved remote host (~/.config/gamectl/remote_host).\n\nNote: environment variable override is still active:\n$env_rhost" || return $?
                    else
                        tui_modal_notice "Remote Companion Host" "Cleared remote companion host." || return $?
                    fi
                elif [[ "$new_rhost" == -* ]]; then
                    tui_modal_notice "Invalid Remote Host" "Remote host cannot start with '-':\n$new_rhost" || return $?
                    continue
                elif [ -n "$new_rhost" ]; then
                    local parse_err=""
                    if ! parse_err=$(parse_remote_sync_target "$new_rhost" 2>&1); then
                        tui_modal_notice "Invalid Remote Target" "$parse_err" || return $?
                        continue
                    fi
                    mkdir -p "$HOME/.config/gamectl" || return 1
                    printf '%s\n' "$new_rhost" > "$HOME/.config/gamectl/remote_host"
                    log_msg "INFO" "CONFIG" "Saved remote companion host: $new_rhost"
                    if [ -n "$env_rhost" ] && [ "$env_rhost" != "$new_rhost" ]; then
                        tui_modal_notice "Remote Companion Host" "Saved remote companion host:\n$new_rhost\n\nNote: environment variable override is currently active:\n$env_rhost" || return $?
                    else
                        tui_modal_notice "Remote Companion Host" "Saved remote companion host:\n$new_rhost" || return $?
                    fi
                fi
                ;;
        esac
    done
}

# Main Library View
library_menu() {
    if [ ! -t 0 ] || [ ! -t 1 ]; then
        echo "[ERROR] Game Library requires a terminal (TTY)." >&2
        return 1
    fi
    if ! command -v fzf >/dev/null 2>&1; then
        echo "[ERROR] fzf is required for Game Library but was not found in PATH." >&2
        return 127
    fi

    local standalone="${1:-false}"
    [ "$standalone" = "true" ] && enter_tui_screen
    clean_stale_locks

    export GAMECTL_PREVIEW_BIN="$SELF_BIN"
    local active_store="ALL"

    while true; do
        flush_tty_input
        local fzf_out fzf_rc=0
        fzf_out=$(scan_installed_games --formatted --store "$active_store" | fzf \
            --delimiter=$'\t' \
            --with-nth=1,2,3 \
            --expect=ctrl-f,ctrl-d,ctrl-l,ctrl-o,ctrl-p,ctrl-i,ctrl-s,ctrl-b,ctrl-r,ctrl-x,tab,alt-s \
            --border-label="  ╢ gamectl :: Game Library [Store: $active_store] ╟  " \
            --border-label-pos=2 \
            --header="Enter: Launch/Manage │ Tab/Alt-S: Store │ Ctrl-I: Inject GBE │ Ctrl-F: Search │ Esc: Dashboard" \
            --prompt="Library > " \
            --preview='"$GAMECTL_PREVIEW_BIN" --preview {1} {2} {3} {4} {5}' \
            --preview-window=right:55%:border-rounded:wrap \
        ) || fzf_rc=$?

        [ "$fzf_rc" -eq 130 ] && break
        if [ "$fzf_rc" -ne 0 ] && [ "$fzf_rc" -ne 1 ]; then
            echo "[ERROR] Game Library menu failed (fzf exit code $fzf_rc)." >&2
            return "$fzf_rc"
        fi
        [ -z "$fzf_out" ] && continue

        local trigger_key selection
        trigger_key=$(echo "$fzf_out" | head -n 1)
        selection=$(echo "$fzf_out" | sed -n '2p')

        # Global in-process hotkeys that do not require item selection
        local hk_rc=0
        if [ "$trigger_key" = "ctrl-l" ]; then
            view_logs_interactive || hk_rc=$?
        elif [ "$trigger_key" = "ctrl-f" ]; then
            search_steam "" false || hk_rc=$?
            invalidate_scan_cache
        elif [ "$trigger_key" = "tab" ]; then
            case "$active_store" in
                ALL) active_store="STEAM" ;;
                STEAM) active_store="GOG" ;;
                GOG) active_store="EPIC" ;;
                EPIC) active_store="STANDALONE" ;;
                *) active_store="ALL" ;;
            esac
            continue
        elif [ "$trigger_key" = "alt-s" ]; then
            local store_pick=""
            store_pick=$(tui_action_palette \
                "Store Filter" \
                "Select Store View (Enter: Apply │ Esc: Cancel)" \
                "$(printf 'ALL\tAll Stores (Unified)\nSTEAM\tSteam Library\nGOG\tGOG Library (DRM-Free)\nEPIC\tEpic Games Library (Legendary)\nSTANDALONE\tStandalone / Portable\n')" \
                "" \
                "Store > ") || hk_rc=$?
            if [ "$hk_rc" -ne 0 ] && [ "$hk_rc" -ne 1 ] && [ "$hk_rc" -ne 130 ]; then
                return "$hk_rc"
            fi
            if [ "$hk_rc" -eq 0 ] && [ -n "$store_pick" ]; then
                active_store=$(printf '%s' "$store_pick" | cut -f1)
            fi
            continue
        fi
        if [ "$hk_rc" -ne 0 ] && [ "$hk_rc" -ne 1 ] && [ "$hk_rc" -ne 130 ]; then
            return "$hk_rc"
        fi
        if [ "$trigger_key" = "ctrl-l" ] || [ "$trigger_key" = "ctrl-f" ]; then
            continue
        fi

        [ -z "$selection" ] && continue

        local sel_appid sel_title sel_status sel_dir sel_bin
        sel_appid=$(echo "$selection" | awk -F'\t' '{print $1}')
        sel_title=$(echo "$selection" | awk -F'\t' '{print $2}')
        sel_status=$(echo "$selection" | awk -F'\t' '{print $3}')
        sel_dir=$(echo "$selection" | awk -F'\t' '{print $4}')
        sel_bin=$(echo "$selection" | awk -F'\t' '{print $5}')

        case "$trigger_key" in
            ctrl-d)
                if tui_run_engine --fail-title "Desktop Shortcut Failed" "Create Desktop Shortcut (${sel_title:-$sel_dir})" create_desktop_entry "$sel_dir" "$sel_title"; then
                    tui_modal_notice "Desktop Shortcut Created" "Created application launcher for:\n${sel_title:-$sel_dir}\nSaved to ~/.local/share/applications/" || return $?
                fi
                continue
                ;;
            ctrl-o)
                configure_wrappers "$sel_dir" "$sel_title" || return $?
                invalidate_scan_cache
                continue
                ;;
            ctrl-p)
                set_id_interactive "$sel_dir" "$sel_title" || return $?
                invalidate_scan_cache
                continue
                ;;
            ctrl-i)
                if tui_run_engine --fail-title "GBE Injection Failed" "GBE Injection (${sel_title:-$sel_dir})" inject_game "$sel_dir" "$sel_appid" --no-sync; then
                    tui_modal_notice "Standalone GBE Injection" "Successfully injected GBE Fork for:\n${sel_title:-$sel_dir}" || return $?
                fi
                invalidate_scan_cache
                continue
                ;;
            ctrl-s)
                remote_sync_interactive "$sel_dir" "$sel_title" || return $?
                invalidate_scan_cache
                continue
                ;;
            ctrl-b)
                if tui_run_engine --fail-title "Save Backup Error" "Save Backup (${sel_title:-$sel_dir})" backup_save "$sel_dir"; then
                    tui_modal_notice "Save Backup" "Savegame snapshot created in slot for:\n${sel_title:-$sel_dir}" || return $?
                fi
                continue
                ;;
            ctrl-r)
                if [ -d "$sel_dir/.save_snapshots" ]; then
                    local snaps
                    snaps=$(ls -d "$sel_dir/.save_snapshots"/slot* 2>/dev/null | wc -l)
                    if [ "$snaps" -gt 0 ]; then
                        local chosen_slot="1"
                        if [ "$snaps" -gt 1 ]; then
                            local slot_list=""
                            for s in "$sel_dir/.save_snapshots"/slot*; do
                                [ -d "$s" ] || continue
                                local s_name s_time
                                s_name=$(basename "$s")
                                s_time=$(date -r "$s" "+%Y-%m-%d %H:%M:%S" 2>/dev/null || echo "Snapshot")
                                slot_list+="${s_name}\t${s_time}\n"
                            done
                            flush_tty_input
                            local pick="" p_rc=0
                            pick=$(printf '%b' "$slot_list" | fzf \
                                --delimiter=$'\t' \
                                --border-label="  ╢ Restore Save Snapshot :: ${sel_title:-$sel_dir} ╟  " \
                                --border-label-pos=2 \
                                --header="Select Recovery Slot to Restore (Enter: Restore │ Esc: Cancel)" \
                                --prompt="Restore Slot > " \
                                --reverse 2>/dev/null) || p_rc=$?
                            check_fzf_status "$p_rc" || return $?
                            [ "$p_rc" -eq 130 ] || [ -z "$pick" ] && continue
                            chosen_slot=$(echo "$pick" | cut -f1)
                            chosen_slot="${chosen_slot#slot}"
                        fi
                        if tui_run_engine --fail-title "Save Restore Error" "Save Restore slot${chosen_slot} (${sel_title:-$sel_dir})" restore_save "$sel_dir" "$chosen_slot"; then
                            tui_modal_notice "Save Restore" "Savegame restored successfully from slot${chosen_slot} for:\n${sel_title:-$sel_dir}" || return $?
                        fi
                    else
                        tui_modal_notice "Save Restore" "No snapshot recovery slots found for:\n${sel_title:-$sel_dir}" || return $?
                    fi
                else
                    tui_modal_notice "Save Restore" "No snapshot recovery directory (.save_snapshots) found for:\n${sel_title:-$sel_dir}" || return $?
                fi
                continue
                ;;
            ctrl-x)
                manage_game_fixes_interactive "$sel_appid" "$sel_title" "$sel_dir" || return $?
                invalidate_scan_cache
                continue
                ;;
            *)
                local launch_rc=0
                if [ -z "$sel_bin" ]; then
                    local cand_bin
                    cand_bin=$(find_game_binary "$sel_dir" 2>/dev/null || echo "")
                    if [ -z "$cand_bin" ] && [ -n "$sel_appid" ] && [[ "$sel_appid" =~ ^[0-9]+$ ]]; then
                        local target_os
                        target_os="$(detect_app_platform_os "$sel_appid")"
                        log_msg "INFO" "LIBRARY" "Missing executable binary in $sel_dir for $sel_title ($sel_appid). Bridging to standalone download."
                        tui_exec_action "Download Missing Files ($sel_title)" download_game "$sel_appid" "$sel_dir" "$sel_title" --all --os "$target_os"
                        invalidate_scan_cache
                        continue
                    fi
                fi
                # Check if game is already active / running
                local active_inf="" active_pid=""
                local run_dir
                run_dir="$(get_runtime_dir)"
                if [ -d "$run_dir/active_games" ]; then
                    for inf in "$run_dir/active_games"/*.info; do
                        [ -f "$inf" ] || continue
                        local inf_dir
                        inf_dir=$(grep -E '^DIR=' "$inf" 2>/dev/null | head -n 1 | cut -d'=' -f2-)
                        if [ "$inf_dir" = "$sel_dir" ]; then
                            local check_pid
                            check_pid=$(grep -E '^PID=' "$inf" 2>/dev/null | head -n 1 | cut -d'=' -f2)
                            if [ -n "$check_pid" ] && kill -0 "$check_pid" 2>/dev/null; then
                                active_inf="$inf"
                                active_pid="$check_pid"
                                break
                            fi
                        fi
                    done
                fi

                if [ -n "$active_pid" ]; then
                    # Game is already running: open In-Dashboard Process Controller
                    local active_log
                    active_log=$(grep -E '^LOG=' "$active_inf" 2>/dev/null | head -n 1 | cut -d'=' -f2-)
                    local hud_rc=0
                    game_controller_hud "$active_pid" "$sel_title" "$active_log" "$sel_dir" "$sel_bin" "$active_inf" "Running Process" || hud_rc=$?
                    invalidate_scan_cache
                    if [ "$hud_rc" -eq 10 ]; then
                        break
                    fi
                    continue
                fi

                # Launch game via isolated engine harness (zero terminal leaks, seamless background launch)
                # Engine failures are already logged and surfaced via tui_run_engine modal; do not conflate with fzf status
                tui_run_engine "Launch $sel_title" launch_game "$sel_dir" "$sel_bin" "$sel_title" || launch_rc=$?
                invalidate_scan_cache
                [ "$launch_rc" -ne 0 ] && log_msg "WARN" "LIBRARY" "Launch returned exit code $launch_rc for $sel_title"
                ;;
        esac
    done

    [ "$standalone" = "true" ] && exit_tui_screen
    return 0
}

# Live Steam Search View (Actionable TUI Search)
search_steam() {
    if [ ! -t 0 ] || [ ! -t 1 ]; then
        echo "[ERROR] Interactive Steam search requires a terminal (TTY)." >&2
        return 1
    fi
    if ! command -v fzf >/dev/null 2>&1; then
        echo "[ERROR] fzf is required for interactive mode but was not found in PATH." >&2
        return 127
    fi

    local query="${1:-}"
    local standalone="${2:-false}"
    [ "$standalone" = "true" ] && enter_tui_screen
    flush_tty_input
    if [ -z "$query" ]; then
        local fzf_rc=0
        # Input primitive canonicalized via tui_prompt_input (: | fzf wrapper)
        query=$(tui_prompt_input "gamectl :: Steam Store Search" "Type game title to search (Enter: Search │ Esc: Cancel)" "" "Search Store > ") || fzf_rc=$?
        [ "$fzf_rc" -eq 130 ] && return 0
        if [ "$fzf_rc" -ne 0 ]; then
            [ "$standalone" = "true" ] && exit_tui_screen
            return "$fzf_rc"
        fi
        query=$(echo "$query" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
        if [ -z "$query" ]; then
            [ "$standalone" = "true" ] && exit_tui_screen
            return 0
        fi
    fi

    log_msg "INFO" "STORE" "Searching '$query' on Steam Store API..."
    local encoded_query
    encoded_query=$(python3 -c "import urllib.parse, sys; print(urllib.parse.quote(sys.argv[1]))" "$query")
    local raw_results
    raw_results=$(curl -s --connect-timeout 5 --max-time 15 "https://store.steampowered.com/api/storesearch/?term=${encoded_query}&l=english&cc=US" 2>/dev/null)

    local items
    items=$(printf '%s' "$raw_results" | store_search_items) || {
        echo "[ERROR] Invalid Steam search catalog." >&2
        return 1
    }

    if [ -z "$items" ]; then
        log_msg "WARN" "STORE" "Game '$query' not found on Steam Store API."
        tui_modal_notice "Steam Store Search" "Game '$query' was not found on Steam Store." || return $?
        [ "$standalone" = "true" ] && exit_tui_screen
        return 0
    fi

    # Build list with local installed status across all libraries via scan_installed_games
    local results=""
    local type_filter="ALL"
    declare -A installed_by_id=()
    declare -A installed_by_title=()
    declare -A installed_dir=()
    declare -A item_type_map=()
    declare -A item_parent_map=()

    _classify_current_items() {
        item_type_map=()
        item_parent_map=()
        local -a batch_ids=()
        local c_id c_name
        while IFS=$'\t' read -r c_id c_name; do
            c_id="${c_id//[[:space:]]/}"
            [[ "$c_id" =~ ^[0-9]+$ ]] && batch_ids+=("$c_id")
        done <<< "$items"
        [ "${#batch_ids[@]}" -eq 0 ] && return 0

        local c_out c_type c_parent
        c_out=$(classify_steam_app_types "${batch_ids[@]}" 2>/dev/null || true)
        while IFS=$'\t' read -r c_id c_type c_parent; do
            [ -n "$c_id" ] || continue
            item_type_map["$c_id"]="${c_type:-APP}"
            item_parent_map["$c_id"]="${c_parent:-}"
        done <<< "$c_out"
    }

    _refresh_search_results() {
        results=""
        installed_by_id=()
        installed_by_title=()
        installed_dir=()

        local sc_id sc_name sc_st sc_dir sc_bin
        while IFS=$'\t' read -r sc_id sc_name sc_st sc_dir sc_bin; do
            sc_id="${sc_id//[[:space:]]/}"
            sc_name="${sc_name#"${sc_name%%[![:space:]]*}"}"
            sc_name="${sc_name%"${sc_name##*[![:space:]]}"}"
            sc_dir="${sc_dir//$'\r'/}"
            if [ -n "$sc_id" ] && [ "$sc_id" != "STANDALONE" ]; then
                installed_by_id["$sc_id"]=1
                installed_dir["$sc_id"]="$sc_dir"
            fi
            if [ -n "$sc_name" ]; then
                local clean_title="${sc_name,,}"
                installed_by_title["$clean_title"]=1
                [ -z "${installed_dir["$clean_title"]:-}" ] && installed_dir["$clean_title"]="$sc_dir"
            fi
        done < <(scan_installed_games --refresh)

        while IFS=$'\t' read -r appid name; do
            [ -z "$appid" ] && continue
            local is_installed=0
            local clean_name="${name,,}"
            if [[ -v installed_by_id["$appid"] ]] || [[ -v installed_by_title["$clean_name"] ]]; then
                is_installed=1
            fi
            local status="${UI_DIM}[NOT INSTALLED]${UI_RST}"
            [ "$is_installed" -eq 1 ] && status="${UI_GREEN}[INSTALLED]    ${UI_RST}"
            local raw_type="${item_type_map[$appid]:-APP}"
            local parent_appid="${item_parent_map[$appid]:-}"
            local type_badge
            type_badge="$(format_app_type_badge "$raw_type")"
            validate_tui_fields "$appid" "$name" "$raw_type" "$parent_appid" || continue
            results+="${appid}"$'\t'"${type_badge}"$'\t'"${name}"$'\t'"${status}"$'\t'"${raw_type}"$'\t'"${parent_appid}"$'\n'
        done <<< "$items"
    }

    _filtered_search_results() {
        if [ "$type_filter" = "ALL" ]; then
            printf '%s' "$results"
        else
            printf '%s' "$results" | awk -F'\t' -v tf="$type_filter" '$5 == tf'
        fi
    }

    _classify_current_items
    _refresh_search_results

    export GAMECTL_PREVIEW_BIN="$SELF_BIN"

    while true; do
        flush_tty_input
        local fzf_out fzf_rc=0
        local fzf_header="Enter: Actions │ Tab: Type ($type_filter) │ Ctrl-F: New Search │ Esc: Dashboard"
        fzf_out=$(_filtered_search_results | fzf \
            --delimiter=$'\t' \
            --with-nth=1,2,3,4 \
            --expect=tab,ctrl-a,ctrl-u,ctrl-s,ctrl-d,ctrl-f \
            --bind="tab:accept,ctrl-a:accept,ctrl-u:accept,ctrl-s:accept,ctrl-d:accept,ctrl-f:accept" \
            --border-label="  ╢ gamectl :: Steam Store Catalog [Type: $type_filter] ╟  " \
            --border-label-pos=2 \
            --header="$fzf_header" \
            --prompt="Filter Results > " \
            --preview='"$GAMECTL_PREVIEW_BIN" --preview-search {1} {3} {4}' \
            --preview-window=right:52%:border-rounded:wrap \
        ) || fzf_rc=$?

        [ "$fzf_rc" -eq 130 ] && break
        if [ "$fzf_rc" -ne 0 ] && [ "$fzf_rc" -ne 1 ]; then
            echo "[ERROR] Steam search catalog failed (fzf exit code $fzf_rc)." >&2
            return "$fzf_rc"
        fi
        [ -z "$fzf_out" ] && continue

        local trigger_key selection
        trigger_key=$(echo "$fzf_out" | sed -n '1p')
        selection=$(echo "$fzf_out" | sed -n '2,$p')

        if [ "$trigger_key" = "tab" ]; then
            case "$type_filter" in
                ALL)  type_filter="GAME" ;;
                GAME) type_filter="DLC" ;;
                *)    type_filter="ALL" ;;
            esac
            continue
        fi

        if [ "$trigger_key" = "ctrl-f" ]; then
            local new_q n_rc=0
            new_q=$(tui_prompt_input "gamectl :: Steam Store Search" "Type game title to search (Enter: Search │ Esc: Keep Current List)" "" "Search Store > ") || n_rc=$?
            if [ "$n_rc" -eq 130 ]; then
                continue
            fi
            if [ "$n_rc" -ne 0 ]; then
                return "$n_rc"
            fi
            new_q=$(echo "$new_q" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
            if [ -z "$new_q" ]; then
                continue
            fi

            log_msg "INFO" "STORE" "Searching '$new_q' on Steam Store API..."
            local new_encoded_query
            new_encoded_query=$(python3 -c "import urllib.parse, sys; print(urllib.parse.quote(sys.argv[1]))" "$new_q")
            local new_raw_results
            new_raw_results=$(curl -s --connect-timeout 5 --max-time 15 "https://store.steampowered.com/api/storesearch/?term=${new_encoded_query}&l=english&cc=US" 2>/dev/null)
            local new_items
            new_items=$(printf '%s' "$new_raw_results" | store_search_items) || true

            if [ -z "$new_items" ]; then
                log_msg "WARN" "STORE" "Game '$new_q' not found on Steam Store API."
                tui_modal_notice "Steam Store Search" "Game '$new_q' was not found on Steam Store." || true
                continue
            fi

            query="$new_q"
            items="$new_items"
            type_filter="ALL"
            _classify_current_items
            _refresh_search_results
            continue
        fi

        [ -z "$selection" ] && continue

        local sel_id="" sel_name="" sel_status="" sel_type="" sel_parent=""
        local _c1="" _c2="" _c3="" _c4="" _c5="" _c6=""
        IFS=$'\t' read -r _c1 _c2 _c3 _c4 _c5 _c6 <<< "$selection"
        if [ -n "$_c4" ]; then
            sel_id="$_c1"
            sel_name="$_c3"
            sel_status="$_c4"
            sel_type="$_c5"
            sel_parent="$_c6"
        else
            sel_id="$_c1"
            sel_name="$_c2"
            sel_status="$_c3"
        fi

        local gdir=""
        local clean_sel_name="${sel_name,,}"
        if [[ "$sel_status" =~ INSTALLED ]] && [[ ! "$sel_status" =~ NOT ]]; then
            if [ -n "${installed_dir["$sel_id"]:-}" ] && [ -d "${installed_dir["$sel_id"]}" ]; then
                gdir="${installed_dir["$sel_id"]}"
            elif [ -n "${installed_dir["$clean_sel_name"]:-}" ] && [ -d "${installed_dir["$clean_sel_name"]}" ]; then
                gdir="${installed_dir["$clean_sel_name"]}"
            elif [ -d "$HOME/Games/$sel_name" ]; then
                gdir="$HOME/Games/$sel_name"
            fi
        fi

        # Resolve optimal destination library and target OS platform for uninstalled games
        local dest_dir target_os="linux"
        local -a dl_extra_args=()
        if [[ ! "$sel_status" =~ INSTALLED ]] || [[ "$sel_status" =~ NOT ]]; then
            dest_dir="$(resolve_target_library_dir "$sel_name")"
            target_os="$(detect_app_platform_os "$sel_id")"
        fi

        _prepare_download_target() {
            dl_extra_args=()
            [ "$sel_type" = "DLC" ] || return 0

            local parent_id="$sel_parent" parent_name=""
            if [ -z "$parent_id" ] && declare -F resolve_steam_app_type >/dev/null 2>&1; then
                local r_info="" r_type=""
                r_info=$(resolve_steam_app_type "$sel_id" 2>/dev/null || true)
                IFS=$'\t' read -r r_type parent_id parent_name <<< "$r_info"
            elif [[ "$parent_id" =~ ^[0-9]+$ ]] && declare -F fetch_steam_app_details >/dev/null 2>&1; then
                parent_name=$(fetch_steam_app_details "$parent_id" 2>/dev/null | jq -r '.name // empty' 2>/dev/null || true)
            fi
            [[ "$parent_id" =~ ^[0-9]+$ ]] || return 0

            local dlc_choice="" dlc_rc=0
            local base_label="${parent_name:-AppID $parent_id}"
            dlc_choice=$(tui_action_palette \
                "DLC Selected" \
                "AppID $sel_id ($sel_name) is a DLC. Base game downloads already include associated DLC depots." \
                "$(printf 'base\tDownload Base Game (%s • %s) [Recommended]\ndlc\tDownload DLC Only (%s • %s) [--allow-dlc]\ncancel\tCancel / Return\n' "$base_label" "$parent_id" "$sel_name" "$sel_id")" \
                "" \
                "DLC Action > ") || dlc_rc=$?
            [ "$dlc_rc" -eq 130 ] && return 130
            if [ "$dlc_rc" -ne 0 ] && [ "$dlc_rc" -ne 1 ]; then
                return "$dlc_rc"
            fi
            local dlc_opt="${dlc_choice%%$'\t'*}"
            case "$dlc_opt" in
                base)
                    sel_id="$parent_id"
                    sel_name="${parent_name:-AppID_${parent_id}}"
                    dest_dir="$(resolve_target_library_dir "$sel_name")"
                    target_os="$(detect_app_platform_os "$sel_id")"
                    dl_extra_args=()
                    return 0
                    ;;
                dlc)
                    dl_extra_args=("--allow-dlc")
                    return 0
                    ;;
                *)
                    return 130
                    ;;
            esac
        }

        # Direct hotkey triggers
        if [ "$trigger_key" = "ctrl-a" ]; then
            if [[ "$sel_status" =~ INSTALLED ]] && [[ ! "$sel_status" =~ NOT ]]; then
                log_msg "INFO" "HOTKEY" "Shortcut <Ctrl-A>: Injecting standalone GBE for $sel_name ($sel_id)"
                tui_exec_action "Inject Standalone GBE ($sel_name)" inject_game "$gdir" "$sel_id"
            else
                local prep_rc=0
                _prepare_download_target || prep_rc=$?
                [ "$prep_rc" -eq 130 ] && continue
                [ "$prep_rc" -ne 0 ] && return "$prep_rc"
                log_msg "INFO" "HOTKEY" "Shortcut <Ctrl-A>: Starting All-in-One Download for $sel_name ($target_os)"
                tui_exec_action "All-in-One Download ($sel_name)" download_game "$sel_id" "$dest_dir" "$sel_name" --all --os "$target_os" ${dl_extra_args[@]+"${dl_extra_args[@]}"}
            fi
        elif [ "$trigger_key" = "ctrl-u" ]; then
            if [[ "$sel_status" =~ INSTALLED ]] && [[ ! "$sel_status" =~ NOT ]]; then
                log_msg "INFO" "HOTKEY" "Shortcut <Ctrl-U>: Synchronizing Steam Entitlement & ACF for $sel_name ($sel_id)"
                tui_exec_action "Synchronize Steam Entitlement ($sel_name)" sync_steam "$sel_id" "$sel_name" "$gdir"
            else
                log_msg "INFO" "HOTKEY" "Shortcut <Ctrl-U>: Adopting Steam Entitlement & ACF for $sel_name ($sel_id)"
                tui_exec_action "Adopt Steam Entitlement ($sel_name)" unlock_game "$sel_id" "$sel_name"
            fi
        elif [ "$trigger_key" = "ctrl-s" ]; then
            if [[ "$sel_status" =~ INSTALLED ]] && [[ ! "$sel_status" =~ NOT ]]; then
                log_msg "INFO" "HOTKEY" "Shortcut <Ctrl-S>: Injecting Standalone GBE Fork for $sel_name ($sel_id)"
                tui_exec_action "Inject Standalone GBE ($sel_name)" inject_game "$gdir" "$sel_id" --no-sync
            else
                local prep_rc=0
                _prepare_download_target || prep_rc=$?
                [ "$prep_rc" -eq 130 ] && continue
                [ "$prep_rc" -ne 0 ] && return "$prep_rc"
                log_msg "INFO" "HOTKEY" "Shortcut <Ctrl-S>: Starting Standalone Download for $sel_name ($target_os)"
                tui_exec_action "Standalone Download ($sel_name)" download_game "$sel_id" "$dest_dir" "$sel_name" --inject-only --os "$target_os" ${dl_extra_args[@]+"${dl_extra_args[@]}"}
            fi
        elif [ "$trigger_key" = "ctrl-d" ]; then
            if [[ "$sel_status" =~ INSTALLED ]] && [[ ! "$sel_status" =~ NOT ]]; then
                local gbin
                gbin=$(find_game_binary "$gdir" 2>/dev/null || echo "")
                if [ -n "$gbin" ]; then
                    local launch_rc=0
                    tui_run_engine "Launch $sel_name" launch_game "$gdir" "$gbin" "$sel_name" || launch_rc=$?
                    if [ "$launch_rc" -eq 10 ]; then
                        break
                    fi
                else
                    log_msg "ERROR" "LAUNCH" "Binary executable not found in $gdir for $sel_name"
                    tui_modal_notice "Executable Not Found" "Binary executable not found in directory:\n$gdir" || return $?
                fi
            else
                local prep_rc=0
                _prepare_download_target || prep_rc=$?
                [ "$prep_rc" -eq 130 ] && continue
                [ "$prep_rc" -ne 0 ] && return "$prep_rc"
                log_msg "INFO" "HOTKEY" "Shortcut <Ctrl-D>: Starting Live Stream Download for $sel_name ($target_os)"
                tui_exec_action "Live Stream Download ($sel_name)" download_game "$sel_id" "$dest_dir" "$sel_name" --all --os "$target_os" ${dl_extra_args[@]+"${dl_extra_args[@]}"}
            fi
        else
            # Enter key: Open Modal Action Palette
            if [[ "$sel_status" =~ INSTALLED ]] && [[ ! "$sel_status" =~ NOT ]]; then
                local action_palette
                action_palette=$(cat <<EOF
1	Launch Game Directly
2	Inject GBE Fork Only (Standalone ./saves & DLC.txt)
3	Inject GBE + Sync Steam Client (All-in-One Full DLC)
4	Sync to Steam Client Entitlement Only (ACF & Steam Input)
5	Check Community Fixes & Online-Fix Catalog
6	Cancel / Return
EOF
)
                local action_sel action_rc=0
                action_sel=$(echo "$action_palette" | fzf \
                    --delimiter=$'\t' \
                    --with-nth=2 \
                    --border-label="  ╢ Action Palette: $sel_name ╟  " \
                    --border-label-pos=2 \
                    --header="ACTION PALETTE (Enter: Execute │ Esc: Return)" \
                    --prompt="Action > " \
                    --reverse 2>/dev/null) || action_rc=$?
                check_fzf_status "$action_rc" || return $?
                [ "$action_rc" -eq 130 ] && continue

                local act_opt
                act_opt=$(echo "$action_sel" | awk -F'\t' '{print $1}')

                case "$act_opt" in
                    1)
                        local gbin
                        gbin=$(find_game_binary "$gdir" 2>/dev/null || echo "")
                        if [ -n "$gbin" ]; then
                            local launch_rc=0
                            tui_run_engine "Launch $sel_name" launch_game "$gdir" "$gbin" "$sel_name" || launch_rc=$?
                            if [ "$launch_rc" -eq 10 ]; then
                                break
                            fi
                        else
                            log_msg "ERROR" "LAUNCH" "Binary executable not found in $gdir for $sel_name"
                            tui_modal_notice "Executable Not Found" "Binary executable not found in directory:\n$gdir" || return $?
                        fi
                        ;;
                    2)
                        tui_exec_action "Inject Standalone GBE ($sel_name)" inject_game "$gdir" "$sel_id" --no-sync
                        ;;
                    3)
                        tui_exec_action "Inject GBE + Steam Sync ($sel_name)" inject_game "$gdir" "$sel_id" --all
                        ;;
                    4)
                        tui_exec_action "Synchronize Steam Entitlement ($sel_name)" sync_steam "$sel_id" "$sel_name" "$gdir"
                        ;;
                    5)
                        manage_game_fixes_interactive "$sel_id" "$sel_name" "$gdir" || return $?
                        ;;
                    *)
                        ;;
                esac
            else
                local not_installed_palette
                not_installed_palette=$(cat <<EOF
1	[Sovereign Standalone] Download & Auto-Provision via CDN (Zero-Steam GBE)
2	[Steam Client Bridge] Adopt files & DLC to Steam Client (Requires Steam)
3	[Offline GBE] Inject GBE LAN runtime (Steam-free)
4	[Fixes & OnlineFix] Check Community Fixes & Online-Fix Catalog
5	Cancel / Return
EOF
)
                local pkg_sel pkg_rc=0
                pkg_sel=$(echo "$not_installed_palette" | fzf \
                    --delimiter=$'\t' \
                    --with-nth=2 \
                    --border-label="  ╢ Action Palette: $sel_name ╟  " \
                    --border-label-pos=2 \
                    --header="PACKAGE SELECTION (Enter: Execute │ Esc: Return)" \
                    --prompt="Package > " \
                    --reverse 2>/dev/null) || pkg_rc=$?
                check_fzf_status "$pkg_rc" || return $?
                [ "$pkg_rc" -eq 130 ] && continue

                local opt
                opt=$(echo "$pkg_sel" | awk -F'\t' '{print $1}')
                case "$opt" in
                    1)
                        local prep_rc=0
                        _prepare_download_target || prep_rc=$?
                        [ "$prep_rc" -eq 130 ] && continue
                        [ "$prep_rc" -ne 0 ] && return "$prep_rc"
                        tui_exec_action "Sovereign Standalone Download ($sel_name)" download_game "$sel_id" "$dest_dir" "$sel_name" --all --os "$target_os" ${dl_extra_args[@]+"${dl_extra_args[@]}"}
                        ;;
                    2)
                        tui_exec_action "Adopt Steam Entitlement ($sel_name)" unlock_game "$sel_id" "$sel_name"
                        ;;
                    3)
                        tui_exec_action "Inject Standalone GBE ($sel_name)" inject_game "$dest_dir" "$sel_id" --no-sync
                        ;;
                    4)
                        manage_game_fixes_interactive "$sel_id" "$sel_name" "" || return $?
                        ;;
                    *)
                        ;;
                esac
            fi
        fi
        _refresh_search_results
    done

    flush_tty_input
    [ "$standalone" = "true" ] && exit_tui_screen
    return 0
}


# Standalone-source compatibility: load split tui submodules when sourced directly outside bin/gamectl
if [ -z "${GAMECTL_BUNDLED:-}" ] && [ -n "${BASH_SOURCE[0]:-}" ]; then
    _tui_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd)"
    for _tui_sub in 71_previews.sh; do
        if [ -f "$_tui_dir/$_tui_sub" ]; then
            # shellcheck source=/dev/null
            source "$_tui_dir/$_tui_sub"
        fi
    done
    unset _tui_dir _tui_sub
fi

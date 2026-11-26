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
    local p_pid p_title p_dir p_bin p_log p_inf _p_scope _p_sep=$'\x1f'
    while IFS="$_p_sep" read -r p_pid p_title p_dir p_bin p_log p_inf _p_scope; do
        [ -n "$p_pid" ] || continue
        count=$((count + 1))
        running_list+="${p_pid}\t${p_title}\t${p_dir}\t${p_bin}\t${p_log}\t${p_inf}\n"
    done < <(list_active_games)

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

        local dash_sock=""
        local -a dash_live_args=()
        if tui_supports_live_events; then
            local dash_ldir="$(get_runtime_dir)/tui_listeners"
            mkdir -p -m 700 "$dash_ldir" 2>/dev/null || true
            dash_sock="$dash_ldir/d_${BASHPID}.sock"
            if [ "${#dash_sock}" -le 100 ]; then
                rm -f "$dash_sock" 2>/dev/null || true
                dash_live_args=("--listen=$dash_sock" "--bind=f12:refresh-preview")
            else
                dash_sock=""
            fi
        fi

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
            "${dash_live_args[@]}" \
        ) || fzf_rc=$?
        [ -n "$dash_sock" ] && rm -f "$dash_sock" 2>/dev/null || true

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
    local last_status_banner=""

    while true; do
        flush_tty_input
        _format_library_chrome "$active_store" "$last_status_banner"
        last_status_banner=""
        local lib_label="$GAMECTL_LIB_LABEL" lib_header="$GAMECTL_LIB_HEADER"
        local lib_sock=""
        local -a fzf_live_args=()
        if tui_supports_live_events; then
            local lib_ldir="$(get_runtime_dir)/tui_listeners"
            mkdir -p -m 700 "$lib_ldir" 2>/dev/null || true
            lib_sock="$lib_ldir/l_${BASHPID}.sock"
            if [ "${#lib_sock}" -le 100 ]; then
                rm -f "$lib_sock" 2>/dev/null || true
                export GAMECTL_ACTIVE_STORE="$active_store"
                fzf_live_args=("--listen=$lib_sock" '--bind=f12:transform("$GAMECTL_PREVIEW_BIN" --tui-library-sync "$GAMECTL_ACTIVE_STORE")')
            else
                lib_sock=""
            fi
        fi
        local fzf_out fzf_rc=0
        fzf_out=$(scan_installed_games --formatted --store "$active_store" | fzf \
            --delimiter=$'\t' \
            --with-nth=1,2,3 \
            --expect=ctrl-f,ctrl-d,ctrl-l,ctrl-o,ctrl-p,ctrl-i,ctrl-s,ctrl-b,ctrl-r,ctrl-x,tab,alt-s \
            --border-label="$lib_label" \
            --border-label-pos=2 \
            --header="$lib_header" \
            --prompt="Library > " \
            --preview='"$GAMECTL_PREVIEW_BIN" --preview {1} {2} {3} {4} {5}' \
            --preview-window=right:55%:border-rounded:wrap \
            "${fzf_live_args[@]}" \
        ) || fzf_rc=$?
        [ -n "$lib_sock" ] && rm -f "$lib_sock" 2>/dev/null || true

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
                EPIC) active_store="AMAZON" ;;
                AMAZON) active_store="STANDALONE" ;;
                *) active_store="ALL" ;;
            esac
            continue
        elif [ "$trigger_key" = "alt-s" ]; then
            local store_pick=""
            store_pick=$(tui_action_palette \
                "Store Filter" \
                "Select Store View (Enter: Apply │ Esc: Cancel)" \
                "$(printf 'ALL\tAll Stores (Unified)\nSTEAM\tSteam Library\nGOG\tGOG Library (DRM-Free)\nEPIC\tEpic Games Library (Legendary)\nAMAZON\tAmazon Games Library (Nile)\nSTANDALONE\tStandalone / Portable\n')" \
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
                local active_row="" active_pid="" active_log="" active_inf=""
                active_row=$(find_active_game_for_dir "$sel_dir" 2>/dev/null || true)
                if [ -n "$active_row" ]; then
                    local _a_title _a_dir _a_bin _a_scope _a_sep=$'\x1f'
                    IFS="$_a_sep" read -r active_pid _a_title _a_dir _a_bin active_log active_inf _a_scope <<< "$active_row"
                fi

                if [ -n "$active_pid" ]; then
                    # Game is already running: open In-Dashboard Process Controller
                    local hud_rc=0
                    game_controller_hud "$active_pid" "$sel_title" "$active_log" "$sel_dir" "$sel_bin" "$active_inf" "Running Process" || hud_rc=$?
                    invalidate_scan_cache
                    if [ "$hud_rc" -eq 10 ]; then
                        break
                    fi
                    continue
                elif [[ "$(strip_ansi "$sel_status")" == *"[RUNNING]"* ]]; then
                    local stale_log="" stale_hint="" stale_tail="" stale_msg=""
                    stale_log="$(get_game_log_file "$sel_dir" "${sel_bin:-game}")"
                    stale_hint="$(inspect_game_log_hint "$stale_log" 2>/dev/null || true)"
                    [ -s "$stale_log" ] && stale_tail=$(tail -n 12 "$stale_log" 2>/dev/null || true)
                    stale_msg="Game '$sel_title' is no longer running (stale [RUNNING] selection)."
                    [ -n "$stale_hint" ] && stale_msg+=$'\n\n'"[HINT] $stale_hint"
                    [ -n "$stale_tail" ] && stale_msg+=$'\n\n'"Recent Log Output:"$'\n'"$stale_tail"
                    stale_msg+=$'\n\n'"Full log:"$'\n'"$stale_log"
                    tui_modal_notice "Game No Longer Running ($sel_title)" "$stale_msg" || true
                    invalidate_scan_cache
                    continue
                fi

                # Launch game via isolated engine harness (zero terminal leaks, seamless background launch)
                # Engine failures are already logged and surfaced via tui_run_engine modal; do not conflate with fzf status
                tui_run_engine "Launch $sel_title" launch_game "$sel_dir" "$sel_bin" "$sel_title" || launch_rc=$?
                invalidate_scan_cache
                if [ "$launch_rc" -eq 0 ]; then
                    if verify_launched_game_startup "$sel_dir" "$sel_bin" "$sel_title"; then
                        last_status_banner="[RUNNING] $sel_title (PID $GAMECTL_VERIFY_PID) — Press Enter on it to Stop / View Logs"
                    else
                        log_msg "ERROR" "LIBRARY" "Game '$sel_title' exited immediately after launch (Log: ${GAMECTL_VERIFY_LOG:-unknown})"
                        tui_modal_notice "Launch Failed ($sel_title)" "$GAMECTL_VERIFY_SUMMARY" || true
                        last_status_banner="[FAILED] $sel_title exited immediately — Log: ${GAMECTL_VERIFY_LOG:-unknown}"
                    fi
                else
                    log_msg "WARN" "LIBRARY" "Launch returned exit code $launch_rc for $sel_title"
                    last_status_banner="[FAILED] $sel_title failed to launch (exit code $launch_rc)"
                fi
                ;;
        esac
    done

    [ "$standalone" = "true" ] && exit_tui_screen
    return 0
}

# Standalone-source compatibility: load split tui submodules when sourced directly outside bin/gamectl
if [ -z "${GAMECTL_BUNDLED:-}" ] && [ -n "${BASH_SOURCE[0]:-}" ]; then
    _tui_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd)"
    for _tui_sub in 71_previews.sh 72_store_tui.sh 73_search_tui.sh; do
        if [ -f "$_tui_dir/$_tui_sub" ]; then
            # shellcheck source=/dev/null
            source "$_tui_dir/$_tui_sub"
        fi
    done
    unset _tui_dir _tui_sub
fi

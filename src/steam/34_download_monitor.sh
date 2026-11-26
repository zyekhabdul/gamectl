# ==============================================================================
# Interactive Download Monitor TUI & Preview (Split from 30_downloader.sh)
# ==============================================================================

# Dedicated Download Telemetry & ACF Preview Handler
preview_download() {
    local appid="${1:-}"
    local engine="${2:-}"
    local ref_path="${3:-}"

    appid=$(strip_ansi "$appid" | tr -d '[:space:]')
    engine=$(strip_ansi "$engine" | tr -d '[:space:]')
    ref_path=$(strip_ansi "$ref_path" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')

    if [ -z "$appid" ] || [ "$appid" = "0" ] || [ -z "$ref_path" ]; then
        printf "%s╭─ DOWNLOAD TELEMETRY MONITOR ────────────────────────╮%s\n" "${UI_BOX}" "${UI_RST}"
        printf "│ %sNo Active Download Selected%s\n" "${UI_DIM}" "${UI_RST}"
        printf "%s╰─────────────────────────────────────────────────────╯%s\n" "${UI_BOX}" "${UI_RST}"
        printf "  %sNo active download telemetry or reference available in queue.%s\n" "${UI_DIM}" "${UI_RST}"
        return 0
    fi

    if [ -d "$ref_path" ]; then
        # Standalone Staging Directory
        local title="Unknown Title" target_dir="Not configured" pid="Unknown" start_time="" log_file="$ref_path/download.log" status="DOWNLOADING"
        if [ -f "$ref_path/status.info" ]; then
            local k v
            while IFS='=' read -r k v || [ -n "$k" ]; do
                case "$k" in
                    TITLE) title="$v" ;;
                    TARGET_DIR) target_dir="$v" ;;
                    PID) pid="$v" ;;
                    START_TIME) start_time="$v" ;;
                    LOG_FILE) [ -n "$v" ] && log_file="$v" ;;
                    STATUS) status="$v" ;;
                esac
            done < "$ref_path/status.info"
        fi

        local pid_status="${UI_RED}[TERMINATED]${UI_RST}"
        if [[ "$pid" =~ ^[0-9]+$ ]] && kill -0 "$pid" 2>/dev/null; then
            local p_stat
            p_stat=$(awk '/^State:/ {print $2}' "/proc/$pid/status" 2>/dev/null || true)
            if [[ "$p_stat" =~ ^[Tt] ]]; then
                pid_status="${UI_PURPLE}[PAUSED (SIGSTOP)]${UI_RST}"
            else
                pid_status="${UI_GREEN}[RUNNING (PID $pid)]${UI_RST}"
            fi
        fi

        local elapsed_str="N/A"
        if [ -n "$start_time" ] && [[ "$start_time" =~ ^[0-9]+$ ]]; then
            local now_ts elapsed
            now_ts=$(date +%s)
            elapsed=$(( now_ts - start_time ))
            if [ "$elapsed" -ge 0 ]; then
                local mins=$(( elapsed / 60 ))
                local secs=$(( elapsed % 60 ))
                elapsed_str="${mins}m ${secs}s"
            fi
        fi

        local prog_data st_pct st_bytes st_state
        prog_data=$(get_depot_dl_progress "$log_file" "$pid")
        IFS=$'\t' read -r st_pct st_bytes st_state <<< "$prog_data"

        printf "%s╭─ STANDALONE CDN DOWNLOAD TELEMETRY ────────────────╮%s\n" "${UI_BOX}" "${UI_RST}"
        printf "│ %s%s%s %s(AppID: %s)%s\n" "${UI_BOLD}" "$title" "${UI_RST}" "${UI_DIM}" "$appid" "${UI_RST}"
        printf "%s╰─────────────────────────────────────────────────────╯%s\n" "${UI_BOX}" "${UI_RST}"
        printf "  %sEngine%s        : %s\n" "${UI_CYAN}" "${UI_RST}" "Native Rust gamectl-depot-dl (Valve CDN)"
        printf "  %sProcess State%s : %s\n" "${UI_CYAN}" "${UI_RST}" "$pid_status"
        printf "  %sProgress%s      : %s%s%s (%s)\n" "${UI_CYAN}" "${UI_RST}" "${UI_BOLD}" "$st_pct" "${UI_RST}" "$st_bytes"
        printf "  %sElapsed Time%s  : %s\n" "${UI_CYAN}" "${UI_RST}" "$elapsed_str"
        printf "  %sTarget Dir%s    : %s\n" "${UI_CYAN}" "${UI_RST}" "$target_dir"
        printf "  %sStaging Dir%s   : %s\n" "${UI_CYAN}" "${UI_RST}" "$ref_path"
        printf "\n"
        printf "%s╭─ RECENT DOWNLOAD LOG (tail -n 12) ──────────────────╮%s\n" "${UI_BOX}" "${UI_RST}"
        if [ -f "$log_file" ]; then
            tail -n 12 "$log_file"
        else
            printf "%s(No log file generated yet)%s\n" "${UI_DIM}" "${UI_RST}"
        fi
        return 0
    fi

    if [ -f "$ref_path" ]; then
        # Steam ACF Manifest
        local state_data
        state_data=$(parse_acf_download_state "$ref_path" 2>/dev/null || true)
        if [ -n "$state_data" ]; then
            local a_id a_name a_status a_pct a_dl a_tot a_flags a_dir a_path
            IFS=$'\t' read -r a_id a_name a_status a_pct a_dl a_tot a_flags a_dir a_path <<< "$state_data"
            local dl_fmt tot_fmt
            dl_fmt=$(format_bytes "$a_dl")
            tot_fmt=$(format_bytes "$a_tot")
            local install_path; install_path="$(dirname "$ref_path")/common/$a_dir"

            printf "%s╭─ STEAM CLIENT DOWNLOAD TELEMETRY ───────────────────╮%s\n" "${UI_BOX}" "${UI_RST}"
            printf "│ %s%s%s %s(AppID: %s)%s\n" "${UI_BOLD}" "$a_name" "${UI_RST}" "${UI_DIM}" "$a_id" "${UI_RST}"
            printf "%s╰─────────────────────────────────────────────────────╯%s\n" "${UI_BOX}" "${UI_RST}"
            printf "  %sEngine%s        : %s\n" "${UI_CYAN}" "${UI_RST}" "Steam Client (ACF Manifest Engine)"
            printf "  %sStatus%s        : %s\n" "${UI_CYAN}" "${UI_RST}" "$a_status"
            printf "  %sProgress%s      : %s%s%s (%s / %s)\n" "${UI_CYAN}" "${UI_RST}" "${UI_BOLD}" "$a_pct" "${UI_RST}" "$dl_fmt" "$tot_fmt"
            printf "  %sStateFlags%s    : %s\n" "${UI_CYAN}" "${UI_RST}" "$a_flags"
            printf "  %sInstall Dir%s   : %s\n" "${UI_CYAN}" "${UI_RST}" "$install_path"
            printf "  %sManifest File%s : %s\n" "${UI_CYAN}" "${UI_RST}" "$ref_path"
            printf "\n"
            printf "%s╭─ MANIFEST CONFIGURATION (VDF) ──────────────────────╮%s\n" "${UI_BOX}" "${UI_RST}"
            grep -E '"(appid|name|StateFlags|BytesDownloaded|BytesToDownload|installdir|buildid|LastOwner)"' "$ref_path" 2>/dev/null || true
            return 0
        fi
    fi

    printf "%s╭─ DOWNLOAD TELEMETRY MONITOR ────────────────────────╮%s\n" "${UI_BOX}" "${UI_RST}"
    printf "│ %sReference: %s%s\n" "${UI_DIM}" "$ref_path" "${UI_RST}"
    printf "%s╰─────────────────────────────────────────────────────╯%s\n" "${UI_BOX}" "${UI_RST}"
    printf "  No active download telemetry or reference available for this target.\n"
}

# Interactive Download Monitor TUI
list_downloads_interactive() {
    if [ ! -t 0 ] || [ ! -t 1 ]; then
        echo "[ERROR] Interactive download monitor requires a terminal (TTY)." >&2
        return 1
    fi
    if ! command -v fzf >/dev/null 2>&1; then
        echo "[ERROR] fzf is required for interactive mode but was not found in PATH." >&2
        return 127
    fi

    local run_dir
    run_dir="$(get_runtime_dir)"
    while true; do
        local entries=""
        local total_items=0

        # Scan Steam ACF entries
        local steam_apps
        steam_apps="$(get_steam_primary_apps 2>/dev/null || echo "$HOME/.local/share/Steam/steamapps")"
        shopt -s nullglob
        local acf_files=("$steam_apps"/appmanifest_*.acf)
        shopt -u nullglob

        for acf in "${acf_files[@]}"; do
            local state_data
            state_data=$(parse_acf_download_state "$acf" 2>/dev/null || true)
            [ -z "$state_data" ] && continue

            local a_id a_title a_status a_pct a_dl a_total a_flags a_dir a_path
            IFS=$'\t' read -r a_id a_title a_status a_pct a_dl a_total a_flags a_dir a_path <<< "$state_data"

            if [ "$a_status" = "[DOWNLOADING]" ] || [ "$a_status" = "[PAUSED]" ] || [ "$a_status" = "[UPDATE REQUIRED]" ] || [ "$a_status" = "[INSTALLED]" ]; then
                local ui_status="${UI_ICE}${a_status}${UI_RST}"
                [ "$a_status" = "[DOWNLOADING]" ] && ui_status="${UI_GREEN}[DOWNLOADING ${a_pct}]${UI_RST}"
                [ "$a_status" = "[PAUSED]" ] && ui_status="${UI_PURPLE}[PAUSED ${a_pct}]${UI_RST}"
                [ "$a_status" = "[INSTALLED]" ] && ui_status="${UI_CYAN}[INSTALLED]${UI_RST}"

                local dl_fmt tot_fmt
                dl_fmt=$(format_bytes "$a_dl")
                tot_fmt=$(format_bytes "$a_total")
                local detail="${a_title} (${dl_fmt}/${tot_fmt})"
                validate_tui_fields "$a_id" "$detail" "$a_path" || continue
                entries+="${a_id}"$'\t'"Steam"$'\t'"${ui_status}"$'\t'"${a_pct}"$'\t'"${detail}"$'\t'"${a_path}"$'\n'
                total_items=$((total_items + 1))
            fi
        done

        shopt -s nullglob
        for st_dir in "$run_dir"/depot_dl_*; do
            [ -d "$st_dir" ] || continue
            local base_st="${st_dir##*/}"
            local st_pid="${base_st##*_}"
            local rest_st="${base_st#depot_dl_}"
            local st_appid="${rest_st%_*}"
            [ -z "$st_appid" ] || [ -z "$st_pid" ] && continue

            # Self-healing: purge orphaned staging dir if downloader process is dead
            if ! [[ "$st_pid" =~ ^[0-9]+$ ]] || ! kill -0 "$st_pid" 2>/dev/null; then
                rm -rf "$st_dir" 2>/dev/null || true
                continue
            fi

            local st_info="$st_dir/status.info"
            local st_title="Native CDN Download"
            local st_log="$st_dir/download.log"
            if [ -f "$st_info" ]; then
                local info_title info_log
                info_title=$(grep -E '^TITLE=' "$st_info" | cut -d= -f2- || true)
                info_log=$(grep -E '^LOG_FILE=' "$st_info" | cut -d= -f2- || true)
                [ -n "$info_title" ] && st_title="$info_title"
                [ -n "$info_log" ] && [ -f "$info_log" ] && st_log="$info_log"
            fi

            local prog_data st_pct st_bytes st_state
            prog_data=$(get_depot_dl_progress "$st_log" "$st_pid")
            IFS=$'\t' read -r st_pct st_bytes st_state <<< "$prog_data"

            local st_ui="${UI_GREEN}[DOWNLOADING ${st_pct}]${UI_RST}"
            if [ "$st_state" = "[PAUSED]" ]; then
                st_ui="${UI_PURPLE}[PAUSED ${st_pct}]${UI_RST}"
            elif [ "$st_state" = "[COMPLETED]" ]; then
                st_ui="${UI_CYAN}[COMPLETED]${UI_RST}"
            elif [ "$st_state" = "[FAILED]" ]; then
                st_ui="${UI_RED}[FAILED]${UI_RST}"
            elif [ "$st_state" = "[STARTING]" ]; then
                st_ui="${UI_ICE}[STARTING]${UI_RST}"
            fi

            local st_detail="${st_title} (${st_bytes}, PID: ${st_pid})"
            validate_tui_fields "$st_appid" "$st_detail" "$st_dir" || continue
            entries+="${st_appid}"$'\t'"Standalone"$'\t'"${st_ui}"$'\t'"${st_pct}"$'\t'"${st_detail}"$'\t'"${st_dir}"$'\n'
            total_items=$((total_items + 1))
        done
        shopt -u nullglob

        if [ "$total_items" -eq 0 ]; then
            entries+="0"$'\t'"Info"$'\t'"${UI_DIM}[NO ACTIVE DOWNLOADS]${UI_RST}"$'\t'"0%"$'\t'"No active downloads found in Steam or Standalone engine. Press Esc to return."$'\t\n'
        fi

        flush_tty_input
        local fzf_out fzf_rc=0
        export GAMECTL_PREVIEW_BIN="$SELF_BIN"
        fzf_out=$(printf "%s" "$entries" | fzf \
            --delimiter=$'\t' \
            --with-nth=1,2,3,5 \
            --expect=ctrl-k \
            --border-label="  ╢ gamectl :: Download Manager ╟  " \
            --border-label-pos=2 \
            --header="Enter: Actions │ Ctrl-K: Pause │ Esc: Back" \
            --prompt="Downloads > " \
            --preview='"$GAMECTL_PREVIEW_BIN" --preview-download {1} {2} {6}' \
            --preview-window=right:60%:border-rounded:wrap \
        ) || fzf_rc=$?

        [ "$fzf_rc" -eq 130 ] && break
        if [ "$fzf_rc" -ne 0 ] && [ "$fzf_rc" -ne 1 ]; then
            echo "[ERROR] Download monitor failed (fzf exit code $fzf_rc)." >&2
            return "$fzf_rc"
        fi
        [ -z "$fzf_out" ] && continue

        local trigger_key selection
        trigger_key=$(echo "$fzf_out" | head -n 1)
        selection=$(echo "$fzf_out" | sed -n '2p')

        [ -z "$selection" ] && continue

        local sel_appid sel_engine sel_status sel_pct sel_title sel_ref
        sel_appid=$(echo "$selection" | awk -F'\t' '{print $1}')
        sel_engine=$(echo "$selection" | awk -F'\t' '{print $2}')
        sel_status=$(echo "$selection" | awk -F'\t' '{print $3}')
        sel_pct=$(echo "$selection" | awk -F'\t' '{print $4}')
        sel_title=$(echo "$selection" | awk -F'\t' '{print $5}')
        sel_ref=$(echo "$selection" | awk -F'\t' '{print $6}')

        [ "$sel_appid" = "0" ] && break

        if [ "$trigger_key" = "ctrl-k" ]; then
            if [ "$sel_engine" = "Standalone" ]; then
                local t_pid="${sel_ref##*_}"
                if [[ "$t_pid" =~ ^[0-9]+$ ]] && kill -0 "$t_pid" 2>/dev/null; then
                    kill -STOP "$t_pid" 2>/dev/null || true
                    log_msg "INFO" "DOWNLOAD" "Paused standalone download PID $t_pid (AppID: $sel_appid) via SIGSTOP"
                    tui_modal_notice "Standalone Download Paused" "Dispatched SIGSTOP to process PID: $t_pid (AppID: $sel_appid).\nUse Action Menu to resume or terminate." || return $?
                else
                    tui_modal_notice "Pause Standalone" "Downloader process (PID: $t_pid) is no longer active." || return $?
                fi
            elif command -v steam >/dev/null 2>&1; then
                steam "steam://pause/$sel_appid" >/dev/null 2>&1 &
                log_msg "INFO" "DOWNLOAD" "Paused download for AppID $sel_appid"
                tui_modal_notice "Download Paused" "Dispatched pause signal to Steam Client for AppID: $sel_appid" || return $?
            else
                tui_modal_notice "Pause Unsupported" "Steam client CLI is not available in PATH." || return $?
            fi
            continue
        fi

        local action_entries
        if [ "$sel_engine" = "Standalone" ]; then
            local t_pid="${sel_ref##*_}"
            action_entries=$(cat <<EOF
1	Pause Standalone Download (SIGSTOP)	Suspend process PID $t_pid
2	Resume Standalone Download (SIGCONT)	Continue process PID $t_pid
3	Terminate Standalone Download (SIGTERM)	Kill process PID $t_pid
4	Inject Standalone GBE Fork LAN Runtime	Deploy Goldberg emulator
5	Return to Download List	Back
EOF
)
        else
            action_entries=$(cat <<EOF
1	Pause Steam Client Download	steam://pause/$sel_appid
2	Resume Steam Client Download	steam://resume/$sel_appid
3	Inject Standalone GBE Fork LAN Runtime	Deploy Goldberg emulator
4	Return to Download List	Back
EOF
)
        fi
        flush_tty_input
        local act_sel act_rc=0
        act_sel=$(echo "$action_entries" | fzf \
            --delimiter=$'\t' \
            --with-nth=2,3 \
            --border-label="  ╢ Actions: AppID $sel_appid ($sel_engine) ╟  " \
            --border-label-pos=2 \
            --header="DOWNLOAD ACTIONS (Enter: Execute │ Esc: Return)" \
            --prompt="Action > " \
            --reverse 2>/dev/null) || act_rc=$?

        check_fzf_status "$act_rc" || return $?
        [ "$act_rc" -eq 130 ] && continue
        [ -z "$act_sel" ] && continue

        local dl_opt
        dl_opt=$(echo "$act_sel" | cut -f1 | tr -d '[:space:]')

        case "$dl_opt" in
            1)
                if [ "$sel_engine" = "Standalone" ]; then
                    local t_pid="${sel_ref##*_}"
                    if [[ "$t_pid" =~ ^[0-9]+$ ]] && kill -0 "$t_pid" 2>/dev/null; then
                        kill -STOP "$t_pid" 2>/dev/null || true
                        log_msg "INFO" "DOWNLOAD" "Paused standalone download PID $t_pid (AppID: $sel_appid) via SIGSTOP"
                        tui_modal_notice "Download Paused" "Sent SIGSTOP to standalone downloader PID $t_pid." || return $?
                    fi
                elif command -v steam >/dev/null 2>&1; then
                    steam "steam://pause/$sel_appid" >/dev/null 2>&1 &
                    log_msg "INFO" "DOWNLOAD" "Paused download for AppID $sel_appid"
                fi
                ;;
            2)
                if [ "$sel_engine" = "Standalone" ]; then
                    local t_pid="${sel_ref##*_}"
                    if [[ "$t_pid" =~ ^[0-9]+$ ]] && kill -0 "$t_pid" 2>/dev/null; then
                        kill -CONT "$t_pid" 2>/dev/null || true
                        log_msg "INFO" "DOWNLOAD" "Resumed standalone download PID $t_pid (AppID: $sel_appid) via SIGCONT"
                        tui_modal_notice "Download Resumed" "Sent SIGCONT to standalone downloader PID $t_pid." || return $?
                    fi
                elif command -v steam >/dev/null 2>&1; then
                    steam "steam://resume/$sel_appid" >/dev/null 2>&1 &
                    log_msg "INFO" "DOWNLOAD" "Resumed download for AppID $sel_appid"
                fi
                ;;
            3)
                if [ "$sel_engine" = "Standalone" ]; then
                    local t_pid="${sel_ref##*_}"
                    if [[ "$t_pid" =~ ^[0-9]+$ ]] && kill -0 "$t_pid" 2>/dev/null; then
                        kill -TERM "$t_pid" 2>/dev/null || true
                        rm -rf "$sel_ref" 2>/dev/null || true
                        log_msg "WARN" "DOWNLOAD" "Terminated standalone download PID $t_pid (AppID: $sel_appid) via SIGTERM"
                        tui_modal_notice "Download Terminated" "Sent SIGTERM to standalone downloader PID $t_pid and purged staging." || return $?
                    fi
                else
                    local g_dir=""
                    if [ -f "$sel_ref" ]; then
                        local i_dir
                        i_dir=$(grep -m1 '"installdir"' "$sel_ref" 2>/dev/null | awk -F'"' '{print $4}')
                        if [ -n "$i_dir" ]; then
                            g_dir="$(dirname "$sel_ref")/common/$i_dir"
                        fi
                    fi
                    if [ -n "$g_dir" ] && [ -d "$g_dir" ]; then
                        log_msg "INFO" "DOWNLOAD" "Injecting GBE Fork LAN runtime into: $g_dir"
                        "$SELF_BIN" inject "$g_dir" "$sel_appid"
                        tui_modal_notice "GBE Runtime Injected" "Goldberg emulator LAN runtime successfully injected into:\n$g_dir" || return $?
                    else
                        tui_modal_notice "Target Not Found" "Steam common game directory not found:\n$g_dir" || return $?
                    fi
                fi
                ;;
            4)
                if [ "$sel_engine" = "Standalone" ]; then
                    local g_dir=""
                    if [ -f "$sel_ref/status.info" ]; then
                        g_dir=$(grep -E '^TARGET_DIR=' "$sel_ref/status.info" | cut -d= -f2-)
                    fi
                    if [ -z "$g_dir" ] || [ ! -d "$g_dir" ]; then
                        local st_title=""
                        [ -f "$sel_ref/status.info" ] && st_title=$(grep -E '^TITLE=' "$sel_ref/status.info" | cut -d= -f2-)
                        if [ -n "$st_title" ]; then
                            g_dir="$(resolve_standalone_library_dir "$st_title")"
                        fi
                    fi
                    if [ -n "$g_dir" ] && [ -d "$g_dir" ]; then
                        log_msg "INFO" "DOWNLOAD" "Injecting GBE Fork LAN runtime into target dir: $g_dir"
                        "$SELF_BIN" inject "$g_dir" "$sel_appid"
                        tui_modal_notice "GBE Runtime Injected" "Goldberg emulator LAN runtime successfully injected into:\n$g_dir" || return $?
                    else
                        tui_modal_notice "Target Not Found" "Target installation directory not found or not yet created:\n$g_dir" || return $?
                    fi
                else
                    continue
                fi
                ;;
            *)
                continue
                ;;
        esac
    done
}

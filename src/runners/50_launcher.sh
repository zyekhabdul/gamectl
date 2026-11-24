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
        if kill -0 "$game_pid" 2>/dev/null; then
            is_alive=1
        fi

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
                while kill -0 "$game_pid" 2>/dev/null && [ "$wait_cnt" -lt 6 ]; do
                    sleep 0.2
                    wait_cnt=$((wait_cnt + 1))
                done
                if [ -d "$gdir/pfx" ]; then
                    local ws_bin
                    ws_bin="$(get_wineserver_bin "$(find_runner "$gdir" 2>/dev/null || true)" 2>/dev/null || true)"
                    [ -n "$ws_bin" ] && WINEPREFIX="$gdir/pfx" "$ws_bin" -w 2>/dev/null || true # wineserver -w
                fi
                if ! kill -0 "$game_pid" 2>/dev/null; then
                    rm -f "$info_file" 2>/dev/null || true
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
                rm -f "$info_file" 2>/dev/null || true
                log_msg "WARN" "LAUNCH" "Game '$title' (PID $game_pid) force-killed"
                tui_modal_notice "Force Terminated" "Game '$title' (PID $game_pid) force-killed via SIGKILL." || return $?
                ;;
            *)
                return 0
                ;;
        esac
    done
}

# Launch game with performance wrapping and runner isolation
launch_game() {
    local gdir="$1"
    local gbin="$2"
    local title="$3"
    shift 3 || true

    local in_tui="${GAMECTL_IN_ALT_SCREEN:-0}"
    local run_dir
    run_dir="$(get_runtime_dir)"
    mkdir -p -m 700 "$run_dir/active_games" 2>/dev/null || true
    local log_file
    log_file="$(get_game_log_file "$gdir" "${gbin:-game}")"
    : >> "$log_file" 2>/dev/null || true

    _launch_echo() {
        if [ "$in_tui" -eq 1 ]; then
            local clean_text
            clean_text=$(strip_ansi "$*")
            [ -n "${log_file:-}" ] && echo "$clean_text" >> "$log_file" 2>/dev/null || true
            log_msg "INFO" "LAUNCH" "$clean_text"
        else
            echo "$@"
        fi
    }

    _launch_err() {
        if [ "$in_tui" -eq 1 ]; then
            local clean_text
            clean_text=$(strip_ansi "$*")
            [ -n "${log_file:-}" ] && echo "$clean_text" >> "$log_file" 2>/dev/null || true
            log_msg "ERROR" "LAUNCH" "$clean_text"
        else
            echo "$@" >&2
        fi
    }

    _launch_echo "[INFO] Preparing launch: $title..."
    log_msg "INFO" "LAUNCH" "Preparing launch: $title ($gdir/$gbin)"
    load_wrapper_config "$gdir" 1
    if [ "${GAMECTL_CFG_AUTO_LOCATE_SAVES:-0}" = "1" ] && [ -d "$gdir/pfx" ]; then
        if ! collect_prefix_saves "$gdir" true; then
            _launch_err "[WARN] Pre-launch prefix save collection failed for '$title'. Proceeding with launch."
            log_msg "WARN" "LAUNCH" "Pre-launch prefix save collection failed for $title"
        fi
    fi
    if [ -d "$gdir/saves" ] || [ -L "$gdir/saves" ]; then
        if ! backup_save "$gdir" true; then
            _launch_err "[WARN] Pre-launch save snapshot backup failed for '$title'. Proceeding with launch."
            log_msg "WARN" "LAUNCH" "Pre-launch save snapshot backup failed for $title"
        fi
    fi

    # Resolve wrappers and extra flags
    declare -a GAMECTL_WRAPPER_PREFIX=()
    declare -a GAMECTL_REMAINING_ARGS=()
    GAMECTL_ACTIVE_GLTHREAD=0
    build_wrapper_command "$gdir" "$@"
    local wrappers=("${GAMECTL_WRAPPER_PREFIX[@]}")
    local game_args=("${GAMECTL_REMAINING_ARGS[@]}")

    # Resolve Developer Mode & Engine Profiler (default OFF -> zero env pollution)
    resolve_dev_profiler_env "$gdir" 1
    local dev_trace_log=""
    if [ "${GAMECTL_DEV_ACTIVE:-0}" -eq 1 ] && [ -n "${GAMECTL_DEV_TRACE_LOG:-}" ]; then
        dev_trace_log="$GAMECTL_DEV_TRACE_LOG"
        mkdir -p -m 700 "$(dirname "$dev_trace_log")" 2>/dev/null || true
        {
            printf '=== gamectl dev-trace [%s] ===\n' "$(date '+%Y-%m-%d %H:%M:%S')"
            printf 'Title=%s\nDir=%s\nBin=%s\n' "$title" "$gdir" "$gbin"
            printf 'WINEDEBUG=%s (user_override=%s)\n' "${GAMECTL_DEV_RESOLVED_WINEDEBUG:-<unset>}" "${GAMECTL_DEV_RESPECTED_USER_WINEDEBUG:-0}"
            printf 'VK_LOADER_DEBUG=%s (user_override=%s)\n' "${GAMECTL_DEV_RESOLVED_VK_DEBUG:-<unset>}" "${GAMECTL_DEV_RESPECTED_USER_VK_DEBUG:-0}"
            printf 'GBE_LOG=%s\nMainLog=%s\n' "${GAMECTL_DEV_RESOLVED_GBE_LOG:-0}" "$log_file"
        } > "$dev_trace_log" 2>/dev/null || true
        _launch_echo "[INFO] Developer Profiler active. Trace log: $dev_trace_log"
        log_msg "INFO" "LAUNCH" "Developer Profiler active for $title (Trace: $dev_trace_log)"
    fi

    # Set Mesa performance env safely (only enable glthread if explicitly opted in)
    if [ "${GAMECTL_ACTIVE_GLTHREAD:-0}" = "1" ]; then
        export mesa_glthread=true
    else
        unset mesa_glthread
    fi
    export vblank_mode=0

    # Hybrid dGPU PRIME offloading
    if [ "${GAMECTL_ACTIVE_PRIME:-0}" = "1" ]; then
        case "${GAMECTL_ACTIVE_PRIME_VENDOR:-none}" in
            nvidia)
                export __NV_PRIME_RENDER_OFFLOAD=1
                export __GLX_VENDOR_LIBRARY_NAME=nvidia
                export __VK_LAYER_NV_optimus=NVIDIA_only
                _launch_echo "[INFO] Hybrid Graphics: Injected NVIDIA PRIME offload environment."
                ;;
            amd|intel)
                export DRI_PRIME=1
                _launch_echo "[INFO] Hybrid Graphics: Injected DRI_PRIME=1 offload environment."
                ;;
            *)
                export DRI_PRIME=1
                _launch_echo "[INFO] Hybrid Graphics: Fallback to DRI_PRIME=1 offload environment."
                ;;
        esac
    fi

    # Remedi Audio (DEFECT-03): Set buffer latency environment safely (PipeWire / PulseAudio)
    export PIPEWIRE_LATENCY="${GAMECTL_PIPEWIRE_LATENCY:-256/48000}"
    export PULSE_LATENCY_MSEC="${GAMECTL_PULSE_LATENCY:-60}"

    # Sovereign Steam Interceptor: traps and silences unshielded Steam Client calls
    local prev_path="$PATH"
    local interceptor_dir="$(get_runtime_dir)/interceptor"
    setup_steam_interceptor "$interceptor_dir"
    export PATH="$interceptor_dir:$PATH"



    # Capture current CPU scaling governor for clean restoration
    local prev_governor=""
    if [ -f /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor ]; then
        prev_governor=$(cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor 2>/dev/null || echo "")
    fi

    # Attempt CPU scaling governor if permitted and not already in performance mode
    if [ -w /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor ]; then
        if [ "$prev_governor" != "performance" ]; then
            echo performance | tee /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor >/dev/null 2>&1 || true
        fi
    fi

    # Local state cleanup helper & signal trap (scoped so TUI owner traps are never clobbered)
    local unit_name=""
    local _launch_traps_installed=0
    _disarm_launch_traps() {
        if [ "${_launch_traps_installed:-0}" -eq 1 ]; then
            if [ "${GAMECTL_IN_ALT_SCREEN:-0}" -eq 1 ] && [ "${BASHPID:-$$}" = "${GAMECTL_TUI_OWNER_PID:-}" ] && type install_tui_screen_traps >/dev/null 2>&1; then
                install_tui_screen_traps
            else
                trap - INT TERM EXIT
            fi
            _launch_traps_installed=0
        fi
    }
    _restore_launch_state() {
        _disarm_launch_traps
        if [ -n "${unit_name:-}" ]; then
            systemctl --user stop --no-block "$unit_name.scope" 2>/dev/null || true
        fi
        if [ -n "${prev_governor:-}" ] && [ -w /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor ]; then
            echo "$prev_governor" | tee /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor >/dev/null 2>&1 || true
        fi
        if [ "${is_win:-false}" = true ] && [ -n "${gdir:-}" ] && [ -d "$gdir/pfx" ]; then
            # Remediation DEFECT-02: Flush wine prefix writes to disk (wineserver -w)
            local ws_bin
            ws_bin="$(get_wineserver_bin "${runner_bin:-}" 2>/dev/null || true)"
            [ -n "$ws_bin" ] && WINEPREFIX="$gdir/pfx" "$ws_bin" -w 2>/dev/null || true
        fi
        unset __NV_PRIME_RENDER_OFFLOAD __GLX_VENDOR_LIBRARY_NAME __VK_LAYER_NV_optimus DRI_PRIME
        [ -n "${prev_path:-}" ] && export PATH="$prev_path"
        type clean_stale_locks >/dev/null 2>&1 && clean_stale_locks || true
    }
    if [ "${GAMECTL_IN_ALT_SCREEN:-0}" -ne 1 ] || [ "${BASHPID:-$$}" != "${GAMECTL_TUI_OWNER_PID:-}" ]; then
        _launch_traps_installed=1
        trap '_restore_launch_state; trap - INT TERM EXIT; return 130 2>/dev/null || exit 130' INT
        trap '_restore_launch_state; trap - INT TERM EXIT; return 143 2>/dev/null || exit 143' TERM
        trap '_restore_launch_state' EXIT
    fi

    if [ ${#wrappers[@]} -gt 0 ]; then
        _launch_echo "[INFO] Active wrappers: ${wrappers[*]}"
    fi

    cd "$gdir"

    # Pre-flight SteamStub DRM inspection & mitigation
    if [ -f "$gdir/$gbin" ] && detect_steamstub_drm "$gdir/$gbin"; then
        local stub_type
        stub_type=$(detect_steamstub_type "$gdir/$gbin" 2>/dev/null || echo "unknown")
        if [ "$stub_type" = "windows_pe" ]; then
            local unpacked_bin
            unpacked_bin=$(resolve_unpacked_binary "$gdir" "$gbin" 2>/dev/null || true)
            if [ -n "$unpacked_bin" ] && [ -f "$gdir/$unpacked_bin" ]; then
                if [ "$gbin" != "$unpacked_bin" ]; then
                    _launch_echo "  ${UI_GREEN}[SUCCESS] SteamStub PE: Automatically switched to unpacked binary: $unpacked_bin${UI_RST}"
                    gbin="$unpacked_bin"
                fi
            else
                _launch_echo "  ${UI_AMBER}[INFO] SteamStub PE DRM detected on ($gbin). Attempting Steamless unpacking...${UI_RST}"
                if unpack_steamstub_pe "$gdir/$gbin" "${runner_bin:-}" "${pfx_dir:-}"; then
                    unpacked_bin=$(resolve_unpacked_binary "$gdir" "$gbin" 2>/dev/null || true)
                    if [ -n "$unpacked_bin" ] && [ -f "$gdir/$unpacked_bin" ]; then
                        _launch_echo "  ${UI_GREEN}[SUCCESS] SteamStub PE: Unpacked binary generated: $unpacked_bin${UI_RST}"
                        gbin="$unpacked_bin"
                    fi
                else
                    _launch_echo "  ${UI_AMBER}[WARN] SteamStub PE detected on ($gbin) but Steamless CLI not available or unpacking failed.${UI_RST}"
                    _launch_echo "  ${UI_DIM}       If launch fails, unpack $gbin with Steamless (producing ${gbin%.*}.unpacked.exe).${UI_RST}"
                fi
            fi
        elif [ "$stub_type" = "linux_elf" ]; then
            local unpacked_bin
            unpacked_bin=$(resolve_unpacked_binary "$gdir" "$gbin" 2>/dev/null || true)
            if [ -n "$unpacked_bin" ] && [ -f "$gdir/$unpacked_bin" ]; then
                if [ "$gbin" != "$unpacked_bin" ]; then
                    _launch_echo "  ${UI_GREEN}[SUCCESS] SteamStub ELF: Automatically switched to unpacked binary: $unpacked_bin${UI_RST}"
                    gbin="$unpacked_bin"
                fi
            else
                local is_active=true
                if ! is_steamstub_elf_active "$gdir/$gbin"; then
                    is_active=false
                fi
                if [ "$is_active" = false ]; then
                    :
                else
                    _launch_echo "  ${UI_AMBER}[INFO] SteamStub ELF DRM (.bind) detected on ($gbin). Attempting native unpacking...${UI_RST}"
                    if unpack_steamstub_elf "$gdir/$gbin"; then
                        unpacked_bin=$(resolve_unpacked_binary "$gdir" "$gbin" 2>/dev/null || true)
                        if [ -n "$unpacked_bin" ] && [ -f "$gdir/$unpacked_bin" ]; then
                            _launch_echo "  ${UI_GREEN}[SUCCESS] SteamStub ELF: Unpacked binary generated: $unpacked_bin${UI_RST}"
                            gbin="$unpacked_bin"
                        fi
                    else
                        _launch_echo "  ${UI_AMBER}[WARN] Linux ELF SteamStub unpacking failed or unsupported stub variant.${UI_RST}"
                        _launch_echo "  ${UI_CYAN}[INFO] Sovereign steam.sh interceptor active in PATH to trap unsolicited Steam Client calls.${UI_RST}"
                    fi
                fi
            fi
        else
            _launch_echo "  ${UI_AMBER}[WARN] SteamStub DRM markers detected on binary ($gbin).${UI_RST}"
        fi
    fi

    # Pre-flight savegame redirection & offline DLC check
    mkdir -p -m 700 "$gdir/saves" 2>/dev/null || true
    local raw_appid
    raw_appid="$(resolve_game_appid "$gdir")"
    if [ -n "$raw_appid" ] && [ ! -f "$gdir/steam_settings/DLC.txt" ]; then
        fetch_dlc "$gdir" "$raw_appid" 2>/dev/null || true
    fi

    # Pre-flight GBE auto-injection & Sovereign Hard-Stop Guard
    local allow_unshielded="${GAMECTL_ACTIVE_ALLOW_UNSHIELDED:-${GAMECTL_ALLOW_UNSHIELDED:-0}}"
    local has_steam_api=false
    local probe_candidates=()
    while IFS= read -r api_found || [ -n "$api_found" ]; do
        [ -f "$api_found" ] && probe_candidates+=("$api_found")
    done < <(find "$gdir" -maxdepth 4 \
        \( -name "pfx" -o -name ".git" -o -name "saves" -o -name ".save_snapshots" \) -prune \
        -o \( -name "steam_api64.dll" -o -name "steam_api.dll" -o -name "libsteam_api.so" \) -print 2>/dev/null)

    if [ ${#probe_candidates[@]} -gt 0 ]; then
        has_steam_api=true
        local unshielded_candidates=()
        for api_cand in "${probe_candidates[@]}"; do
            if ! is_gbe_library "$api_cand"; then
                unshielded_candidates+=("$api_cand")
            fi
        done

        if [ ${#unshielded_candidates[@]} -gt 0 ]; then
            _launch_echo "  ${UI_AMBER}[INFO] Steamworks API detected without emulator shield. Attempting auto-injection...${UI_RST}"
            inject_game "$gdir" "" --no-sync 2>/dev/null || true

            local still_unshielded=()
            for api_cand in "${unshielded_candidates[@]}"; do
                if ! is_gbe_library "$api_cand"; then
                    still_unshielded+=("$api_cand")
                fi
            done

            if [ ${#still_unshielded[@]} -gt 0 ]; then
                if [ "$allow_unshielded" = "1" ]; then
                    _launch_echo "  ${UI_AMBER}[WARN] Launching unshielded Steamworks binary by user override (--allow-unshielded).${UI_RST}"
                else
                    _launch_err "  ${UI_RED}================================================================${UI_RST}"
                    _launch_err "  ${UI_RED}[HARD-STOP] Valve Steamworks API detected without emulator shield!${UI_RST}"
                    _launch_err "  ${UI_AMBER}Unshielded library: ${still_unshielded[*]}${UI_RST}"
                    _launch_err "  ${UI_AMBER}Launch halted to prevent Valve DRM from spawning Steam Client ('PURCHASE' prompt).${UI_RST}"
                    _launch_err "  ${UI_DIM}Remedy: Run 'gamectl setup-gbe' to provision templates or 'gamectl inject \"$gdir\"'.${UI_RST}"
                    _launch_err "  ${UI_DIM}Bypass: Pass --allow-unshielded to override this sovereign safety gate.${UI_RST}"
                    _launch_err "  ${UI_RED}================================================================${UI_RST}"
                    _restore_launch_state
                    return 1
                fi
            else
                invalidate_scan_cache
                _launch_echo "  ${UI_GREEN}[VERIFIED] GBE Fork emulator shield successfully engaged.${UI_RST}"
            fi
        else
            _launch_echo "  ${UI_GREEN}[VERIFIED] GBE Fork emulator shield confirmed active.${UI_RST}"
        fi
    fi

    # Check if target is a Windows executable (.exe / PE)
    local is_win=false
    case "$gbin" in
        *.exe|*.EXE) is_win=true ;;
    esac
    if [ "$is_win" = false ] && [ -f "$gdir/$gbin" ]; then
        if file -b "$gdir/$gbin" 2>/dev/null | grep -qi -E "PE32|MS Windows"; then
            is_win=true
        fi
    fi

    # Prepare runtime directory and log stream (collision-free SSoT)
    log_file="$(get_game_log_file "$gdir" "$gbin")"
    : >> "$log_file" 2>/dev/null || true

    local game_pid=""
    local run_type="Native Linux"

    local safe_title
    safe_title=$(echo "$title" | tr -cd '[:alnum:]_-')
    [ -z "$safe_title" ] && safe_title="game"

    local use_scope=false
    if [ "${GAMECTL_ACTIVE_SYSTEMD_SCOPE:-0}" = "1" ] && check_systemd_scope_support; then
        use_scope=true
    fi

    local -a sandbox_cmd=()
    if [ "${GAMECTL_ACTIVE_SANDBOX:-0}" = "1" ] && [ ${#GAMECTL_SANDBOX_PREFIX[@]} -gt 0 ]; then
        sandbox_cmd=("${GAMECTL_SANDBOX_PREFIX[@]}")
        _launch_echo "[INFO] Security Sandbox: Bubblewrap rootless filesystem isolation active."
    fi

    _exec_in_scope() {
        local fn
        while IFS= read -r fn; do
            [ -n "$fn" ] && export -fn "$fn" 2>/dev/null || true
        done < <(declare -Fx | awk '{print $NF}')
        local -a final_cmd=()
        [ ${#sandbox_cmd[@]} -gt 0 ] && final_cmd+=("${sandbox_cmd[@]}")
        final_cmd+=("$@")
        if [ "$use_scope" = true ]; then
            exec systemd-run --user --scope --quiet --unit="gamectl-${safe_title}-${BASHPID}" --description="gamectl: ${title}" "${final_cmd[@]}"
        else
            exec "${final_cmd[@]}"
        fi
    }

    if [ "$is_win" = true ]; then
        local detected_overrides
        detected_overrides=$(detect_dll_overrides "$gdir")
        if [ -n "$detected_overrides" ]; then
            export WINEDLLOVERRIDES="$detected_overrides"
            _launch_echo "[INFO] Active DLL Overrides: $WINEDLLOVERRIDES"
        fi

        local runner_bin
        runner_bin=$(find_runner "$gdir" 2>/dev/null || true)
        if [ -z "$runner_bin" ]; then
            _launch_err "[ERROR] Windows runner not found (umu-run, Proton, or Wine not installed)."
            _launch_err "        Install GE-Proton in ~/.local/share/Steam/compatibilitytools.d/ or install wine."
            _restore_launch_state
            return 1
        fi

        local appid
        appid="$(resolve_game_appid "$gdir" "0")"
        prepare_windows_runner_env "$runner_bin" "$gdir" "$appid" "${GAMECTL_RENDERER_MODE:-auto}" "${GAMECTL_ACTIVE_PRIME:-0}"
        local pfx_dir="$GAMECTL_WIN_PFX_DIR"
        mkdir -p "$pfx_dir"

        if [ "$GAMECTL_WIN_RUNNER_KIND" = "umu" ] || [ "$GAMECTL_WIN_RUNNER_KIND" = "proton" ]; then
            if [ "$GAMECTL_WIN_RENDERER" = "wined3d" ]; then
                _launch_echo "[INFO] Graphics Renderer: WineD3D / OpenGL fallback (PROTON_USE_WINED3D=1)."
            else
                _launch_echo "[INFO] Graphics Renderer: DXVK / Vulkan (PROTON_USE_WINED3D=0)."
            fi
        else
            _launch_echo "[INFO] Graphics Renderer: Wine native (WineD3D / OpenGL)."
        fi

        run_type="Windows ($(basename "$runner_bin"))"
        _launch_echo "[INFO] Launching Windows game via $(basename "$runner_bin") in background..."
        _launch_echo "[INFO] Isolated Wine Prefix: $pfx_dir"
        _launch_echo "[INFO] Log stream: $log_file"

        case "$GAMECTL_WIN_RUNNER_KIND" in
            umu)
                (
                    export WINEPREFIX="$GAMECTL_WIN_PFX_DIR" \
                        GAMEID="$GAMECTL_WIN_UMU_GAMEID" \
                        STEAM_COMPAT_APP_ID="$GAMECTL_WIN_APPID" \
                        SteamAppId="$GAMECTL_WIN_APPID" \
                        SteamGameId="$GAMECTL_WIN_APPID" \
                        WINEDLLOVERRIDES="${WINEDLLOVERRIDES:-}" \
                        PROTON_USE_WINED3D="$GAMECTL_WIN_PROTON_WINED3D"
                    [ "$GAMECTL_WIN_DISABLE_PROTONFIXES" = "1" ] && export PROTONFIXES_DISABLE=1
                    [ -n "${GAMECTL_DEV_RESOLVED_WINEDEBUG:-}" ] && export WINEDEBUG="$GAMECTL_DEV_RESOLVED_WINEDEBUG"
                    [ -n "${GAMECTL_DEV_RESOLVED_VK_DEBUG:-}" ] && export VK_LOADER_DEBUG="$GAMECTL_DEV_RESOLVED_VK_DEBUG"
                    [ "${GAMECTL_DEV_RESOLVED_GBE_LOG:-0}" = "1" ] && export GAMECTL_GBE_LOG=1 GBE_LOG_FILE="$dev_trace_log"
                    _exec_in_scope "${wrappers[@]}" "$runner_bin" "$gdir/$gbin" "${game_args[@]}"
                ) > "$log_file" 2>&1 &
                game_pid=$!
                ;;
            proton)
                (
                    export STEAM_COMPAT_CLIENT_INSTALL_PATH="$GAMECTL_WIN_STEAM_ROOT" \
                        STEAM_COMPAT_DATA_PATH="$gdir" \
                        STEAM_COMPAT_APP_ID="$GAMECTL_WIN_APPID" \
                        SteamAppId="$GAMECTL_WIN_APPID" \
                        SteamGameId="$GAMECTL_WIN_APPID" \
                        GAMEID="$GAMECTL_WIN_UMU_GAMEID" \
                        WINEPREFIX="$GAMECTL_WIN_PFX_DIR" \
                        WINEDLLOVERRIDES="${WINEDLLOVERRIDES:-}" \
                        PROTON_USE_WINED3D="$GAMECTL_WIN_PROTON_WINED3D"
                    [ "$GAMECTL_WIN_DISABLE_PROTONFIXES" = "1" ] && export PROTONFIXES_DISABLE=1
                    [ -n "${GAMECTL_DEV_RESOLVED_WINEDEBUG:-}" ] && export WINEDEBUG="$GAMECTL_DEV_RESOLVED_WINEDEBUG"
                    [ -n "${GAMECTL_DEV_RESOLVED_VK_DEBUG:-}" ] && export VK_LOADER_DEBUG="$GAMECTL_DEV_RESOLVED_VK_DEBUG"
                    [ "${GAMECTL_DEV_RESOLVED_GBE_LOG:-0}" = "1" ] && export GAMECTL_GBE_LOG=1 GBE_LOG_FILE="$dev_trace_log"
                    _exec_in_scope "${wrappers[@]}" "$runner_bin" waitforexitandrun "$gdir/$gbin" "${game_args[@]}"
                ) > "$log_file" 2>&1 &
                game_pid=$!
                ;;
            *)
                (
                    export WINEPREFIX="$GAMECTL_WIN_PFX_DIR" \
                        STEAM_COMPAT_APP_ID="$GAMECTL_WIN_APPID" \
                        SteamAppId="$GAMECTL_WIN_APPID" \
                        SteamGameId="$GAMECTL_WIN_APPID" \
                        WINEDLLOVERRIDES="${WINEDLLOVERRIDES:-}"
                    [ -n "${GAMECTL_DEV_RESOLVED_WINEDEBUG:-}" ] && export WINEDEBUG="$GAMECTL_DEV_RESOLVED_WINEDEBUG"
                    [ -n "${GAMECTL_DEV_RESOLVED_VK_DEBUG:-}" ] && export VK_LOADER_DEBUG="$GAMECTL_DEV_RESOLVED_VK_DEBUG"
                    [ "${GAMECTL_DEV_RESOLVED_GBE_LOG:-0}" = "1" ] && export GAMECTL_GBE_LOG=1 GBE_LOG_FILE="$dev_trace_log"
                    _exec_in_scope "${wrappers[@]}" "$runner_bin" "$gdir/$gbin" "${game_args[@]}"
                ) > "$log_file" 2>&1 &
                game_pid=$!
                ;;
        esac
    else
        _launch_echo "[INFO] Launching $title (Native Linux) in background..."
        _launch_echo "[INFO] Log stream: $log_file"
        (
            export LD_LIBRARY_PATH=".:$gdir:${LD_LIBRARY_PATH:-}"
            [ -n "${GAMECTL_DEV_RESOLVED_WINEDEBUG:-}" ] && export WINEDEBUG="$GAMECTL_DEV_RESOLVED_WINEDEBUG"
            [ -n "${GAMECTL_DEV_RESOLVED_VK_DEBUG:-}" ] && export VK_LOADER_DEBUG="$GAMECTL_DEV_RESOLVED_VK_DEBUG"
            [ "${GAMECTL_DEV_RESOLVED_GBE_LOG:-0}" = "1" ] && export GAMECTL_GBE_LOG=1 GBE_LOG_FILE="$dev_trace_log"
            _exec_in_scope "${wrappers[@]}" ./"$gbin" "${game_args[@]}"
        ) > "$log_file" 2>&1 &
        game_pid=$!
    fi

    if [ -z "$game_pid" ] || ! kill -0 "$game_pid" 2>/dev/null; then
        _launch_err "[ERROR] Failed to launch game into background."
        _restore_launch_state
        return 1
    fi

    if [ "$use_scope" = true ]; then
        unit_name="gamectl-${safe_title}-${game_pid}"
    fi

    local info_file="$run_dir/active_games/${game_pid}.info"
    cat <<EOF > "$info_file"
PID=$game_pid
TITLE=$title
DIR=$gdir
BIN=$gbin
LOG=$log_file
START=$(date +%s)
SCOPE_UNIT=$unit_name
EOF

    # Detached background watchdog to restore CPU governor and cleanup when process exits
    _run_launch_watchdog() {
        # This watchdog is a sibling of the game, so shell wait cannot reap it.
        if ! tail --pid="$game_pid" --sleep-interval=0.2 -f /dev/null >/dev/null 2>&1; then
            log_msg "ERROR" "LAUNCH" "Unable to monitor game process $game_pid"
            exit 1
        fi
        if [ -n "$unit_name" ]; then
            systemctl --user stop --no-block "$unit_name.scope" 2>/dev/null || true
        fi
        if [ "$is_win" = true ] && [ -d "$pfx_dir" ]; then
            # Remediation DEFECT-02: Wait for wineserver to flush data & release lockfile before snapshot (wineserver -w)
            local ws_bin
            ws_bin="$(get_wineserver_bin "${runner_bin:-}" 2>/dev/null || true)"
            [ -n "$ws_bin" ] && WINEPREFIX="$pfx_dir" "$ws_bin" -w 2>/dev/null || true
        fi
        rm -f "$info_file" 2>/dev/null || true
        if [ "$is_win" = true ] && [ "${GAMECTL_ACTIVE_AUTO_LOCATE_SAVES:-0}" = "1" ] && [ -d "$gdir/pfx" ]; then
            collect_prefix_saves "$gdir" true || true
        fi
        if [ "${GAMECTL_DEV_ACTIVE:-0}" -eq 1 ] && [ -n "${dev_trace_log:-}" ]; then
            {
                if [ -s "$log_file" ]; then
                    printf '\n--- Runner Output (%s) ---\n' "$log_file"
                    cat "$log_file"
                fi
                if [ "${GAMECTL_DEV_RESOLVED_GBE_LOG:-0}" = "1" ] && [ -s "$gdir/STEAM_LOG.txt" ]; then
                    printf '\n--- GBE STEAM_LOG.txt ---\n'
                    cat "$gdir/STEAM_LOG.txt"
                fi
            } >> "$dev_trace_log" 2>/dev/null || true
        fi
        log_msg "INFO" "LAUNCH" "Game '$title' (PID: $game_pid) exited"
        _restore_launch_state
    }
    if [ "${GAMECTL_IN_ALT_SCREEN:-0}" -eq 1 ] || [ "${GAMECTL_ENGINE_ISOLATED:-0}" -eq 1 ]; then
        ( _run_launch_watchdog ) </dev/null >/dev/null 2>&1 &
    else
        ( _run_launch_watchdog ) </dev/null &
    fi

    _launch_echo "[VERIFIED] Game '$title' running in background (PID: $game_pid)."
    log_msg "INFO" "LAUNCH" "Game '$title' running in background (PID: $game_pid, Log: $log_file)"

    export GAMECTL_LAST_LAUNCH_PID="$game_pid"
    export GAMECTL_LAST_INFO_FILE="$info_file"
    export GAMECTL_LAST_LOG_FILE="$log_file"
    export GAMECTL_LAST_RUN_TYPE="$run_type"

    _disarm_launch_traps
    export PATH="$prev_path"
    return 0
}

# CLI helper for launching games with wrappers and options
cli_launch() {
    local l_dir="${1:-}"
    shift || true

    # Auto-resolve numeric AppID to installed game directory
    if [[ "$l_dir" =~ ^[0-9]+$ ]] && [ ! -d "$l_dir" ]; then
        local resolved_dir
        resolved_dir=$(scan_installed_games 2>/dev/null | awk -F'\t' -v aid="$l_dir" '$1 == aid {print $4}' | head -n 1)
        if [ -n "$resolved_dir" ] && [ -d "$resolved_dir" ]; then
            l_dir="$resolved_dir"
        fi
    fi

    local l_bin=""
    local l_title=""
    local l_flags=()

    while [ $# -gt 0 ]; do
        case "$1" in
            --hud|--mangohud|--no-hud|--no-mangohud|--gamemode|--no-gamemode|--gamescope|--no-gamescope|--fsr|--no-fsr|--glthread|--no-glthread|--scope|--systemd-scope|--no-scope|--no-systemd-scope|--prime|--no-prime|--sandbox|--no-sandbox)
                l_flags+=("$1")
                shift
                ;;
            *)
                if [ -z "$l_bin" ]; then
                    l_bin="$1"
                elif [ -z "$l_title" ]; then
                    l_title="$1"
                else
                    l_flags+=("$1")
                fi
                shift
                ;;
        esac
    done

    [ -z "$l_title" ] && l_title="$(basename "$l_dir")"
    if [ -z "$l_bin" ]; then
        l_bin=$(find_game_binary "$l_dir" 2>/dev/null || echo "")
    fi

    if [ -n "$l_bin" ]; then
        local l_rc=0
        launch_game "$l_dir" "$l_bin" "$l_title" "${l_flags[@]}" || l_rc=$?
        if [ "$l_rc" -eq 0 ] && [ -t 0 ] && [ -t 1 ] && [ "${GAMECTL_IN_ALT_SCREEN:-0}" -eq 0 ]; then
            local gpid="${GAMECTL_LAST_LAUNCH_PID:-}"
            local inf="${GAMECTL_LAST_INFO_FILE:-}"
            local lfile="${GAMECTL_LAST_LOG_FILE:-}"
            local rtype="${GAMECTL_LAST_RUN_TYPE:-Native Linux}"
            if [ -n "$gpid" ] && [ -f "$inf" ] && kill -0 "$gpid" 2>/dev/null; then
                game_controller_hud "$gpid" "$l_title" "$lfile" "$l_dir" "$l_bin" "$inf" "$rtype" || true
            fi
        fi
        return "$l_rc"
    else
        echo "[ERROR] Executable binary not found in: $l_dir" >&2
        return 1
    fi
}


# Standalone-source compatibility: load split launcher submodules when sourced directly outside bin/gamectl
if [ -z "${GAMECTL_BUNDLED:-}" ] && [ -n "${BASH_SOURCE[0]:-}" ]; then
    _launcher_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd)"
    for _launcher_sub in 51_remote_sync.sh 52_inject_runtime.sh; do
        if [ -f "$_launcher_dir/$_launcher_sub" ]; then
            # shellcheck source=/dev/null
            source "$_launcher_dir/$_launcher_sub"
        fi
    done
    unset _launcher_dir _launcher_sub
fi

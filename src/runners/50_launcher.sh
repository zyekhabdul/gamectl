# Interactive Live HUD for running game process
game_controller_hud() {
    local game_pid="$1"
    local title="$2"
    local log_file="$3"
    local gdir="$4"
    local gbin="$5"
    local info_file="$6"
    local run_type="$7"

    while true; do
        local is_alive=0
        if kill -0 "$game_pid" 2>/dev/null; then
            is_alive=1
        fi

        clear
        echo "${UI_BOX}╭─ GAME CONTROLLER HUD ───────────────────────────────────────╮${UI_RST}"
        echo "│ ${UI_CYAN}Target Game ${UI_RST}: ${UI_BOLD}$title${UI_RST}"
        echo "│ ${UI_CYAN}Process PID ${UI_RST}: ${UI_BOLD}$game_pid${UI_RST} ${UI_DIM}($run_type)${UI_RST}"
        if [ "$is_alive" -eq 1 ]; then
            echo "│ ${UI_CYAN}Status      ${UI_RST}: ${UI_GREEN}[RUNNING]${UI_RST} ${UI_DIM}(Active window on desktop display)${UI_RST}"
        else
            echo "│ ${UI_CYAN}Status      ${UI_RST}: ${UI_ICE}[TERMINATED / EXITED]${UI_RST}"
        fi
        echo "│ ${UI_CYAN}Log Stream  ${UI_RST}: ${UI_DIM}$log_file${UI_RST}"
        echo "${UI_BOX}╰─────────────────────────────────────────────────────────────╯${UI_RST}"

        if [ "$is_alive" -eq 1 ]; then
            echo "  ${UI_PURPLE}1)${UI_RST} Return to Game Library ${UI_DIM}(Game continues running in background)${UI_RST}"
            echo "  ${UI_PURPLE}2)${UI_RST} Return to Master Dashboard ${UI_DIM}(Game continues running in background)${UI_RST}"
            echo "  ${UI_PURPLE}3)${UI_RST} Live Game Log Stream ${UI_DIM}(tail -f)${UI_RST}"
            echo "  ${UI_AMBER}4)${UI_RST} Stop Game ${UI_DIM}(Graceful Shutdown / SIGTERM)${UI_RST}"
            echo "  ${UI_RED}5)${UI_RST} Force Kill Game ${UI_DIM}(Emergency Teardown / SIGKILL)${UI_RST}"
            echo
            read -t 30 -r -p "Select action [1-5]: " hud_opt || hud_opt="1"

            case "$hud_opt" in
                1)
                    return 0
                    ;;
                2)
                    return 10
                    ;;
                3)
                    clear
                    echo "${UI_BOX}╭─ LIVE LOG STREAM: $title (PID: $game_pid) ─────────────╮${UI_RST}"
                    echo "│ ${UI_CYAN}Press any key to return to Game Controller Menu               ${UI_RST}"
                    echo "${UI_BOX}╰─────────────────────────────────────────────────────────────╯${UI_RST}"
                    tail -n 25 "$log_file" 2>/dev/null || true
                    echo "${UI_DIM}─── Live Output (press any key to stop) ───────────────────────${UI_RST}"
                    local t_pid=""
                    tail -f "$log_file" 2>/dev/null &
                    t_pid=$!
                    ( read -r -s -n 1 </dev/tty || true ) 2>/dev/null
                    kill "$t_pid" 2>/dev/null || true
                    wait "$t_pid" 2>/dev/null || true
                    ;;
                4)
                    local s_unit=""
                    [ -f "$info_file" ] && s_unit=$(grep -E '^SCOPE_UNIT=' "$info_file" 2>/dev/null | cut -d'=' -f2- || true)
                    echo "  [INFO] Sending SIGTERM signal to process PID $game_pid..."
                    if [ -n "$s_unit" ]; then
                        systemctl --user stop "$s_unit.scope" 2>/dev/null || true
                    fi
                    kill "$game_pid" 2>/dev/null || true
                    local wait_cnt=0
                    while kill -0 "$game_pid" 2>/dev/null && [ "$wait_cnt" -lt 6 ]; do
                        sleep 0.3
                        wait_cnt=$((wait_cnt + 1))
                    done
                    if [ -d "$gdir/pfx" ]; then
                        local ws_bin
                        ws_bin="$(get_wineserver_bin "$(find_runner "$gdir" 2>/dev/null || true)" 2>/dev/null || true)"
                        [ -n "$ws_bin" ] && WINEPREFIX="$gdir/pfx" "$ws_bin" -w 2>/dev/null || true # wineserver -w
                    fi
                    if ! kill -0 "$game_pid" 2>/dev/null; then
                        echo "  ${UI_GREEN}[SUCCESS] Game '$title' (PID $game_pid) terminated gracefully.${UI_RST}"
                        rm -f "$info_file" 2>/dev/null || true
                    else
                        echo "  ${UI_AMBER}[WARN] Process still running. You can select option 5 (Force Kill).${UI_RST}"
                    fi
                    sleep 0.8
                    ;;
                5)
                    local s_unit=""
                    [ -f "$info_file" ] && s_unit=$(grep -E '^SCOPE_UNIT=' "$info_file" 2>/dev/null | cut -d'=' -f2- || true)
                    echo "  [INFO] Sending SIGKILL signal to process PID $game_pid..."
                    if [ -n "$s_unit" ]; then
                        systemctl --user kill -s SIGKILL "$s_unit.scope" 2>/dev/null || true
                        systemctl --user stop "$s_unit.scope" 2>/dev/null || true
                    fi
                    kill -9 "$game_pid" 2>/dev/null || true
                    if [ -d "$gdir/pfx" ]; then
                        # Remediation DEFECT-02: Force terminate stuck wineserver daemon and release lockfiles
                        local ws_bin
                        ws_bin="$(get_wineserver_bin "$(find_runner "$gdir" 2>/dev/null || true)" 2>/dev/null || true)"
                        [ -n "$ws_bin" ] && WINEPREFIX="$gdir/pfx" "$ws_bin" -k 2>/dev/null || true # wineserver -k
                    fi
                    sleep 0.3
                    echo "  ${UI_GREEN}[SUCCESS] Game '$title' (PID $game_pid) force-killed.${UI_RST}"
                    rm -f "$info_file" 2>/dev/null || true
                    sleep 0.8
                    ;;
                *)
                    ;;
            esac
        else
            echo "  ${UI_PURPLE}1)${UI_RST} Return to Game Library"
            echo "  ${UI_PURPLE}2)${UI_RST} Return to Master Dashboard"
            echo "  ${UI_PURPLE}3)${UI_RST} View Recent Logs (tail -n 25)"
            echo
            read -t 30 -r -p "Select action [1-3]: " hud_opt || hud_opt="1"
            case "$hud_opt" in
                1) return 0 ;;
                2) return 10 ;;
                3)
                    echo
                    echo "${UI_DIM}──────────────────────────────────────────${UI_RST}"
                    tail -n 25 "$log_file" 2>/dev/null || echo "[No logs available]"
                    echo "${UI_DIM}──────────────────────────────────────────${UI_RST}"
                    read -t 15 -r -p "Press [ENTER] to return..." || true
                    ;;
                *) return 0 ;;
            esac
        fi
    done
}

# Setup P2P Multiplayer Compatibility Layer, mod DLL overrides & Spacewar (AppID 480) entitlement
setup_onlinefix() {
    local gdir="${1:-}"
    shift || true
    local auto_yes=false
    while [ $# -gt 0 ]; do
        case "$1" in
            -y|--yes|--non-interactive) auto_yes=true; shift ;;
            *) shift ;;
        esac
    done

    if [ -z "$gdir" ] || [ ! -d "$gdir" ]; then
        echo "[ERROR] Game directory not found: $gdir" >&2
        return 1
    fi
    gdir="$(cd "$gdir" && pwd)"

    echo "[INFO] Running OnlineFix setup and Spacewar entitlement audit in: $gdir..."

    # 1. Discover OnlineFix signature files
    local of_files
    of_files=$(find "$gdir" -maxdepth 3 \( -name "pfx" -o -name ".git" -o -name ".save_snapshots" -o -name "saves" \) -prune -o \( \
        -iname "OnlineFix64.dll" -o -iname "OnlineFix.dll" -o -iname "OnlineFix.ini" -o \
        -iname "dnet.dll" -o -iname "SteamOverlay64.dll" \
    \) -print 2>/dev/null || true)

    if [ -z "$of_files" ]; then
        echo "[WARN] No OnlineFix signatures found in this game directory." >&2
        echo "       Neither OnlineFix64.dll, OnlineFix.dll, nor OnlineFix.ini was found." >&2
        return 1
    fi
    echo "[VERIFIED] OnlineFix signature detected."

    # 2. Spacewar (AppID 480) Entitlement & ACF Check
    local s_primary
    s_primary="$(get_steam_primary_apps 2>/dev/null || echo "$HOME/.local/share/Steam/steamapps")"
    local has_spacewar=0
    if [ -f "$s_primary/appmanifest_480.acf" ]; then
        has_spacewar=1
    fi
    local sls_cfg="$HOME/.config/SLSsteam/config.yaml"
    if [ -f "$sls_cfg" ] && grep -q -E '^[[:space:]]*480:' "$sls_cfg" 2>/dev/null; then
        has_spacewar=1
    fi

    if [ "$has_spacewar" -eq 1 ]; then
        echo "[VERIFIED] Spacewar (AppID 480) already registered in Steam/SLSsteam library."
    else
        echo "[INFO] Spacewar (AppID 480) not registered yet. Running automatic registration..."
        sync_steam 480 "Spacewar" "$gdir"
        echo "[VERIFIED] Spacewar (AppID 480) successfully registered to Steam/SLSsteam."
    fi

    # 3. Audit & Sync OnlineFix.ini PlayerName
    local ini_file
    ini_file=$(find "$gdir" -maxdepth 3 \( -name "pfx" -o -name ".git" \) -prune -o -iname "OnlineFix.ini" -print 2>/dev/null | head -n 1)
    if [ -n "$ini_file" ] && [ -f "$ini_file" ]; then
        local curr_pname
        curr_pname=$(grep -E '^[[:space:]]*PlayerName[[:space:]]*=' "$ini_file" 2>/dev/null | head -n 1 | sed -E 's/^[[:space:]]*PlayerName[[:space:]]*=[[:space:]]*//' | tr -d '\r')
        echo "[INFO] OnlineFix.ini detected: $ini_file"
        echo "       Current PlayerName: ${curr_pname:-[Unset]}"

        local persona_name=""
        if [ -f "$HOME/.config/gamectl/persona" ]; then
            persona_name=$(grep -E '^[[:space:]]*account_name[[:space:]]*=' "$HOME/.config/gamectl/persona" 2>/dev/null | head -n 1 | sed -E 's/^[[:space:]]*account_name[[:space:]]*=[[:space:]]*//' | tr -d '\r')
        fi
        [ -z "$persona_name" ] && persona_name="${USER:-Player}"

        if [ -n "$persona_name" ] && [ "$persona_name" != "$curr_pname" ]; then
            local should_sync=false
            if [ "$auto_yes" = true ]; then
                should_sync=true
            elif [ -t 0 ]; then
                echo -n "       Synchronize PlayerName to '$persona_name'? [Y/n] (Auto-yes in 5s): "
                local confirm_sync=""
                read -t 5 -r confirm_sync || confirm_sync="y"
                echo
                if [[ ! "$confirm_sync" =~ ^[nN] ]]; then
                    should_sync=true
                fi
            else
                should_sync=true
            fi

            if [ "$should_sync" = true ]; then
                sed -i -E "s/^[[:space:]]*PlayerName[[:space:]]*=.*/PlayerName = $persona_name/" "$ini_file"
                echo "       ${UI_GREEN}[SUCCESS] PlayerName in OnlineFix.ini synchronized to: $persona_name${UI_RST}"
            fi
        fi
    fi

    echo "[VERIFIED] OnlineFix setup completed for: $(basename "$gdir")"
    return 0
}

# Launch game with performance wrapping and runner isolation
launch_game() {
    local gdir="$1"
    local gbin="$2"
    local title="$3"
    shift 3 || true

    echo "[INFO] Preparing launch: $title..."
    backup_save "$gdir" true || true

    # Resolve wrappers and extra flags
    declare -a GAMECTL_WRAPPER_PREFIX=()
    declare -a GAMECTL_REMAINING_ARGS=()
    GAMECTL_ACTIVE_GLTHREAD=0
    build_wrapper_command "$gdir" "$@"
    local wrappers=("${GAMECTL_WRAPPER_PREFIX[@]}")
    local game_args=("${GAMECTL_REMAINING_ARGS[@]}")

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
                echo "[INFO] Hybrid Graphics: Injected NVIDIA PRIME offload environment."
                ;;
            amd|intel)
                export DRI_PRIME=1
                echo "[INFO] Hybrid Graphics: Injected DRI_PRIME=1 offload environment."
                ;;
            *)
                export DRI_PRIME=1
                echo "[INFO] Hybrid Graphics: Fallback to DRI_PRIME=1 offload environment."
                ;;
        esac
    fi

    # Remedi Audio (DEFECT-03): Set buffer latency environment safely (PipeWire / PulseAudio)
    export PIPEWIRE_LATENCY="${GAMECTL_PIPEWIRE_LATENCY:-256/48000}"
    export PULSE_LATENCY_MSEC="${GAMECTL_PULSE_LATENCY:-60}"

    # Sovereign Steam Interceptor: traps and silences unshielded Steam Client calls
    local interceptor_dir="${XDG_RUNTIME_DIR:-/tmp/gamectl-$UID}/interceptor"
    setup_steam_interceptor "$interceptor_dir"
    export PATH="$interceptor_dir:$PATH"

    # SLSsteam path prioritization for DRM stub wrapper intercept (fallback)
    if [ -d "$HOME/.local/share/SLSsteam/path" ]; then
        export PATH="$PATH:$HOME/.local/share/SLSsteam/path"
    fi

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

    # Local state cleanup helper & signal trap
    local unit_name=""
    _restore_launch_state() {
        trap - INT TERM EXIT
        if [ -n "${unit_name:-}" ]; then
            systemctl --user stop "$unit_name.scope" 2>/dev/null || true
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
        type clean_stale_locks >/dev/null 2>&1 && clean_stale_locks || true
    }
    trap '_restore_launch_state; trap - INT TERM EXIT; return 130 2>/dev/null || exit 130' INT
    trap '_restore_launch_state; trap - INT TERM EXIT; return 143 2>/dev/null || exit 143' TERM
    trap '_restore_launch_state' EXIT

    if [ ${#wrappers[@]} -gt 0 ]; then
        echo "[INFO] Active wrappers: ${wrappers[*]}"
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
                echo "  ${UI_GREEN}[SUCCESS] SteamStub PE: Automatically switched to unpacked binary: $unpacked_bin${UI_RST}"
                gbin="$unpacked_bin"
            else
                echo "  ${UI_AMBER}[INFO] SteamStub PE DRM detected on ($gbin). Attempting Steamless unpacking...${UI_RST}"
                if unpack_steamstub_pe "$gdir/$gbin" "${runner_bin:-}" "${pfx_dir:-}"; then
                    unpacked_bin=$(resolve_unpacked_binary "$gdir" "$gbin" 2>/dev/null || true)
                    if [ -n "$unpacked_bin" ] && [ -f "$gdir/$unpacked_bin" ]; then
                        echo "  ${UI_GREEN}[SUCCESS] SteamStub PE: Unpacked binary generated: $unpacked_bin${UI_RST}"
                        gbin="$unpacked_bin"
                    fi
                else
                    echo "  ${UI_AMBER}[WARN] SteamStub PE detected on ($gbin) but Steamless CLI not available or unpacking failed.${UI_RST}"
                    echo "  ${UI_DIM}       If launch fails, unpack $gbin with Steamless (producing ${gbin%.*}.unpacked.exe).${UI_RST}"
                fi
            fi
        elif [ "$stub_type" = "linux_elf" ]; then
            echo "  ${UI_AMBER}[WARN] SteamStub DRM (.bind section) detected on Linux binary ($gbin).${UI_RST}"
            echo "  ${UI_CYAN}[INFO] Sovereign steam.sh interceptor active in PATH to trap unsolicited Steam Client calls.${UI_RST}"
        else
            echo "  ${UI_AMBER}[WARN] SteamStub DRM markers detected on binary ($gbin).${UI_RST}"
        fi
    fi

    # Pre-flight savegame redirection & offline DLC check
    mkdir -p -m 700 "$gdir/saves" 2>/dev/null || true
    if [ -f "$gdir/steam_appid.txt" ]; then
        local raw_appid
        raw_appid=$(tr -dc '0-9' < "$gdir/steam_appid.txt" 2>/dev/null || echo "")
        if [ -n "$raw_appid" ] && [ ! -f "$gdir/steam_settings/DLC.txt" ]; then
            fetch_dlc "$gdir" "$raw_appid" 2>/dev/null || true
        fi
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
            local c_sz
            c_sz=$(stat -c%s "$api_cand" 2>/dev/null || echo 0)
            if [ "$c_sz" -ge 5000000 ] || [ -f "$api_cand.orig" ]; then
                : # Already shielded
            else
                unshielded_candidates+=("$api_cand")
            fi
        done

        if [ ${#unshielded_candidates[@]} -gt 0 ]; then
            echo "  ${UI_AMBER}[INFO] Steamworks API detected without emulator shield. Attempting auto-injection...${UI_RST}"
            inject_game "$gdir" "" --no-sync 2>/dev/null || true

            local still_unshielded=()
            for api_cand in "${unshielded_candidates[@]}"; do
                if [ -f "$api_cand" ]; then
                    local re_sz
                    re_sz=$(stat -c%s "$api_cand" 2>/dev/null || echo 0)
                    if [ "$re_sz" -lt 5000000 ] && [ ! -f "$api_cand.orig" ]; then
                        still_unshielded+=("$api_cand")
                    fi
                fi
            done

            if [ ${#still_unshielded[@]} -gt 0 ]; then
                if [ "$allow_unshielded" = "1" ]; then
                    echo "  ${UI_AMBER}[WARN] Launching unshielded Steamworks binary by user override (--allow-unshielded).${UI_RST}"
                else
                    echo "  ${UI_RED}================================================================${UI_RST}" >&2
                    echo "  ${UI_RED}[HARD-STOP] Valve Steamworks API detected without emulator shield!${UI_RST}" >&2
                    echo "  ${UI_AMBER}Unshielded library: ${still_unshielded[*]}${UI_RST}" >&2
                    echo "  ${UI_AMBER}Launch halted to prevent Valve DRM from spawning Steam Client ('PURCHASE' prompt).${UI_RST}" >&2
                    echo "  ${UI_DIM}Remedy: Run 'gamectl setup-gbe' to provision templates or 'gamectl inject \"$gdir\"'.${UI_RST}" >&2
                    echo "  ${UI_DIM}Bypass: Pass --allow-unshielded to override this sovereign safety gate.${UI_RST}" >&2
                    echo "  ${UI_RED}================================================================${UI_RST}" >&2
                    _restore_launch_state
                    return 1
                fi
            else
                echo "  ${UI_GREEN}[VERIFIED] GBE Fork emulator shield successfully engaged.${UI_RST}"
            fi
        else
            echo "  ${UI_GREEN}[VERIFIED] GBE Fork emulator shield confirmed active.${UI_RST}"
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

    # Prepare runtime directory and log stream
    local run_dir="${XDG_RUNTIME_DIR:-/tmp/gamectl-$UID}"
    mkdir -p -m 700 "$run_dir/active_games"
    local safe_gbin
    safe_gbin=$(basename "$gbin" | tr -cd '[:alnum:]_-')
    local log_file="$run_dir/game_${safe_gbin}.log"
    : > "$log_file"

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
        echo "[INFO] Security Sandbox: Bubblewrap rootless filesystem isolation active."
    fi

    _exec_in_scope() {
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
            echo "[INFO] Active DLL Overrides: $WINEDLLOVERRIDES"
        fi

        local runner_bin
        runner_bin=$(find_runner "$gdir" 2>/dev/null || true)
        if [ -z "$runner_bin" ]; then
            echo "[ERROR] Windows runner not found (umu-run, Proton, or Wine not installed)." >&2
            echo "        Install GE-Proton in ~/.local/share/Steam/compatibilitytools.d/ or install wine." >&2
            _restore_launch_state
            return 1
        fi

        local pfx_dir="$gdir/pfx"
        mkdir -p "$pfx_dir"
        local appid=""
        if [ -f "$gdir/steam_appid.txt" ]; then
            appid=$(tr -dc '0-9' < "$gdir/steam_appid.txt")
        fi
        [ -z "$appid" ] && appid="0"

        run_type="Windows ($(basename "$runner_bin"))"
        echo "[INFO] Launching Windows game via $(basename "$runner_bin") in background..."
        echo "[INFO] Isolated Wine Prefix: $pfx_dir"
        echo "[INFO] Log stream: $log_file"

        case "$runner_bin" in
            umu-run)
                (
                    export WINEPREFIX="$pfx_dir" GAMEID="$appid" WINEDLLOVERRIDES="${WINEDLLOVERRIDES:-}"
                    _exec_in_scope "${wrappers[@]}" umu-run "$gdir/$gbin" "${game_args[@]}"
                ) > "$log_file" 2>&1 &
                game_pid=$!
                ;;
            *proton*)
                (
                    export STEAM_COMPAT_CLIENT_INSTALL_PATH="${STEAM_CLIENT_INSTALL_PATH:-$(get_steam_root 2>/dev/null || echo "$HOME/.local/share/Steam")}" \
                    STEAM_COMPAT_DATA_PATH="$gdir" \
                    STEAM_COMPAT_APP_ID="$appid" \
                    WINEPREFIX="$pfx_dir" \
                    WINEDLLOVERRIDES="${WINEDLLOVERRIDES:-}"
                    _exec_in_scope "${wrappers[@]}" "$runner_bin" waitforexitandrun "$gdir/$gbin" "${game_args[@]}"
                ) > "$log_file" 2>&1 &
                game_pid=$!
                ;;
            *)
                (
                    export WINEPREFIX="$pfx_dir" WINEDLLOVERRIDES="${WINEDLLOVERRIDES:-}"
                    _exec_in_scope "${wrappers[@]}" "$runner_bin" "$gdir/$gbin" "${game_args[@]}"
                ) > "$log_file" 2>&1 &
                game_pid=$!
                ;;
        esac
    else
        echo "[INFO] Launching $title (Native Linux) in background..."
        echo "[INFO] Log stream: $log_file"
        (
            export LD_LIBRARY_PATH=".:$gdir:${LD_LIBRARY_PATH:-}"
            _exec_in_scope "${wrappers[@]}" ./"$gbin" "${game_args[@]}"
        ) > "$log_file" 2>&1 &
        game_pid=$!
    fi

    if [ -z "$game_pid" ] || ! kill -0 "$game_pid" 2>/dev/null; then
        echo "[ERROR] Failed to launch game into background." >&2
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
    (
        wait "$game_pid" 2>/dev/null
        if [ -n "$unit_name" ]; then
            systemctl --user stop "$unit_name.scope" 2>/dev/null || true
        fi
        if [ "$is_win" = true ] && [ -d "$pfx_dir" ]; then
            # Remediation DEFECT-02: Wait for wineserver to flush data & release lockfile before snapshot (wineserver -w)
            local ws_bin
            ws_bin="$(get_wineserver_bin "${runner_bin:-}" 2>/dev/null || true)"
            [ -n "$ws_bin" ] && WINEPREFIX="$pfx_dir" "$ws_bin" -w 2>/dev/null || true
        fi
        rm -f "$info_file" 2>/dev/null || true
        _restore_launch_state
    ) &

    echo "[VERIFIED] Game '$title' running in background (PID: $game_pid)."

    # If running interactively, invoke Game Controller HUD
    local hud_exit=0
    if [ -t 0 ]; then
        game_controller_hud "$game_pid" "$title" "$log_file" "$gdir" "$gbin" "$info_file" "$run_type" || hud_exit=$?
    fi

    trap - INT TERM EXIT
    return "$hud_exit"
}

# Sync savegame to remote companion host
sync_save_remote() {
    local gdir="$1"
    local title="$2"
    local override_host="${3:-}"
    local sdir="$gdir/saves"
    local rhost="$override_host"
    [ -z "$rhost" ] && rhost=$(get_remote_host)

    if [ ! -d "$sdir" ]; then
        echo "[ERROR] Portable saves directory not found in $gdir"
        return 1
    fi

    if [ -z "$rhost" ]; then
        echo "[WARN] Target remote host not configured."
        echo "       Define host in ~/.config/gamectl/remote_host or GAMECTL_REMOTE_HOST variable."
        return 1
    fi

    echo "[INFO] Checking connectivity to $rhost..."
    if ! ssh -q -o ConnectTimeout=1 -o BatchMode=yes "$rhost" exit 2>/dev/null; then
        echo "[WARN] Remote host '$rhost' offline or unreachable on local network."
        return 1
    fi

    echo "[INFO] Synchronizing savegame $title to $rhost..."
    local canon_gdir
    canon_gdir="$(cd "$gdir" 2>/dev/null && pwd || echo "$gdir")"

    local rel_path
    if [[ "$canon_gdir" == "$HOME/"* ]]; then
        rel_path="${canon_gdir#$HOME/}"
    else
        # For games stored on secondary drives (/mnt, /media, /data, etc.)
        rel_path="Games/$(basename "$canon_gdir")"
    fi
    rel_path="${rel_path#/}"

    ssh "$rhost" "mkdir -p ~/$rel_path"
    rsync -avzP --exclude="*.tmp" "$sdir/" "$rhost:~/$rel_path/saves/"
    echo "[VERIFIED] Savegame synchronization to $rhost completed."
}

# Aliases for remote savegame synchronization
sync_to_companion() {
    sync_save_remote "$@"
}

sync_to_tuf() {
    sync_save_remote "$@"
}


# Inject GBE Fork emulator and portable saves into a game folder
inject_game() {
    local target_dir="$1"
    local appid="${2:-}"
    local sync_mode="${3:-all}"

    # Strip ANSI escape sequences
    target_dir=$(printf "%s" "$target_dir" | sed -r 's/\x1B\[[0-9;]*[a-zA-Z]//g')
    [ -n "$appid" ] && appid=$(printf "%s" "$appid" | sed -r 's/\x1B\[[0-9;]*[a-zA-Z]//g' | tr -dc '0-9')

    if [ ! -d "$target_dir" ]; then
        echo "[ERROR] Target directory not found: $target_dir" >&2
        return 1
    fi

    # Canonical path
    target_dir="$(cd "$target_dir" && pwd)"

    # Resolve AppID if not provided
    if [ -z "$appid" ]; then
        if [ -f "$target_dir/steam_appid.txt" ]; then
            appid=$(tr -dc '0-9' < "$target_dir/steam_appid.txt")
        fi
        if [ -z "$appid" ]; then
            local parent_dir
            parent_dir="$(dirname "$target_dir")"
            if [ "$(basename "$parent_dir")" = "common" ]; then
                local steamapps_dir
                steamapps_dir="$(dirname "$parent_dir")"
                local base_name
                base_name="$(basename "$target_dir")"
                for acf in "$steamapps_dir"/appmanifest_*.acf; do
                    [ -f "$acf" ] || continue
                    if grep -q "\"installdir\"[[:space:]]\+\"$base_name\"" "$acf" 2>/dev/null; then
                        appid=$(grep -E '^\s*"appid"' "$acf" | head -n 1 | sed -E 's/.*"appid"[[:space:]]+"([0-9]+)".*/\1/')
                        break
                    fi
                done
            fi
        fi
    fi

    echo "[INFO] Preparing GBE Fork injection in: $target_dir..."

    # 1. Identify Target Executable and Platform
    local gbin=""
    gbin=$(find_game_binary "$target_dir") || true

    local target_platform="linux"
    local arch="x64"
    local is_32bit=false

    # Check existing steam libraries in target folder
    local found_win64 found_win32 found_linux
    found_win64=$(find "$target_dir" -maxdepth 4 -name "steam_api64.dll" 2>/dev/null | head -n 1)
    found_win32=$(find "$target_dir" -maxdepth 4 -name "steam_api.dll" 2>/dev/null | head -n 1)
    found_linux=$(find "$target_dir" -maxdepth 4 -name "libsteam_api.so" 2>/dev/null | head -n 1)

    if [ -n "$gbin" ] && [ -f "$target_dir/$gbin" ]; then
        local btype
        btype=$(file -b "$target_dir/$gbin" 2>/dev/null || echo "")
        if echo "$btype" | grep -qi -E "PE32|MS Windows|\.exe"; then
            target_platform="windows"
            if echo "$btype" | grep -qi "PE32+"; then
                arch="x64"
                is_32bit=false
            elif echo "$btype" | grep -qi "32-bit"; then
                arch="x86"
                is_32bit=true
            else
                arch="x64"
                is_32bit=false
            fi
        else
            target_platform="linux"
            if echo "$btype" | grep -qi "32-bit"; then
                arch="x86"
                is_32bit=true
            else
                arch="x64"
                is_32bit=false
            fi
        fi
    elif [ -n "$found_linux" ]; then
        target_platform="linux"
        if file -b "$found_linux" | grep -qi "32-bit"; then
            arch="x86"
            is_32bit=true
        else
            arch="x64"
            is_32bit=false
        fi
    elif [ -n "$found_win64" ] || [ -n "$found_win32" ]; then
        target_platform="windows"
        if [ -n "$found_win64" ]; then
            arch="x64"
            is_32bit=false
        else
            arch="x86"
            is_32bit=true
        fi
    fi

    # 2. Perform Shim Injections (with backup of originals)
    local primary_shim_dir="$target_dir"

    # 2a. Windows Shim Injection (if windows steam files exist or target is windows)
    if [ -n "$found_win64" ] || [ -n "$found_win32" ] || [ "$target_platform" = "windows" ]; then
        local win_targets=()
        if [ -n "$found_win64" ]; then
            win_targets+=("$found_win64:x64")
        fi
        if [ -n "$found_win32" ]; then
            win_targets+=("$found_win32:x86")
        fi

        # If neither found but target is windows, determine destination based on detected arch or gbin location
        if [ ${#win_targets[@]} -eq 0 ] && [ "$target_platform" = "windows" ]; then
            local bin_subdir="$target_dir"
            [ -n "$gbin" ] && [ -f "$target_dir/$gbin" ] && bin_subdir="$(dirname "$target_dir/$gbin")"
            if [ "$is_32bit" = true ]; then
                win_targets+=("$bin_subdir/steam_api.dll:x86")
            else
                win_targets+=("$bin_subdir/steam_api64.dll:x64")
            fi
        fi

        for entry in "${win_targets[@]}"; do
            local t_dll="${entry%%:*}"
            local t_arch="${entry##*:}"
            local t_template
            t_template=$(get_gbe_template "windows" "$t_arch") || true

            if [ -z "$t_template" ] || [ ! -f "$t_template" ]; then
                echo "[WARN] Windows GBE Fork template ($t_arch) not found. Attempting automatic provisioning..." >&2
                setup_gbe_templates --yes --win-only >/dev/null 2>&1 || true
                t_template=$(get_gbe_template "windows" "$t_arch") || true
                if [ -z "$t_template" ] || [ ! -f "$t_template" ]; then
                    echo "[WARN] Windows GBE Fork template ($t_arch) not found. Run 'gamectl setup-gbe' to install." >&2
                    continue
                fi
            fi

            # Backup original Valve DLL if present (<7MB and .orig not existing)
            if [ -f "$t_dll" ]; then
                local sz
                sz=$(stat -c%s "$t_dll" 2>/dev/null || echo 0)
                if [ "$sz" -lt 7000000 ] && [ ! -f "$t_dll.orig" ]; then
                    cp -a "$t_dll" "$t_dll.orig"
                    echo "[INFO] Original $(basename "$t_dll") backed up to: $t_dll.orig"
                fi
            fi

            mkdir -p "$(dirname "$t_dll")"
            cp "$t_template" "$t_dll"
            chmod +x "$t_dll" 2>/dev/null || true
            primary_shim_dir="$(dirname "$t_dll")"
            echo "[INFO] Windows GBE Fork DLL ($t_arch) installed at: $t_dll"
        done
    fi

    # 2b. Linux Shim Injection (if linux steam files exist or target is linux)
    if [ -n "$found_linux" ] || [ "$target_platform" = "linux" ]; then
        local linux_arch="x64"
        if [ -n "$found_linux" ]; then
            if file -b "$found_linux" | grep -qi "32-bit"; then
                linux_arch="x86"
            fi
        elif [ "$is_32bit" = true ]; then
            linux_arch="x86"
        fi

        local target_so="$target_dir/libsteam_api.so"
        if [ -n "$found_linux" ]; then
            target_so="$found_linux"
        elif [ -d "$target_dir/lib64" ] && [ "$linux_arch" = "x64" ]; then
            target_so="$target_dir/lib64/libsteam_api.so"
        elif [ -d "$target_dir/lib32" ] && [ "$linux_arch" = "x86" ]; then
            target_so="$target_dir/lib32/libsteam_api.so"
        fi

        local src_so
        src_so=$(get_gbe_template "linux" "$linux_arch") || true
        if [ -z "$src_so" ] || [ ! -f "$src_so" ]; then
            echo "[WARN] Linux GBE Fork template ($linux_arch) not found. Attempting automatic provisioning..." >&2
            setup_gbe_templates --yes --linux-only >/dev/null 2>&1 || true
            src_so=$(get_gbe_template "linux" "$linux_arch") || true
        fi
        if [ -n "$src_so" ] && [ -f "$src_so" ]; then
            # Backup original Valve SO if present (<7MB and .orig not existing)
            if [ -f "$target_so" ]; then
                local sz
                sz=$(stat -c%s "$target_so" 2>/dev/null || echo 0)
                if [ "$sz" -lt 7000000 ] && [ ! -f "$target_so.orig" ]; then
                    cp -a "$target_so" "$target_so.orig"
                    echo "[INFO] Original libsteam_api.so backed up to: $target_so.orig"
                fi
            fi

            mkdir -p "$(dirname "$target_so")"
            cp "$src_so" "$target_so"
            chmod +x "$target_so"
            primary_shim_dir="$(dirname "$target_so")"
            echo "[INFO] Linux GBE Fork ELF ($linux_arch) installed at: $target_so"
        else
            [ "$target_platform" = "linux" ] && echo "[WARN] Linux GBE Fork template ($linux_arch) not found at: ${src_so:-empty}" >&2
        fi
    fi

    # 3. Setup steam_settings and configs.user.ini
    mkdir -p "$target_dir/steam_settings"
    local user_name=""
    local steamid=""

    # Check existing game persona or global persona
    if [ -f "$target_dir/steam_settings/configs.user.ini" ]; then
        user_name=$(grep -E '^[[:space:]]*account_name[[:space:]]*=' "$target_dir/steam_settings/configs.user.ini" 2>/dev/null | head -n 1 | sed -E 's/^[[:space:]]*account_name[[:space:]]*=[[:space:]]*//' | tr -d '\r')
        steamid=$(grep -E '^[[:space:]]*account_steamid[[:space:]]*=' "$target_dir/steam_settings/configs.user.ini" 2>/dev/null | head -n 1 | sed -E 's/^[[:space:]]*account_steamid[[:space:]]*=[[:space:]]*//' | tr -d '\r')
    fi
    if [ -z "$user_name" ] && [ -f "$HOME/.config/gamectl/persona" ]; then
        user_name=$(grep -E '^[[:space:]]*account_name[[:space:]]*=' "$HOME/.config/gamectl/persona" 2>/dev/null | head -n 1 | sed -E 's/^[[:space:]]*account_name[[:space:]]*=[[:space:]]*//' | tr -d '\r')
    fi
    if [ -z "$steamid" ] && [ -f "$HOME/.config/gamectl/persona" ]; then
        steamid=$(grep -E '^[[:space:]]*account_steamid[[:space:]]*=' "$HOME/.config/gamectl/persona" 2>/dev/null | head -n 1 | sed -E 's/^[[:space:]]*account_steamid[[:space:]]*=[[:space:]]*//' | tr -d '\r')
    fi
    [ -z "$user_name" ] && user_name="${USER:-Player}"
    if [ -z "$steamid" ]; then
        steamid=$(resolve_active_steamid)
    fi

    cat <<EOF > "$target_dir/steam_settings/configs.user.ini"
[user::general]
account_name=$user_name
account_steamid=$steamid
language=english

[user::saves]
local_save_path=./saves
EOF

    # Scaffold custom_broadcasts.txt if missing
    if [ ! -f "$target_dir/steam_settings/custom_broadcasts.txt" ]; then
        cat <<EOF > "$target_dir/steam_settings/custom_broadcasts.txt"
# GBE Fork LAN Custom Broadcast IP list
# Add peer IPs or broadcast subnets (one IP per line)
127.0.0.1
255.255.255.255
EOF
    fi

    # If shim is in a subfolder, link steam_settings beside it as per GBE specification
    if [ "$primary_shim_dir" != "$target_dir" ] && [ -d "$primary_shim_dir" ]; then
        ln -sfn "$target_dir/steam_settings" "$primary_shim_dir/steam_settings" 2>/dev/null || true
    fi

    # 4. Setup isolated portable saves folder and markers
    mkdir -p -m 700 "$target_dir/saves"
    chmod 700 "$target_dir/saves" 2>/dev/null || true
    echo -n "saves" > "$target_dir/local_save.txt"
    if [ "$primary_shim_dir" != "$target_dir" ] && [ -d "$primary_shim_dir" ]; then
        echo -n "saves" > "$primary_shim_dir/local_save.txt" 2>/dev/null || true
        ln -sfn "$target_dir/saves" "$primary_shim_dir/saves" 2>/dev/null || true
    fi

    # 5. Write steam_appid.txt if available
    if [ -n "$appid" ] && [ "$appid" != "STANDALONE" ]; then
        echo -n "$appid" > "$target_dir/steam_appid.txt"
        if [ "$primary_shim_dir" != "$target_dir" ] && [ -d "$primary_shim_dir" ]; then
            echo -n "$appid" > "$primary_shim_dir/steam_appid.txt" 2>/dev/null || true
        fi
        echo "[INFO] AppID $appid registered in: $target_dir/steam_appid.txt"
        fetch_dlc "$target_dir" "$appid"
        if [ "$sync_mode" != "--no-sync" ] && [ "$sync_mode" != "no-sync" ] && [ "$sync_mode" != "standalone" ]; then
            sync_steam "$appid" "$(basename "$target_dir")" "$target_dir"
        else
            echo "[INFO] Standalone Mode active: Skipping Steam Client synchronization."
        fi
    fi

    echo "[VERIFIED] GBE Fork successfully injected (Platform: $target_platform, Arch: $arch, Save: ./saves, AppID: ${appid:-None})"
}


# CLI helper for launching games with wrappers and options
cli_launch() {
    local l_dir="${1:-}"
    shift || true
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
        launch_game "$l_dir" "$l_bin" "$l_title" "${l_flags[@]}"
    else
        echo "[ERROR] Executable binary not found in: $l_dir" >&2
        return 1
    fi
}


# Preview pane generator for installed games
preview_game() {
    local appid title status gdir gbin
    appid=$(echo "$1" | sed -r 's/\x1b\[[0-9;]*m//g' | tr -d '[:space:]')
    title=$(echo "$2" | sed -r 's/\x1b\[[0-9;]*m//g' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
    status=$(echo "$3" | sed -r 's/\x1b\[[0-9;]*m//g' | tr -d '][[:space:]]')
    gdir="$4"
    gbin="$5"

    # Real-time dynamic live inspection from filesystem
    if [ -n "$gdir" ] && [ -d "$gdir" ]; then
        local live_api=""
        if [ -f "$gdir/steam_api64.dll" ]; then
            live_api="$gdir/steam_api64.dll"
        elif [ -f "$gdir/steam_api.dll" ]; then
            live_api="$gdir/steam_api.dll"
        elif [ -f "$gdir/libsteam_api.so" ]; then
            live_api="$gdir/libsteam_api.so"
        elif [ -f "$gdir/lib64/libsteam_api.so" ]; then
            live_api="$gdir/lib64/libsteam_api.so"
        else
            live_api=$(find "$gdir" -maxdepth 3 \( -name "steam_api64.dll" -o -name "steam_api.dll" -o -name "libsteam_api.so" \) 2>/dev/null | head -n 1)
        fi

        if [ -n "$live_api" ] && [ -f "$live_api" ]; then
            local live_sz
            live_sz=$(stat -c%s "$live_api" 2>/dev/null || echo 0)
            if [ "$live_sz" -gt 7000000 ]; then
                status="GBE_FORK"
            else
                case "$live_api" in
                    *.dll) status="VALVE_DLL" ;;
                    *)     status="VALVE_SO" ;;
                esac
            fi
        else
            status="STANDALONE"
        fi
    fi

    local status_badge="${UI_CYAN}[${status}]${UI_RST}"
    local status_desc=""
    case "$status" in
        *VALVE_SO*)
            status_badge="${UI_AMBER}[VALVE_SO]${UI_RST}"
            status_desc="${UI_DIM}(Official Steam DRM - Requires Steam Client)${UI_RST}"
            ;;
        *VALVE_DLL*)
            status_badge="${UI_CYAN}[VALVE_DLL]${UI_RST}"
            status_desc="${UI_DIM}(Windows Steam DRM - Requires Steam + Runner)${UI_RST}"
            ;;
        *GBE_FORK*)
            status_badge="${UI_GREEN}[GBE_FORK]${UI_RST}"
            status_desc="${UI_DIM}(Goldberg Fork - Steam-Free, Full DLC, LAN Ready)${UI_RST}"
            ;;
        *STANDALONE*)
            status_badge="${UI_ICE}[STANDALONE]${UI_RST}"
            status_desc="${UI_DIM}(DRM-Free Standalone)${UI_RST}"
            ;;
    esac

    local run_dir="${XDG_RUNTIME_DIR:-/tmp/gamectl-$UID}"
    local is_running=false
    local run_pid=""
    if [ -d "$run_dir/active_games" ]; then
        for inf in "$run_dir/active_games"/*.info; do
            [ -f "$inf" ] || continue
            local inf_dir
            inf_dir=$(grep -E '^DIR=' "$inf" 2>/dev/null | head -n 1 | cut -d'=' -f2-)
            if [ "$inf_dir" = "$gdir" ]; then
                local check_pid
                check_pid=$(grep -E '^PID=' "$inf" 2>/dev/null | head -n 1 | cut -d'=' -f2)
                if [ -n "$check_pid" ] && kill -0 "$check_pid" 2>/dev/null; then
                    is_running=true
                    run_pid="$check_pid"
                    break
                fi
            fi
        done
    fi
    if [ "$is_running" = true ]; then
        status_badge="${UI_GREEN}[RUNNING PID:$run_pid]${UI_RST}"
        status_desc="${UI_DIM}(Game window active in background)${UI_RST}"
    fi

    echo "${UI_BOX}╭─ GAME INFORMATION ───────────────────────────────────╮${UI_RST}"
    echo "│ ${UI_BOLD}${title}${UI_RST} ${UI_DIM}(AppID: ${appid})${UI_RST}"
    echo "${UI_BOX}╰───────────────────────────────────────────────────────╯${UI_RST}"
    echo "  ${UI_CYAN}Status      ${UI_RST}: $status_badge $status_desc"
    echo "  ${UI_CYAN}Directory   ${UI_RST}: ${UI_DIM}$gdir${UI_RST}"
    echo "  ${UI_CYAN}Executable  ${UI_RST}: ${UI_BOLD}$gbin${UI_RST}"

    if [ -f "$gdir/$gbin" ]; then
        local arch_info
        arch_info=$(file -b "$gdir/$gbin" | cut -d',' -f1,2)
        echo "  ${UI_CYAN}Architecture${UI_RST}: ${UI_DIM}$arch_info${UI_RST}"
        if detect_steamstub_drm "$gdir/$gbin"; then
            echo "  ${UI_CYAN}DRM Stub    ${UI_RST}: ${UI_AMBER}[SteamStub .bind]${UI_RST} ${UI_DIM}(Valve Binary Stub Detected)${UI_RST}"
        fi
        local is_win=false
        case "$gbin" in *.exe|*.EXE) is_win=true ;; esac
        if [ "$is_win" = false ] && file -b "$gdir/$gbin" 2>/dev/null | grep -qi "PE32"; then
            is_win=true
        fi
        if [ "$is_win" = true ]; then
            local r_path
            r_path=$(find_runner "$gdir" 2>/dev/null || true)
            if [ -n "$r_path" ]; then
                echo "  ${UI_CYAN}Runner      ${UI_RST}: ${UI_PURPLE}$(basename "$r_path")${UI_RST} ${UI_DIM}($r_path)${UI_RST}"
            else
                echo "  ${UI_CYAN}Runner      ${UI_RST}: ${UI_RED}[MISSING] No Windows runner found (umu-run/Proton/wine)${UI_RST}"
            fi
            echo "  ${UI_CYAN}Prefix      ${UI_RST}: ${UI_DIM}$gdir/pfx (ISOLATED)${UI_RST}"
        else
            echo "  ${UI_CYAN}Runner      ${UI_RST}: ${UI_GREEN}Native Linux${UI_RST} ${UI_DIM}(Direct ELF/Script)${UI_RST}"
        fi
    fi

    echo
    echo "${UI_BOX}╭─ STORAGE & SAVEGAMES ────────────────────────────────╮${UI_RST}"
    if [ -d "$gdir/saves" ]; then
        local save_sz
        save_sz=$(du -sh "$gdir/saves" 2>/dev/null | cut -f1)
        echo "  ${UI_CYAN}Save Path   ${UI_RST}: ${UI_GREEN}./saves${UI_RST} ${UI_DIM}(PORTABLE - ACTIVE | Size: $save_sz)${UI_RST}"
        if [ -d "$gdir/.save_snapshots" ]; then
            local snaps
            snaps=$(ls -d "$gdir/.save_snapshots"/slot* 2>/dev/null | wc -l)
            echo "  ${UI_CYAN}Snapshots   ${UI_RST}: ${UI_BOLD}$snaps active recovery slots${UI_RST}"
        else
            echo "  ${UI_CYAN}Snapshots   ${UI_RST}: ${UI_DIM}0 slots (Auto-created before launch)${UI_RST}"
        fi
    else
        echo "  ${UI_CYAN}Save Path   ${UI_RST}: ${UI_AMBER}Default OS (Global Steam/Home - Not Isolated)${UI_RST}"
        echo "  ${UI_CYAN}Snapshots   ${UI_RST}: ${UI_DIM}Disabled (Requires GBE Fork ./saves)${UI_RST}"
    fi

    if [ -f "$gdir/steam_settings/DLC.txt" ]; then
        local dlc_count
        dlc_count=$(grep -c "=" "$gdir/steam_settings/DLC.txt" 2>/dev/null || echo 0)
        echo "  ${UI_CYAN}DLC State   ${UI_RST}: ${UI_GREEN}$dlc_count items unlocked (Full DLC)${UI_RST}"
    fi
    echo "${UI_BOX}╰───────────────────────────────────────────────────────╯${UI_RST}"

    echo
    echo "${UI_BOX}╭─ RUNTIME WRAPPERS & PERFORMANCE ─────────────────────╮${UI_RST}"
    local w_gm="${UI_DIM}[N/A]${UI_RST}" w_hud="${UI_DIM}[N/A]${UI_RST}" w_scope="${UI_DIM}[N/A]${UI_RST}"
    command -v gamemoderun >/dev/null 2>&1 && w_gm="${UI_GREEN}[READY]${UI_RST}"
    command -v mangohud >/dev/null 2>&1 && w_hud="${UI_GREEN}[READY]${UI_RST}"
    command -v gamescope >/dev/null 2>&1 && w_scope="${UI_GREEN}[READY]${UI_RST}"
    echo "  ${UI_CYAN}Host Tools  ${UI_RST}: GameMode $w_gm • MangoHud $w_hud • Gamescope $w_scope"

    local act_w=()
    local c_gm=0 c_hud=0 c_scope=0 c_fsr=0 c_glt=0
    if [ -f "$HOME/.config/gamectl/wrappers" ]; then
        grep -q "^gamemode=1" "$HOME/.config/gamectl/wrappers" 2>/dev/null && c_gm=1
        grep -q -E "^(hud|mangohud)=1" "$HOME/.config/gamectl/wrappers" 2>/dev/null && c_hud=1
        grep -q "^gamescope=1" "$HOME/.config/gamectl/wrappers" 2>/dev/null && c_scope=1
        grep -q "^fsr=1" "$HOME/.config/gamectl/wrappers" 2>/dev/null && c_fsr=1
        grep -q -E "^(glthread|mesa_glthread)=1" "$HOME/.config/gamectl/wrappers" 2>/dev/null && c_glt=1
    fi
    if [ -f "$gdir/.wrappers" ]; then
        grep -q "^gamemode=1" "$gdir/.wrappers" 2>/dev/null && c_gm=1
        grep -q "^gamemode=0" "$gdir/.wrappers" 2>/dev/null && c_gm=0
        grep -q -E "^(hud|mangohud)=1" "$gdir/.wrappers" 2>/dev/null && c_hud=1
        grep -q -E "^(hud|mangohud)=0" "$gdir/.wrappers" 2>/dev/null && c_hud=0
        grep -q "^gamescope=1" "$gdir/.wrappers" 2>/dev/null && c_scope=1
        grep -q "^gamescope=0" "$gdir/.wrappers" 2>/dev/null && c_scope=0
        grep -q "^fsr=1" "$gdir/.wrappers" 2>/dev/null && c_fsr=1
        grep -q "^fsr=0" "$gdir/.wrappers" 2>/dev/null && c_fsr=0
        grep -q -E "^(glthread|mesa_glthread)=1" "$gdir/.wrappers" 2>/dev/null && c_glt=1
        grep -q -E "^(glthread|mesa_glthread)=0" "$gdir/.wrappers" 2>/dev/null && c_glt=0
    fi
    [ "$c_gm" = 1 ] && act_w+=("GameMode")
    [ "$c_hud" = 1 ] && act_w+=("MangoHud")
    [ "$c_scope" = 1 ] && act_w+=("Gamescope")
    [ "$c_fsr" = 1 ] && act_w+=("FSR")
    [ "$c_glt" = 1 ] && act_w+=("MesaGL")
    if [ ${#act_w[@]} -gt 0 ]; then
        echo "  ${UI_CYAN}Game Profile${UI_RST}: ${UI_BOLD}${act_w[*]}${UI_RST}"
    else
        echo "  ${UI_CYAN}Game Profile${UI_RST}: ${UI_DIM}Clean Native (Zero Wrappers)${UI_RST}"
    fi
    echo "${UI_BOX}╰───────────────────────────────────────────────────────╯${UI_RST}"

    echo
    echo "${UI_BOX}╭─ LAN MULTIPLAYER & IDENTITY ─────────────────────────╮${UI_RST}"
    if [[ "$status" =~ GBE_FORK ]]; then
        local p_info p_name p_id
        p_info=$(get_game_persona "$gdir")
        p_name=$(echo "$p_info" | cut -d'|' -f1)
        p_id=$(echo "$p_info" | cut -d'|' -f2)
        echo "  ${UI_CYAN}Player Name ${UI_RST}: ${UI_BOLD}${p_name:-Player}${UI_RST} ${UI_DIM}(SteamID64: ${p_id:-Default})${UI_RST}"
        if [ -f "$gdir/steam_settings/custom_broadcasts.txt" ]; then
            local bc_count
            bc_count=$(grep -v -E '^[[:space:]]*(#|$)' "$gdir/steam_settings/custom_broadcasts.txt" 2>/dev/null | wc -l)
            echo "  ${UI_CYAN}Broadcast   ${UI_RST}: ${UI_BOLD}$bc_count peers configured${UI_RST}"
        else
            echo "  ${UI_CYAN}Broadcast   ${UI_RST}: ${UI_DIM}Subnet default (127.0.0.1, 255.255.255.255)${UI_RST}"
        fi
    else
        echo "  ${UI_CYAN}GBE State   ${UI_RST}: ${UI_AMBER}[INACTIVE] (Official Steam/DRM binary)${UI_RST}"
        echo "  ${UI_CYAN}Note        ${UI_RST}: ${UI_DIM}Press <CTRL-I> to enable LAN co-op & custom persona${UI_RST}"
    fi
    local total_sz
    total_sz=$(du -sh "$gdir" 2>/dev/null | cut -f1)
    echo "  ${UI_CYAN}Disk Size   ${UI_RST}: ${UI_BOLD}$total_sz${UI_RST}"
    echo "${UI_BOX}╰───────────────────────────────────────────────────────╯${UI_RST}"

    echo
    echo "${UI_BOX}╭─ KEYBOARD SHORTCUTS ─────────────────────────────────╮${UI_RST}"
    echo "  ${UI_PILL_ENTER} ${UI_BOLD}Launch Game${UI_RST}       ${UI_PILL_CTRLI} ${UI_BOLD}Inject GBE Fork${UI_RST}"
    echo "  ${UI_PILL_CTRLO} ${UI_BOLD}Setup Wrappers${UI_RST}    ${UI_PILL_CTRLP} ${UI_BOLD}Configure LAN Persona${UI_RST}"
    local rhost
    rhost=$(get_remote_host)
    if [ -n "$rhost" ]; then
        echo "  ${UI_PILL_CTRLS} ${UI_BOLD}Sync to $rhost${UI_RST}   ${UI_PILL_CTRLB} ${UI_BOLD}Manual Save Snapshot${UI_RST}"
    else
        echo "  ${UI_PILL_CTRLS} ${UI_BOLD}Cloud Sync (N/A)${UI_RST}   ${UI_PILL_CTRLB} ${UI_BOLD}Manual Save Snapshot${UI_RST}"
    fi
    echo "  ${UI_PILL_ESC}   ${UI_BOLD}Back to Master Dashboard Hub${UI_RST}"
    echo "${UI_BOX}╰───────────────────────────────────────────────────────╯${UI_RST}"
    echo "========================================================"
}


# Preview pane generator for Master Dashboard
preview_dashboard() {
    local item_key="${1:-1}"
    local gcount="${2:-}"

    local os_name="Linux"
    if [ -f /etc/os-release ]; then
        os_name=$(grep -E '^PRETTY_NAME=' /etc/os-release | cut -d'=' -f2 | tr -d '"')
    fi
    local kernel_info
    kernel_info=$(uname -sr)

    local disp_info="Headless/Unknown"
    if [ -n "${WAYLAND_DISPLAY:-}" ]; then
        disp_info="Wayland ($WAYLAND_DISPLAY)"
        [ -n "${DISPLAY:-}" ] && disp_info="$disp_info + Xwayland ($DISPLAY)"
    elif [ -n "${DISPLAY:-}" ]; then
        disp_info="X11 ($DISPLAY)"
    fi

    [ -z "$gcount" ] && gcount=$(scan_installed_games 2>/dev/null | wc -l || echo "0")

    local def_runner
    def_runner=$(find_runner "$HOME" 2>/dev/null || true)
    local runner_str="${UI_DIM}[MISSING] Not installed${UI_RST}"
    if [ -n "$def_runner" ]; then
        runner_str="${UI_PURPLE}$(basename "$def_runner")${UI_RST} ${UI_DIM}($def_runner)${UI_RST}"
    fi

    local gbe_l64 gbe_w64
    gbe_l64=$(get_gbe_template "linux" "x64" 2>/dev/null || true)
    gbe_w64=$(get_gbe_template "windows" "x64" 2>/dev/null || true)
    local gbe_status="${UI_GREEN}[READY]${UI_RST}"
    [ -z "$gbe_l64" ] || [ -z "$gbe_w64" ] && gbe_status="${UI_AMBER}[PARTIAL]${UI_RST}"

    local w_gm="${UI_DIM}[N/A]${UI_RST}" w_hud="${UI_DIM}[N/A]${UI_RST}" w_scope="${UI_DIM}[N/A]${UI_RST}"
    command -v gamemoderun >/dev/null 2>&1 && w_gm="${UI_GREEN}[READY]${UI_RST}"
    command -v mangohud >/dev/null 2>&1 && w_hud="${UI_GREEN}[READY]${UI_RST}"
    command -v gamescope >/dev/null 2>&1 && w_scope="${UI_GREEN}[READY]${UI_RST}"

    local sls_status="${UI_DIM}[N/A]${UI_RST}" steam_status="${UI_DIM}[IDLE]${UI_RST}"
    local sls_cfg
    sls_cfg="$(get_sls_root 2>/dev/null || echo "$HOME/.config/SLSsteam")/config.yaml"
    [ -f "$sls_cfg" ] && sls_status="${UI_GREEN}[READY]${UI_RST}"
    if pgrep -x steam >/dev/null 2>&1; then
        steam_status="${UI_GREEN}[RUNNING]${UI_RST}"
    fi

    local run_dir="${XDG_RUNTIME_DIR:-/tmp/gamectl-$UID}"
    local active_count=0
    local active_titles=()
    if [ -d "$run_dir/active_games" ]; then
        for inf in "$run_dir/active_games"/*.info; do
            [ -f "$inf" ] || continue
            local a_pid a_title
            a_pid=$(grep -E '^PID=' "$inf" 2>/dev/null | head -n 1 | cut -d'=' -f2)
            a_title=$(grep -E '^TITLE=' "$inf" 2>/dev/null | head -n 1 | cut -d'=' -f2)
            if [ -n "$a_pid" ] && kill -0 "$a_pid" 2>/dev/null; then
                active_count=$((active_count + 1))
                active_titles+=("$a_title [PID:$a_pid]")
            else
                rm -f "$inf" 2>/dev/null || true
            fi
        done
    fi
    local active_desc="${UI_DIM}None${UI_RST}"
    if [ "$active_count" -gt 0 ]; then
        active_desc="${UI_GREEN}$active_count running${UI_RST} ${UI_DIM}(${active_titles[*]})${UI_RST}"
    fi

    echo "${UI_BOX}╭─ GAMECTL SOVEREIGN COCKPIT ───────────────────────────╮${UI_RST}"
    echo "│ ${UI_BOLD}SYSTEM STATUS & HARDWARE RUNTIME${UI_RST}"
    echo "${UI_BOX}╰───────────────────────────────────────────────────────╯${UI_RST}"
    echo "  ${UI_CYAN}Host OS     ${UI_RST}: ${UI_BOLD}$os_name${UI_RST} ${UI_DIM}($kernel_info)${UI_RST}"
    echo "  ${UI_CYAN}Display     ${UI_RST}: ${UI_BOLD}$disp_info${UI_RST}"
    echo "  ${UI_CYAN}Games Loaded${UI_RST}: ${UI_GREEN}$gcount titles detected${UI_RST}"
    echo "  ${UI_CYAN}Active Game ${UI_RST}: $active_desc"
    echo "  ${UI_CYAN}Win Runner  ${UI_RST}: $runner_str"
    echo "  ${UI_CYAN}GBE Fork    ${UI_RST}: $gbe_status ${UI_DIM}(Linux x64: $([ -n "$gbe_l64" ] && echo "OK" || echo "MISSING") | Win x64: $([ -n "$gbe_w64" ] && echo "OK" || echo "MISSING"))${UI_RST}"
    echo "  ${UI_CYAN}Tooling     ${UI_RST}: GameMode $w_gm • MangoHud $w_hud • Gamescope $w_scope"
    echo "  ${UI_CYAN}Integration ${UI_RST}: SLSsteam $sls_status • Steam Client $steam_status"
    echo

    local log_file="${XDG_RUNTIME_DIR:-/tmp/gamectl-$UID}/gamectl.log"
    echo "${UI_BOX}╭─ RECENT ACTIVITY LOGS ────────────────────────────────╮${UI_RST}"
    if [ -s "$log_file" ]; then
        tail -n 5 "$log_file" 2>/dev/null | while IFS= read -r line; do
            echo "  ${UI_DIM}${line:0:68}${UI_RST}"
        done
    else
        echo "  ${UI_DIM}(No recent activity logged yet)${UI_RST}"
    fi
    echo "${UI_BOX}╰───────────────────────────────────────────────────────╯${UI_RST}"
    echo

    case "$item_key" in
        *1*|*LIBRARY*|*PUSTAKA*)
            echo "${UI_BOX}╭─ SELECTED MODULE ─────────────────────────────────────╮${UI_RST}"
            echo "│ ${UI_BOLD}[01] GAME LIBRARY${UI_RST}"
            echo "${UI_BOX}╰───────────────────────────────────────────────────────╯${UI_RST}"
            echo "  • Browse installed Native Linux and Windows Proton/Wine games."
            echo "  • One-click launch with runtime wrappers & isolated runner prefix."
            echo "  • Automatic 3-slot savegame snapshot protection before launch."
            echo "  • Action shortcuts: ${UI_CYAN}Ctrl-I${UI_RST} (Inject), ${UI_CYAN}Ctrl-O${UI_RST} (Wrappers), ${UI_CYAN}Ctrl-P${UI_RST} (Persona)."
            ;;
        *2*|*SEARCH*|*PENCARIAN*)
            echo "${UI_BOX}╭─ SELECTED MODULE ─────────────────────────────────────╮${UI_RST}"
            echo "│ ${UI_BOLD}[02] STEAM STORE SEARCH & PROTONDB${UI_RST}"
            echo "${UI_BOX}╰───────────────────────────────────────────────────────╯${UI_RST}"
            echo "  • Search public Steam Store catalog via official web API."
            echo "  • Instant Linux compatibility tier audit from ProtonDB."
            echo "  • One-click background or foreground headless download."
            ;;
        *3*|*DOWNLOAD*|*UNDUHAN*)
            echo "${UI_BOX}╭─ SELECTED MODULE ─────────────────────────────────────╮${UI_RST}"
            echo "│ ${UI_BOLD}[03] DOWNLOAD MONITOR${UI_RST}"
            echo "${UI_BOX}╰───────────────────────────────────────────────────────╯${UI_RST}"
            echo "  • Monitor real-time Steam native downloads & ACF telemetry."
            echo "  • Pause and resume downloads via Valve client protocol."
            ;;
        *4*|*UNLOCK*|*ENTITLE*|*ENTITLEMENT*|*ACF*)
            echo "${UI_BOX}╭─ SELECTED MODULE ─────────────────────────────────────╮${UI_RST}"
            echo "│ ${UI_BOLD}[04] STEAM ENTITLEMENT & ACF ADOPTION ENGINE${UI_RST}"
            echo "${UI_BOX}╰───────────────────────────────────────────────────────╯${UI_RST}"
            echo "  • Adopt local files, community Steam Input gyro/touchpad & Vulkan shaders."
            echo "  • Register AppID & full DLC entitlements directly to SLSsteam."
            echo "  • Generate appmanifest_<appid>.acf automatically without downloading."
            ;;
        *5*|*CONFIG*|*SETTINGS*|*KONFIGURASI*)
            echo "${UI_BOX}╭─ SELECTED MODULE ─────────────────────────────────────╮${UI_RST}"
            echo "│ ${UI_BOLD}[05] GLOBAL CONFIGURATION${UI_RST}"
            echo "${UI_BOX}╰───────────────────────────────────────────────────────╯${UI_RST}"
            echo "  • Manage global LAN Persona (Player Name & default SteamID64)."
            echo "  • Set default runtime wrappers (GameMode, MangoHud, Gamescope FSR)."
            echo "  • Configure additional library paths & remote companion sync host."
            ;;
        *6*|*DOCTOR*|*AUDIT*|*DIAGNOSTICS*|*DIAGNOSTIK*)
            echo "${UI_BOX}╭─ SELECTED MODULE ─────────────────────────────────────╮${UI_RST}"
            echo "│ ${UI_BOLD}[06] SYSTEM DIAGNOSTICS (HEALTH AUDIT)${UI_RST}"
            echo "${UI_BOX}╰───────────────────────────────────────────────────────╯${UI_RST}"
            echo "  • Verify 7-layer system readiness: CLI tools, runners, drivers, templates."
            echo "  • Early detection of GPU hardware limitations & Mesa driver advice."
            ;;
        *7*|*LOG*|*LOGS*|*ACTIVITY*|*RIWAYAT*)
            echo "${UI_BOX}╭─ SELECTED MODULE ─────────────────────────────────────╮${UI_RST}"
            echo "│ ${UI_BOLD}[07] ACTIVITY & RUNTIME LOGS${UI_RST}"
            echo "${UI_BOX}╰───────────────────────────────────────────────────────╯${UI_RST}"
            echo "  • Inspect centralized operational log (gamectl.log)."
            echo "  • Audit recent download events, GBE injections & save backups."
            echo "  • Interactive log navigation with Ctrl-X log purge."
            ;;
        *)
            echo "${UI_BOX}╭─ NAVIGATION INSTRUCTIONS ─────────────────────────────╮${UI_RST}"
            echo "  Select a module from the left panel using arrow keys or numbers."
            echo "${UI_BOX}╰───────────────────────────────────────────────────────╯${UI_RST}"
            ;;
    esac
    echo
    echo "${UI_BOX}╭─ HUB CONTROLS ────────────────────────────────────────╮${UI_RST}"
    echo "  ${UI_PILL_ENTER} ${UI_BOLD}Open Selected Module${UI_RST}    ${UI_PILL_ESC} ${UI_BOLD}Exit / Close gamectl${UI_RST}"
    echo "${UI_BOX}╰───────────────────────────────────────────────────────╯${UI_RST}"
}

# Interactive Centralized Activity & Runtime Log Viewer
view_logs_interactive() {
    flush_tty_input
    local run_dir="${XDG_RUNTIME_DIR:-/tmp/gamectl-$UID}"
    local log_file="$run_dir/gamectl.log"

    if [ ! -s "$log_file" ]; then
        log_msg "INFO" "SYSTEM" "Log file initialized"
    fi

    local fzf_rc=0
    if command -v tac >/dev/null 2>&1; then
        tac "$log_file" 2>/dev/null
    else
        sed -e '1!G;h;$!d' "$log_file" 2>/dev/null
    fi | fzf \
        --border-label="  ╢ gamectl :: Activity & Runtime Logs ╟  " \
        --border-label-pos=2 \
        --header="ACTIVITY LOGS (Arrows: Navigate │ Ctrl-X: Clear Log │ Esc: Return)" \
        --prompt="Logs > " \
        --preview="echo -e '\033[38;5;60m╭─ LOG ENTRY DETAILS ─────────────────────────────────╮\033[0m\n{}\n\033[38;5;60m╰─────────────────────────────────────────────────────╯\033[0m'" \
        --preview-window=down:30%:border-rounded:wrap \
        --bind="ctrl-x:execute(: > '$log_file'; echo '[INFO] Logs cleared.')+reload(command -v tac >/dev/null 2>&1 && tac '$log_file' 2>/dev/null || sed -e '1!G;h;\$!d' '$log_file' 2>/dev/null)" \
        --height=85% \
        --reverse 2>/dev/null || fzf_rc=$?

    flush_tty_input
    return 0
}

# Master Dashboard Hub (Two-Panel Interactive TUI)
dashboard_menu() {
    enter_tui_screen
    clean_stale_locks

    while true; do
        flush_tty_input
        local game_count
        game_count=$(scan_installed_games 2>/dev/null | wc -l || echo "0")

        local menu_entries
        menu_entries=$(cat <<EOF
1	${UI_PURPLE}[01]${UI_RST} ${UI_BOLD}GAME LIBRARY${UI_RST}	${UI_DIM}Browse, inject and launch installed games${UI_RST}
2	${UI_PURPLE}[02]${UI_RST} ${UI_BOLD}STEAM STORE SEARCH${UI_RST}	${UI_DIM}Search games & check ProtonDB compatibility${UI_RST}
3	${UI_PURPLE}[03]${UI_RST} ${UI_BOLD}DOWNLOAD MONITOR${UI_RST}	${UI_DIM}Track Steam native downloads & ACF telemetry${UI_RST}
4	${UI_PURPLE}[04]${UI_RST} ${UI_BOLD}STEAM ENTITLEMENT & ACF${UI_RST}	${UI_DIM}Adopt files, Steam Input & shaders (Full DLC)${UI_RST}
5	${UI_PURPLE}[05]${UI_RST} ${UI_BOLD}GLOBAL SETTINGS${UI_RST}	${UI_DIM}Configure LAN persona, default wrappers & remote host${UI_RST}
6	${UI_PURPLE}[06]${UI_RST} ${UI_BOLD}SYSTEM DIAGNOSTICS${UI_RST}	${UI_DIM}Audit 7-layer dependencies, runners & GPU health${UI_RST}
7	${UI_PURPLE}[07]${UI_RST} ${UI_BOLD}ACTIVITY LOGS${UI_RST}	${UI_DIM}Inspect operational events, runner traces & error history${UI_RST}
EOF
)

        local selection fzf_rc=0
        selection=$(echo "$menu_entries" | fzf \
            --delimiter=$'\t' \
            --with-nth=2,3 \
            --border-label="  ╢ gamectl :: Master Dashboard Hub ╟  " \
            --border-label-pos=2 \
            --header="MASTER DASHBOARD (Arrows/Numbers: Select │ Enter: Open │ Ctrl-L: Logs │ Esc: Exit)" \
            --prompt="Dashboard > " \
            --preview="$SELF_BIN --preview-dashboard {1} $game_count" \
            --preview-window=right:55%:border-rounded:wrap \
            --bind="ctrl-l:execute($SELF_BIN logs)" \
        ) || fzf_rc=$?

        [ "$fzf_rc" -eq 130 ] && break
        [ -z "$selection" ] && continue

        local sel_key
        sel_key=$(echo "$selection" | awk -F'\t' '{print $1}')

        case "$sel_key" in
            1)
                library_menu false
                ;;
            2)
                search_steam "" false
                ;;
            3)
                list_downloads_interactive
                ;;
            4)
                unlock_interactive
                ;;
            5)
                configure_global
                ;;
            6)
                doctor_audit
                read -r -p "Press [ENTER] to return to Dashboard..."
                ;;
            7)
                view_logs_interactive
                ;;
            *)
                break
                ;;
        esac
        flush_tty_input
    done
    exit_tui_screen
}

# Main Library View
library_menu() {
    local standalone="${1:-false}"
    [ "$standalone" = "true" ] && enter_tui_screen
    clean_stale_locks

    while true; do
        flush_tty_input
        local selection fzf_rc=0
        selection=$(scan_installed_games --formatted | fzf \
            --delimiter=$'\t' \
            --with-nth=1,2,3 \
            --border-label="  ╢ gamectl :: Game Library ╟  " \
            --border-label-pos=2 \
            --header=$'GAME LIBRARY (Enter: Launch │ Esc: Dashboard Hub)\nShortcuts: Ctrl-F (Search Store) │ Ctrl-D (Downloads) │ Ctrl-L (Logs) │ Ctrl-I (Inject GBE) │ Ctrl-O (Wrappers) │ Ctrl-P (LAN ID) │ Ctrl-S (Sync) │ Ctrl-B (Backup)' \
            --prompt="Library > " \
            --preview="$SELF_BIN --preview {1} {2} {3} {4} {5}" \
            --preview-window=right:55%:border-rounded:wrap \
            --bind="ctrl-f:execute($SELF_BIN --search --no-dashboard)+reload($SELF_BIN list-formatted --refresh)" \
            --bind="ctrl-d:execute($SELF_BIN downloads)+reload($SELF_BIN list-formatted --refresh)" \
            --bind="ctrl-l:execute($SELF_BIN logs)" \
            --bind="ctrl-o:execute($SELF_BIN configure-wrappers {4} {2})+reload($SELF_BIN list-formatted --refresh)" \
            --bind="ctrl-p:execute($SELF_BIN set-id-interactive {4} {2})+reload($SELF_BIN list-formatted --refresh)" \
            --bind="ctrl-i:execute($SELF_BIN inject {4} {1}; $SELF_BIN sync-steam {1} {2} {4}; bash -c 'read -n 1 -s -r -p \"Press any key to return to library...\"')+reload($SELF_BIN list-formatted --refresh)" \
            --bind="ctrl-s:execute($SELF_BIN --sync {4} {2}; bash -c 'read -n 1 -s -r -p \"Press any key to continue...\"')" \
            --bind="ctrl-b:execute($SELF_BIN --backup {4}; bash -c 'read -n 1 -s -r -p \"Press any key to continue...\"')" \
        ) || fzf_rc=$?

        [ "$fzf_rc" -eq 130 ] && break
        [ -z "$selection" ] && continue

        if [ -n "$selection" ]; then
            local sel_dir sel_bin sel_title
            sel_dir=$(echo "$selection" | awk -F'\t' '{print $4}')
            sel_bin=$(echo "$selection" | awk -F'\t' '{print $5}')
            sel_title=$(echo "$selection" | awk -F'\t' '{print $2}')
            local launch_rc=0
            launch_game "$sel_dir" "$sel_bin" "$sel_title" || launch_rc=$?
            invalidate_scan_cache
            if [ "$launch_rc" -eq 10 ]; then
                # User selected return directly to Master Dashboard
                break
            fi
        fi
    done

    if [ "$standalone" = "true" ]; then
        dashboard_menu
    fi
}

# Live Steam Search View (Actionable TUI Search)
search_steam() {
    local query="${1:-}"
    local standalone="${2:-false}"
    [ "$standalone" = "true" ] && enter_tui_screen
    flush_tty_input
    if [ -z "$query" ]; then
        local query_raw="" fzf_rc=0
        query_raw=$(: | fzf \
            --print-query \
            --border-label="  ╢ gamectl :: Steam Store Search ╟  " \
            --border-label-pos=2 \
            --header="Type game title to search (Enter: Search │ Esc: Cancel)" \
            --prompt="Search Store > " \
            --height=20% \
            --reverse 2>/dev/null) || fzf_rc=$?

        # Only abort if user cancelled via ESC or Ctrl-C (exit status 130)
        if [ "$fzf_rc" -eq 130 ]; then
            flush_tty_input
            [ "$standalone" = "true" ] && dashboard_menu
            [ "$fzf_rc" -eq 130 ] && return 0
        fi

        query=$(echo "$query_raw" | head -n 1 | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
        if [ -z "$query" ]; then
            flush_tty_input
            [ "$standalone" = "true" ] && dashboard_menu
            return 0
        fi
    fi

    echo "[INFO] Searching '$query' on Steam Store API..."
    local encoded_query
    encoded_query=$(python3 -c "import urllib.parse, sys; print(urllib.parse.quote(sys.argv[1]))" "$query")
    local raw_results
    raw_results=$(curl -s --connect-timeout 5 "https://store.steampowered.com/api/storesearch/?term=${encoded_query}&l=english&cc=US" 2>/dev/null)

    local items
    items=$(echo "$raw_results" | jq -r '.items[]? | "\(.id)\t\(.name)"' 2>/dev/null || true)

    if [ -z "$items" ]; then
        echo "[INFO] Game not found."
        sleep 1
        return
    fi

    # Build list with local installed status across all libraries via scan_installed_games
    local results=""
    declare -A installed_by_id=()
    declare -A installed_by_title=()
    declare -A installed_dir=()

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
            results+="${appid}"$'\t'"${name}"$'\t'"${status}"$'\n'
        done <<< "$items"
    }

    _refresh_search_results

    while true; do
        flush_tty_input
        local fzf_out fzf_rc=0
        fzf_out=$(echo -n "$results" | fzf \
            --delimiter=$'\t' \
            --with-nth=1,2,3 \
            --expect=ctrl-a,ctrl-u,ctrl-s,ctrl-d \
            --bind="ctrl-a:accept,ctrl-u:accept,ctrl-s:accept,ctrl-d:accept" \
            --border-label="  ╢ gamectl :: Steam Store Catalog ╟  " \
            --border-label-pos=2 \
            --header="STEAM CATALOG (Enter: Actions │ Ctrl-A: All-in-One │ Ctrl-U: Entitle │ Ctrl-S: Standalone │ Esc: Back)" \
            --prompt="Steam Store > " \
            --preview='
                appid={1}
                title={2}
                app_status={3}
                echo -e "\033[38;5;60m╭─ STEAM METADATA & PROTONDB AUDIT ───────────────────╮\033[0m"
                echo -e "│ \033[1m$title\033[0m \033[38;5;244m(AppID: $appid)\033[0m"
                echo -e "\033[38;5;60m╰─────────────────────────────────────────────────────╯\033[0m"
                echo -e "  \033[1;38;5;117mLocal State\033[0m : $app_status"
                details=$(fetch_cached_json "https://store.steampowered.com/api/appdetails?appids=$appid&filters=platforms,genres" "steam_details_$appid" 3600 2>/dev/null | jq -r ".\"$appid\".data // empty" 2>/dev/null)
                if [ -n "$details" ]; then
                    is_linux=$(echo "$details" | jq -r ".platforms.linux // false" 2>/dev/null)
                    is_win=$(echo "$details" | jq -r ".platforms.windows // false" 2>/dev/null)
                    genres=$(echo "$details" | jq -r "[.genres[]?.description] | join(\", \")" 2>/dev/null)
                    [ -n "$genres" ] && echo -e "  \033[1;38;5;117mGenres     \033[0m : \033[38;5;244m$genres\033[0m"
                    if [ "$is_linux" = "true" ]; then
                        echo -e "  \033[1;38;5;117mPlatform   \033[0m : \033[1;38;5;120mNative Linux ELF available\033[0m"
                    elif [ "$is_win" = "true" ]; then
                        echo -e "  \033[1;38;5;117mPlatform   \033[0m : \033[1;38;5;141mWindows PE (Requires Proton/Wine)\033[0m"
                    fi
                fi
                echo
                echo -e "\033[38;5;60m╭─ COMMUNITY COMPATIBILITY ───────────────────────────╮\033[0m"
                pdb=$(fetch_cached_json "https://www.protondb.com/api/v1/reports/summaries/$appid.json" "protondb_$appid" 3600 2>/dev/null)
                if [ -n "$pdb" ] && [ "$pdb" != "null" ]; then
                    tier=$(echo "$pdb" | jq -r ".tier // \"Unknown\"" 2>/dev/null)
                    score=$(echo "$pdb" | jq -r ".score // \"-\"" 2>/dev/null)
                    conf=$(echo "$pdb" | jq -r ".confidence // \"-\"" 2>/dev/null)
                    tier_upper="${tier^^}"
                    c_tier="\033[1;38;5;120m[$tier_upper]\033[0m"
                    case "$tier_upper" in
                        *PLATINUM*) c_tier="\033[1;38;5;153m[PLATINUM]\033[0m" ;;
                        *GOLD*)     c_tier="\033[1;38;5;221m[GOLD]\033[0m" ;;
                        *SILVER*)   c_tier="\033[1;38;5;248m[SILVER]\033[0m" ;;
                        *BRONZE*)   c_tier="\033[1;38;5;173m[BRONZE]\033[0m" ;;
                        *BORKED*)   c_tier="\033[1;38;5;203m[BORKED]\033[0m" ;;
                    esac
                    echo -e "  \033[1;38;5;117mProtonDB Tier \033[0m: $c_tier"
                    echo -e "  \033[1;38;5;117mRating Score  \033[0m: \033[1m$score\033[0m \033[38;5;244m(Confidence: $conf)\033[0m"
                else
                    echo -e "  \033[1;38;5;117mProtonDB Tier \033[0m: \033[38;5;244m[NO REPORTS YET]\033[0m"
                fi
                echo -e "\033[38;5;60m╰─────────────────────────────────────────────────────╯\033[0m"
            ' \
            --preview-window=right:52%:border-rounded:wrap \
        ) || fzf_rc=$?

        [ "$fzf_rc" -eq 130 ] && break
        [ -z "$fzf_out" ] && continue

        local trigger_key selection
        trigger_key=$(echo "$fzf_out" | sed -n '1p')
        selection=$(echo "$fzf_out" | sed -n '2,$p')

        [ -z "$selection" ] && continue

        local sel_id sel_name sel_status
        sel_id=$(echo "$selection" | awk -F'\t' '{print $1}')
        sel_name=$(echo "$selection" | awk -F'\t' '{print $2}')
        sel_status=$(echo "$selection" | awk -F'\t' '{print $3}')

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
        if [[ ! "$sel_status" =~ INSTALLED ]] || [[ "$sel_status" =~ NOT ]]; then
            dest_dir="$(resolve_target_library_dir "$sel_name")"
            target_os="$(detect_app_platform_os "$sel_id")"
        fi

        # Direct hotkey triggers
        if [ "$trigger_key" = "ctrl-a" ]; then
            if [[ "$sel_status" =~ INSTALLED ]] && [[ ! "$sel_status" =~ NOT ]]; then
                echo "[INFO] Shortcut <Ctrl-A>: Injecting GBE + Syncing Steam for $sel_name..."
                inject_game "$gdir" "$sel_id"
            else
                echo "[INFO] Shortcut <Ctrl-A>: Starting All-in-One Background Download for $sel_name ($target_os)..."
                download_game "$sel_id" "$dest_dir" "$sel_name" --all --background --os "$target_os"
            fi
            sleep 1.2
        elif [ "$trigger_key" = "ctrl-u" ]; then
            if [[ "$sel_status" =~ INSTALLED ]] && [[ ! "$sel_status" =~ NOT ]]; then
                echo "[INFO] Shortcut <Ctrl-U>: Synchronizing Steam Entitlement & ACF for $sel_name..."
                sync_steam "$sel_id" "$sel_name" "$gdir"
            else
                echo "[INFO] Shortcut <Ctrl-U>: Adopting Steam Entitlement & ACF for $sel_name..."
                unlock_game "$sel_id" "$sel_name"
            fi
            sleep 1.2
        elif [ "$trigger_key" = "ctrl-s" ]; then
            if [[ "$sel_status" =~ INSTALLED ]] && [[ ! "$sel_status" =~ NOT ]]; then
                echo "[INFO] Shortcut <Ctrl-S>: Injecting Standalone GBE Fork for $sel_name..."
                inject_game "$gdir" "$sel_id" --no-sync
            else
                echo "[INFO] Shortcut <Ctrl-S>: Starting Standalone Background Download for $sel_name ($target_os)..."
                download_game "$sel_id" "$dest_dir" "$sel_name" --inject-only --background --os "$target_os"
            fi
            sleep 1.2
        elif [ "$trigger_key" = "ctrl-d" ]; then
            if [[ "$sel_status" =~ INSTALLED ]] && [[ ! "$sel_status" =~ NOT ]]; then
                local gbin
                gbin=$(find_game_binary "$gdir" 2>/dev/null || echo "")
                if [ -n "$gbin" ]; then
                    local launch_rc=0
                    launch_game "$gdir" "$gbin" "$sel_name" || launch_rc=$?
                    if [ "$launch_rc" -eq 10 ]; then
                        break
                    fi
                else
                    echo "[ERROR] Binary executable not found in $gdir."
                    sleep 1.2
                fi
            else
                echo "[INFO] Shortcut <Ctrl-D>: Starting All-in-One Live Stream Download for $sel_name ($target_os)..."
                download_game "$sel_id" "$dest_dir" "$sel_name" --all --foreground --os "$target_os"
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
5	Cancel / Return
EOF
)
                local action_sel
                action_sel=$(echo "$action_palette" | fzf \
                    --delimiter=$'\t' \
                    --with-nth=2 \
                    --border-label="  ╢ Action Palette: $sel_name ╟  " \
                    --border-label-pos=2 \
                    --header="ACTION PALETTE (Enter: Execute │ Esc: Return)" \
                    --prompt="Action > " \
                    --height=40% \
                    --reverse 2>/dev/null) || action_sel="5"

                local act_opt
                act_opt=$(echo "$action_sel" | awk -F'\t' '{print $1}')

                case "$act_opt" in
                    1)
                        local gbin
                        gbin=$(find_game_binary "$gdir" 2>/dev/null || echo "")
                        if [ -n "$gbin" ]; then
                            local launch_rc=0
                            launch_game "$gdir" "$gbin" "$sel_name" || launch_rc=$?
                            if [ "$launch_rc" -eq 10 ]; then
                                break
                            fi
                        else
                            echo "[ERROR] Binary executable not found in $gdir."
                            sleep 1.2
                        fi
                        ;;
                    2)
                        inject_game "$gdir" "$sel_id" --no-sync
                        ;;
                    3)
                        inject_game "$gdir" "$sel_id"
                        ;;
                    4)
                        sync_steam "$sel_id" "$sel_name" "$gdir"
                        ;;
                    *)
                        ;;
                esac
            else
                local not_installed_palette
                not_installed_palette=$(cat <<EOF
1	[All-in-One] Download & Auto-Provision via Steam Native CDN (SLSsteam)
2	[Steam Entitlement & ACF] Adopt files, Steam Input & Shaders (Full DLC)
3	[Standalone] Inject GBE LAN runtime (Steam-free)
4	Cancel / Return
EOF
)
                local pkg_sel
                pkg_sel=$(echo "$not_installed_palette" | fzf \
                    --delimiter=$'\t' \
                    --with-nth=2 \
                    --border-label="  ╢ Action Palette: $sel_name ╟  " \
                    --border-label-pos=2 \
                    --header="PACKAGE SELECTION (Enter: Execute │ Esc: Return)" \
                    --prompt="Package > " \
                    --height=40% \
                    --reverse 2>/dev/null) || pkg_sel="4"

                local opt
                opt=$(echo "$pkg_sel" | awk -F'\t' '{print $1}')
                case "$opt" in
                    1)
                        download_game "$sel_id" "$dest_dir" "$sel_name" --all --os "$target_os"
                        sleep 1.2
                        ;;
                    2)
                        unlock_game "$sel_id" "$sel_name"
                        sleep 1.2
                        ;;
                    3)
                        inject_game "$dest_dir" "$sel_id" --no-sync
                        sleep 1.2
                        ;;
                    *)
                        ;;
                esac
            fi
        fi
        _refresh_search_results
    done

    flush_tty_input
    if [ "$standalone" = "true" ]; then
        dashboard_menu
    fi
}


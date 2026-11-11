# Preview pane generator for installed games
preview_game() {
    local appid title status gdir gbin
    appid=$(strip_ansi "$1" | tr -d '[:space:]')
    title=$(strip_ansi "$2" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
    status=$(strip_ansi "$3" | tr -d '][[:space:]]')
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

    local run_dir
    run_dir="$(get_runtime_dir)"
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

    local run_dir
    run_dir="$(get_runtime_dir)"
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

    local log_file
    log_file="$(get_runtime_log_file)"

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

    case "$item_key" in
        *1*|*LIBRARY*|*PUSTAKA*)
            echo "${UI_BOX}╭─ SELECTED MODULE: [01] GAME LIBRARY ──────────────────╮${UI_RST}"
            echo "│ ${UI_BOLD}LOCAL LIBRARY & RUNTIME DEPLOYMENT METRICS${UI_RST}"
            echo "${UI_BOX}╰───────────────────────────────────────────────────────╯${UI_RST}"

            local cache_file="$run_dir/scancache.tab"
            if [ ! -f "$cache_file" ]; then
                scan_installed_games >/dev/null 2>&1 || true
            fi

            local lib_total=0 lib_linux=0 lib_win=0 lib_gbe=0 lib_valve=0
            if [ -f "$cache_file" ]; then
                read -r lib_total lib_linux lib_win lib_gbe lib_valve < <(awk -F"\t" '
                    NF >= 4 {
                        tot++
                        if ($3 ~ /GBE_FORK/) gbe++
                        else if ($3 ~ /VALVE/) valve++
                        if ($5 ~ /\.(exe|EXE)$/) win++
                        else linux++
                    }
                    END {
                        printf "%d %d %d %d %d\n", tot, linux, win, gbe, valve
                    }
                ' "$cache_file")
            fi
            [ -z "$lib_total" ] || [ "$lib_total" -eq 0 ] && lib_total="${gcount:-0}"

            local storage_cache="$run_dir/lib_storage.cache"
            local storage_str="0 MB"
            if [ -f "$storage_cache" ] && [ $(($(date +%s) - $(stat -c%Y "$storage_cache" 2>/dev/null || echo 0))) -lt 60 ]; then
                storage_str=$(cat "$storage_cache" 2>/dev/null || echo "0 MB")
            elif [ -f "$cache_file" ]; then
                storage_str=$(cut -f4 "$cache_file" 2>/dev/null | sort -u | tr '\n' '\0' | xargs -0 -r du -sk 2>/dev/null | awk '{s+=$1} END {if (s>1048576) printf "%.2f GB", s/1048576; else printf "%.1f MB", s/1024}')
                [ -n "$storage_str" ] && echo "$storage_str" > "$storage_cache" 2>/dev/null || true
            fi

            echo "  ${UI_CYAN}Installed Titles   ${UI_RST}: ${UI_BOLD}${UI_GREEN}${lib_total} titles detected${UI_RST}"
            echo "  ${UI_CYAN}Storage Footprint  ${UI_RST}: ${UI_BOLD}${storage_str:-0 MB}${UI_RST}"
            echo "  ${UI_CYAN}Platform Ratio     ${UI_RST}: ${UI_BOLD}Linux ELF: $lib_linux${UI_RST} • ${UI_BOLD}Windows PE: $lib_win${UI_RST}"
            echo "  ${UI_CYAN}GBE Fork Injected  ${UI_RST}: ${UI_BOLD}${UI_GREEN}$lib_gbe titles${UI_RST} ${UI_DIM}(DRM-Free LAN Emulation)${UI_RST}"
            echo "  ${UI_CYAN}Stock / Standalone ${UI_RST}: ${UI_BOLD}$((lib_total - lib_gbe)) titles${UI_RST}"
            echo
            echo "  ${UI_DIM}Quick Shortcuts:${UI_RST}"
            echo "  • ${UI_CYAN}Ctrl-I${UI_RST} Inject GBE Fork   • ${UI_CYAN}Ctrl-O${UI_RST} Wrappers & Overrides"
            echo "  • ${UI_CYAN}Ctrl-P${UI_RST} LAN Persona       • ${UI_CYAN}Ctrl-S${UI_RST} Savegame Snapshots"
            ;;
        *2*|*SEARCH*|*PENCARIAN*)
            echo "${UI_BOX}╭─ SELECTED MODULE: [02] STEAM STORE & PROTONDB ────────╮${UI_RST}"
            echo "│ ${UI_BOLD}REMOTE CATALOG & COMPATIBILITY TELEMETRY${UI_RST}"
            echo "${UI_BOX}╰───────────────────────────────────────────────────────╯${UI_RST}"

            local net_cache="$run_dir/net_status.cache"
            local steam_st="${UI_GREEN}[ONLINE]${UI_RST}" pdb_st="${UI_GREEN}[ONLINE]${UI_RST}"
            if [ -f "$net_cache" ] && [ $(($(date +%s) - $(stat -c%Y "$net_cache" 2>/dev/null || echo 0))) -lt 60 ]; then
                read -r steam_st pdb_st < "$net_cache"
            else
                if curl -s -I --connect-timeout 1 --max-time 1 "https://store.steampowered.com" >/dev/null 2>&1; then
                    steam_st="${UI_GREEN}[ONLINE]${UI_RST}"
                else
                    steam_st="${UI_RED}[OFFLINE]${UI_RST}"
                fi
                if curl -s -I --connect-timeout 1 --max-time 1 "https://www.protondb.com" >/dev/null 2>&1; then
                    pdb_st="${UI_GREEN}[ONLINE]${UI_RST}"
                else
                    pdb_st="${UI_RED}[OFFLINE]${UI_RST}"
                fi
                printf "%s %s\n" "$steam_st" "$pdb_st" > "$net_cache" 2>/dev/null || true
            fi

            local c_dir="$HOME/.cache/gamectl"
            local c_total=0 c_size="0B" c_steam=0 c_pdb=0
            if [ -d "$c_dir" ]; then
                c_total=$(find "$c_dir" -type f 2>/dev/null | wc -l)
                c_size=$(du -sh "$c_dir" 2>/dev/null | awk '{print $1}' || echo "0B")
                c_steam=$(find "$c_dir" -name "*steam*" -o -name "store_*" 2>/dev/null | wc -l)
                c_pdb=$(find "$c_dir" -name "*proton*" -o -name "protondb_*" 2>/dev/null | wc -l)
            fi

            echo "  ${UI_CYAN}Steam Store API    ${UI_RST}: $steam_st ${UI_DIM}(store.steampowered.com)${UI_RST}"
            echo "  ${UI_CYAN}ProtonDB API       ${UI_RST}: $pdb_st ${UI_DIM}(protondb.com/api/v1)${UI_RST}"
            echo "  ${UI_CYAN}Local Cache Dir    ${UI_RST}: ${UI_BOLD}~/.cache/gamectl/${UI_RST} ${UI_DIM}($c_size total)${UI_RST}"
            echo "  ${UI_CYAN}Cached Store Items ${UI_RST}: ${UI_BOLD}$c_steam entries${UI_RST}"
            echo "  ${UI_CYAN}Cached ProtonDB    ${UI_RST}: ${UI_BOLD}$c_pdb ratings${UI_RST}"
            echo
            echo "  ${UI_DIM}Catalog Features:${UI_RST}"
            echo "  • Live ProtonDB tier badges: Platinum, Gold, Silver, Bronze, Borked"
            echo "  • Direct metadata retrieval: Genres, Platform (Linux ELF vs Windows PE)"
            echo "  • Headless downloads via Standalone CDN or Steam native install"
            ;;
        *3*|*DOWNLOAD*|*UNDUHAN*)
            echo "${UI_BOX}╭─ SELECTED MODULE: [03] DOWNLOAD MONITOR ──────────────╮${UI_RST}"
            echo "│ ${UI_BOLD}UNIFIED DOWNLOAD ENGINE & REAL-TIME TELEMETRY${UI_RST}"
            echo "${UI_BOX}╰───────────────────────────────────────────────────────╯${UI_RST}"

            local st_count=0 steam_count=0
            local dl_items=()

            # Standalone downloads
            shopt -s nullglob
            for s_dir in "$run_dir"/depot_dl_*; do
                [ -d "$s_dir" ] || continue
                local s_base="${s_dir##*/}"
                local s_pid="${s_base##*_}"
                local s_rest="${s_base#depot_dl_}"
                local s_aid="${s_rest%_*}"
                [ -z "$s_aid" ] || [ -z "$s_pid" ] && continue
                if ! [[ "$s_pid" =~ ^[0-9]+$ ]] || ! kill -0 "$s_pid" 2>/dev/null; then
                    continue
                fi

                local s_title="Standalone CDN Download"
                local s_info="$s_dir/status.info"
                local s_log="$s_dir/download.log"
                if [ -f "$s_info" ]; then
                    local i_title i_log
                    i_title=$(grep -E '^TITLE=' "$s_info" | cut -d= -f2- || true)
                    i_log=$(grep -E '^LOG_FILE=' "$s_info" | cut -d= -f2- || true)
                    [ -n "$i_title" ] && s_title="$i_title"
                    [ -n "$i_log" ] && [ -f "$i_log" ] && s_log="$i_log"
                fi

                local s_prog s_pct s_bytes s_st
                s_prog=$(get_depot_dl_progress "$s_log" "$s_pid" 2>/dev/null || printf "0%%\t0 MB / 0 MB\t[DOWNLOADING]\n")
                IFS=$'\t' read -r s_pct s_bytes s_st <<< "$s_prog"
                st_count=$((st_count + 1))
                dl_items+=("${UI_CYAN}$s_title${UI_RST} ${UI_GREEN}$s_pct${UI_RST} ${UI_DIM}($s_bytes - Standalone CDN)${UI_RST}")
            done

            # Steam native downloads
            local s_apps
            s_apps="$(get_steam_primary_apps 2>/dev/null || echo "$HOME/.local/share/Steam/steamapps")"
            for s_acf in "$s_apps"/appmanifest_*.acf; do
                [ -f "$s_acf" ] || continue
                local s_data
                s_data=$(parse_acf_download_state "$s_acf" 2>/dev/null || true)
                [ -z "$s_data" ] && continue
                local a_id a_title a_status a_pct a_dl a_total a_flags a_dir a_path
                IFS=$'\t' read -r a_id a_title a_status a_pct a_dl a_total a_flags a_dir a_path <<< "$s_data"
                if [ "$a_status" = "[DOWNLOADING]" ] || [ "$a_status" = "[PAUSED]" ] || [ "$a_status" = "[UPDATE REQUIRED]" ]; then
                    steam_count=$((steam_count + 1))
                    local d_fmt t_fmt
                    d_fmt=$(format_bytes "$a_dl")
                    t_fmt=$(format_bytes "$a_total")
                    dl_items+=("${UI_CYAN}$a_title${UI_RST} ${UI_PURPLE}$a_pct${UI_RST} ${UI_DIM}($d_fmt / $t_fmt - Steam Engine)${UI_RST}")
                fi
            done
            shopt -u nullglob

            local total_active=$((st_count + steam_count))
            echo "  ${UI_CYAN}Active Downloads   ${UI_RST}: ${UI_BOLD}${UI_GREEN}$total_active active task(s)${UI_RST}"
            echo "  ${UI_CYAN}Standalone Engine  ${UI_RST}: ${UI_BOLD}$st_count running${UI_RST} ${UI_DIM}(Direct CDN depot download)${UI_RST}"
            echo "  ${UI_CYAN}Steam Client Engine${UI_RST}: ${UI_BOLD}$steam_count running/queued${UI_RST} ${UI_DIM}(ACF manifest telemetry)${UI_RST}"
            echo
            if [ "$total_active" -gt 0 ]; then
                echo "  ${UI_BOLD}Active Tasks In Progress:${UI_RST}"
                for item in "${dl_items[@]}"; do
                    echo "  • $item"
                done
            else
                echo "  ${UI_DIM}(No active downloads currently running in background)${UI_RST}"
            fi
            echo
            echo "  ${UI_DIM}Engine Capabilities:${UI_RST}"
            echo "  • Live real-time download log streaming"
            echo "  • Interactive pause/resume and process cancellation (${UI_CYAN}Ctrl-K${UI_RST})"
            ;;
        *4*|*UNLOCK*|*ENTITLE*|*ENTITLEMENT*|*ACF*|*ADOPT*)
            echo "${UI_BOX}╭─ SELECTED MODULE: [04] STEAM ACF ADOPTION ────────────╮${UI_RST}"
            echo "│ ${UI_BOLD}PHYSICAL DISCOVERY & ASSET ADOPTION MANAGER${UI_RST}"
            echo "${UI_BOX}╰───────────────────────────────────────────────────────╯${UI_RST}"

            local unadopted=()
            local total_phys=0
            if [ -d "$HOME/Games" ]; then
                for g_cand in "$HOME/Games"/*; do
                    [ -d "$g_cand" ] || continue
                    local g_base="${g_cand##*/}"
                    [[ "$g_base" =~ ^\. ]] && continue
                    total_phys=$((total_phys + 1))

                    local c_aid=""
                    if [ -f "$g_cand/steam_appid.txt" ]; then
                        c_aid=$(cat "$g_cand/steam_appid.txt" 2>/dev/null | tr -cd "0-9")
                    elif [ -f "$g_cand/.gamectl_appid" ]; then
                        c_aid=$(cat "$g_cand/.gamectl_appid" 2>/dev/null | tr -cd "0-9")
                    fi

                    local has_acf=""
                    [ -n "$c_aid" ] && has_acf=$(find_app_acf "$c_aid" 2>/dev/null || true)

                    if [ -z "$has_acf" ]; then
                        unadopted+=("$g_base [AppID:${c_aid:-N/A}]")
                    fi
                done
            fi

            local s_papps
            s_papps="$(get_steam_primary_apps 2>/dev/null || echo "$HOME/.local/share/Steam/steamapps")"

            echo "  ${UI_CYAN}Physical Games Dir ${UI_RST}: ${UI_BOLD}~/Games/${UI_RST} ${UI_DIM}($total_phys titles scanned)${UI_RST}"
            echo "  ${UI_CYAN}Pending Adoption   ${UI_RST}: ${UI_BOLD}${UI_AMBER}${#unadopted[@]} titles pending ACF${UI_RST}"
            echo "  ${UI_CYAN}Steam Apps Target  ${UI_RST}: ${UI_BOLD}$s_papps${UI_RST}"
            echo "  ${UI_CYAN}Steam Client State ${UI_RST}: $steam_status"
            echo
            if [ ${#unadopted[@]} -gt 0 ]; then
                echo "  ${UI_BOLD}Titles Ready For Adoption (Missing ACF Manifest):${UI_RST}"
                local u_shown=0
                for u_item in "${unadopted[@]}"; do
                    if [ "$u_shown" -ge 4 ]; then
                        echo "  • ${UI_DIM}...and $((${#unadopted[@]} - u_shown)) more title(s)${UI_RST}"
                        break
                    fi
                    echo "  • ${UI_CYAN}$u_item${UI_RST}"
                    u_shown=$((u_shown + 1))
                done
            else
                echo "  ${UI_GREEN}All physical game directories are properly adopted into Steam.${UI_RST}"
            fi
            echo
            echo "  ${UI_DIM}Adoption Workflow:${UI_RST}"
            echo "  • Dual-input adoption by Game Title or numeric AppID without prior lookup"
            echo "  • Auto-provisions physical appmanifest ACF with StateFlags=4"
            ;;
        *5*|*CONFIG*|*SETTINGS*|*KONFIGURASI*)
            echo "${UI_BOX}╭─ SELECTED MODULE: [05] GLOBAL CONFIGURATION ──────────╮${UI_RST}"
            echo "│ ${UI_BOLD}SOVEREIGN ENVIRONMENT & PREFERENCE STATE${UI_RST}"
            echo "${UI_BOX}╰───────────────────────────────────────────────────────╯${UI_RST}"

            local persona_data
            persona_data=$(get_game_persona "" 2>/dev/null || printf "Player|76561197960287930|english\n")
            local p_name p_id p_lang
            IFS='|' read -r p_name p_id p_lang <<< "$persona_data"

            local r_host
            r_host=$(get_remote_host 2>/dev/null || true)

            local act_w=()
            if [ -f "$HOME/.config/gamectl/wrappers" ]; then
                grep -q "^gamemode=1" "$HOME/.config/gamectl/wrappers" 2>/dev/null && act_w+=("GameMode")
                grep -q -E "^(hud|mangohud)=1" "$HOME/.config/gamectl/wrappers" 2>/dev/null && act_w+=("MangoHud")
                grep -q "^gamescope=1" "$HOME/.config/gamectl/wrappers" 2>/dev/null && act_w+=("Gamescope")
                grep -q "^fsr=1" "$HOME/.config/gamectl/wrappers" 2>/dev/null && act_w+=("FSR")
                grep -q -E "^(glthread|mesa_glthread)=1" "$HOME/.config/gamectl/wrappers" 2>/dev/null && act_w+=("MesaGL")
            fi
            local wrappers_desc="${UI_DIM}None (Disabled)${UI_RST}"
            [ ${#act_w[@]} -gt 0 ] && wrappers_desc="${UI_GREEN}${act_w[*]}${UI_RST}"

            local lib_paths_count=0
            if [ -f "$HOME/.config/gamectl/libraries" ]; then
                lib_paths_count=$(grep -v -E '^[[:space:]]*(#|$)' "$HOME/.config/gamectl/libraries" 2>/dev/null | wc -l || echo 0)
            fi

            echo "  ${UI_CYAN}Player Name (LAN)  ${UI_RST}: ${UI_BOLD}${UI_GREEN}${p_name:-Player}${UI_RST}"
            echo "  ${UI_CYAN}Default SteamID64  ${UI_RST}: ${UI_BOLD}${p_id:-76561197960287930}${UI_RST}"
            echo "  ${UI_CYAN}Default Wrappers   ${UI_RST}: $wrappers_desc"
            echo "  ${UI_CYAN}Remote Sync Host   ${UI_RST}: ${UI_BOLD}${r_host:-None (Local Only)}${UI_RST}"
            echo "  ${UI_CYAN}Custom Libraries   ${UI_RST}: ${UI_BOLD}$lib_paths_count path(s) configured${UI_RST}"
            echo "  ${UI_CYAN}Config Location    ${UI_RST}: ${UI_BOLD}~/.config/gamectl/${UI_RST}"
            echo
            echo "  ${UI_DIM}Configurable Subsystems:${UI_RST}"
            echo "  • LAN Persona: Custom nickname and SteamID64 for multiplayer save isolation"
            echo "  • Runtime Wrappers: Global toggle for GameMode, MangoHud, and Gamescope FSR"
            echo "  • Multi-Library: Custom paths scanned across external drives or shared mounts"
            ;;
        *6*|*DOCTOR*|*AUDIT*|*DIAGNOSTICS*|*DIAGNOSTIK*)
            echo "${UI_BOX}╭─ SELECTED MODULE: [06] SYSTEM DIAGNOSTICS ────────────╮${UI_RST}"
            echo "│ ${UI_BOLD}7-LAYER DEPENDENCY & RUNTIME HEALTH AUDIT${UI_RST}"
            echo "${UI_BOX}╰───────────────────────────────────────────────────────╯${UI_RST}"

            local pass_cnt=0 warn_cnt=0 miss_cnt=0
            local l1_st="${UI_GREEN}[OK]${UI_RST}"
            local l2_st="${UI_GREEN}[OK]${UI_RST}"
            local l3_st="${UI_GREEN}[OK]${UI_RST}"
            local l4_st="${UI_GREEN}[OK]${UI_RST}"

            # Layer 1: CLI tools
            for t in fzf jq curl file zip unzip rsync ssh; do
                if command -v "$t" >/dev/null 2>&1; then
                    pass_cnt=$((pass_cnt + 1))
                else
                    miss_cnt=$((miss_cnt + 1))
                    l1_st="${UI_RED}[MISSING]${UI_RST}"
                fi
            done
            local has_7z=""
            for c in 7z 7za 7zr; do command -v "$c" >/dev/null 2>&1 && { has_7z="$c"; break; }; done
            if [ -n "$has_7z" ]; then
                pass_cnt=$((pass_cnt + 1))
            else
                warn_cnt=$((warn_cnt + 1))
            fi

            # Layer 2: Python Runtime
            if command -v python3 >/dev/null 2>&1; then
                pass_cnt=$((pass_cnt + 1))
                if python3 -c "import ruamel.yaml" >/dev/null 2>&1 || python3 -c "import yaml" >/dev/null 2>&1; then
                    pass_cnt=$((pass_cnt + 1))
                else
                    warn_cnt=$((warn_cnt + 1))
                    l2_st="${UI_AMBER}[WARN]${UI_RST}"
                fi
            else
                miss_cnt=$((miss_cnt + 1))
                l2_st="${UI_RED}[MISSING]${UI_RST}"
            fi

            # Layer 3: Runner
            if [ -n "$def_runner" ]; then
                pass_cnt=$((pass_cnt + 1))
            else
                miss_cnt=$((miss_cnt + 1))
                l3_st="${UI_RED}[MISSING]${UI_RST}"
            fi

            # Layer 4: GBE Templates
            if [ -n "$gbe_l64" ] && [ -n "$gbe_w64" ]; then
                pass_cnt=$((pass_cnt + 1))
            else
                warn_cnt=$((warn_cnt + 1))
                l4_st="${UI_AMBER}[PARTIAL]${UI_RST}"
            fi

            # Layer 5: Tooling wrappers
            for w in gamemoderun mangohud gamescope; do
                if command -v "$w" >/dev/null 2>&1; then
                    pass_cnt=$((pass_cnt + 1))
                else
                    warn_cnt=$((warn_cnt + 1))
                fi
            done

            # Layer 8: Security Sandboxing & Process Isolation
            local has_bwrap=0 has_scope=0
            if command -v bwrap >/dev/null 2>&1; then
                pass_cnt=$((pass_cnt + 1))
                has_bwrap=1
            else
                warn_cnt=$((warn_cnt + 1))
            fi
            if check_systemd_scope_support >/dev/null 2>&1; then
                pass_cnt=$((pass_cnt + 1))
                has_scope=1
            else
                warn_cnt=$((warn_cnt + 1))
            fi

            local health_badge="${UI_GREEN}[HEALTHY] Ready for Gaming${UI_RST}"
            if [ "$miss_cnt" -gt 0 ]; then
                health_badge="${UI_RED}[DEGRADED] Missing Core Dependencies${UI_RST}"
            elif [ "$warn_cnt" -gt 0 ]; then
                health_badge="${UI_AMBER}[OPERATIONAL] Minor Warnings Detected${UI_RST}"
            fi

            echo "  ${UI_CYAN}Overall Health     ${UI_RST}: $health_badge"
            echo "  ${UI_CYAN}Audit Summary      ${UI_RST}: ${UI_BOLD}${UI_GREEN}$pass_cnt passed${UI_RST} • ${UI_BOLD}${UI_AMBER}$warn_cnt warnings${UI_RST} • ${UI_BOLD}${UI_RED}$miss_cnt missing${UI_RST}"
            echo
            echo "  ${UI_BOLD}7-Layer Architecture Status:${UI_RST}"
            echo "  • L1 CLI Core Tools: $l1_st    • L2 Python & YAML: $l2_st"
            echo "  • L3 Windows Runner: $l3_st    • L4 GBE Templates: $l4_st"
            echo "  • L5 Wrappers      : GameMode $w_gm • MangoHud $w_hud • Gamescope $w_scope"
            echo "  • L6 Integrations  : SLSsteam $sls_status • Steam Client $steam_status"
            echo "  • L8 Security      : Sandbox $([ "$has_bwrap" -eq 1 ] && echo "${UI_GREEN}[READY]${UI_RST}" || echo "${UI_AMBER}[OFF]${UI_RST}") • Scope $([ "$has_scope" -eq 1 ] && echo "${UI_GREEN}[READY]${UI_RST}" || echo "${UI_AMBER}[OFF]${UI_RST}")"
            echo
            echo "  ${UI_DIM}Full Audit: Press Enter to launch interactive 7-layer doctor_audit${UI_RST}"
            ;;
        *7*|*LOG*|*LOGS*|*ACTIVITY*|*RIWAYAT*)
            echo "${UI_BOX}╭─ SELECTED MODULE: [07] ACTIVITY & RUNTIME LOGS ───────╮${UI_RST}"
            echo "│ ${UI_BOLD}CENTRALIZED OPERATIONAL TELEMETRY & AUDIT${UI_RST}"
            echo "${UI_BOX}╰───────────────────────────────────────────────────────╯${UI_RST}"

            local log_lines=0 log_size="0B" log_warn=0 log_err=0 log_info=0
            if [ -s "$log_file" ]; then
                log_lines=$(wc -l < "$log_file" 2>/dev/null || echo 0)
                log_size=$(du -sh "$log_file" 2>/dev/null | awk '{print $1}' || echo "0B")
                log_warn=$(grep -c -E "\[WARN[ ]*\]" "$log_file" 2>/dev/null || true)
                log_err=$(grep -c -E "\[ERROR[ ]*\]" "$log_file" 2>/dev/null || true)
                log_info=$(grep -c -E "\[INFO[ ]*\]" "$log_file" 2>/dev/null || true)
            fi

            echo "  ${UI_CYAN}Log File Path      ${UI_RST}: ${UI_BOLD}$log_file${UI_RST}"
            echo "  ${UI_CYAN}Total Records      ${UI_RST}: ${UI_BOLD}$log_lines lines${UI_RST} ${UI_DIM}($log_size)${UI_RST}"
            echo "  ${UI_CYAN}Severity Breakdown ${UI_RST}: ${UI_GREEN}$log_info INFO${UI_RST} • ${UI_AMBER}$log_warn WARN${UI_RST} • ${UI_RED}$log_err ERROR${UI_RST}"
            echo
            echo "${UI_BOX}╭─ RECENT ACTIVITY LOGS ────────────────────────────────╮${UI_RST}"
            if [ -s "$log_file" ]; then
                tail -n 5 "$log_file" 2>/dev/null | while IFS= read -r line; do
                    echo "  ${UI_DIM}${line:0:84}${UI_RST}"
                done
            else
                echo "  ${UI_DIM}(No recent activity logged yet)${UI_RST}"
            fi
            echo "${UI_BOX}╰───────────────────────────────────────────────────────╯${UI_RST}"
            echo
            echo "  ${UI_DIM}Log Controls: Press Enter to open viewer │ Ctrl-X in viewer to clear${UI_RST}"
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

# Preview pane generator for Steam Store Search & ProtonDB compatibility
preview_search_game() {
    local appid="${1:-}"
    local title="${2:-}"
    local app_status="${3:-[NOT INSTALLED]}"

    appid=$(strip_ansi "$appid" | tr -d '[:space:]')
    title=$(strip_ansi "$title" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
    app_status=$(strip_ansi "$app_status" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')

    printf "%s╭─ STEAM METADATA & PROTONDB AUDIT ───────────────────╮%s\n" "${UI_BOX}" "${UI_RST}"
    printf "│ %s%s%s %s(AppID: %s)%s\n" "${UI_BOLD}" "$title" "${UI_RST}" "${UI_DIM}" "$appid" "${UI_RST}"
    printf "%s╰─────────────────────────────────────────────────────╯%s\n" "${UI_BOX}" "${UI_RST}"
    printf "  %sLocal State%s : %s\n" "${UI_CYAN}" "${UI_RST}" "$app_status"

    if [ -n "$appid" ] && [[ "$appid" =~ ^[0-9]+$ ]]; then
        local details
        details=$(fetch_cached_json "https://store.steampowered.com/api/appdetails?appids=${appid}&filters=platforms,genres" "steam_details_${appid}" 3600 2>/dev/null | jq -r ".\"${appid}\".data // empty" 2>/dev/null || true)
        if [ -n "$details" ] && [ "$details" != "null" ]; then
            local is_linux is_win genres
            is_linux=$(echo "$details" | jq -r ".platforms.linux // false" 2>/dev/null || echo "false")
            is_win=$(echo "$details" | jq -r ".platforms.windows // false" 2>/dev/null || echo "false")
            genres=$(echo "$details" | jq -r "[.genres[]?.description] | join(\", \")" 2>/dev/null || true)
            [ -n "$genres" ] && printf "  %sGenres     %s : %s%s%s\n" "${UI_CYAN}" "${UI_RST}" "${UI_DIM}" "$genres" "${UI_RST}"
            if [ "$is_linux" = "true" ]; then
                printf "  %sPlatform   %s : %sNative Linux ELF available%s\n" "${UI_CYAN}" "${UI_RST}" "${UI_GREEN}" "${UI_RST}"
            elif [ "$is_win" = "true" ]; then
                printf "  %sPlatform   %s : %sWindows PE (Requires Proton/Wine)%s\n" "${UI_CYAN}" "${UI_RST}" "${UI_PURPLE}" "${UI_RST}"
            fi
        fi

        printf "\n%s╭─ COMMUNITY COMPATIBILITY ───────────────────────────╮%s\n" "${UI_BOX}" "${UI_RST}"
        local pdb
        pdb=$(fetch_cached_json "https://www.protondb.com/api/v1/reports/summaries/${appid}.json" "protondb_${appid}" 3600 2>/dev/null || true)
        if [ -n "$pdb" ] && [ "$pdb" != "null" ]; then
            local tier score conf total tier_upper c_tier
            tier=$(echo "$pdb" | jq -r ".tier // \"Unknown\"" 2>/dev/null || echo "Unknown")
            score=$(echo "$pdb" | jq -r ".score // \"-\"" 2>/dev/null || echo "-")
            conf=$(echo "$pdb" | jq -r ".confidence // \"-\"" 2>/dev/null || echo "-")
            total=$(echo "$pdb" | jq -r ".total // \"-\"" 2>/dev/null || echo "-")
            tier_upper="${tier^^}"
            c_tier="${UI_GREEN}[$tier_upper]${UI_RST}"
            case "$tier_upper" in
                *PLATINUM*) c_tier="${UI_ICE}[PLATINUM]${UI_RST}" ;;
                *GOLD*)     c_tier="${UI_AMBER}[GOLD]${UI_RST}" ;;
                *SILVER*)   c_tier="${UI_DIM}[SILVER]${UI_RST}" ;;
                *BRONZE*)   c_tier="${UI_RED}[BRONZE]${UI_RST}" ;;
                *BORKED*)   c_tier="${UI_RED}[BORKED]${UI_RST}" ;;
            esac
            printf "  %sProtonDB Tier %s: %s\n" "${UI_CYAN}" "${UI_RST}" "$c_tier"
            local rep_str=""
            [ "$total" != "-" ] && rep_str=" • Reports: $total"
            printf "  %sRating Score  %s: %s%s%s %s(Confidence: %s%s)%s\n" "${UI_CYAN}" "${UI_RST}" "${UI_BOLD}" "$score" "${UI_RST}" "${UI_DIM}" "$conf" "$rep_str" "${UI_RST}"
        else
            printf "  %sProtonDB Tier %s: %s[NO REPORTS YET]%s\n" "${UI_CYAN}" "${UI_RST}" "${UI_DIM}" "${UI_RST}"
        fi
        printf "%s╰─────────────────────────────────────────────────────╯%s\n" "${UI_BOX}" "${UI_RST}"
    else
        printf "\n%s╭─ COMMUNITY COMPATIBILITY ───────────────────────────╮%s\n" "${UI_BOX}" "${UI_RST}"
        printf "  %sProtonDB Tier %s: %s[INVALID APPID]%s\n" "${UI_CYAN}" "${UI_RST}" "${UI_DIM}" "${UI_RST}"
        printf "%s╰─────────────────────────────────────────────────────╯%s\n" "${UI_BOX}" "${UI_RST}"
    fi
}

# Preview pane generator for Activity & Runtime Log entries
preview_log_entry() {
    local raw_entry="$1"
    [ -z "$raw_entry" ] && return 0

    local ts="N/A" lvl="UNKNOWN" mod="GENERAL" msg="$raw_entry"
    if [[ "$raw_entry" =~ ^\[([^]]+)\][[:space:]]+\[([^]]+)\][[:space:]]+\[([^]]+)\][[:space:]]+(.*)$ ]]; then
        ts="${BASH_REMATCH[1]}"
        lvl="${BASH_REMATCH[2]// /}"
        mod="${BASH_REMATCH[3]// /}"
        msg="${BASH_REMATCH[4]}"
    fi

    local lvl_badge="${UI_BOLD}$lvl${UI_RST}"
    case "$lvl" in
        INFO)  lvl_badge="${UI_GREEN}${UI_BOLD}[INFO]${UI_RST}" ;;
        WARN)  lvl_badge="${UI_AMBER}${UI_BOLD}[WARN]${UI_RST}" ;;
        ERROR) lvl_badge="${UI_RED}${UI_BOLD}[ERROR]${UI_RST}" ;;
        DEBUG) lvl_badge="${UI_CYAN}${UI_BOLD}[DEBUG]${UI_RST}" ;;
    esac

    echo "${UI_BOX}╭─ LOG ENTRY DETAILS ─────────────────────────────────╮${UI_RST}"
    echo "  ${UI_CYAN}Timestamp  ${UI_RST}: ${UI_BOLD}$ts${UI_RST}"
    echo "  ${UI_CYAN}Severity   ${UI_RST}: $lvl_badge"
    echo "  ${UI_CYAN}Subsystem  ${UI_RST}: ${UI_PURPLE}${UI_BOLD}$mod${UI_RST}"
    echo "  ${UI_CYAN}Message    ${UI_RST}: $msg"
    echo "${UI_BOX}╰─────────────────────────────────────────────────────╯${UI_RST}"

    if [ "$lvl" = "ERROR" ]; then
        echo
        echo "${UI_RED}╭─ REMEDIATION & TROUBLESHOOTING GUIDANCE ────────────╮${UI_RST}"
        local advice="Run 'gamectl doctor' to audit system health or review recent activity logs."
        case "$mod" in
            *LAUNCH*|*RUNNER*)
                advice="Windows runner missing or crashed. Run 'gamectl doctor' or install Proton-GE/Wine."
                ;;
            *STORE*|*DOWNLOAD*|*DEPOT*)
                advice="Network or CDN timeout. Check connectivity to Steam Store or CDN endpoints."
                ;;
            *GBE*|*INJECT*)
                advice="GBE injection failure. Check file permissions or verify 32-bit vs 64-bit architecture."
                ;;
            *SAVE*|*BACKUP*|*RESTORE*)
                advice="Savegame snapshot error. Verify disk space in target directory or storage quota."
                ;;
            *DRM*|*STEAMSTUB*)
                advice="SteamStub DRM detected. Run 'gamectl unpack <exe>' using Steamless CLI."
                ;;
            *)
                if [[ "$msg" =~ (runner|wine|proton) ]]; then
                    advice="Windows runner failure. Verify runner configuration in ~/.config/gamectl/."
                elif [[ "$msg" =~ (permission|denied|write) ]]; then
                    advice="Filesystem permission error. Verify user write permissions on target directory."
                fi
                ;;
        esac
        echo "  ${UI_AMBER}• Suggestion: ${advice}${UI_RST}"
        echo "${UI_RED}╰─────────────────────────────────────────────────────╯${UI_RST}"
    fi
}

# Interactive Centralized Activity & Runtime Log Viewer
view_logs_interactive() {
    flush_tty_input
    local log_file
    log_file="$(get_runtime_log_file)"

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
        --preview="$SELF_BIN --preview-log {}" \
        --preview-window=down:35%:border-rounded:wrap \
        --bind="ctrl-x:execute(: > '$log_file')+reload(command -v tac >/dev/null 2>&1 && tac '$log_file' 2>/dev/null || sed -e '1!G;h;\$!d' '$log_file' 2>/dev/null)" \
        --height=85% \
        --reverse 2>/dev/null || fzf_rc=$?

    flush_tty_input
    return 0
}

# Master Dashboard Hub (Two-Panel Interactive TUI)
dashboard_menu() {
    enter_tui_screen
    clean_stale_locks

    local initial_count
    initial_count=$(scan_installed_games 2>/dev/null | wc -l || echo "0")
    log_msg "INFO" "DASHBOARD" "Cockpit active ($initial_count titles indexed)"

    while true; do
        flush_tty_input
        local game_count
        game_count=$(scan_installed_games 2>/dev/null | wc -l || echo "0")

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
            --expect=ctrl-l \
            --border-label="  ╢ gamectl :: Master Dashboard Hub ╟  " \
            --border-label-pos=2 \
            --header="MASTER DASHBOARD (Arrows/Numbers: Select │ Enter: Open │ Ctrl-L: Logs │ Esc: Exit)" \
            --prompt="Dashboard > " \
            --preview="$SELF_BIN --preview-dashboard {1} $game_count" \
            --preview-window=right:55%:border-rounded:wrap \
        ) || fzf_rc=$?

        [ "$fzf_rc" -eq 130 ] && break
        [ -z "$fzf_out" ] && continue

        local trigger_key selection
        trigger_key=$(echo "$fzf_out" | head -n 1)
        selection=$(echo "$fzf_out" | sed -n '2p')

        if [ "$trigger_key" = "ctrl-l" ]; then
            view_logs_interactive
            continue
        fi

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
                flush_tty_input
                doctor_audit 2>&1 | fzf \
                    --ansi \
                    --no-sort \
                    --border-label="  ╢ gamectl :: System Diagnostics Audit ╟  " \
                    --border-label-pos=2 \
                    --header="SYSTEM DIAGNOSTICS (Arrows: Scroll │ Esc / q / Enter: Return to Dashboard)" \
                    --prompt="Audit > " \
                    --bind="q:abort" \
                    --reverse 2>/dev/null || true
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
        local fzf_out fzf_rc=0
        fzf_out=$(scan_installed_games --formatted | fzf \
            --delimiter=$'\t' \
            --with-nth=1,2,3 \
            --expect=ctrl-f,ctrl-d,ctrl-l,ctrl-o,ctrl-p,ctrl-i,ctrl-s,ctrl-b,ctrl-r,ctrl-x \
            --border-label="  ╢ gamectl :: Game Library ╟  " \
            --border-label-pos=2 \
            --header=$'GAME LIBRARY (Enter: Launch │ Esc: Dashboard Hub)\nShortcuts: Ctrl-F (Search) │ Ctrl-D (Downloads) │ Ctrl-L (Logs) │ Ctrl-I (Inject) │ Ctrl-O (Wrappers) │ Ctrl-P (LAN ID) │ Ctrl-S (Sync) │ Ctrl-B (Backup) │ Ctrl-R (Restore) │ Ctrl-X (Fixes)' \
            --prompt="Library > " \
            --preview="$SELF_BIN --preview {1} {2} {3} {4} {5}" \
            --preview-window=right:55%:border-rounded:wrap \
        ) || fzf_rc=$?

        [ "$fzf_rc" -eq 130 ] && break
        [ -z "$fzf_out" ] && continue

        local trigger_key selection
        trigger_key=$(echo "$fzf_out" | head -n 1)
        selection=$(echo "$fzf_out" | sed -n '2p')

        # Global in-process hotkeys that do not require item selection
        if [ "$trigger_key" = "ctrl-l" ]; then
            view_logs_interactive
            continue
        elif [ "$trigger_key" = "ctrl-f" ]; then
            search_steam "" false
            invalidate_scan_cache
            continue
        elif [ "$trigger_key" = "ctrl-d" ]; then
            list_downloads_interactive
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
            ctrl-o)
                configure_wrappers "$sel_dir" "$sel_title"
                invalidate_scan_cache
                continue
                ;;
            ctrl-p)
                set_id_interactive "$sel_dir" "$sel_title"
                invalidate_scan_cache
                continue
                ;;
            ctrl-i)
                inject_game "$sel_dir" "$sel_appid"
                sync_steam "$sel_appid" "$sel_title" "$sel_dir"
                invalidate_scan_cache
                tui_modal_notice "GBE Injection & Steam Sync" "Successfully injected GBE Fork & synchronized Steam entitlement for:\n${sel_title:-$sel_dir}"
                continue
                ;;
            ctrl-s)
                sync_save_remote "$sel_dir" "$sel_title"
                tui_modal_notice "Remote Sync" "Savegames synchronized with remote companion host for:\n${sel_title:-$sel_dir}"
                continue
                ;;
            ctrl-b)
                backup_save "$sel_dir"
                tui_modal_notice "Save Backup" "Savegame snapshot created in slot for:\n${sel_title:-$sel_dir}"
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
                                --height=30% \
                                --reverse 2>/dev/null) || p_rc=$?
                            [ "$p_rc" -eq 130 ] || [ -z "$pick" ] && continue
                            chosen_slot=$(echo "$pick" | cut -f1)
                            chosen_slot="${chosen_slot#slot}"
                        fi
                        if restore_save "$sel_dir" "$chosen_slot"; then
                            tui_modal_notice "Save Restore" "Savegame restored successfully from slot${chosen_slot} for:\n${sel_title:-$sel_dir}"
                        else
                            tui_modal_notice "Save Restore Error" "Failed to restore savegame from slot${chosen_slot} for:\n${sel_title:-$sel_dir}"
                        fi
                    else
                        tui_modal_notice "Save Restore" "No snapshot recovery slots found for:\n${sel_title:-$sel_dir}"
                    fi
                else
                    tui_modal_notice "Save Restore" "No snapshot recovery directory (.save_snapshots) found for:\n${sel_title:-$sel_dir}"
                fi
                continue
                ;;
            ctrl-x)
                manage_game_fixes_interactive "$sel_appid" "$sel_title" "$sel_dir"
                invalidate_scan_cache
                continue
                ;;
            *)
                local launch_rc=0
                launch_game "$sel_dir" "$sel_bin" "$sel_title" || launch_rc=$?
                invalidate_scan_cache
                if [ "$launch_rc" -eq 10 ]; then
                    # User selected return directly to Master Dashboard
                    break
                fi
                ;;
        esac
    done

    [ "$standalone" = "true" ] && exit_tui_screen
    return 0
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
            [ "$standalone" = "true" ] && exit_tui_screen
            [ "$fzf_rc" -eq 130 ] && return 0
        fi

        query=$(echo "$query_raw" | head -n 1 | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
        if [ -z "$query" ]; then
            flush_tty_input
            [ "$standalone" = "true" ] && exit_tui_screen
            return 0
        fi
    fi

    log_msg "INFO" "STORE" "Searching '$query' on Steam Store API..."
    local encoded_query
    encoded_query=$(python3 -c "import urllib.parse, sys; print(urllib.parse.quote(sys.argv[1]))" "$query")
    local raw_results
    raw_results=$(curl -s --connect-timeout 5 "https://store.steampowered.com/api/storesearch/?term=${encoded_query}&l=english&cc=US" 2>/dev/null)

    local items
    items=$(echo "$raw_results" | jq -r '.items[]? | "\(.id)\t\(.name)"' 2>/dev/null || true)

    if [ -z "$items" ]; then
        log_msg "WARN" "STORE" "Game '$query' not found on Steam Store API."
        tui_modal_notice "Steam Store Search" "Game '$query' was not found on Steam Store."
        [ "$standalone" = "true" ] && exit_tui_screen
        return 0
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
            --preview="$SELF_BIN --preview-search {1} {2} {3}" \
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
                log_msg "INFO" "HOTKEY" "Shortcut <Ctrl-A>: Injecting GBE + Syncing Steam for $sel_name ($sel_id)"
                inject_game "$gdir" "$sel_id"
            else
                log_msg "INFO" "HOTKEY" "Shortcut <Ctrl-A>: Starting All-in-One Background Download for $sel_name ($target_os)"
                download_game "$sel_id" "$dest_dir" "$sel_name" --all --background --os "$target_os"
            fi
        elif [ "$trigger_key" = "ctrl-u" ]; then
            if [[ "$sel_status" =~ INSTALLED ]] && [[ ! "$sel_status" =~ NOT ]]; then
                log_msg "INFO" "HOTKEY" "Shortcut <Ctrl-U>: Synchronizing Steam Entitlement & ACF for $sel_name ($sel_id)"
                sync_steam "$sel_id" "$sel_name" "$gdir"
            else
                log_msg "INFO" "HOTKEY" "Shortcut <Ctrl-U>: Adopting Steam Entitlement & ACF for $sel_name ($sel_id)"
                unlock_game "$sel_id" "$sel_name"
            fi
        elif [ "$trigger_key" = "ctrl-s" ]; then
            if [[ "$sel_status" =~ INSTALLED ]] && [[ ! "$sel_status" =~ NOT ]]; then
                log_msg "INFO" "HOTKEY" "Shortcut <Ctrl-S>: Injecting Standalone GBE Fork for $sel_name ($sel_id)"
                inject_game "$gdir" "$sel_id" --no-sync
            else
                log_msg "INFO" "HOTKEY" "Shortcut <Ctrl-S>: Starting Standalone Background Download for $sel_name ($target_os)"
                download_game "$sel_id" "$dest_dir" "$sel_name" --inject-only --background --os "$target_os"
            fi
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
                    log_msg "ERROR" "LAUNCH" "Binary executable not found in $gdir for $sel_name"
                    tui_modal_notice "Executable Not Found" "Binary executable not found in directory:\n$gdir"
                fi
            else
                log_msg "INFO" "HOTKEY" "Shortcut <Ctrl-D>: Starting All-in-One Live Stream Download for $sel_name ($target_os)"
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
5	Check Community Fixes & Online-Fix Catalog
6	Cancel / Return
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
                    --reverse 2>/dev/null) || action_sel="6"

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
                            log_msg "ERROR" "LAUNCH" "Binary executable not found in $gdir for $sel_name"
                            tui_modal_notice "Executable Not Found" "Binary executable not found in directory:\n$gdir"
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
                    5)
                        manage_game_fixes_interactive "$sel_id" "$sel_name" "$gdir"
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
4	[Fixes & OnlineFix] Check Community Fixes & Online-Fix Catalog
5	Cancel / Return
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
                    --reverse 2>/dev/null) || pkg_sel="5"

                local opt
                opt=$(echo "$pkg_sel" | awk -F'\t' '{print $1}')
                case "$opt" in
                    1)
                        download_game "$sel_id" "$dest_dir" "$sel_name" --all --os "$target_os"
                        ;;
                    2)
                        unlock_game "$sel_id" "$sel_name"
                        ;;
                    3)
                        inject_game "$dest_dir" "$sel_id" --no-sync
                        ;;
                    4)
                        manage_game_fixes_interactive "$sel_id" "$sel_name" ""
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


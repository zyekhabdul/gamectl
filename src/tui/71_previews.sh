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
        status=$(resolve_game_drm_status "$gdir" "" "$gbin")
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
    local run_log=""
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
                    run_log=$(grep -E '^LOG=' "$inf" 2>/dev/null | head -n 1 | cut -d'=' -f2- || true)
                    break
                fi
            fi
        done
    fi
    if [ "$is_running" = true ]; then
        status_badge="${UI_GREEN}[RUNNING PID:$run_pid]${UI_RST}"
        status_desc="${UI_DIM}(Active in background)${UI_RST}"
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
                local r_label r_short
                r_label=$(basename "$r_path")
                [ "$r_label" = "proton" ] && r_label=$(basename "$(dirname "$r_path")")
                r_short="${r_path/#$HOME/~}"
                echo "  ${UI_CYAN}Runner      ${UI_RST}: ${UI_PURPLE}$r_label${UI_RST} ${UI_DIM}($r_short)${UI_RST}"
            else
                echo "  ${UI_CYAN}Runner      ${UI_RST}: ${UI_RED}[MISSING] No Windows runner found (umu-run/Proton/wine)${UI_RST}"
            fi
            echo "  ${UI_CYAN}Prefix      ${UI_RST}: ${UI_DIM}$gdir/pfx (ISOLATED)${UI_RST}"
        else
            echo "  ${UI_CYAN}Runner      ${UI_RST}: ${UI_GREEN}Native Linux${UI_RST} ${UI_DIM}(Direct ELF/Script)${UI_RST}"
        fi
        local target_log log_hint
        target_log="${run_log:-$(get_game_log_file "$gdir" "$gbin")}"
        log_hint=$(inspect_game_log_hint "$target_log" 2>/dev/null || true)
        [ -n "$log_hint" ] && echo "  ${UI_AMBER}Log Hint    ${UI_RST}: [HINT] $log_hint"
    fi

    echo
    echo "${UI_BOX}╭─ STORAGE & SAVEGAMES ────────────────────────────────╮${UI_RST}"
    if [ -d "$gdir/saves" ]; then
        local save_sz=""
        local s_cache="$gdir/saves/.size_cache"
        local s_mtime
        s_mtime=$(stat -c%Y "$gdir/saves" 2>/dev/null || echo 0)
        if [ -f "$s_cache" ] && [ "$(head -n 1 "$s_cache" 2>/dev/null)" = "$s_mtime" ]; then
            save_sz=$(tail -n 1 "$s_cache" 2>/dev/null)
        fi
        if [ -z "$save_sz" ]; then
            save_sz=$(du -sh "$gdir/saves" 2>/dev/null | cut -f1)
            [ -w "$gdir/saves" ] && printf "%s\n%s\n" "$s_mtime" "$save_sz" > "$s_cache" 2>/dev/null || true
        fi
        echo "  ${UI_CYAN}Save Path   ${UI_RST}: ${UI_GREEN}./saves${UI_RST} ${UI_DIM}(PORTABLE - ACTIVE | Size: ${save_sz:-0B})${UI_RST}"
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
    load_wrapper_config "$gdir" 1
    [ "$GAMECTL_CFG_GM" = 1 ] && act_w+=("GameMode")
    [ "$GAMECTL_CFG_HUD" = 1 ] && act_w+=("MangoHud")
    [ "$GAMECTL_CFG_SCOPE" = 1 ] && act_w+=("Gamescope")
    [ "$GAMECTL_CFG_FSR" = 1 ] && act_w+=("FSR")
    [ "$GAMECTL_CFG_GLTHREAD" = 1 ] && act_w+=("MesaGL")
    [ "$GAMECTL_CFG_PRIME" = 1 ] && act_w+=("PRIME")
    [ "$GAMECTL_CFG_SANDBOX" = 1 ] && act_w+=("Sandbox")
    if [ ${#act_w[@]} -gt 0 ]; then
        echo "  ${UI_CYAN}Game Profile${UI_RST}: ${UI_BOLD}${act_w[*]}${UI_RST}"
    else
        echo "  ${UI_CYAN}Game Profile${UI_RST}: ${UI_DIM}Clean Native (Zero Wrappers)${UI_RST}"
    fi
    local c_renderer="${GAMECTL_CFG_RENDERER:-auto}" eff_renderer vk_cap_label renderer_label
    eff_renderer=$(resolve_graphics_renderer "$c_renderer" "$GAMECTL_CFG_PRIME" 2>/dev/null || echo "wined3d")
    if [ "$eff_renderer" = "wined3d" ]; then
        vk_cap_label="WineD3D"
    else
        vk_cap_label="DXVK"
    fi
    if [ "$c_renderer" = "auto" ]; then
        renderer_label="${UI_ICE}Auto ($vk_cap_label)${UI_RST}"
    else
        renderer_label="${UI_BOLD}${vk_cap_label}${UI_RST} ${UI_DIM}(forced: $c_renderer)${UI_RST}"
    fi
    echo "  ${UI_CYAN}Renderer    ${UI_RST}: $renderer_label"
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
    local total_sz=""
    if [ -n "$appid" ] && [[ "$appid" =~ ^[0-9]+$ ]]; then
        local acf_path=""
        if [ -f "$gdir/appmanifest_${appid}.acf" ]; then
            acf_path="$gdir/appmanifest_${appid}.acf"
        elif [ -f "$(dirname "$gdir")/appmanifest_${appid}.acf" ]; then
            acf_path="$(dirname "$gdir")/appmanifest_${appid}.acf"
        else
            acf_path=$(find_app_acf "$appid" 2>/dev/null || true)
        fi
        if [ -n "$acf_path" ] && [ -f "$acf_path" ]; then
            local bytes_on_disk
            bytes_on_disk=$(sed -n 's/^[[:space:]]*"SizeOnDisk"[[:space:]]*"\([0-9]*\)".*/\1/p' "$acf_path" | head -n 1)
            if [ -n "$bytes_on_disk" ] && [ "$bytes_on_disk" -gt 0 ] 2>/dev/null; then
                total_sz=$(format_bytes "$bytes_on_disk")
            fi
        fi
    fi
    if [ -z "$total_sz" ]; then
        local run_dir
        run_dir="$(get_runtime_dir)"
        local sz_hash
        sz_hash=$(echo -n "$gdir" | md5sum 2>/dev/null | cut -d' ' -f1 || echo "")
        local sz_cache="$run_dir/sz_${sz_hash}.cache"
        if [ -n "$sz_hash" ] && [ -f "$sz_cache" ]; then
            total_sz=$(cat "$sz_cache" 2>/dev/null || true)
        fi
        if [ -z "$total_sz" ]; then
            total_sz=$(du -sh "$gdir" 2>/dev/null | cut -f1)
            [ -n "$sz_hash" ] && echo "$total_sz" > "$sz_cache" 2>/dev/null || true
        fi
    fi
    echo "  ${UI_CYAN}Disk Size   ${UI_RST}: ${UI_BOLD}$total_sz${UI_RST}"
    echo "${UI_BOX}╰───────────────────────────────────────────────────────╯${UI_RST}"

    echo
    echo "${UI_BOX}╭─ KEYBOARD SHORTCUTS ─────────────────────────────────╮${UI_RST}"
    echo "  ${UI_PILL_ENTER} ${UI_BOLD}Launch Game${UI_RST}       ${UI_PILL_CTRLI} ${UI_BOLD}Inject GBE Fork${UI_RST}"
    echo "  ${UI_PILL_CTRLO} ${UI_BOLD}Setup Wrappers${UI_RST}    ${UI_PILL_CTRLP} ${UI_BOLD}Configure LAN Persona${UI_RST}"
    local rhost
    rhost=$(get_remote_host)
    if [ -n "$rhost" ]; then
        echo "  ${UI_PILL_CTRLS} ${UI_BOLD}Remote Sync ($rhost)${UI_RST}   ${UI_PILL_CTRLB} ${UI_BOLD}Manual Save Snapshot${UI_RST}"
    else
        echo "  ${UI_PILL_CTRLS} ${UI_BOLD}Remote Sync (Setup)${UI_RST}   ${UI_PILL_CTRLB} ${UI_BOLD}Manual Save Snapshot${UI_RST}"
    fi
    echo "  ${UI_PILL_CTRLR} ${UI_BOLD}Restore Snapshot${UI_RST}   ${UI_PILL_CTRLX} ${UI_BOLD}Community Fixes${UI_RST}"
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
    echo "  ${UI_CYAN}Bridge (Opt)${UI_RST}: SLSsteam $sls_status • Steam Client $steam_status"
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
            local c_size="0B" c_steam=0 c_pdb=0
            local c_hash
            c_hash=$(printf '%s' "$c_dir" | md5sum 2>/dev/null | cut -c1-12 || echo "default")
            local c_cache="$run_dir/cache_stat_${c_hash}.cache"
            if [ -f "$c_cache" ] && [ $(($(date +%s) - $(stat -c%Y "$c_cache" 2>/dev/null || echo 0))) -lt 60 ]; then
                read -r c_size c_steam c_pdb < "$c_cache"
            elif [ -d "$c_dir" ]; then
                c_size=$(du -sh "$c_dir" 2>/dev/null | awk '{print $1}' || echo "0B")
                for f in "$c_dir"/*; do
                    [ -f "$f" ] || continue
                    local fname="${f##*/}"
                    case "$fname" in
                        *steam*|store_*) c_steam=$((c_steam + 1)) ;;
                        *proton*) c_pdb=$((c_pdb + 1)) ;;
                    esac
                done
                printf "%s %s %s\n" "$c_size" "$c_steam" "$c_pdb" > "$c_cache" 2>/dev/null || true
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
        *4*|*UNLOCK*|*ENTITLE*|*ACF*|*ADOPT*)
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

                    local c_aid
                    c_aid="$(resolve_game_appid "$g_cand")"

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
            load_wrapper_config "" 0
            [ "$GAMECTL_CFG_GM" = 1 ] && act_w+=("GameMode")
            [ "$GAMECTL_CFG_HUD" = 1 ] && act_w+=("MangoHud")
            [ "$GAMECTL_CFG_SCOPE" = 1 ] && act_w+=("Gamescope")
            [ "$GAMECTL_CFG_FSR" = 1 ] && act_w+=("FSR")
            [ "$GAMECTL_CFG_GLTHREAD" = 1 ] && act_w+=("MesaGL")
            [ "$GAMECTL_CFG_PRIME" = 1 ] && act_w+=("PRIME")
            [ "$GAMECTL_CFG_SANDBOX" = 1 ] && act_w+=("Sandbox")
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
            echo "  • L6 Bridge (Opt)  : SLSsteam $sls_status • Steam Client $steam_status"
            echo "  • L8 Security      : Sandbox $([ "$has_bwrap" -eq 1 ] && echo "${UI_GREEN}[READY]${UI_RST}" || echo "${UI_AMBER}[OFF]${UI_RST}") • Scope $([ "$has_scope" -eq 1 ] && echo "${UI_GREEN}[READY]${UI_RST}" || echo "${UI_AMBER}[OFF]${UI_RST}")"
            echo
            echo "  ${UI_DIM}Full Audit: Press Enter to launch interactive 7-layer doctor_audit${UI_RST}"
            ;;
        *7*|*LOG*|*ACTIVITY*|*RIWAYAT*)
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
        details=$(fetch_steam_app_details "$appid" 2>/dev/null || true)
        if [ -n "$details" ] && [ "$details" != "null" ]; then
            local raw_type parent_id parent_name is_linux is_win genres
            raw_type=$(echo "$details" | jq -r '.type // empty' 2>/dev/null || true)
            parent_id=$(echo "$details" | jq -r '.fullgame.appid // empty' 2>/dev/null || true)
            parent_name=$(echo "$details" | jq -r '.fullgame.name // empty' 2>/dev/null || true)
            if [ -n "$raw_type" ]; then
                local norm_type type_badge
                norm_type="$(normalize_steam_app_type "$raw_type")"
                type_badge="$(format_app_type_badge "$norm_type")"
                if [ "$norm_type" = "DLC" ] && [[ "$parent_id" =~ ^[0-9]+$ ]]; then
                    if [ -n "$parent_name" ]; then
                        printf "  %sType       %s : %s %s(Base: %s • %s)%s\n" "${UI_CYAN}" "${UI_RST}" "$type_badge" "${UI_DIM}" "$parent_name" "$parent_id" "${UI_RST}"
                    else
                        printf "  %sType       %s : %s %s(Base: %s)%s\n" "${UI_CYAN}" "${UI_RST}" "$type_badge" "${UI_DIM}" "$parent_id" "${UI_RST}"
                    fi
                else
                    printf "  %sType       %s : %s\n" "${UI_CYAN}" "${UI_RST}" "$type_badge"
                fi
            fi
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
            *SAVE*|*BACKUP*|*RESTORE*)
                advice="Savegame snapshot error. Verify disk space in target directory or storage quota."
                ;;
            *STORE*|*DOWNLOAD*|*DEPOT*)
                advice="Network or CDN timeout. Check connectivity to Steam Store or CDN endpoints."
                ;;
            *GBE*|*INJECT*)
                advice="GBE injection failure. Check file permissions or verify 32-bit vs 64-bit architecture."
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

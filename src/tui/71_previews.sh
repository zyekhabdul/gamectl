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
    local active_row=""
    active_row=$(find_active_game_for_dir "$gdir" 2>/dev/null || true)
    if [ -n "$active_row" ]; then
        local _r_title _r_dir _r_bin _r_inf _r_scope _r_sep=$'\x1f'
        IFS="$_r_sep" read -r run_pid _r_title _r_dir _r_bin run_log _r_inf _r_scope <<< "$active_row"
        is_running=true
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
    if [ "$is_running" = true ]; then
        echo "  ${UI_PILL_ENTER} ${UI_BOLD}Manage Running Game${UI_RST} ${UI_PILL_CTRLI} ${UI_BOLD}Inject GBE Fork${UI_RST}"
    else
        echo "  ${UI_PILL_ENTER} ${UI_BOLD}Launch Game${UI_RST}       ${UI_PILL_CTRLI} ${UI_BOLD}Inject GBE Fork${UI_RST}"
    fi
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
            local has_type="0" norm_type="APP" parent_id="" parent_name="" is_linux is_win genres
            if declare -F parse_steam_app_type_json >/dev/null 2>&1; then
                local parsed_type
                parsed_type=$(parse_steam_app_type_json "$details")
                IFS=$'\t' read -r has_type norm_type parent_id parent_name <<< "$parsed_type"
            fi
            if [ "$has_type" = "1" ]; then
                local type_badge
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

# Standalone-source compatibility: load split dashboard preview when sourced directly outside bin/gamectl
if [ -z "${GAMECTL_BUNDLED:-}" ] && [ -n "${BASH_SOURCE[0]:-}" ] && ! declare -F preview_dashboard >/dev/null 2>&1; then
    _prev_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd)"
    if [ -f "$_prev_dir/74_dashboard_preview.sh" ]; then
        # shellcheck source=/dev/null
        source "$_prev_dir/74_dashboard_preview.sh"
    fi
    unset _prev_dir
fi

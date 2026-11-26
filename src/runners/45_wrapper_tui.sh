# ==============================================================================
# Wrapper & Global Settings TUI Menus (Split from 40_wrappers.sh)
# ==============================================================================

# Interactive wrapper configuration for a game or global defaults
configure_wrappers() {
    require_tui "Runtime wrappers" || return $?
    local gdir="${1:-}"
    local title="${2:-}"
    local w_file

    if [ -n "$gdir" ] && [ -d "$gdir" ]; then
        [ -z "$title" ] && title="$(basename "$gdir")"
        w_file="$gdir/.wrappers"
    else
        title="Global Default Wrappers"
        mkdir -p "$HOME/.config/gamectl"
        w_file="$HOME/.config/gamectl/wrappers"
    fi

    load_wrapper_config "${gdir:-}" 0
    local gm="$GAMECTL_CFG_GM" hud="$GAMECTL_CFG_HUD" scope="$GAMECTL_CFG_SCOPE"
    local fsr="$GAMECTL_CFG_FSR" glt="$GAMECTL_CFG_GLTHREAD" renderer="${GAMECTL_CFG_RENDERER:-auto}"
    local auto_saves="${GAMECTL_CFG_AUTO_LOCATE_SAVES:-0}"
    local dev_wd="${GAMECTL_CFG_DEV_WINEDEBUG:-0}" dev_vk="${GAMECTL_CFG_DEV_VK_DEBUG:-0}" dev_gbe="${GAMECTL_CFG_DEV_GBE_LOG:-0}"
    local gscope_args="${GAMECTL_CFG_GAMESCOPE_ARGS:-}"
    [ -z "$gscope_args" ] && gscope_args=$(get_default_gamescope_args)

    while true; do
        local b_gm="${UI_DIM}[OFF]${UI_RST}" b_hud="${UI_DIM}[OFF]${UI_RST}"
        local b_scope="${UI_DIM}[OFF]${UI_RST}" b_fsr="${UI_DIM}[OFF]${UI_RST}" b_glt="${UI_DIM}[OFF]${UI_RST}"
        local b_autosaves="${UI_DIM}[OFF]${UI_RST}" b_devwd="${UI_DIM}[OFF]${UI_RST}"
        local b_devvk="${UI_DIM}[OFF]${UI_RST}" b_devgbe="${UI_DIM}[OFF]${UI_RST}"
        [ "$gm" = 1 ] && b_gm="${UI_GREEN}[ACTIVE]${UI_RST}"
        [ "$hud" = 1 ] && b_hud="${UI_GREEN}[ACTIVE]${UI_RST}"
        [ "$scope" = 1 ] && b_scope="${UI_GREEN}[ACTIVE]${UI_RST}"
        [ "$fsr" = 1 ] && b_fsr="${UI_GREEN}[ACTIVE]${UI_RST}"
        [ "$glt" = 1 ] && b_glt="${UI_GREEN}[ACTIVE]${UI_RST}"
        [ "$auto_saves" = 1 ] && b_autosaves="${UI_GREEN}[ACTIVE]${UI_RST}"
        case "${dev_wd,,}" in
            ""|0|off|false) ;;
            basic) b_devwd="${UI_AMBER}[BASIC]${UI_RST}" ;;
            full)  b_devwd="${UI_RED}[FULL]${UI_RST}" ;;
            *)     b_devwd="${UI_CYAN}[$dev_wd]${UI_RST}" ;;
        esac
        [ "$dev_vk" = 1 ] && b_devvk="${UI_AMBER}[ACTIVE]${UI_RST}"
        [ "$dev_gbe" = 1 ] && b_devgbe="${UI_AMBER}[ACTIVE]${UI_RST}"

        local eff_rend b_rend
        eff_rend="$(resolve_graphics_renderer "$renderer" 0)"
        case "$renderer" in
            wined3d) b_rend="${UI_AMBER}[WINED3D]${UI_RST}" ;;
            dxvk)    b_rend="${UI_CYAN}[DXVK]${UI_RST}" ;;
            *)       b_rend="${UI_GREEN}[AUTO -> ${eff_rend^^}]${UI_RST}" ;;
        esac

        local h_gm="${UI_DIM}[N/A]${UI_RST}" h_hud="${UI_DIM}[N/A]${UI_RST}" h_scope="${UI_DIM}[N/A]${UI_RST}"
        command -v gamemoderun >/dev/null 2>&1 && h_gm="${UI_GREEN}[READY]${UI_RST}"
        command -v mangohud >/dev/null 2>&1 && h_hud="${UI_GREEN}[READY]${UI_RST}"
        command -v gamescope >/dev/null 2>&1 && h_scope="${UI_GREEN}[READY]${UI_RST}"

        local glt_hint="${UI_DIM}(Opt-in Performance)${UI_RST}"
        is_haswell_gpu && glt_hint="${UI_AMBER}(Intel Haswell: Keep OFF)${UI_RST}"

        local entries
        entries=$(cat <<EOF
1	GameMode (gamemoderun)	$b_gm
2	MangoHud (FPS & Telemetry)	$b_hud
3	Gamescope (Isolated Window)	$b_scope
4	Gamescope FSR Upscaling	$b_fsr
5	Mesa GL Threading (mesa_gl)	$b_glt $glt_hint
r	Graphics Renderer (DXVK/WineD3D)	$b_rend
s	Auto-Locate Wine Prefix Saves	$b_autosaves
d	Dev Profiler: WINEDEBUG	$b_devwd
v	Dev Profiler: Vulkan Debug	$b_devvk
g	Dev Profiler: GBE Callback Log	$b_devgbe
6	Preset: Balanced Performance	GameMode + MangoHud
7	Preset: Handheld / FSR	GameMode + MangoHud + Gamescope FSR
8	Reset: Safe Defaults	All Disabled (Renderer: Auto)
9	Save & Return	Save configuration
0	Cancel / Discard Changes	Discard changes and return
EOF
)

        flush_tty_input
        local selection fzf_rc=0
        selection=$(echo "$entries" | fzf \
            --delimiter=$'\t' \
            --with-nth=2,3 \
            --border-label="  ╢ gamectl :: Wrappers : $title ╟  " \
            --border-label-pos=2 \
            --header="Enter: Toggle/Select │ Esc: Save & Return" \
            --prompt="Wrappers > " \
            --reverse 2>/dev/null) || fzf_rc=$?

        check_fzf_status "$fzf_rc" || return $?
        local opt
        if [ "$fzf_rc" -eq 130 ]; then
            opt="9"
        elif [ -z "$selection" ]; then
            continue
        else
            opt=$(echo "$selection" | cut -f1 | tr -d '[:space:]')
        fi

        case "$opt" in
            1) gm=$((1 - gm)) ;;
            2) hud=$((1 - hud)) ;;
            3) scope=$((1 - scope)) ;;
            4) fsr=$((1 - fsr)); [ "$fsr" = 1 ] && scope=1 ;;
            5) glt=$((1 - glt)) ;;
            r|R)
                case "$renderer" in
                    auto|"") renderer="wined3d" ;;
                    wined3d) renderer="dxvk" ;;
                    *)       renderer="auto" ;;
                esac
                ;;
            s|S) auto_saves=$((1 - auto_saves)) ;;
            d|D)
                case "${dev_wd,,}" in
                    ""|0|off|false) dev_wd="basic" ;;
                    basic) dev_wd="full" ;;
                    *)     dev_wd="0" ;;
                esac
                ;;
            v|V) dev_vk=$((1 - dev_vk)) ;;
            g|G) dev_gbe=$((1 - dev_gbe)) ;;
            6) gm=1; hud=1; scope=0; fsr=0; glt=0 ;;
            7) gm=1; hud=1; scope=1; fsr=1; glt=0 ;;
            8) gm=0; hud=0; scope=0; fsr=0; glt=0; renderer="auto"; auto_saves=0; dev_wd="0"; dev_vk=0; dev_gbe=0 ;;
            9)
                cat <<EOF > "$w_file"
# Runtime wrappers for $title
gamemode=$gm
hud=$hud
gamescope=$scope
fsr=$fsr
glthread=$glt
renderer=$renderer
gamescope_args=$gscope_args
auto_locate_saves=$auto_saves
dev_winedebug=$dev_wd
dev_vk_debug=$dev_vk
dev_gbe_log=$dev_gbe
EOF
                log_msg "INFO" "WRAPPERS" "Saved wrapper configuration for $title -> $w_file (gm=$gm,hud=$hud,scope=$scope,fsr=$fsr,glt=$glt,renderer=$renderer,auto_saves=$auto_saves,dev_wd=$dev_wd,dev_vk=$dev_vk,dev_gbe=$dev_gbe)"
                break
                ;;
            0|q|Q|cancel)
                return 0
                ;;
            *)
                continue
                ;;
        esac
    done
}

# Global Configuration Manager TUI
configure_global() {
    require_tui "Global settings" || return $?
    mkdir -p "$HOME/.config/gamectl"

    while true; do
        local p_name="Player" p_id=""
        if [ -f "$HOME/.config/gamectl/persona" ]; then
            p_name=$(grep -E '^[[:space:]]*account_name[[:space:]]*=' "$HOME/.config/gamectl/persona" 2>/dev/null | head -n 1 | sed -E 's/^[[:space:]]*account_name[[:space:]]*=[[:space:]]*//' | tr -d '\r')
            p_id=$(grep -E '^[[:space:]]*account_steamid[[:space:]]*=' "$HOME/.config/gamectl/persona" 2>/dev/null | head -n 1 | sed -E 's/^[[:space:]]*account_steamid[[:space:]]*=[[:space:]]*//' | tr -d '\r')
        fi
        [ -z "$p_name" ] && p_name="${USER:-Player}"

        local w_desc="Default (All Disabled)"
        if [ -f "$HOME/.config/gamectl/wrappers" ]; then
            local act_w=()
            grep -q "^gamemode=1" "$HOME/.config/gamectl/wrappers" 2>/dev/null && act_w+=("GameMode")
            grep -q -E "^(hud|mangohud)=1" "$HOME/.config/gamectl/wrappers" 2>/dev/null && act_w+=("MangoHud")
            grep -q "^gamescope=1" "$HOME/.config/gamectl/wrappers" 2>/dev/null && act_w+=("Gamescope")
            grep -q "^fsr=1" "$HOME/.config/gamectl/wrappers" 2>/dev/null && act_w+=("FSR")
            grep -q -E "^(glthread|mesa_glthread)=1" "$HOME/.config/gamectl/wrappers" 2>/dev/null && act_w+=("MesaGL")
            [ ${#act_w[@]} -gt 0 ] && w_desc="${act_w[*]}"
        fi

        local lib_count=0
        [ -f "$HOME/.config/gamectl/libraries" ] && lib_count=$(grep -v -E '^[[:space:]]*(#|$)' "$HOME/.config/gamectl/libraries" 2>/dev/null | wc -l || echo 0)

        local r_host="Not Configured"
        if [ -f "$HOME/.config/gamectl/remote_host" ]; then
            r_host=$(head -n 1 "$HOME/.config/gamectl/remote_host" 2>/dev/null | tr -d '[:space:]')
            [ -z "$r_host" ] && r_host="Not Configured"
        fi

        local lt_status="Not Configured"
        local cfg_auth="$HOME/.config/gamectl/lua_tools_auth.json"
        if [ -f "$cfg_auth" ]; then
            local u_name
            u_name=$(jq -r '.user.user_metadata.custom_claims.global_name // .user.user_metadata.full_name // .user.email // "Active"' "$cfg_auth" 2>/dev/null || echo "Active")
            lt_status="Active ($u_name)"
        fi

        local hc_status="Not Configured"
        local hc_key
        hc_key=$(get_hubcap_api_key 2>/dev/null || true)
        if [ -n "$hc_key" ]; then
            if [ ${#hc_key} -gt 8 ]; then
                hc_status="Active (${hc_key:0:4}...${hc_key: -4})"
            else
                hc_status="Active"
            fi
        fi

        validate_tui_fields "$p_name" "$p_id" "$r_host" "$lt_status" "$hc_status" || return 1
        local menu_entries
        menu_entries=$(cat <<EOF
1	Global LAN Persona	Name: $p_name | SteamID: ${p_id:-Auto}
2	Default Runtime Wrappers	$w_desc
3	Custom Game Libraries	$lib_count paths registered
4	Remote Companion Host	$r_host
5	LuaTools Provider Session	$lt_status
6	Hubcap Manifest API Key	$hc_status
7	Return to Master Dashboard Hub	Return
EOF
)

        flush_tty_input
        local selection fzf_rc=0
        selection=$(echo "$menu_entries" | fzf \
            --delimiter=$'\t' \
            --with-nth=2,3 \
            --border-label="  ╢ gamectl :: Global Settings (~/.config/gamectl/) ╟  " \
            --border-label-pos=2 \
            --header="GLOBAL SETTINGS (Enter: Configure │ Esc: Return to Dashboard)" \
            --prompt="Settings > " \
            --reverse 2>/dev/null) || fzf_rc=$?

        check_fzf_status "$fzf_rc" || return $?
        [ "$fzf_rc" -eq 130 ] && break
        [ -z "$selection" ] && continue

        local cfg_opt
        cfg_opt=$(echo "$selection" | cut -f1 | tr -d '[:space:]')

        case "$cfg_opt" in
            1)
                local new_name rc=0
                new_name=$(tui_prompt_input "Configure LAN Persona Name" "Enter Player Name (Current: $p_name │ Enter: Confirm │ Esc: Cancel)" "$p_name" "Player Name > ") || rc=$?
                [ "$rc" -eq 130 ] && continue
                [ "$rc" -ne 0 ] && return "$rc"
                validate_tui_fields "$new_name" || return 1
                [ -n "$new_name" ] && p_name="$new_name"

                local new_id
                rc=0
                new_id=$(tui_prompt_input "Configure SteamID64" "Enter 17-digit SteamID64, 'gen' for random ID, or blank for Auto (Current: ${p_id:-Auto})" "" "SteamID64 > ") || rc=$?
                [ "$rc" -eq 130 ] && continue
                [ "$rc" -ne 0 ] && return "$rc"
                new_id=$(echo "$new_id" | tr -d '[:space:]')
                if [ "$new_id" = "gen" ]; then
                    p_id=$(generate_steamid64)
                elif [ -n "$new_id" ]; then
                    p_id="$new_id"
                fi

                cat <<EOF > "$HOME/.config/gamectl/persona"
[user::general]
account_name=$p_name
account_steamid=$p_id
language=english
EOF
                log_msg "INFO" "CONFIG" "Saved global LAN persona: $p_name | $p_id"
                ;;
            2)
                configure_wrappers "" || return $?
                ;;
            3)
                while true; do
                    local lib_items=""
                    local l_idx=1
                    if [ -f "$HOME/.config/gamectl/libraries" ]; then
                        while IFS= read -r l_path; do
                            [ -z "$l_path" ] && continue
                            [[ "$l_path" =~ ^[[:space:]]*# ]] && continue
                            validate_tui_fields "$l_path" || return 1
                            lib_items+="${l_idx}"$'\t'"[REMOVE] $l_path"$'\t'"Select to remove this library path"$'\n'
                            l_idx=$((l_idx + 1))
                        done < "$HOME/.config/gamectl/libraries"
                    fi
                    local lib_menu
                    lib_menu=$(cat <<EOF
add	[+] Register New Library Path	Enter filesystem path (e.g. ~/Games)
EOF
)
                    [ -n "$lib_items" ] && lib_menu="${lib_menu}"$'\n'"${lib_items%$'\n'}"
                    lib_menu="${lib_menu}"$'\n'"back	[<] Return to Global Settings	Back"

                    flush_tty_input
                    local lib_sel l_rc=0
                    lib_sel=$(echo "$lib_menu" | fzf \
                        --delimiter=$'\t' \
                        --with-nth=2,3 \
                        --border-label="  ╢ gamectl :: Custom Game Libraries ╟  " \
                        --border-label-pos=2 \
                        --header="CUSTOM LIBRARIES (Enter: Select │ Esc: Return)" \
                        --prompt="Libraries > " \
                        --reverse 2>/dev/null) || l_rc=$?

                    check_fzf_status "$l_rc" || return $?
                    [ "$l_rc" -eq 130 ] && break
                    [ -z "$lib_sel" ] && continue

                    local l_action
                    l_action=$(echo "$lib_sel" | cut -f1 | tr -d '[:space:]')

                    if [ "$l_action" = "add" ]; then
                        local new_path rc=0
                        new_path=$(tui_prompt_input "Add Game Library Directory" "Enter directory path (e.g. ~/Games │ Enter: Add │ Esc: Cancel)" "" "Path > ") || rc=$?
                        [ "$rc" -eq 130 ] && continue
                        [ "$rc" -ne 0 ] && return "$rc"
                        validate_tui_fields "$new_path" || return 1
                        if [ -n "$new_path" ]; then
                            new_path="${new_path/#\~/$HOME}"
                            echo "$new_path" >> "$HOME/.config/gamectl/libraries"
                            log_msg "INFO" "CONFIG" "Added custom library: $new_path"
                            invalidate_scan_cache
                        fi
                    elif [ "$l_action" = "back" ]; then
                        break
                    else
                        local target_line
                        target_line=$(grep -v -E '^[[:space:]]*(#|$)' "$HOME/.config/gamectl/libraries" 2>/dev/null | sed -n "${l_action}p")
                        if [ -n "$target_line" ]; then
                            grep -v -F "$target_line" "$HOME/.config/gamectl/libraries" > "$HOME/.config/gamectl/libraries.tmp" 2>/dev/null && mv "$HOME/.config/gamectl/libraries.tmp" "$HOME/.config/gamectl/libraries"
                            log_msg "INFO" "CONFIG" "Removed custom library: $target_line"
                            invalidate_scan_cache
                        fi
                    fi
                done
                ;;
            4)
                local new_rhost rc=0
                new_rhost=$(tui_prompt_input "Remote Companion Host" "Enter SSH host (serv, host:~/path), rclone (gdrive:path), or '-' to clear (Current: $r_host │ Enter: Save │ Esc: Cancel)" "$r_host" "Remote Target > ") || rc=$?
                [ "$rc" -eq 130 ] && continue
                [ "$rc" -ne 0 ] && return "$rc"
                new_rhost=$(printf '%s' "$new_rhost" | tr -d '[:space:]')
                if [ "$new_rhost" = "-" ]; then
                    rm -f "$HOME/.config/gamectl/remote_host"
                    log_msg "INFO" "CONFIG" "Cleared remote companion host"
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
                fi
                ;;
            5)
                login_luatools_interactive || return $?
                ;;
            6)
                local new_hckey rc=0
                new_hckey=$(tui_prompt_input "Hubcap Manifest API Key" "Enter Hubcap API key (prefix 'smm_') or '-' to clear (Current: $hc_status │ Enter: Save │ Esc: Cancel)" "" "Hubcap Key > ") || rc=$?
                [ "$rc" -eq 130 ] && continue
                [ "$rc" -ne 0 ] && return "$rc"
                new_hckey=$(echo "$new_hckey" | tr -d '[:space:]')
                if [ "$new_hckey" = "-" ]; then
                    set_config_value "hubcap_api_key" ""
                    log_msg "INFO" "CONFIG" "Cleared Hubcap Manifest API key"
                elif [ -n "$new_hckey" ]; then
                    set_config_value "hubcap_api_key" "$new_hckey"
                    log_msg "INFO" "CONFIG" "Saved Hubcap Manifest API key (${new_hckey:0:4}...)"
                fi
                ;;
            7)
                break
                ;;
            0|q|Q|cancel)
                break
                ;;
            *)
                continue
                ;;
        esac
    done
}

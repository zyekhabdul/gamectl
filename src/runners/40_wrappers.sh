# Discover runner for Windows games (priority: umu-run -> GE-Proton / Proton Steam -> wine)
find_runner() {
    local target_dir="${1:-}"

    # Priority 0: Per-game runner override or environment override
    if [ -n "$target_dir" ] && [ -f "$target_dir/.runner" ]; then
        local g_runner
        g_runner=$(head -n 1 "$target_dir/.runner" | tr -d '[:space:]')
        if [ -n "$g_runner" ] && { [ -x "$g_runner" ] || command -v "$g_runner" >/dev/null 2>&1; }; then
            echo "$g_runner"
            return 0
        fi
    fi
    if [ -n "${GAMECTL_RUNNER:-}" ]; then
        if [ -x "$GAMECTL_RUNNER" ] || command -v "$GAMECTL_RUNNER" >/dev/null 2>&1; then
            echo "$GAMECTL_RUNNER"
            return 0
        fi
    fi
    if [ -f "$HOME/.config/gamectl/runner" ]; then
        local user_runner
        user_runner=$(head -n 1 "$HOME/.config/gamectl/runner" | tr -d '[:space:]')
        if [ -n "$user_runner" ] && { [ -x "$user_runner" ] || command -v "$user_runner" >/dev/null 2>&1; }; then
            echo "$user_runner"
            return 0
        fi
    fi

    # Priority 1: umu-run
    if command -v umu-run >/dev/null 2>&1; then
        echo "umu-run"
        return 0
    fi

    # Priority 2: GE-Proton / Proton in Steam compatibilitytools.d or common
    local s_dyn_root
    s_dyn_root="$(get_steam_root 2>/dev/null || true)"
    local compat_dirs=(
        "$s_dyn_root/compatibilitytools.d"
        "$HOME/.local/share/Steam/compatibilitytools.d"
        "$HOME/.steam/root/compatibilitytools.d"
        "$HOME/.var/app/com.valvesoftware.Steam/.local/share/Steam/compatibilitytools.d"
    )
    for cdir in "${compat_dirs[@]}"; do
        [ -d "$cdir" ] || continue
        local p
        while read -r p; do
            [ -z "$p" ] && continue
            if [ -x "$p/proton" ]; then
                echo "$p/proton"
                return 0
            fi
        done < <(find "$cdir" -mindepth 1 -maxdepth 1 -type d -name "*Proton*" 2>/dev/null | sort -Vr)
    done

    # Check Proton in Steam common libraries
    local steam_lib
    while read -r steam_lib; do
        [ -d "$steam_lib/common" ] || continue
        local p
        while read -r p; do
            [ -z "$p" ] && continue
            if [ -x "$p/proton" ]; then
                echo "$p/proton"
                return 0
            fi
        done < <(find "$steam_lib/common" -mindepth 1 -maxdepth 1 -type d -name "Proton*" 2>/dev/null | sort -Vr)
    done < <(get_steam_libraries 2>/dev/null || true)

    # Priority 3: System Wine
    if command -v wine64 >/dev/null 2>&1; then
        echo "wine64"
        return 0
    elif command -v wine >/dev/null 2>&1; then
        echo "wine"
        return 0
    fi

    # Priority 4: Internal wine binary inside GE-Proton files/bin
    for cdir in "${compat_dirs[@]}"; do
        [ -d "$cdir" ] || continue
        local w
        w=$(find "$cdir" -type f -name "wine64" -o -name "wine" 2>/dev/null | head -n 1)
        if [ -n "$w" ] && [ -x "$w" ]; then
            echo "$w"
            return 0
        fi
    done

    return 1
}

# Check if host GPU is Intel Haswell / 4th Gen Core (prone to Mesa GL threaded asset decompression crashes)
is_haswell_gpu() {
    local gpu_info=""
    if command -v lspci >/dev/null 2>&1; then
        gpu_info=$(lspci 2>/dev/null | grep -E "VGA|3D" || true)
    fi
    if [ -z "$gpu_info" ] && [ -d /sys/bus/pci/devices ]; then
        gpu_info=$(cat /sys/bus/pci/devices/*/uevent 2>/dev/null | grep -E "PCI_ID=" || true)
    fi
    if echo "$gpu_info" | grep -qi -E "Haswell|4th Gen Core"; then
        return 0
    fi
    return 1
}

# Dynamically detect host native display resolution via DRM / Wayland / X11
get_native_resolution() {
    local res=""
    # Priority 1: DRM kernel modes (direct & universal across all compositors/X11)
    for m_file in /sys/class/drm/card*-*/modes; do
        [ -f "$m_file" ] || continue
        local s_file="$(dirname "$m_file")/status"
        if [ -f "$s_file" ] && grep -q "^connected" "$s_file" 2>/dev/null; then
            local line
            line=$(head -n 1 "$m_file" 2>/dev/null | tr -d '[:space:]')
            if [[ "$line" =~ ^[0-9]+x[0-9]+$ ]]; then
                res="$line"
                break
            fi
        fi
    done

    # Priority 2: Hyprland monitor inspection
    if [ -z "$res" ] && command -v hyprctl >/dev/null 2>&1; then
        res=$(hyprctl monitors 2>/dev/null | grep -E '^[[:space:]]*[0-9]+x[0-9]+@' | head -n 1 | sed -E 's/.*([0-9]+x[0-9]+)@.*/\1/' || true)
    fi

    # Priority 3: X11 / Xwayland via xrandr
    if [ -z "$res" ] && command -v xrandr >/dev/null 2>&1; then
        res=$(xrandr --current 2>/dev/null | grep -E '\bconnected\b' | grep -o -E '[0-9]+x[0-9]+\+[0-9]+\+[0-9]+' | head -n 1 | cut -d'+' -f1 || true)
        [ -z "$res" ] && res=$(xrandr --current 2>/dev/null | grep -E '^[[:space:]]+[0-9]+x[0-9]+' | head -n 1 | awk '{print $1}' || true)
    fi

    # Fallback default
    if [[ ! "$res" =~ ^[0-9]+x[0-9]+$ ]]; then
        res="1920x1080"
    fi
    echo "$res"
}

# Dynamically calculate Gamescope display & FSR render arguments based on native resolution
get_default_gamescope_args() {
    local n_res
    n_res=$(get_native_resolution)
    local nw="${n_res%x*}"
    local nh="${n_res#*x}"

    local rw rh
    if [ "$nw" -ge 3840 ] && [ "$nh" -ge 2160 ]; then
        rw=2560; rh=1440
    elif [ "$nw" -ge 2560 ] && [ "$nh" -ge 1440 ]; then
        rw=1920; rh=1080
    elif [ "$nw" -eq 1920 ] && [ "$nh" -eq 1080 ]; then
        rw=1280; rh=720
    elif [ "$nw" -eq 1600 ] && [ "$nh" -eq 900 ]; then
        rw=1280; rh=720
    elif [ "$nw" -eq 1280 ] && [ "$nh" -eq 800 ]; then
        rw=960; rh=600
    else
        rw=$(( (nw * 2 / 3 + 1) / 2 * 2 ))
        rh=$(( (nh * 2 / 3 + 1) / 2 * 2 ))
    fi
    echo "-W $rw -H $rh -w $nw -h $nh -F fsr -f"
}

# Resolve and build wrapper prefix command array (gamemoderun, mangohud, gamescope)
build_wrapper_command() {
    local gdir="$1"
    shift || true
    local opt_gamemode="" opt_hud="" opt_gamescope="" opt_fsr=""
    local remaining_args=()

    while [ $# -gt 0 ]; do
        case "$1" in
            --hud|--mangohud) opt_hud=1; shift ;;
            --no-hud|--no-mangohud) opt_hud=0; shift ;;
            --gamemode) opt_gamemode=1; shift ;;
            --no-gamemode) opt_gamemode=0; shift ;;
            --gamescope) opt_gamescope=1; shift ;;
            --no-gamescope) opt_gamescope=0; shift ;;
            --fsr) opt_fsr=1; opt_gamescope=1; shift ;;
            --no-fsr) opt_fsr=0; shift ;;
            --glthread) opt_glthread=1; shift ;;
            --no-glthread) opt_glthread=0; shift ;;
            --) shift; remaining_args+=("$@"); break ;;
            *) remaining_args+=("$1"); shift ;;
        esac
    done

    # 1. Base defaults
    local use_gm=0 use_hud=0 use_scope=0 use_fsr=0 use_glthread=0
    local gscope_args
    gscope_args=$(get_default_gamescope_args)

    # 2. Global configuration (~/.config/gamectl/wrappers)
    if [ -f "$HOME/.config/gamectl/wrappers" ]; then
        while IFS='=' read -r k v || [ -n "$k" ]; do
            k=$(echo "$k" | tr -d '[:space:]')
            v=$(echo "$v" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' -e 's/^"//' -e 's/"$//')
            [[ "$k" =~ ^# ]] && continue
            case "$k" in
                gamemode) use_gm="$v" ;;
                hud|mangohud) use_hud="$v" ;;
                gamescope) use_scope="$v" ;;
                fsr) use_fsr="$v" ;;
                glthread|mesa_glthread) use_glthread="$v" ;;
                gamescope_args) gscope_args="$v" ;;
            esac
        done < "$HOME/.config/gamectl/wrappers"
    fi

    # 3. Per-game override ($gdir/.wrappers)
    if [ -n "$gdir" ] && [ -f "$gdir/.wrappers" ]; then
        while IFS='=' read -r k v || [ -n "$k" ]; do
            k=$(echo "$k" | tr -d '[:space:]')
            v=$(echo "$v" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' -e 's/^"//' -e 's/"$//')
            [[ "$k" =~ ^# ]] && continue
            case "$k" in
                gamemode) use_gm="$v" ;;
                hud|mangohud) use_hud="$v" ;;
                gamescope) use_scope="$v" ;;
                fsr) use_fsr="$v" ;;
                glthread|mesa_glthread) use_glthread="$v" ;;
                gamescope_args) gscope_args="$v" ;;
            esac
        done < "$gdir/.wrappers"
    fi

    # 4. Environment variable overrides
    [ -n "${GAMECTL_GAMEMODE:-}" ] && use_gm="$GAMECTL_GAMEMODE"
    [ -n "${GAMECTL_HUD:-${GAMECTL_MANGOHUD:-}}" ] && use_hud="${GAMECTL_HUD:-$GAMECTL_MANGOHUD}"
    [ -n "${GAMECTL_GAMESCOPE:-}" ] && use_scope="$GAMECTL_GAMESCOPE"
    [ -n "${GAMECTL_FSR:-}" ] && use_fsr="$GAMECTL_FSR"
    [ -n "${GAMECTL_GLTHREAD:-}" ] && use_glthread="$GAMECTL_GLTHREAD"
    [ -n "${GAMECTL_GAMESCOPE_ARGS:-}" ] && gscope_args="$GAMECTL_GAMESCOPE_ARGS"

    # 5. CLI flag overrides
    [ -n "$opt_gamemode" ] && use_gm="$opt_gamemode"
    [ -n "$opt_hud" ] && use_hud="$opt_hud"
    [ -n "$opt_gamescope" ] && use_scope="$opt_gamescope"
    [ -n "$opt_fsr" ] && use_fsr="$opt_fsr"
    [ -n "${opt_glthread:-}" ] && use_glthread="$opt_glthread"

    GAMECTL_ACTIVE_GLTHREAD="$use_glthread"

    local prefix=()
    if [ "$use_gm" = "1" ]; then
        if command -v gamemoderun >/dev/null 2>&1; then
            prefix+=("gamemoderun")
        else
            echo "[WARN] gamemoderun diaktifkan tetapi biner tidak ditemukan di PATH." >&2
        fi
    fi

    if [ "$use_hud" = "1" ]; then
        if command -v mangohud >/dev/null 2>&1; then
            prefix+=("mangohud")
        else
            echo "[WARN] mangohud diaktifkan tetapi biner tidak ditemukan di PATH." >&2
        fi
    fi

    if [ "$use_scope" = "1" ] || [ "$use_fsr" = "1" ]; then
        if command -v gamescope >/dev/null 2>&1; then
            prefix+=("gamescope")
            local active_args="$gscope_args"
            if [ "$use_fsr" = "1" ] && [[ ! "$active_args" =~ (-F|fsr|-U) ]]; then
                active_args="-F fsr $active_args"
            elif [ "$use_fsr" = "0" ]; then
                active_args=$(echo "$active_args" | sed -E 's/-F[[:space:]]+fsr//g' | xargs)
            fi
            if [ -n "$active_args" ]; then
                read -r -a parsed_args <<< "$active_args"
                prefix+=("${parsed_args[@]}")
            fi
            prefix+=("--")
        else
            echo "[WARN] gamescope diaktifkan tetapi biner tidak ditemukan di PATH." >&2
        fi
    fi

    GAMECTL_WRAPPER_PREFIX=("${prefix[@]}")
    GAMECTL_REMAINING_ARGS=("${remaining_args[@]}")
}

# Interactive wrapper configuration for a game or global defaults
configure_wrappers() {
    local gdir="$1"
    local title="${2:-$(basename "$gdir")}"
    local w_file="$gdir/.wrappers"

    local gm=0 hud=0 scope=0 fsr=0 glt=0
    local gscope_args
    gscope_args=$(get_default_gamescope_args)
    if [ -f "$HOME/.config/gamectl/wrappers" ]; then
        grep -q "^gamemode=1" "$HOME/.config/gamectl/wrappers" 2>/dev/null && gm=1
        grep -q -E "^(hud|mangohud)=1" "$HOME/.config/gamectl/wrappers" 2>/dev/null && hud=1
        grep -q "^gamescope=1" "$HOME/.config/gamectl/wrappers" 2>/dev/null && scope=1
        grep -q "^fsr=1" "$HOME/.config/gamectl/wrappers" 2>/dev/null && fsr=1
        grep -q -E "^(glthread|mesa_glthread)=1" "$HOME/.config/gamectl/wrappers" 2>/dev/null && glt=1
        local g_custom
        g_custom=$(grep -E '^[[:space:]]*gamescope_args[[:space:]]*=' "$HOME/.config/gamectl/wrappers" 2>/dev/null | head -n 1 | sed -E 's/^[[:space:]]*gamescope_args[[:space:]]*=[[:space:]]*//' | tr -d '\r')
        [ -n "$g_custom" ] && gscope_args="$g_custom"
    fi
    if [ -f "$w_file" ]; then
        grep -q "^gamemode=1" "$w_file" 2>/dev/null && gm=1
        grep -q "^gamemode=0" "$w_file" 2>/dev/null && gm=0
        grep -q -E "^(hud|mangohud)=1" "$w_file" 2>/dev/null && hud=1
        grep -q -E "^(hud|mangohud)=0" "$w_file" 2>/dev/null && hud=0
        grep -q "^gamescope=1" "$w_file" 2>/dev/null && scope=1
        grep -q "^gamescope=0" "$w_file" 2>/dev/null && scope=0
        grep -q "^fsr=1" "$w_file" 2>/dev/null && fsr=1
        grep -q "^fsr=0" "$w_file" 2>/dev/null && fsr=0
        grep -q -E "^(glthread|mesa_glthread)=1" "$w_file" 2>/dev/null && glt=1
        grep -q -E "^(glthread|mesa_glthread)=0" "$w_file" 2>/dev/null && glt=0
        local w_custom
        w_custom=$(grep -E '^[[:space:]]*gamescope_args[[:space:]]*=' "$w_file" 2>/dev/null | head -n 1 | sed -E 's/^[[:space:]]*gamescope_args[[:space:]]*=[[:space:]]*//' | tr -d '\r')
        [ -n "$w_custom" ] && gscope_args="$w_custom"
    fi

    while true; do
        local b_gm="${UI_DIM}[OFF]${UI_RST}" b_hud="${UI_DIM}[OFF]${UI_RST}"
        local b_scope="${UI_DIM}[OFF]${UI_RST}" b_fsr="${UI_DIM}[OFF]${UI_RST}" b_glt="${UI_DIM}[OFF]${UI_RST}"
        [ "$gm" = 1 ] && b_gm="${UI_GREEN}[ACTIVE]${UI_RST}"
        [ "$hud" = 1 ] && b_hud="${UI_GREEN}[ACTIVE]${UI_RST}"
        [ "$scope" = 1 ] && b_scope="${UI_GREEN}[ACTIVE]${UI_RST}"
        [ "$fsr" = 1 ] && b_fsr="${UI_GREEN}[ACTIVE]${UI_RST}"
        [ "$glt" = 1 ] && b_glt="${UI_GREEN}[ACTIVE]${UI_RST}"

        local h_gm="${UI_DIM}[N/A]${UI_RST}" h_hud="${UI_DIM}[N/A]${UI_RST}" h_scope="${UI_DIM}[N/A]${UI_RST}"
        command -v gamemoderun >/dev/null 2>&1 && h_gm="${UI_GREEN}[READY]${UI_RST}"
        command -v mangohud >/dev/null 2>&1 && h_hud="${UI_GREEN}[READY]${UI_RST}"
        command -v gamescope >/dev/null 2>&1 && h_scope="${UI_GREEN}[READY]${UI_RST}"

        local glt_hint="${UI_DIM}(Opt-in Performance)${UI_RST}"
        is_haswell_gpu && glt_hint="${UI_AMBER}(Intel Haswell: Keep OFF)${UI_RST}"

        clear
        echo "${UI_BOX}╭─ CONFIGURE RUNTIME WRAPPERS: ${UI_BOLD}${title}${UI_RST}${UI_BOX} ────────────╮${UI_RST}"
        echo "│ ${UI_CYAN}Host Tools${UI_RST}: GameMode $h_gm • MangoHud $h_hud • Gamescope $h_scope"
        echo "${UI_BOX}╰─────────────────────────────────────────────────────────────╯${UI_RST}"
        echo "  ${UI_PURPLE}1)${UI_RST} GameMode (gamemoderun)       : $b_gm"
        echo "  ${UI_PURPLE}2)${UI_RST} MangoHud (FPS & Telemetry)   : $b_hud"
        echo "  ${UI_PURPLE}3)${UI_RST} Gamescope (Isolated Window)  : $b_scope"
        echo "  ${UI_PURPLE}4)${UI_RST} Gamescope FSR Upscaling      : $b_fsr"
        echo "  ${UI_PURPLE}5)${UI_RST} Mesa GL Threading (mesa_gl)  : $b_glt $glt_hint"
        echo "${UI_BOX}  ─────────────────────────────────────────────────────────────${UI_RST}"
        echo "  ${UI_CYAN}6)${UI_RST} Preset: Balanced Performance (GameMode + MangoHud)"
        echo "  ${UI_CYAN}7)${UI_RST} Preset: Handheld / FSR (GameMode + MangoHud + Gamescope FSR)"
        echo "  ${UI_CYAN}8)${UI_RST} Reset: Safe Defaults (All Disabled)"
        echo "  ${UI_GREEN}9)${UI_RST} Save & Return to Library"
        echo "  ${UI_RED}0)${UI_RST} Cancel / Discard Changes"
        echo
        read -r -p "Select option [0-9]: " opt
        case "$opt" in
            1) gm=$((1 - gm)) ;;
            2) hud=$((1 - hud)) ;;
            3) scope=$((1 - scope)) ;;
            4) fsr=$((1 - fsr)); [ "$fsr" = 1 ] && scope=1 ;;
            5) glt=$((1 - glt)) ;;
            6) gm=1; hud=1; scope=0; fsr=0; glt=0 ;;
            7) gm=1; hud=1; scope=1; fsr=1; glt=0 ;;
            8) gm=0; hud=0; scope=0; fsr=0; glt=0 ;;
            9)
                cat <<EOF > "$w_file"
# Runtime wrappers for $title
gamemode=$gm
hud=$hud
gamescope=$scope
fsr=$fsr
glthread=$glt
gamescope_args=$gscope_args
EOF
                echo "[VERIFIED] Wrapper configuration saved to: $w_file"
                sleep 0.8
                break
                ;;
            0|q|Q)
                return 0
                ;;
            *)
                ;;
        esac
    done
}

# Global Configuration Manager TUI
configure_global() {
    mkdir -p "$HOME/.config/gamectl"

    while true; do
        clear
        echo "${UI_BOX}╭─ GLOBAL SETTINGS (~/.config/gamectl/) ──────────────────────╮${UI_RST}"
        echo "│ ${UI_CYAN}Default Persona, Runtime Wrappers, Libraries & Companion${UI_RST}"
        echo "${UI_BOX}╰─────────────────────────────────────────────────────────────╯${UI_RST}"
        local p_name="Player" p_id=""
        if [ -f "$HOME/.config/gamectl/persona" ]; then
            p_name=$(grep -E '^[[:space:]]*account_name[[:space:]]*=' "$HOME/.config/gamectl/persona" 2>/dev/null | head -n 1 | sed -E 's/^[[:space:]]*account_name[[:space:]]*=[[:space:]]*//' | tr -d '\r')
            p_id=$(grep -E '^[[:space:]]*account_steamid[[:space:]]*=' "$HOME/.config/gamectl/persona" 2>/dev/null | head -n 1 | sed -E 's/^[[:space:]]*account_steamid[[:space:]]*=[[:space:]]*//' | tr -d '\r')
        fi
        [ -z "$p_name" ] && p_name="${USER:-Player}"

        local w_desc="Default (Semua Nonaktif)"
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

        echo "  ${UI_PURPLE}1)${UI_RST} Global LAN Persona     : ${UI_BOLD}$p_name${UI_RST} ${UI_DIM}(SteamID: ${p_id:-Auto})${UI_RST}"
        echo "  ${UI_PURPLE}2)${UI_RST} Default Wrappers       : ${UI_BOLD}$w_desc${UI_RST}"
        echo "  ${UI_PURPLE}3)${UI_RST} Custom Game Libraries  : ${UI_BOLD}$lib_count${UI_RST} ${UI_DIM}paths registered${UI_RST}"
        echo "  ${UI_PURPLE}4)${UI_RST} Remote Companion Host  : ${UI_BOLD}$r_host${UI_RST}"
        echo "${UI_BOX}  ─────────────────────────────────────────────────────────────${UI_RST}"
        echo "  ${UI_GREEN}5)${UI_RST} Return to Master Dashboard Hub"
        echo
        read -r -p "Select option [1-5]: " cfg_opt

        case "$cfg_opt" in
            1)
                echo
                echo "${UI_BOX}╭─ GLOBAL LAN PERSONA SETTINGS ───────────────────────────────╮${UI_RST}"
                echo -n "  Player Name [$p_name]: "; read -r new_name
                [ -n "$new_name" ] && p_name="$new_name"
                echo -n "  SteamID64 [${p_id:-Auto}] ('gen' for random ID): "; read -r new_id
                if [ "$new_id" = "gen" ]; then
                    p_id=$(generate_steamid64)
                    echo "  [INFO] Generated SteamID64: $p_id"
                elif [ -n "$new_id" ]; then
                    p_id="$new_id"
                fi
                cat <<EOF > "$HOME/.config/gamectl/persona"
[user::general]
account_name=$p_name
account_steamid=$p_id
language=english
EOF
                echo "  ${UI_GREEN}[SUCCESS] Persona saved: $p_name | $p_id${UI_RST}"
                sleep 0.8
                ;;
            2)
                local gm=0 hud=0 scope=0 fsr=0 glt=0
                local gscope_args
                gscope_args=$(get_default_gamescope_args)
                if [ -f "$HOME/.config/gamectl/wrappers" ]; then
                    grep -q "^gamemode=1" "$HOME/.config/gamectl/wrappers" 2>/dev/null && gm=1
                    grep -q -E "^(hud|mangohud)=1" "$HOME/.config/gamectl/wrappers" 2>/dev/null && hud=1
                    grep -q "^gamescope=1" "$HOME/.config/gamectl/wrappers" 2>/dev/null && scope=1
                    grep -q "^fsr=1" "$HOME/.config/gamectl/wrappers" 2>/dev/null && fsr=1
                    grep -q -E "^(glthread|mesa_glthread)=1" "$HOME/.config/gamectl/wrappers" 2>/dev/null && glt=1
                    local g_custom
                    g_custom=$(grep -E '^[[:space:]]*gamescope_args[[:space:]]*=' "$HOME/.config/gamectl/wrappers" 2>/dev/null | head -n 1 | sed -E 's/^[[:space:]]*gamescope_args[[:space:]]*=[[:space:]]*//' | tr -d '\r')
                    [ -n "$g_custom" ] && gscope_args="$g_custom"
                fi
                while true; do
                    local b_gm="${UI_DIM}[OFF]${UI_RST}" b_hud="${UI_DIM}[OFF]${UI_RST}"
                    local b_scope="${UI_DIM}[OFF]${UI_RST}" b_fsr="${UI_DIM}[OFF]${UI_RST}" b_glt="${UI_DIM}[OFF]${UI_RST}"
                    [ "$gm" = 1 ] && b_gm="${UI_GREEN}[ACTIVE]${UI_RST}"
                    [ "$hud" = 1 ] && b_hud="${UI_GREEN}[ACTIVE]${UI_RST}"
                    [ "$scope" = 1 ] && b_scope="${UI_GREEN}[ACTIVE]${UI_RST}"
                    [ "$fsr" = 1 ] && b_fsr="${UI_GREEN}[ACTIVE]${UI_RST}"
                    [ "$glt" = 1 ] && b_glt="${UI_GREEN}[ACTIVE]${UI_RST}"

                    local glt_hint="${UI_DIM}(Opt-in Performance)${UI_RST}"
                    is_haswell_gpu && glt_hint="${UI_AMBER}(Intel Haswell: Keep OFF)${UI_RST}"

                    clear
                    echo "${UI_BOX}╭─ DEFAULT GLOBAL RUNTIME WRAPPERS ───────────────────────────╮${UI_RST}"
                    echo "│ ${UI_CYAN}These wrappers apply to all games unless overridden per-game${UI_RST}"
                    echo "${UI_BOX}╰─────────────────────────────────────────────────────────────╯${UI_RST}"
                    echo "  ${UI_PURPLE}1)${UI_RST} GameMode (gamemoderun)       : $b_gm"
                    echo "  ${UI_PURPLE}2)${UI_RST} MangoHud (FPS & Telemetry)   : $b_hud"
                    echo "  ${UI_PURPLE}3)${UI_RST} Gamescope (Isolated Window)  : $b_scope"
                    echo "  ${UI_PURPLE}4)${UI_RST} Gamescope FSR Upscaling      : $b_fsr"
                    echo "  ${UI_PURPLE}5)${UI_RST} Mesa GL Threading (mesa_gl)  : $b_glt $glt_hint"
                    echo "${UI_BOX}  ─────────────────────────────────────────────────────────────${UI_RST}"
                    echo "  ${UI_CYAN}6)${UI_RST} Preset: Balanced Performance (GameMode + MangoHud)"
                    echo "  ${UI_CYAN}7)${UI_RST} Preset: Handheld / FSR (GameMode + MangoHud + Gamescope FSR)"
                    echo "  ${UI_CYAN}8)${UI_RST} Reset: Safe Defaults (All Disabled)"
                    echo "  ${UI_GREEN}9)${UI_RST} Save & Return"
                    echo
                    read -r -p "Select option [1-9]: " w_opt
                    case "$w_opt" in
                        1) gm=$((1 - gm)) ;;
                        2) hud=$((1 - hud)) ;;
                        3) scope=$((1 - scope)) ;;
                        4) fsr=$((1 - fsr)); [ "$fsr" = 1 ] && scope=1 ;;
                        5) glt=$((1 - glt)) ;;
                        6) gm=1; hud=1; scope=0; fsr=0; glt=0 ;;
                        7) gm=1; hud=1; scope=1; fsr=1; glt=0 ;;
                        8) gm=0; hud=0; scope=0; fsr=0; glt=0 ;;
                        9)
                            cat <<EOF > "$HOME/.config/gamectl/wrappers"
gamemode=$gm
hud=$hud
gamescope=$scope
fsr=$fsr
glthread=$glt
gamescope_args=$gscope_args
EOF
                            echo "  ${UI_GREEN}[SUCCESS] Global wrappers saved.${UI_RST}"
                            sleep 0.8
                            break
                            ;;
                        *) break ;;
                    esac
                done
                ;;
            3)
                clear
                echo "${UI_BOX}╭─ CUSTOM GAME LIBRARIES (~/.config/gamectl/libraries) ───────╮${UI_RST}"
                echo "│ ${UI_CYAN}Direct scan paths for game binaries and appmanifests${UI_RST}"
                echo "${UI_BOX}╰─────────────────────────────────────────────────────────────╯${UI_RST}"
                [ -f "$HOME/.config/gamectl/libraries" ] && grep -v -E '^[[:space:]]*(#|$)' "$HOME/.config/gamectl/libraries" 2>/dev/null | nl -w2 -s'. ' || echo "  ${UI_DIM}(No custom libraries registered)${UI_RST}"
                echo "${UI_BOX}  ─────────────────────────────────────────────────────────────${UI_RST}"
                echo "  ${UI_CYAN}1)${UI_RST} Add Directory | ${UI_CYAN}2)${UI_RST} Remove Directory | ${UI_CYAN}3)${UI_RST} Back"
                read -r -p "Select option [1-3]: " lib_opt
                case "$lib_opt" in
                    1)
                        echo -n "  Enter path (e.g. ~/Games): "; read -r new_path
                        if [ -n "$new_path" ]; then
                            new_path="${new_path/#\~/$HOME}"
                            echo "$new_path" >> "$HOME/.config/gamectl/libraries"
                            echo "  ${UI_GREEN}[SUCCESS] Path '$new_path' added.${UI_RST}"
                        fi
                        read -r -p "Press [ENTER] to continue..."
                        ;;
                    2)
                        if [ -f "$HOME/.config/gamectl/libraries" ]; then
                            echo -n "  Enter line number to remove: "; read -r del_num
                            if [[ "$del_num" =~ ^[0-9]+$ ]]; then
                                local target_line
                                target_line=$(grep -v -E '^[[:space:]]*(#|$)' "$HOME/.config/gamectl/libraries" 2>/dev/null | sed -n "${del_num}p")
                                if [ -n "$target_line" ]; then
                                    grep -v -F "$target_line" "$HOME/.config/gamectl/libraries" > "$HOME/.config/gamectl/libraries.tmp" && mv "$HOME/.config/gamectl/libraries.tmp" "$HOME/.config/gamectl/libraries"
                                    echo "  ${UI_GREEN}[SUCCESS] '$target_line' removed.${UI_RST}"
                                fi
                            fi
                        fi
                        read -r -p "Press [ENTER] to continue..."
                        ;;
                    *) ;;
                esac
                ;;
            4)
                echo
                echo "${UI_BOX}╭─ REMOTE COMPANION HOST (~/.config/gamectl/remote_host) ─────╮${UI_RST}"
                echo "│ ${UI_CYAN}Target SSH server for savegame synchronization${UI_RST}"
                echo "${UI_BOX}╰─────────────────────────────────────────────────────────────╯${UI_RST}"
                echo "  Current Host: ${UI_BOLD}$r_host${UI_RST}"
                echo -n "  Enter new hostname or SSH alias ('-' to clear): "; read -r new_rhost
                if [ "$new_rhost" = "-" ]; then
                    rm -f "$HOME/.config/gamectl/remote_host"
                    echo "  [INFO] Remote host configuration cleared."
                elif [ -n "$new_rhost" ]; then
                    echo "$new_rhost" > "$HOME/.config/gamectl/remote_host"
                    echo "  ${UI_GREEN}[SUCCESS] Remote host '$new_rhost' saved.${UI_RST}"
                    echo -n "  Test SSH connectivity to '$new_rhost'? [y/N]: "; read -r test_ssh
                    if [[ "$test_ssh" =~ ^[yY] ]]; then
                        echo "  [INFO] Testing SSH connection to $new_rhost (3s timeout)..."
                        if ssh -q -o BatchMode=yes -o ConnectTimeout=3 "$new_rhost" exit 2>/dev/null; then
                            echo "  ${UI_GREEN}[VERIFIED] SSH connection successful!${UI_RST}"
                        else
                            echo "  ${UI_AMBER}[WARN] Host did not respond with public key auth. Ensure host is in ~/.ssh/config.${UI_RST}"
                        fi
                    fi
                fi
                read -r -p "Press [ENTER] to continue..."
                ;;
            *)
                break
                ;;
        esac
    done
}


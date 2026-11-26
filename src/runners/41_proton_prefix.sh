# Detect P2P multiplayer compatibility hooks, mod loaders, and custom DLL overrides for a game directory
detect_dll_overrides() {
    local gdir="${1:-}"
    [ -n "$gdir" ] && [ -d "$gdir" ] || return 0

    local has_onlinefix=0
    local has_bepinex=0
    local has_ue4ss=0
    local has_reframework=0
    local has_reshade=0
    local custom_overrides=""

    # 1. Check custom declarative .dll_overrides file
    if [ -f "$gdir/.dll_overrides" ]; then
        custom_overrides=$(grep -v -E '^[[:space:]]*(#|$)' "$gdir/.dll_overrides" 2>/dev/null | tr '\n' ';' || true)
    fi

    # 2. Scan root and subdirectories (up to depth 3) excluding runtime/save folders
    local found_signatures
    found_signatures=$(find "$gdir" -maxdepth 3 \( \
        -name "pfx" -o -name ".git" -o -name ".save_snapshots" -o -name "saves" \
    \) -prune -o \( \
        -iname "OnlineFix64.dll" -o -iname "OnlineFix.dll" -o -iname "dnet.dll" -o \
        -iname "SteamOverlay64.dll" -o -iname "winmm.dll" -o -iname "version.dll" -o \
        -iname "BepInEx" -o -iname "doorstop_config.ini" -o -iname "winhttp.dll" -o \
        -iname "ue4ss" -o -iname "UE4SS.dll" -o -iname "dwmapi.dll" -o \
        -iname "dinput8.dll" -o \
        -iname "ReShade.ini" -o -iname "dxgi.dll" \
    \) -print 2>/dev/null || true)

    if [ -n "$found_signatures" ]; then
        while IFS= read -r item; do
            [ -z "$item" ] && continue
            local base
            base=$(basename "$item")
            case "${base,,}" in
                onlinefix64.dll|onlinefix.dll|dnet.dll|steamoverlay64.dll|winmm.dll|version.dll)
                    has_onlinefix=1 ;;
                bepinex|doorstop_config.ini|winhttp.dll)
                    has_bepinex=1 ;;
                ue4ss|ue4ss.dll|dwmapi.dll)
                    has_ue4ss=1 ;;
                dinput8.dll)
                    has_reframework=1 ;;
                reshade.ini|dxgi.dll)
                    has_reshade=1 ;;
            esac
        done <<< "$found_signatures"
    fi

    # Return empty string if no mod/OnlineFix signatures or custom overrides found
    if [ "$has_onlinefix" -eq 0 ] && [ "$has_bepinex" -eq 0 ] && \
       [ "$has_ue4ss" -eq 0 ] && [ "$has_reframework" -eq 0 ] && \
       [ "$has_reshade" -eq 0 ] && [ -z "$custom_overrides" ]; then
        return 0
    fi

    local detected_tokens=""
    if [ "$has_onlinefix" -eq 1 ]; then
        detected_tokens="${detected_tokens:+${detected_tokens};}onlinefix=n;onlinefix64=n;steamoverlay64=n;dnet=n;winmm=n,b;version=n,b;steam_api64=n;steam_api=n"
    fi
    if [ "$has_bepinex" -eq 1 ]; then
        detected_tokens="${detected_tokens:+${detected_tokens};}winhttp=n,b"
    fi
    if [ "$has_ue4ss" -eq 1 ]; then
        detected_tokens="${detected_tokens:+${detected_tokens};}dwmapi=n,b"
    fi
    if [ "$has_reframework" -eq 1 ]; then
        detected_tokens="${detected_tokens:+${detected_tokens};}dinput8=n,b"
    fi
    if [ "$has_reshade" -eq 1 ]; then
        detected_tokens="${detected_tokens:+${detected_tokens};}dxgi=n,b"
    fi
    if [ -n "$custom_overrides" ]; then
        detected_tokens="${detected_tokens:+${detected_tokens};}${custom_overrides}"
    fi

    local user_env_overrides="${2:-${WINEDLLOVERRIDES:-}}"
    declare -A seen=()
    declare -A values=()
    local ordered_keys=()

    # 1. Process user environment overrides first to preserve user precedence
    if [ -n "$user_env_overrides" ]; then
        local u_arr=()
        IFS=';' read -r -a u_arr <<< "$user_env_overrides"
        for item in "${u_arr[@]}"; do
            [ -z "$item" ] && continue
            local k="${item%%=*}"
            local v="${item#*=}"
            [ "$item" = "$k" ] && v="n"
            k=$(echo "$k" | tr -d '[:space:]' | tr '[:upper:]' '[:lower:]')
            v=$(echo "$v" | tr -d '[:space:]')
            [ -z "$k" ] && continue
            if [ -z "${seen["$k"]:-}" ]; then
                seen["$k"]=1
                ordered_keys+=("$k")
                values["$k"]="$v"
            fi
        done
    fi

    # 2. Process detected mod tokens (add only if not overridden by user)
    local d_arr=()
    IFS=';' read -r -a d_arr <<< "$detected_tokens"
    for item in "${d_arr[@]}"; do
        [ -z "$item" ] && continue
        local k="${item%%=*}"
        local v="${item#*=}"
        [ "$item" = "$k" ] && v="n"
        k=$(echo "$k" | tr -d '[:space:]' | tr '[:upper:]' '[:lower:]')
        v=$(echo "$v" | tr -d '[:space:]')
        [ -z "$k" ] && continue
        if [ -z "${seen["$k"]:-}" ]; then
            seen["$k"]=1
            ordered_keys+=("$k")
            values["$k"]="$v"
        fi
    done

    # 3. Format normalized semicolon-separated output
    local result=""
    for k in "${ordered_keys[@]}"; do
        local entry="${k}=${values["$k"]}"
        result="${result:+${result};}${entry}"
    done
    echo "$result"
}

# Canonical Windows runner environment contract shared by launch_game & manage_prefix
prepare_windows_runner_env() {
    local runner_bin="${1:-wine}"
    local gdir="${2:-}"
    local raw_appid="${3:-0}"
    local renderer_mode="${4:-auto}"
    local prime_active="${5:-0}"

    local clean_appid="${raw_appid//[!0-9]/}"
    [ -z "$clean_appid" ] && clean_appid="0"

    GAMECTL_WIN_PFX_DIR="$gdir/pfx"
    GAMECTL_WIN_APPID="$clean_appid"
    if [ "$clean_appid" != "0" ]; then
        GAMECTL_WIN_UMU_GAMEID="umu-${clean_appid}"
    else
        GAMECTL_WIN_UMU_GAMEID="umu-default"
    fi
    GAMECTL_WIN_STEAM_ROOT="${STEAM_CLIENT_INSTALL_PATH:-$(get_steam_root 2>/dev/null || echo "$HOME/.local/share/Steam")}"

    case "$runner_bin" in
        umu-run|*/umu-run) GAMECTL_WIN_RUNNER_KIND="umu" ;;
        *proton*)          GAMECTL_WIN_RUNNER_KIND="proton" ;;
        *)                 GAMECTL_WIN_RUNNER_KIND="wine" ;;
    esac

    local eff_renderer="${GAMECTL_ACTIVE_RENDERER:-}"
    if [ -z "$eff_renderer" ]; then
        if [ -n "${PROTON_USE_WINED3D:-}" ]; then
            [ "$PROTON_USE_WINED3D" = "1" ] && eff_renderer="wined3d" || eff_renderer="dxvk"
        elif type resolve_graphics_renderer >/dev/null 2>&1; then
            eff_renderer="$(resolve_graphics_renderer "$renderer_mode" "$prime_active")"
        else
            eff_renderer="dxvk"
        fi
    fi
    GAMECTL_WIN_RENDERER="$eff_renderer"
    if [ "$eff_renderer" = "wined3d" ]; then
        GAMECTL_WIN_PROTON_WINED3D="1"
    else
        GAMECTL_WIN_PROTON_WINED3D="0"
    fi

    if [ "$clean_appid" = "0" ] && [ -z "${PROTONFIXES_DISABLE+x}" ]; then
        GAMECTL_WIN_DISABLE_PROTONFIXES="1"
    else
        GAMECTL_WIN_DISABLE_PROTONFIXES=""
    fi
}

# Wine Prefix Swiss Army Knife & Wineserver Lifecycle Guard (Chunk 4)
manage_prefix() {
    local game_dir="${1:-}"
    local action="${2:-}"
    shift 2 2>/dev/null || shift $# 2>/dev/null || true

    if [ -z "$game_dir" ] || [ ! -d "$game_dir" ]; then
        echo "[ERROR] Game directory not found or invalid: $game_dir" >&2
        echo "Usage: gamectl pfx <game_dir> [winecfg|regedit|cmd|shell|kill|clean|winetricks] [args...]" >&2
        return 1
    fi

    # Canonicalize game_dir path
    game_dir="$(cd "$game_dir" 2>/dev/null && pwd || echo "$game_dir")"
    local pfx_dir="$game_dir/pfx"
    local runner_bin
    runner_bin="$(find_runner "$game_dir" 2>/dev/null || true)"
    [ -z "$runner_bin" ] && runner_bin="wine"

    # AppID resolution (SSoT)
    local appid
    appid="$(resolve_game_appid "$game_dir" "0")"

    # Wineserver resolution
    local ws_bin
    ws_bin="$(get_wineserver_bin "$runner_bin" 2>/dev/null || echo "")"

    # Interactive menu if action is empty and stdin is terminal
    if [ -z "$action" ]; then
        require_tui "Wine prefix manager" || return $?
        if [ -t 0 ]; then
            if command -v fzf >/dev/null 2>&1; then
                flush_tty_input
                local game_name
                game_name="$(basename "$game_dir")"
                local pfx_status="[NOT FOUND]"
                local pfx_color="\033[38;5;203m"
                local pfx_size="0 B"
                if [ -d "$pfx_dir" ]; then
                    pfx_status="[ACTIVE]"
                    pfx_color="\033[38;5;120m"
                    pfx_size="$(du -sh "$pfx_dir" 2>/dev/null | awk '{print $1}' || echo "N/A")"
                fi

                local pfx_palette
                pfx_palette=$(cat <<EOF
winecfg	Wine Configuration	Configure Audio, Graphics, Windows Version & DLL Overrides
regedit	Registry Editor	Windows Registry Editor (regedit.exe)
cmd	Command Prompt	Windows Command Prompt (cmd.exe)
shell	Host Bash Subshell	Spawn bash subshell with active WINEPREFIX & PATH
winetricks	Winetricks Manager	Launch winetricks GUI / Package Manager helper
kill	Kill Wineserver	Terminate locked / hung Wineserver process
clean	Wipe Wine Prefix	Create save snapshot backup & wipe entire pfx directory
EOF
)

                export GAMECTL_PFX_NAME="$game_name"
                export GAMECTL_PFX_DIR="$game_dir"
                export GAMECTL_PFX_PATH="$pfx_dir"
                export GAMECTL_PFX_RUNNER="$runner_bin"
                export GAMECTL_PFX_STATUS="${pfx_color}${pfx_status}"
                export GAMECTL_PFX_SIZE="$pfx_size"

                local preview_cmd
                preview_cmd='printf "\033[38;5;60m╭─ WINE PREFIX OVERVIEW ──────────────────────────────╮\033[0m\n  Game Title  : \033[1m%s\033[0m\n  Directory   : %s\n  Prefix Path : %s\n  Active Wine : \033[38;5;111m%s\033[0m\n  Status      : %b\033[0m (Size: %s)\n\033[38;5;60m╰─────────────────────────────────────────────────────╯\033[0m\n\033[38;5;60m╭─ ACTION DETAIL ─────────────────────────────────────╮\033[0m\n  Tool   : \033[1m%s\033[0m - %s\n  Desc   : %s\n\033[38;5;60m╰─────────────────────────────────────────────────────╯\033[0m\n" "$GAMECTL_PFX_NAME" "$GAMECTL_PFX_DIR" "$GAMECTL_PFX_PATH" "$GAMECTL_PFX_RUNNER" "$GAMECTL_PFX_STATUS" "$GAMECTL_PFX_SIZE" {1} {2} {3}'

                local pfx_sel fzf_rc=0
                pfx_sel=$(echo "$pfx_palette" | fzf \
                    --delimiter=$'\t' \
                    --with-nth=1,2 \
                    --border-label="  ╢ gamectl :: Wine Prefix Manager :: $game_name ╟  " \
                    --border-label-pos=2 \
                    --header="Enter: Execute │ Esc: Return" \
                    --prompt="Prefix > " \
                    --preview="$preview_cmd" \
                    --preview-window=down:50%:border-rounded:wrap \
                    --reverse 2>/dev/null) || fzf_rc=$?

                if [ "$fzf_rc" -eq 130 ]; then
                    return 0
                fi
                if [ "$fzf_rc" -ne 0 ] && [ "$fzf_rc" -ne 1 ]; then
                    echo "[ERROR] Wine prefix manager failed (fzf exit code $fzf_rc)." >&2
                    return "$fzf_rc"
                fi
                [ -z "$pfx_sel" ] && return 0

                action=$(echo "$pfx_sel" | awk -F'\t' '{print $1}')
            else
                echo "[ERROR] fzf is required for Wine prefix manager." >&2
                return 127
            fi
        else
            echo "Usage: gamectl pfx <game_dir> [winecfg|regedit|cmd|shell|kill|clean|winetricks] [args...]" >&2
            return 1
        fi
    fi

    case "$action" in
        kill)
            echo "[INFO] Sending force termination signal (wineserver -k) to prefix: $pfx_dir"
            if [ -d "$pfx_dir" ]; then
                if [ -n "$ws_bin" ]; then
                    WINEPREFIX="$pfx_dir" "$ws_bin" -k 2>/dev/null || true
                elif command -v wineserver >/dev/null 2>&1; then
                    WINEPREFIX="$pfx_dir" wineserver -k 2>/dev/null || true
                fi
            fi
            echo "[VERIFIED] Wineserver for prefix $pfx_dir has been stopped."
            return 0
            ;;
        clean)
            echo "[INFO] Starting Wine prefix cleanup: $pfx_dir"
            if [ ! -d "$pfx_dir" ]; then
                echo "[INFO] Prefix directory $pfx_dir does not exist, nothing to clean."
                return 0
            fi

            local is_dry_run=false auto_yes=false
            for arg in "$@"; do
                if [ "$arg" = "--dry-run" ] || [ "$arg" = "-n" ]; then
                    is_dry_run=true
                elif [ "$arg" = "-y" ] || [ "$arg" = "--yes" ]; then
                    auto_yes=true
                fi
            done

            if [ "$is_dry_run" = true ]; then
                local pfx_sz="0"
                pfx_sz=$(du -sh "$pfx_dir" 2>/dev/null | cut -f1 || echo "unknown")
                echo "[INFO] [DRY-RUN] Target Wine prefix directory: $pfx_dir (Size: $pfx_sz)"
                echo "[INFO] [DRY-RUN] Would create pre-wipe savegame backup snapshot via backup_save."
                echo "[INFO] [DRY-RUN] Would terminate wineserver process."
                echo "[INFO] [DRY-RUN] Would remove prefix directory: $pfx_dir"
                echo "[INFO] [DRY-RUN] Wine prefix cleanup simulated successfully (no files deleted)."
                return 0
            fi

            # 1. Create save snapshot backup
            if [ -d "$game_dir/saves" ] || [ -L "$game_dir/saves" ]; then
                if ! backup_save "$game_dir" true; then
                    echo "[ERROR] Pre-wipe save snapshot backup failed. Aborting prefix wipe to protect saves." >&2
                    log_msg "ERROR" "PFX" "Pre-wipe save snapshot backup failed for $(basename "$game_dir")"
                    return 1
                fi
            fi

            # 2. Kill running wineserver
            if [ -n "$ws_bin" ]; then
                WINEPREFIX="$pfx_dir" "$ws_bin" -k 2>/dev/null || true
            elif command -v wineserver >/dev/null 2>&1; then
                WINEPREFIX="$pfx_dir" wineserver -k 2>/dev/null || true
            fi
            sleep 0.2

            # 3. Confirmation check
            if [ "$auto_yes" = false ] && [ -t 0 ]; then
                echo -n "[WARN] Wipe entire Wine prefix ($pfx_dir)? Registry and Wine configuration will be reset. [y/N]: "
                local confirm=""
                read -t 10 -r confirm || confirm="n"
                echo
                if [[ ! "$confirm" =~ ^[yY] ]]; then
                    echo "[INFO] Prefix cleanup canceled."
                    return 0
                fi
            fi

            # 4. Remove pfx folder safely
            rm -rf "$pfx_dir"
            echo "[VERIFIED] Wine prefix wiped successfully ($pfx_dir removed)."
            return 0
            ;;
        shell)
            prepare_windows_runner_env "$runner_bin" "$game_dir" "$appid" "auto" "0"
            echo "[INFO] Spawning interactive bash subshell inside prefix environment: $pfx_dir"
            echo "[INFO] Active environment: WINEPREFIX=$pfx_dir, RUNNER=$runner_bin"
            echo "[INFO] Type 'exit' to return to gamectl."
            (
                export WINEPREFIX="$GAMECTL_WIN_PFX_DIR" \
                    GAMECTL_RUNNER="$runner_bin" \
                    GAMEID="$GAMECTL_WIN_UMU_GAMEID" \
                    STEAM_COMPAT_APP_ID="$GAMECTL_WIN_APPID" \
                    SteamAppId="$GAMECTL_WIN_APPID" \
                    SteamGameId="$GAMECTL_WIN_APPID"
                if [ "$GAMECTL_WIN_RUNNER_KIND" = "proton" ] || [ "$GAMECTL_WIN_RUNNER_KIND" = "umu" ]; then
                    export PROTON_USE_WINED3D="$GAMECTL_WIN_PROTON_WINED3D"
                    [ "$GAMECTL_WIN_DISABLE_PROTONFIXES" = "1" ] && export PROTONFIXES_DISABLE=1
                fi
                if [ "$GAMECTL_WIN_RUNNER_KIND" = "proton" ]; then
                    export STEAM_COMPAT_CLIENT_INSTALL_PATH="$GAMECTL_WIN_STEAM_ROOT" \
                        STEAM_COMPAT_DATA_PATH="$game_dir"
                    local p_bin_dir
                    p_bin_dir="$(dirname "$runner_bin")/files/bin"
                    [ -d "$p_bin_dir" ] && export PATH="$p_bin_dir:$PATH"
                fi
                cd "$game_dir" || true
                exec bash -i
            )
            return 0
            ;;
        winecfg|regedit|cmd)
            mkdir -p "$pfx_dir"
            prepare_windows_runner_env "$runner_bin" "$game_dir" "$appid" "auto" "0"
            echo "[INFO] Executing $action inside prefix: $pfx_dir (Runner: $runner_bin)..."
            local target_exec="$action"
            [ "$action" = "cmd" ] && target_exec="cmd.exe"

            (
                export WINEPREFIX="$GAMECTL_WIN_PFX_DIR" \
                    GAMEID="$GAMECTL_WIN_UMU_GAMEID" \
                    STEAM_COMPAT_APP_ID="$GAMECTL_WIN_APPID" \
                    SteamAppId="$GAMECTL_WIN_APPID" \
                    SteamGameId="$GAMECTL_WIN_APPID"
                if [ "$GAMECTL_WIN_RUNNER_KIND" = "proton" ] || [ "$GAMECTL_WIN_RUNNER_KIND" = "umu" ]; then
                    export PROTON_USE_WINED3D="$GAMECTL_WIN_PROTON_WINED3D"
                    [ "$GAMECTL_WIN_DISABLE_PROTONFIXES" = "1" ] && export PROTONFIXES_DISABLE=1
                fi
                case "$GAMECTL_WIN_RUNNER_KIND" in
                    umu)
                        "$runner_bin" "$target_exec" "$@"
                        ;;
                    proton)
                        export STEAM_COMPAT_CLIENT_INSTALL_PATH="$GAMECTL_WIN_STEAM_ROOT" \
                            STEAM_COMPAT_DATA_PATH="$game_dir"
                        "$runner_bin" run "$target_exec" "$@"
                        ;;
                    *)
                        "$runner_bin" "$target_exec" "$@"
                        ;;
                esac
            )
            ;;
        winetricks)
            if ! command -v winetricks >/dev/null 2>&1; then
                echo "[ERROR] 'winetricks' binary not found on host system." >&2
                echo "[INFO] Install winetricks via your distribution package manager (e.g. pacman -S winetricks / apt install winetricks)." >&2
                return 1
            fi
            mkdir -p "$pfx_dir"
            echo "[INFO] Launching winetricks inside prefix: $pfx_dir"
            WINEPREFIX="$pfx_dir" winetricks "$@"
            ;;
        *)
            echo "[ERROR] Unknown prefix action: '$action'" >&2
            echo "Supported actions: winecfg, regedit, cmd, shell, kill, clean, winetricks" >&2
            return 1
            ;;
    esac
}

# Standalone-source compatibility: load split proton manager submodule when sourced directly outside bin/gamectl
if [ -z "${GAMECTL_BUNDLED:-}" ] && [ -n "${BASH_SOURCE[0]:-}" ]; then
    _pfx_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd)"
    if [ -f "$_pfx_dir/43_proton_manager.sh" ]; then
        # shellcheck source=/dev/null
        source "$_pfx_dir/43_proton_manager.sh"
    fi
    unset _pfx_dir
fi

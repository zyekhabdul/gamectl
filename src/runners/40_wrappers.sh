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
        w=$(find "$cdir" -type f \( -name "wine64" -o -name "wine" \) 2>/dev/null | head -n 1)
        if [ -n "$w" ] && [ -x "$w" ]; then
            echo "$w"
            return 0
        fi
    done

    return 1
}

# Resolve wineserver binary matching active runner or system/Proton installation
get_wineserver_bin() {
    local runner="${1:-}"

    # 1. If runner points directly to a Proton executable or runner string contains proton
    if [ -n "$runner" ]; then
        if [[ "$runner" =~ proton ]] || [ -f "$runner" ]; then
            local p_base
            p_base="$(dirname "$runner")"
            for sub in "files/bin/wineserver" "dist/bin/wineserver" "bin/wineserver"; do
                if [ -x "$p_base/$sub" ]; then
                    echo "$p_base/$sub"
                    return 0
                fi
            done
        fi
    fi

    # 2. Check system PATH for wineserver
    if command -v wineserver >/dev/null 2>&1; then
        command -v wineserver
        return 0
    fi

    # 3. Fallback: Search Steam compatibility tools for highest GE-Proton wineserver
    local s_dyn_root
    s_dyn_root="$(get_steam_root 2>/dev/null || true)"
    local compat_dirs=(
        "$s_dyn_root/compatibilitytools.d"
        "$HOME/.local/share/Steam/compatibilitytools.d"
        "$HOME/.steam/root/compatibilitytools.d"
        "$HOME/.var/app/com.valvesoftware.Steam/.local/share/Steam/compatibilitytools.d"
    )
    for cdir in "${compat_dirs[@]}"; do
        [ -n "$cdir" ] && [ -d "$cdir" ] || continue
        local p
        while read -r p; do
            [ -z "$p" ] && continue
            for sub in "files/bin/wineserver" "dist/bin/wineserver" "bin/wineserver"; do
                if [ -x "$p/$sub" ]; then
                    echo "$p/$sub"
                    return 0
                fi
            done
        done < <(find "$cdir" -mindepth 1 -maxdepth 1 -type d -name "*Proton*" 2>/dev/null | sort -Vr)
    done

    # 4. Check system wine64 / wine adjacent wineserver
    for w in "$(command -v wine64 2>/dev/null || true)" "$(command -v wine 2>/dev/null || true)"; do
        [ -n "$w" ] || continue
        local w_dir
        w_dir="$(dirname "$w")"
        if [ -x "$w_dir/wineserver" ]; then
            echo "$w_dir/wineserver"
            return 0
        fi
    done

    return 1
}

# Resolve active Steam compatibility tools directory
get_compat_dir() {
    local s_dyn_root
    s_dyn_root="$(get_steam_root 2>/dev/null || true)"
    if [ -n "$s_dyn_root" ] && [ -d "$s_dyn_root" ]; then
        echo "$s_dyn_root/compatibilitytools.d"
    elif [ -d "$HOME/.steam/root" ]; then
        echo "$HOME/.steam/root/compatibilitytools.d"
    else
        echo "$HOME/.local/share/Steam/compatibilitytools.d"
    fi
}

# List local and latest upstream GE-Proton releases
proton_list() {
    local s_dyn_root
    s_dyn_root="$(get_steam_root 2>/dev/null || true)"
    local compat_dirs=(
        "$s_dyn_root/compatibilitytools.d"
        "$HOME/.local/share/Steam/compatibilitytools.d"
        "$HOME/.steam/root/compatibilitytools.d"
        "$HOME/.var/app/com.valvesoftware.Steam/.local/share/Steam/compatibilitytools.d"
    )

    declare -A local_installs=()
    for cdir in "${compat_dirs[@]}"; do
        [ -n "$cdir" ] && [ -d "$cdir" ] || continue
        for d in "$cdir"/*; do
            [ -d "$d" ] || continue
            local t_name
            t_name=$(basename "$d")
            local_installs["$t_name"]="$d"
        done
    done

    echo "${UI_BOX}╭─ GE-PROTON RELEASE MANAGER (HEADLESS) ───────────────────────╮${UI_RST}"
    echo "│ ${UI_CYAN}Target Path${UI_RST}: $(get_compat_dir)"
    echo "│ ${UI_CYAN}Installed  ${UI_RST}: ${#local_installs[@]} version(s) detected locally"
    echo "${UI_BOX}╰─────────────────────────────────────────────────────────────╯${UI_RST}"

    # 1. Show local versions
    echo
    echo "  ${UI_PURPLE}[LOCAL VERSIONS]${UI_RST}"
    if [ ${#local_installs[@]} -gt 0 ]; then
        for v in "${!local_installs[@]}"; do
            local v_path="${local_installs["$v"]}"
            local v_sz
            v_sz=$(du -sh "$v_path" 2>/dev/null | awk '{print $1}')
            echo "    • ${UI_BOLD}$(printf '%-22s' "$v")${UI_RST} : ${UI_GREEN}[INSTALLED]${UI_RST} ${UI_DIM}(Size: $v_sz | $v_path)${UI_RST}"
        done
    else
        echo "    ${UI_DIM}(No GE-Proton versions installed in compatibilitytools.d/)${UI_RST}"
    fi

    # 2. Query GitHub Releases upstream
    echo
    echo "  ${UI_PURPLE}[UPSTREAM RELEASES (GitHub: GloriousEggroll/proton-ge-custom)]${UI_RST}"
    local arch_pat="x86_64\\.tar\\.gz$"
    case "$(uname -m 2>/dev/null || echo "x86_64")" in
        aarch64|arm64) arch_pat="aarch64\\.tar\\.gz$" ;;
        *) arch_pat="x86_64\\.tar\\.gz$" ;;
    esac

    local raw_json=""
    raw_json=$(curl -s --connect-timeout 5 --max-time 10 "https://api.github.com/repos/GloriousEggroll/proton-ge-custom/releases?per_page=5" 2>/dev/null || echo "")

    local parsed_releases=""
    if [ -n "$raw_json" ] && echo "$raw_json" | jq -e 'if type=="array" then true else false end' >/dev/null 2>&1; then
        parsed_releases=$(echo "$raw_json" | jq -r --arg pat "$arch_pat" '
            .[] | {
                tag: .tag_name,
                asset: ([.assets[] | select(.name | test($pat))] | first)
            } | select(.asset != null) | [
                .tag,
                .asset.name,
                ((.asset.size // 0) / 1048576 | floor | tostring + " MB"),
                .asset.browser_download_url
            ] | @tsv
        ' 2>/dev/null || true)
    fi

    if [ -n "$parsed_releases" ]; then
        local idx=0
        while IFS=$'\t' read -r r_tag r_asset r_size r_url; do
            [ -z "$r_tag" ] && continue
            idx=$((idx + 1))
            local status_badge="${UI_CYAN}[AVAILABLE]${UI_RST}"
            [ -n "${local_installs["$r_tag"]:-}" ] && status_badge="${UI_GREEN}[INSTALLED]${UI_RST}"
            [ "$idx" -eq 1 ] && status_badge="${status_badge} ${UI_AMBER}(Latest)${UI_RST}"
            echo "    • ${UI_BOLD}$(printf '%-22s' "$r_tag")${UI_RST} : $status_badge ${UI_DIM}(Download Size: $r_size)${UI_RST}"
        done <<< "$parsed_releases"
        echo
        echo "  ${UI_DIM}Install command: gamectl proton-install [tag|latest]${UI_RST}"
    else
        echo "    ${UI_AMBER}[WARN]${UI_RST} ${UI_DIM}Unable to fetch upstream release list (Offline or GitHub API rate-limited).${UI_RST}"
        echo "    ${UI_DIM}You can still install directly via: gamectl proton-install <tag_name>${UI_RST}"
    fi
    echo
}

# Headless GE-Proton installer
proton_install() {
    local target_tag="${1:-latest}"
    local auto_yes=false
    shift || true
    while [ $# -gt 0 ]; do
        case "$1" in
            -y|--yes) auto_yes=true; shift ;;
            *) shift ;;
        esac
    done

    local compat_dir
    compat_dir="$(get_compat_dir)"
    mkdir -p "$compat_dir"

    local arch_suffix="x86_64"
    case "$(uname -m 2>/dev/null || echo "x86_64")" in
        aarch64|arm64) arch_suffix="aarch64" ;;
        *) arch_suffix="x86_64" ;;
    esac

    echo "[INFO] Preparing GE-Proton installation ($target_tag) for architecture $arch_suffix..."

    local resolved_tag=""
    local download_url=""

    if [ "$target_tag" = "latest" ]; then
        local latest_json
        latest_json=$(curl -s --connect-timeout 5 --max-time 10 "https://api.github.com/repos/GloriousEggroll/proton-ge-custom/releases/latest" 2>/dev/null || echo "")
        if [ -n "$latest_json" ] && echo "$latest_json" | jq -e '.tag_name' >/dev/null 2>&1; then
            resolved_tag=$(echo "$latest_json" | jq -r '.tag_name')
            local pat="${arch_suffix}\\.tar\\.gz$"
            download_url=$(echo "$latest_json" | jq -r --arg pat "$pat" '
                [.assets[] | select(.name | test($pat))] | first | .browser_download_url
            ' 2>/dev/null || echo "")
        fi
        if [ -z "$resolved_tag" ] || [ -z "$download_url" ] || [ "$download_url" = "null" ]; then
            echo "[ERROR] Failed to obtain latest release URL from GitHub API." >&2
            echo "        Specify target tag explicitly: gamectl proton-install <tag_name>" >&2
            return 1
        fi
    else
        resolved_tag="$target_tag"
        local tag_json
        tag_json=$(curl -s --connect-timeout 5 --max-time 10 "https://api.github.com/repos/GloriousEggroll/proton-ge-custom/releases/tags/${resolved_tag}" 2>/dev/null || echo "")
        if [ -n "$tag_json" ] && echo "$tag_json" | jq -e '.tag_name' >/dev/null 2>&1; then
            local pat="${arch_suffix}\\.tar\\.gz$"
            download_url=$(echo "$tag_json" | jq -r --arg pat "$pat" '
                [.assets[] | select(.name | test($pat))] | first | .browser_download_url
            ' 2>/dev/null || echo "")
        fi
        if [ -z "$download_url" ] || [ "$download_url" = "null" ]; then
            # Direct asset fallback pattern
            download_url="https://github.com/GloriousEggroll/proton-ge-custom/releases/download/${resolved_tag}/${resolved_tag}-${arch_suffix}.tar.gz"
        fi
    fi

    echo "[INFO] Target version : $resolved_tag"
    echo "[INFO] Download URL   : $download_url"
    echo "[INFO] Target Dir     : $compat_dir/"

    if [ -d "$compat_dir/$resolved_tag" ] && [ "$auto_yes" = false ]; then
        if [ -t 0 ]; then
            echo -n "[WARN] Directory $resolved_tag already exists. Overwrite installation? [y/N]: "
            local confirm=""
            read -t 10 -r confirm || confirm="n"
            if [[ ! "$confirm" =~ ^[yY] ]]; then
                echo "[INFO] Installation canceled."
                return 0
            fi
        fi
    fi

    echo "[INFO] Downloading and streaming tarball extraction..."
    if curl -# -fL "$download_url" | tar -xz -C "$compat_dir/"; then
        local installed_folder="$compat_dir/$resolved_tag"
        if [ ! -d "$installed_folder" ]; then
            installed_folder=$(find "$compat_dir" -mindepth 1 -maxdepth 1 -type d -name "*${resolved_tag}*" 2>/dev/null | head -n 1)
        fi
        if [ -n "$installed_folder" ] && [ -f "$installed_folder/compatibilitytool.vdf" ]; then
            [ -f "$installed_folder/proton" ] && chmod +x "$installed_folder/proton"
            echo "[VERIFIED] GE-Proton $resolved_tag installed successfully in: $installed_folder"
            return 0
        else
            echo "[ERROR] Extraction completed but compatibilitytool.vdf not found in $installed_folder." >&2
            return 1
        fi
    else
        echo "[ERROR] Failed to download or extract $resolved_tag from $download_url" >&2
        return 1
    fi
}

# Safely remove an installed GE-Proton version
proton_remove() {
    local tag="${1:-}"
    local auto_yes=false
    shift || true
    while [ $# -gt 0 ]; do
        case "$1" in
            -y|--yes) auto_yes=true; shift ;;
            *) shift ;;
        esac
    done

    if [ -z "$tag" ]; then
        echo "Usage: gamectl proton-remove <tag> [-y|--yes]" >&2
        return 1
    fi

    # Path traversal protection
    if [[ "$tag" =~ (\.\.|\/|\\) ]]; then
        echo "[ERROR] Invalid tag (path traversal sequence detected): $tag" >&2
        return 1
    fi

    local s_dyn_root
    s_dyn_root="$(get_steam_root 2>/dev/null || true)"
    local compat_dirs=(
        "$s_dyn_root/compatibilitytools.d"
        "$HOME/.local/share/Steam/compatibilitytools.d"
        "$HOME/.steam/root/compatibilitytools.d"
        "$HOME/.var/app/com.valvesoftware.Steam/.local/share/Steam/compatibilitytools.d"
    )

    local target_dir=""
    for cdir in "${compat_dirs[@]}"; do
        [ -n "$cdir" ] && [ -d "$cdir" ] || continue
        if [ -d "$cdir/$tag" ]; then
            target_dir="$cdir/$tag"
            break
        fi
    done

    if [ -z "$target_dir" ] || [ ! -d "$target_dir" ]; then
        echo "[ERROR] GE-Proton version '$tag' not found in compatibilitytools.d/" >&2
        return 1
    fi

    # Canonical path traversal assertion
    local real_target
    real_target="$(realpath "$target_dir" 2>/dev/null || echo "")"
    if [[ "$real_target" != *"compatibilitytools.d"* ]]; then
        echo "[ERROR] Path traversal guard failed for: $target_dir" >&2
        return 1
    fi

    local sz
    sz=$(du -sh "$target_dir" 2>/dev/null | awk '{print $1}')

    if [ "$auto_yes" = false ] && [ -t 0 ]; then
        echo -n "Delete GE-Proton directory '$tag' (Size: $sz)? [y/N]: "
        local confirm=""
        read -t 10 -r confirm || confirm="n"
        echo
        if [[ ! "$confirm" =~ ^[yY] ]]; then
            echo "[INFO] Removal of $tag canceled."
            return 0
        fi
    fi

    rm -rf "$target_dir"
    echo "[VERIFIED] GE-Proton '$tag' removed successfully ($sz disk space freed)."
    return 0
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

    # AppID resolution
    local appid="0"
    if [ -f "$game_dir/steam_appid.txt" ]; then
        appid=$(tr -dc '0-9' < "$game_dir/steam_appid.txt")
        [ -z "$appid" ] && appid="0"
    fi

    # Wineserver resolution
    local ws_bin
    ws_bin="$(get_wineserver_bin "$runner_bin" 2>/dev/null || echo "")"

    # Interactive menu if action is empty and stdin is terminal
    if [ -z "$action" ]; then
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
                    --header="PREFIX PALETTE (Enter: Execute │ Esc: Return)" \
                    --prompt="Prefix > " \
                    --preview="$preview_cmd" \
                    --preview-window=down:50%:border-rounded:wrap \
                    --height=70% \
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
                echo "${UI_BOX}╭─ WINE PREFIX SWISS ARMY KNIFE ──────────────────────────────╮${UI_RST}"
                echo "│ ${UI_CYAN}Game Directory${UI_RST} : ${UI_BOLD}$game_dir${UI_RST}"
                echo "│ ${UI_CYAN}Prefix Path   ${UI_RST} : ${UI_BOLD}$pfx_dir${UI_RST}"
                echo "│ ${UI_CYAN}Active Runner ${UI_RST} : ${UI_GREEN}$runner_bin${UI_RST}"
                echo "${UI_BOX}╰─────────────────────────────────────────────────────────────╯${UI_RST}"
                echo "  ${UI_PURPLE}1)${UI_RST} winecfg      ${UI_DIM}(Wine Audio, Graphics & Windows Version Config)${UI_RST}"
                echo "  ${UI_PURPLE}2)${UI_RST} regedit      ${UI_DIM}(Windows Registry Editor)${UI_RST}"
                echo "  ${UI_PURPLE}3)${UI_RST} cmd          ${UI_DIM}(Windows Command Prompt)${UI_RST}"
                echo "  ${UI_PURPLE}4)${UI_RST} shell        ${UI_DIM}(Host Bash Subshell with active WINEPREFIX)${UI_RST}"
                echo "  ${UI_PURPLE}5)${UI_RST} winetricks   ${UI_DIM}(Winetricks GUI / Package Manager)${UI_RST}"
                echo "  ${UI_AMBER}6)${UI_RST} kill         ${UI_DIM}(Terminate locked / hung Wineserver)${UI_RST}"
                echo "  ${UI_RED}7)${UI_RST} clean        ${UI_DIM}(Backup Saves & Wipe Entire Wine Prefix)${UI_RST}"
                echo "  ${UI_CYAN}8)${UI_RST} Exit"
                echo
                local choice=""
                read -t 15 -r -p "Select action [1-8]: " choice || choice="8"
                case "$choice" in
                    1) action="winecfg" ;;
                    2) action="regedit" ;;
                    3) action="cmd" ;;
                    4) action="shell" ;;
                    5) action="winetricks" ;;
                    6) action="kill" ;;
                    7) action="clean" ;;
                    *) echo "[INFO] Operation canceled."; return 0 ;;
                esac
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
            backup_save "$game_dir" true || true

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
            echo "[INFO] Spawning interactive bash subshell inside prefix environment: $pfx_dir"
            echo "[INFO] Active environment: WINEPREFIX=$pfx_dir, RUNNER=$runner_bin"
            echo "[INFO] Type 'exit' to return to gamectl."
            (
                export WINEPREFIX="$pfx_dir"
                export GAMECTL_RUNNER="$runner_bin"
                if [[ "$runner_bin" =~ proton ]]; then
                    export STEAM_COMPAT_CLIENT_INSTALL_PATH="${STEAM_CLIENT_INSTALL_PATH:-$(get_steam_root 2>/dev/null || echo "$HOME/.local/share/Steam")}"
                    export STEAM_COMPAT_DATA_PATH="$game_dir"
                    export STEAM_COMPAT_APP_ID="$appid"
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
            echo "[INFO] Executing $action inside prefix: $pfx_dir (Runner: $runner_bin)..."
            local target_exec="$action"
            [ "$action" = "cmd" ] && target_exec="cmd.exe"

            local s_root
            s_root="$(get_steam_root 2>/dev/null || echo "$HOME/.local/share/Steam")"

            case "$runner_bin" in
                umu-run)
                    WINEPREFIX="$pfx_dir" GAMEID="$appid" umu-run "$target_exec" "$@"
                    ;;
                *proton*)
                    STEAM_COMPAT_CLIENT_INSTALL_PATH="${STEAM_CLIENT_INSTALL_PATH:-$s_root}" \
                    STEAM_COMPAT_DATA_PATH="$game_dir" \
                    STEAM_COMPAT_APP_ID="$appid" \
                    WINEPREFIX="$pfx_dir" \
                    "$runner_bin" run "$target_exec" "$@"
                    ;;
                *)
                    WINEPREFIX="$pfx_dir" "$runner_bin" "$target_exec" "$@"
                    ;;
            esac
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

# Check if systemd user daemon and cgroups v2 scope unit execution is supported
check_systemd_scope_support() {
    if command -v systemd-run >/dev/null 2>&1 && command -v systemctl >/dev/null 2>&1; then
        if systemd-run --user --scope --quiet true 2>/dev/null; then
            return 0
        fi
    fi
    return 1
}

# Detect discrete secondary GPU vendor on hybrid systems (NVIDIA, AMD, Intel Arc)
detect_dgpu_vendor() {
    if [ -n "${GAMECTL_DGPU_VENDOR:-}" ]; then
        echo "$GAMECTL_DGPU_VENDOR"
        return 0
    fi

    local vga_count=0
    local vendors=()

    for dev in /sys/bus/pci/devices/*; do
        [ -f "$dev/class" ] || continue
        local pci_class
        pci_class=$(cat "$dev/class" 2>/dev/null || echo "")
        case "$pci_class" in
            0x0302*|0x030200*)
                # Secondary 3D controller (Optimized for 3D acceleration / dGPU)
                local v_id
                v_id=$(cat "$dev/vendor" 2>/dev/null || echo "")
                case "$v_id" in
                    0x10de) echo "nvidia"; return 0 ;;
                    0x1002) echo "amd"; return 0 ;;
                    0x8086) echo "intel"; return 0 ;;
                esac
                ;;
            0x0300*|0x030000*)
                vga_count=$((vga_count + 1))
                local v_id
                v_id=$(cat "$dev/vendor" 2>/dev/null || echo "")
                vendors+=("$v_id")
                ;;
        esac
    done

    # If multiple display controllers exist without a specific 0x0302 class device
    if [ "$vga_count" -gt 1 ]; then
        for v in "${vendors[@]}"; do
            if [ "$v" = "0x10de" ]; then
                echo "nvidia"
                return 0
            fi
        done
        local has_amd=false has_intel=false amd_count=0
        for v in "${vendors[@]}"; do
            [ "$v" = "0x1002" ] && { has_amd=true; amd_count=$((amd_count + 1)); }
            [ "$v" = "0x8086" ] && has_intel=true
        done
        if [ "$has_amd" = true ] && [ "$has_intel" = true ]; then
            echo "amd"
            return 0
        fi
        if [ "$amd_count" -gt 1 ]; then
            echo "amd"
            return 0
        fi
    fi

    echo "none"
    return 0
}

# Construct rootless Bubblewrap (bwrap) security sandbox argument array
build_sandbox_command() {
    local gdir="$1"
    declare -ga GAMECTL_SANDBOX_PREFIX=()

    if ! command -v bwrap >/dev/null 2>&1; then
        echo "[WARN] bubblewrap (bwrap) not found in PATH. Sandboxing skipped." >&2
        return 1
    fi

    local run_uid="${UID:-$(id -u)}"
    local runtime_dir="${XDG_RUNTIME_DIR:-/run/user/$run_uid}"
    local wayland_socket="${WAYLAND_DISPLAY:-wayland-0}"
    local xauth_file="${XAUTHORITY:-$HOME/.Xauthority}"

    GAMECTL_SANDBOX_PREFIX=(
        bwrap
        --ro-bind /usr /usr
        --ro-bind-try /lib /lib
        --ro-bind-try /lib64 /lib64
        --ro-bind-try /bin /bin
        --ro-bind-try /sbin /sbin
        --ro-bind-try /etc /etc
        --proc /proc
        --dev /dev
        --ro-bind /sys /sys
        --tmpfs /tmp
        --ro-bind-try /tmp/.X11-unix /tmp/.X11-unix
        --tmpfs /run
        --tmpfs "/run/user/$run_uid"
        --ro-bind-try "$runtime_dir/wayland-0" "$runtime_dir/wayland-0"
        --ro-bind-try "$runtime_dir/$wayland_socket" "$runtime_dir/$wayland_socket"
        --bind-try "$runtime_dir/pipewire-0" "$runtime_dir/pipewire-0"
        --bind-try "$runtime_dir/pulse" "$runtime_dir/pulse"
        --bind-try "$runtime_dir/gamectl-$run_uid" "$runtime_dir/gamectl-$run_uid"
        --tmpfs "$HOME"
        --ro-bind-try "$xauth_file" "$xauth_file"
        --bind-try "$HOME/.config/gamectl" "$HOME/.config/gamectl"
        --ro-bind-try "$HOME/.local/share/Steam" "$HOME/.local/share/Steam"
        --ro-bind-try "$HOME/.local/share/gbe-fork" "$HOME/.local/share/gbe-fork"
        --ro-bind-try "$HOME/.steam" "$HOME/.steam"
        --bind-try "$HOME/.local/share/vulkan" "$HOME/.local/share/vulkan"
        --bind "$gdir" "$gdir"
        --chdir "$gdir"
        --unshare-user
        --unshare-ipc
        --unshare-pid
        --die-with-parent
    )
    return 0
}

# Resolve and build wrapper prefix command array (gamemoderun, mangohud, gamescope)
build_wrapper_command() {
    local gdir="$1"
    shift || true
    local opt_gamemode="" opt_hud="" opt_gamescope="" opt_fsr="" opt_systemd_scope="" opt_prime="" opt_sandbox="" opt_allow_unshielded=""
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
            --scope|--systemd-scope) opt_systemd_scope=1; shift ;;
            --no-scope|--no-systemd-scope) opt_systemd_scope=0; shift ;;
            --prime) opt_prime=1; shift ;;
            --no-prime) opt_prime=0; shift ;;
            --sandbox) opt_sandbox=1; shift ;;
            --no-sandbox) opt_sandbox=0; shift ;;
            --allow-unshielded) opt_allow_unshielded=1; shift ;;
            --) shift; remaining_args+=("$@"); break ;;
            *) remaining_args+=("$1"); shift ;;
        esac
    done

    # 1. Base defaults
    local use_gm=0 use_hud=0 use_scope=0 use_fsr=0 use_glthread=0 use_systemd_scope="" use_prime=0 use_sandbox=0
    local gscope_args
    gscope_args=$(get_default_gamescope_args)

    # 2. Config file hierarchy: Global (~/.config/gamectl/wrappers) -> Per-game override ($gdir/.wrappers)
    local w_cfgs=("$HOME/.config/gamectl/wrappers")
    [ -n "$gdir" ] && w_cfgs+=("$gdir/.wrappers")
    local w_cfg
    for w_cfg in "${w_cfgs[@]}"; do
        if [ -f "$w_cfg" ]; then
            while IFS='=' read -r k v || [ -n "$k" ]; do
                k="${k//[[:space:]]/}"
                v="${v#"${v%%[![:space:]]*}"}"
                v="${v%"${v##*[![:space:]]}"}"
                v="${v#\"}"
                v="${v%\"}"
                [[ "$k" =~ ^# ]] && continue
                case "$k" in
                    gamemode) use_gm="$v" ;;
                    hud|mangohud) use_hud="$v" ;;
                    gamescope) use_scope="$v" ;;
                    fsr) use_fsr="$v" ;;
                    glthread|mesa_glthread) use_glthread="$v" ;;
                    scope|systemd_scope) use_systemd_scope="$v" ;;
                    prime|dgpu) use_prime="$v" ;;
                    sandbox) use_sandbox="$v" ;;
                    gamescope_args) gscope_args="$v" ;;
                esac
            done < "$w_cfg"
        fi
    done

    # 4. Environment variable overrides
    [ -n "${GAMECTL_GAMEMODE:-}" ] && use_gm="$GAMECTL_GAMEMODE"
    [ -n "${GAMECTL_HUD:-${GAMECTL_MANGOHUD:-}}" ] && use_hud="${GAMECTL_HUD:-$GAMECTL_MANGOHUD}"
    [ -n "${GAMECTL_GAMESCOPE:-}" ] && use_scope="$GAMECTL_GAMESCOPE"
    [ -n "${GAMECTL_FSR:-}" ] && use_fsr="$GAMECTL_FSR"
    [ -n "${GAMECTL_GLTHREAD:-}" ] && use_glthread="$GAMECTL_GLTHREAD"
    [ -n "${GAMECTL_SCOPE:-${GAMECTL_SYSTEMD_SCOPE:-}}" ] && use_systemd_scope="${GAMECTL_SCOPE:-$GAMECTL_SYSTEMD_SCOPE}"
    [ -n "${GAMECTL_PRIME:-}" ] && use_prime="$GAMECTL_PRIME"
    [ -n "${GAMECTL_SANDBOX:-}" ] && use_sandbox="$GAMECTL_SANDBOX"
    [ -n "${GAMECTL_GAMESCOPE_ARGS:-}" ] && gscope_args="$GAMECTL_GAMESCOPE_ARGS"

    # 5. CLI flag overrides
    [ -n "$opt_gamemode" ] && use_gm="$opt_gamemode"
    [ -n "$opt_hud" ] && use_hud="$opt_hud"
    [ -n "$opt_gamescope" ] && use_scope="$opt_gamescope"
    [ -n "$opt_fsr" ] && use_fsr="$opt_fsr"
    [ -n "${opt_glthread:-}" ] && use_glthread="$opt_glthread"
    [ -n "${opt_systemd_scope:-}" ] && use_systemd_scope="$opt_systemd_scope"
    [ -n "$opt_prime" ] && use_prime="$opt_prime"
    [ -n "$opt_sandbox" ] && use_sandbox="$opt_sandbox"

    if [ -z "${use_systemd_scope:-}" ]; then
        if check_systemd_scope_support; then
            use_systemd_scope=1
        else
            use_systemd_scope=0
        fi
    fi

    local dgpu_vendor="none"
    if [ "$use_prime" = "1" ]; then
        dgpu_vendor=$(detect_dgpu_vendor)
        if [ "$dgpu_vendor" = "none" ]; then
            echo "[WARN] PRIME offloading requested (--prime) but no secondary dGPU detected." >&2
        fi
    fi

    declare -ga GAMECTL_SANDBOX_PREFIX=()
    if [ "$use_sandbox" = "1" ]; then
        build_sandbox_command "$gdir" || use_sandbox=0
    fi

    GAMECTL_ACTIVE_GLTHREAD="$use_glthread"
    GAMECTL_ACTIVE_SYSTEMD_SCOPE="$use_systemd_scope"
    GAMECTL_ACTIVE_PRIME="$use_prime"
    GAMECTL_ACTIVE_PRIME_VENDOR="$dgpu_vendor"
    GAMECTL_ACTIVE_SANDBOX="$use_sandbox"
    GAMECTL_ACTIVE_ALLOW_UNSHIELDED="${opt_allow_unshielded:-0}"

    local prefix=()
    if [ "$use_gm" = "1" ]; then
        if command -v gamemoderun >/dev/null 2>&1; then
            prefix+=("gamemoderun")
        else
            echo "[WARN] gamemoderun is enabled but binary not found in PATH." >&2
        fi
    fi

    if [ "$use_hud" = "1" ]; then
        if command -v mangohud >/dev/null 2>&1; then
            prefix+=("mangohud")
        else
            echo "[WARN] mangohud is enabled but binary not found in PATH." >&2
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
            echo "[WARN] gamescope is enabled but binary not found in PATH." >&2
        fi
    fi

    GAMECTL_WRAPPER_PREFIX=("${prefix[@]}")
    GAMECTL_REMAINING_ARGS=("${remaining_args[@]}")
}

# Interactive wrapper configuration for a game or global defaults
configure_wrappers() {
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

        local entries
        entries=$(cat <<EOF
1	GameMode (gamemoderun)	$b_gm
2	MangoHud (FPS & Telemetry)	$b_hud
3	Gamescope (Isolated Window)	$b_scope
4	Gamescope FSR Upscaling	$b_fsr
5	Mesa GL Threading (mesa_gl)	$b_glt $glt_hint
6	Preset: Balanced Performance	GameMode + MangoHud
7	Preset: Handheld / FSR	GameMode + MangoHud + Gamescope FSR
8	Reset: Safe Defaults	All Disabled
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
            --header="RUNTIME WRAPPERS (Enter: Toggle/Select │ Esc: Save & Return)" \
            --prompt="Wrappers > " \
            --height=45% \
            --reverse 2>/dev/null) || fzf_rc=$?

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
                log_msg "INFO" "WRAPPERS" "Saved wrapper configuration for $title -> $w_file (gm=$gm,hud=$hud,scope=$scope,fsr=$fsr,glt=$glt)"
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

        local menu_entries
        menu_entries=$(cat <<EOF
1	Global LAN Persona	Name: $p_name | SteamID: ${p_id:-Auto}
2	Default Runtime Wrappers	$w_desc
3	Custom Game Libraries	$lib_count paths registered
4	Remote Companion Host	$r_host
5	Return to Master Dashboard Hub	Return
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
            --height=40% \
            --reverse 2>/dev/null) || fzf_rc=$?

        [ "$fzf_rc" -eq 130 ] && break
        [ -z "$selection" ] && continue

        local cfg_opt
        cfg_opt=$(echo "$selection" | cut -f1 | tr -d '[:space:]')

        case "$cfg_opt" in
            1)
                flush_tty_input
                local in_name_raw in_id_raw rc=0
                in_name_raw=$(: | fzf \
                    --print-query \
                    --border-label="  ╢ Configure LAN Persona Name ╟  " \
                    --border-label-pos=2 \
                    --header="Enter Player Name (Current: $p_name │ Enter: Confirm │ Esc: Cancel)" \
                    --prompt="Player Name > " \
                    --height=20% \
                    --reverse 2>/dev/null) || rc=$?
                [ "$rc" -eq 130 ] && continue
                local new_name
                new_name=$(echo "$in_name_raw" | head -n 1 | tr -d '\r\n')
                [ -n "$new_name" ] && p_name="$new_name"

                flush_tty_input
                in_id_raw=$(: | fzf \
                    --print-query \
                    --border-label="  ╢ Configure SteamID64 ╟  " \
                    --border-label-pos=2 \
                    --header="Enter 17-digit SteamID64, 'gen' for random ID, or blank for Auto (Current: ${p_id:-Auto})" \
                    --prompt="SteamID64 > " \
                    --height=20% \
                    --reverse 2>/dev/null) || rc=$?
                [ "$rc" -eq 130 ] && continue
                local new_id
                new_id=$(echo "$in_id_raw" | head -n 1 | tr -d '[:space:]')
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
                configure_wrappers ""
                ;;
            3)
                while true; do
                    local lib_items=""
                    local l_idx=1
                    if [ -f "$HOME/.config/gamectl/libraries" ]; then
                        while IFS= read -r l_path; do
                            [ -z "$l_path" ] && continue
                            [[ "$l_path" =~ ^[[:space:]]*# ]] && continue
                            lib_items+="${l_idx}\t[REMOVE] $l_path\tSelect to remove this library path\n"
                            l_idx=$((l_idx + 1))
                        done < "$HOME/.config/gamectl/libraries"
                    fi
                    local lib_menu
                    lib_menu=$(cat <<EOF
add	[+] Register New Library Path	Enter filesystem path (e.g. ~/Games)
EOF
)
                    [ -n "$lib_items" ] && lib_menu="${lib_menu}"$'\n'"$(printf '%b' "$lib_items")"
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
                        --height=40% \
                        --reverse 2>/dev/null) || l_rc=$?

                    [ "$l_rc" -eq 130 ] && break
                    [ -z "$lib_sel" ] && continue

                    local l_action
                    l_action=$(echo "$lib_sel" | cut -f1 | tr -d '[:space:]')

                    if [ "$l_action" = "add" ]; then
                        flush_tty_input
                        local in_p_raw p_rc=0
                        in_p_raw=$(: | fzf \
                            --print-query \
                            --border-label="  ╢ Add Game Library Directory ╟  " \
                            --border-label-pos=2 \
                            --header="Enter directory path (e.g. ~/Games │ Enter: Add │ Esc: Cancel)" \
                            --prompt="Path > " \
                            --height=20% \
                            --reverse 2>/dev/null) || p_rc=$?
                        [ "$p_rc" -eq 130 ] && continue
                        local new_path
                        new_path=$(echo "$in_p_raw" | head -n 1 | tr -d '\r\n')
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
                flush_tty_input
                local in_host_raw rc=0
                in_host_raw=$(: | fzf \
                    --print-query \
                    --border-label="  ╢ Remote Companion Host ╟  " \
                    --border-label-pos=2 \
                    --header="Enter SSH hostname/alias or '-' to clear (Current: $r_host │ Enter: Save │ Esc: Cancel)" \
                    --prompt="SSH Host > " \
                    --height=20% \
                    --reverse 2>/dev/null) || rc=$?
                [ "$rc" -eq 130 ] && continue
                local new_rhost
                new_rhost=$(echo "$in_host_raw" | head -n 1 | tr -d '[:space:]')
                if [ "$new_rhost" = "-" ]; then
                    rm -f "$HOME/.config/gamectl/remote_host"
                    log_msg "INFO" "CONFIG" "Cleared remote companion host"
                elif [ -n "$new_rhost" ]; then
                    echo "$new_rhost" > "$HOME/.config/gamectl/remote_host"
                    log_msg "INFO" "CONFIG" "Saved remote companion host: $new_rhost"
                fi
                ;;
            5)
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


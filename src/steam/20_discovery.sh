
# Discover active Steam root directory across standard, custom, Flatpak, and Snap installations
get_steam_root() {
    if [ -n "${STEAM_ROOT:-}" ] && [ -d "$STEAM_ROOT" ]; then
        echo "$STEAM_ROOT"
        return 0
    fi

    local candidate
    for candidate in \
        "$HOME/.local/share/Steam" \
        "$HOME/.steam/steam" \
        "$HOME/.steam/root" \
        "$HOME/.var/app/com.valvesoftware.Steam/.local/share/Steam" \
        "$HOME/snap/steam/common/.local/share/Steam"; do
        if [ -d "$candidate" ]; then
            echo "$candidate"
            return 0
        fi
    done

    return 1
}

# Discover active primary steamapps directory
get_steam_primary_apps() {
    local s_root
    s_root="$(get_steam_root 2>/dev/null || true)"
    if [ -n "$s_root" ] && [ -d "$s_root/steamapps" ]; then
        echo "$s_root/steamapps"
        return 0
    fi

    local first_lib
    first_lib="$(get_steam_libraries 2>/dev/null | head -n 1 || true)"
    if [ -n "$first_lib" ] && [ -d "$first_lib" ]; then
        echo "$first_lib"
        return 0
    fi

    echo "$HOME/.local/share/Steam/steamapps"
}

# Discover all configured Steam library paths with deduplication
get_steam_libraries() {
    declare -A seen_libs=()
    local candidate_roots=(
        "${STEAM_ROOT:-}"
        "$HOME/.local/share/Steam"
        "$HOME/.steam/steam"
        "$HOME/.steam/root"
        "$HOME/.var/app/com.valvesoftware.Steam/.local/share/Steam"
        "$HOME/snap/steam/common/.local/share/Steam"
    )

    for root in "${candidate_roots[@]}"; do
        [ -n "$root" ] && [ -d "$root" ] || continue

        local primary="$root/steamapps"
        if [ -d "$primary" ]; then
            local real_primary
            real_primary="$(realpath "$primary" 2>/dev/null || echo "$primary")"
            if [ -z "${seen_libs["$real_primary"]:-}" ]; then
                seen_libs["$real_primary"]=1
                echo "$primary"
            fi
        fi

        # Check libraryfolders.vdf
        local vdf_candidates=(
            "$root/steamapps/libraryfolders.vdf"
            "$root/config/libraryfolders.vdf"
        )
        for vdf in "${vdf_candidates[@]}"; do
            [ -f "$vdf" ] || continue
            local line p_path
            while read -r line; do
                p_path=$(echo "$line" | sed -E 's/.*"path"[[:space:]]+"([^"]+)".*/\1\/steamapps/')
                if [ -d "$p_path" ]; then
                    local real_p
                    real_p="$(realpath "$p_path" 2>/dev/null || echo "$p_path")"
                    if [ -z "${seen_libs["$real_p"]:-}" ]; then
                        seen_libs["$real_p"]=1
                        echo "$p_path"
                    fi
                fi
            done < <(grep -E '^\s*"path"' "$vdf" 2>/dev/null || true)
        done
    done
}

# Scan installed games dynamically in standard & custom paths
scan_installed_games() {
    local is_formatted=false
    [ "${1:-}" = "--formatted" ] || [ "${1:-}" = "-f" ] && is_formatted=true
    declare -A seen_dirs

    # 1. Scan Steam Libraries
    local steam_lib
    while read -r steam_lib; do
        [ -d "$steam_lib" ] || continue
        for acf in "$steam_lib"/appmanifest_*.acf; do
            [ -f "$acf" ] || continue

            local appid name installdir
            appid=$(grep -E '^\s*"appid"' "$acf" | head -n 1 | sed -E 's/.*"appid"[[:space:]]+"([0-9]+)".*/\1/')
            name=$(grep -E '^\s*"name"' "$acf" | head -n 1 | sed -E 's/.*"name"[[:space:]]+"([^"]+)".*/\1/')
            installdir=$(grep -E '^\s*"installdir"' "$acf" | head -n 1 | sed -E 's/.*"installdir"[[:space:]]+"([^"]+)".*/\1/')

            # Filter out Proton, Steam Linux Runtimes, and tools
            [[ "$name" =~ ^(Steam Linux Runtime|Proton|Steamworks) ]] && continue
            [ -z "$installdir" ] && continue

            local gdir="$steam_lib/common/$installdir"
            [ -d "$gdir" ] || continue
            [[ -v seen_dirs["$gdir"] ]] && continue
            seen_dirs["$gdir"]=1

            local gbin
            gbin=$(find_game_binary "$gdir") || continue
            [ -z "$gbin" ] && continue

            local is_win_bin=false
            case "$gbin" in
                *.exe|*.EXE) is_win_bin=true ;;
            esac

            local status="STANDALONE"
            local api_file=""
            if [ "$is_win_bin" = true ]; then
                if [ -f "$gdir/steam_api64.dll" ]; then
                    api_file="$gdir/steam_api64.dll"
                elif [ -f "$gdir/steam_api.dll" ]; then
                    api_file="$gdir/steam_api.dll"
                elif [ -f "$gdir/libsteam_api.so" ]; then
                    api_file="$gdir/libsteam_api.so"
                elif [ -f "$gdir/lib64/libsteam_api.so" ]; then
                    api_file="$gdir/lib64/libsteam_api.so"
                else
                    api_file=$(find "$gdir" -maxdepth 3 \( -name "steam_api64.dll" -o -name "steam_api.dll" -o -name "libsteam_api.so" \) 2>/dev/null | head -n 1)
                fi
            else
                if [ -f "$gdir/libsteam_api.so" ]; then
                    api_file="$gdir/libsteam_api.so"
                elif [ -f "$gdir/lib64/libsteam_api.so" ]; then
                    api_file="$gdir/lib64/libsteam_api.so"
                elif [ -f "$gdir/steam_api64.dll" ]; then
                    api_file="$gdir/steam_api64.dll"
                elif [ -f "$gdir/steam_api.dll" ]; then
                    api_file="$gdir/steam_api.dll"
                else
                    api_file=$(find "$gdir" -maxdepth 3 \( -name "libsteam_api.so" -o -name "steam_api64.dll" -o -name "steam_api.dll" \) 2>/dev/null | head -n 1)
                fi
            fi

            if [ -n "$api_file" ]; then
                local sz
                sz=$(stat -c%s "$api_file" 2>/dev/null || echo 0)
                if [ "$sz" -gt 7000000 ]; then
                    status="GBE_FORK"
                else
                    case "$api_file" in
                        *.dll) status="VALVE_DLL" ;;
                        *)     status="VALVE_SO" ;;
                    esac
                fi
            fi

            if [ "$is_formatted" = true ]; then
                local c_status=""
                case "$status" in
                    *GBE_FORK*)   c_status="${UI_GREEN}[GBE_FORK]  ${UI_RST}" ;;
                    *VALVE_SO*)   c_status="${UI_AMBER}[VALVE_SO]  ${UI_RST}" ;;
                    *VALVE_DLL*)  c_status="${UI_CYAN}[VALVE_DLL] ${UI_RST}" ;;
                    *STANDALONE*) c_status="${UI_ICE}[STANDALONE]${UI_RST}" ;;
                esac
                printf "%b\t%b\t%b\t%s\t%s\n" "${UI_DIM}${appid}${UI_RST}" "${UI_BOLD}${name}${UI_RST}" "$c_status" "$gdir" "$gbin"
            else
                printf "%-8s\t%-22s\t%-12s\t%s\t%s\n" "$appid" "$name" "[$status]" "$gdir" "$gbin"
            fi
        done
    done < <(get_steam_libraries)

    # 2. Scan Custom & Standalone Directories
    local custom_search_dirs=(
        "$HOME/Games"
        "$HOME/.local/share/lutris/games"
    )

    # Allow extending library directories via ~/.config/gamectl/libraries or env
    if [ -f "$HOME/.config/gamectl/libraries" ]; then
        while IFS= read -r line || [ -n "$line" ]; do
            line="${line#"${line%%[![:space:]]*}"}" # trim leading
            line="${line%"${line##*[![:space:]]}"}" # trim trailing
            [ -z "$line" ] && continue
            [[ "$line" =~ ^# ]] && continue
            custom_search_dirs+=("${line/#\~/$HOME}")
        done < "$HOME/.config/gamectl/libraries"
    fi

    if [ -n "${GAMECTL_LIBRARY_DIRS:-}" ]; then
        IFS=":" read -r -a extra_dirs <<< "$GAMECTL_LIBRARY_DIRS"
        custom_search_dirs+=("${extra_dirs[@]}")
    fi

    for base_dir in "${custom_search_dirs[@]}"; do
        [ -d "$base_dir" ] || continue
        for gdir in "$base_dir"/*; do
            [ -d "$gdir" ] || continue
            [[ -v seen_dirs["$gdir"] ]] && continue
            seen_dirs["$gdir"]=1

            local folder_name
            folder_name=$(basename "$gdir")
            [[ "$folder_name" =~ ^\. ]] && continue

            local gbin
            gbin=$(find_game_binary "$gdir") || continue
            [ -z "$gbin" ] && continue

            local appid="STANDALONE"
            if [ -f "$gdir/steam_appid.txt" ]; then
                appid=$(tr -dc '0-9' < "$gdir/steam_appid.txt")
                [ -z "$appid" ] && appid="STANDALONE"
            elif [ -f "$gdir/.gamectl_appid" ]; then
                appid=$(tr -dc '0-9' < "$gdir/.gamectl_appid")
                [ -z "$appid" ] && appid="STANDALONE"
            fi

            local title="$folder_name"
            if [ -f "$gdir/.gamectl_title" ]; then
                title=$(head -n 1 "$gdir/.gamectl_title")
            fi

            local is_win_bin=false
            case "$gbin" in
                *.exe|*.EXE) is_win_bin=true ;;
            esac

            local status="STANDALONE"
            local api_file=""
            if [ "$is_win_bin" = true ]; then
                if [ -f "$gdir/steam_api64.dll" ]; then
                    api_file="$gdir/steam_api64.dll"
                elif [ -f "$gdir/steam_api.dll" ]; then
                    api_file="$gdir/steam_api.dll"
                elif [ -f "$gdir/libsteam_api.so" ]; then
                    api_file="$gdir/libsteam_api.so"
                elif [ -f "$gdir/lib64/libsteam_api.so" ]; then
                    api_file="$gdir/lib64/libsteam_api.so"
                else
                    api_file=$(find "$gdir" -maxdepth 3 \( -name "steam_api64.dll" -o -name "steam_api.dll" -o -name "libsteam_api.so" \) 2>/dev/null | head -n 1)
                fi
            else
                if [ -f "$gdir/libsteam_api.so" ]; then
                    api_file="$gdir/libsteam_api.so"
                elif [ -f "$gdir/lib64/libsteam_api.so" ]; then
                    api_file="$gdir/lib64/libsteam_api.so"
                elif [ -f "$gdir/steam_api64.dll" ]; then
                    api_file="$gdir/steam_api64.dll"
                elif [ -f "$gdir/steam_api.dll" ]; then
                    api_file="$gdir/steam_api.dll"
                else
                    api_file=$(find "$gdir" -maxdepth 3 \( -name "libsteam_api.so" -o -name "steam_api64.dll" -o -name "steam_api.dll" \) 2>/dev/null | head -n 1)
                fi
            fi

            if [ -n "$api_file" ]; then
                local sz
                sz=$(stat -c%s "$api_file" 2>/dev/null || echo 0)
                if [ "$sz" -gt 7000000 ]; then
                    status="GBE_FORK"
                else
                    case "$api_file" in
                        *.dll) status="VALVE_DLL" ;;
                        *)     status="VALVE_SO" ;;
                    esac
                fi
            fi

            if [ "$is_formatted" = true ]; then
                local c_status=""
                case "$status" in
                    *GBE_FORK*)   c_status="${UI_GREEN}[GBE_FORK]  ${UI_RST}" ;;
                    *VALVE_SO*)   c_status="${UI_AMBER}[VALVE_SO]  ${UI_RST}" ;;
                    *VALVE_DLL*)  c_status="${UI_CYAN}[VALVE_DLL] ${UI_RST}" ;;
                    *STANDALONE*) c_status="${UI_ICE}[STANDALONE]${UI_RST}" ;;
                esac
                printf "%b\t%b\t%b\t%s\t%s\n" "${UI_DIM}${appid}${UI_RST}" "${UI_BOLD}${title}${UI_RST}" "$c_status" "$gdir" "$gbin"
            else
                printf "%-8s\t%-22s\t%-12s\t%s\t%s\n" "$appid" "$title" "[$status]" "$gdir" "$gbin"
            fi
        done
    done
}

# Generate FreeDesktop .desktop application shortcut (Chunk 5)
create_desktop_entry() {
    local game_dir="${1:-}"
    local title="${2:-}"

    if [ -z "$game_dir" ] || [ ! -d "$game_dir" ]; then
        echo "[ERROR] Direktori game tidak ditemukan atau tidak valid: $game_dir" >&2
        echo "Usage: gamectl make-desktop <game_dir> [title]" >&2
        return 1
    fi

    game_dir="$(cd "$game_dir" 2>/dev/null && pwd || echo "$game_dir")"

    # Attempt to resolve title if not supplied
    if [ -z "$title" ]; then
        local base_dir
        base_dir="$(basename "$game_dir")"
        local parent_apps
        parent_apps="$(dirname "$game_dir")"
        if [ "$(basename "$parent_apps")" = "common" ]; then
            local steamapps_dir
            steamapps_dir="$(dirname "$parent_apps")"
            local acf
            for acf in "$steamapps_dir"/appmanifest_*.acf; do
                [ -f "$acf" ] || continue
                local installdir
                installdir=$(grep -E '^\s*"installdir"' "$acf" | head -n 1 | sed -E 's/.*"installdir"[[:space:]]+"([^"]+)".*/\1/')
                if [ "$installdir" = "$base_dir" ]; then
                    title=$(grep -E '^\s*"name"' "$acf" | head -n 1 | sed -E 's/.*"name"[[:space:]]+"([^"]+)".*/\1/')
                    break
                fi
            done
        fi
        [ -z "$title" ] && title="$base_dir"
    fi

    # Locate game binary
    local gbin
    gbin="$(find_game_binary "$game_dir" 2>/dev/null || true)"
    if [ -z "$gbin" ]; then
        echo "[WARN] Biner executable game tidak terdeteksi otomatis di $game_dir" >&2
    fi

    # Locate game icon (prefer icon.png, icon.ico, logo.png, or any png/ico)
    local icon_path="applications-games"
    local found_icon=""
    for candidate in "icon.png" "icon.ico" "logo.png" "app.png" "banner.png"; do
        if [ -f "$game_dir/$candidate" ]; then
            found_icon="$game_dir/$candidate"
            break
        fi
    done
    if [ -z "$found_icon" ]; then
        found_icon=$(find "$game_dir" -maxdepth 2 \( -name "*.ico" -o -name "*.png" \) 2>/dev/null | head -n 1 || true)
    fi
    [ -n "$found_icon" ] && icon_path="$found_icon"

    # Resolve gamectl binary
    local gamectl_bin
    gamectl_bin="$(command -v gamectl 2>/dev/null || true)"
    if [ -z "$gamectl_bin" ]; then
        if [ -x "$HOME/.local/bin/gamectl" ]; then
            gamectl_bin="$HOME/.local/bin/gamectl"
        elif [ -x "/usr/local/bin/gamectl" ]; then
            gamectl_bin="/usr/local/bin/gamectl"
        else
            gamectl_bin="gamectl"
        fi
    fi

    # Sanitize title for desktop entry file name
    local safe_title
    safe_title=$(echo "$title" | tr -dc '[:alnum:]_-' | tr '[:upper:]' '[:lower:]')
    [ -z "$safe_title" ] && safe_title="game"

    local desk_dir="$HOME/.local/share/applications"
    mkdir -p "$desk_dir"
    local desk_file="$desk_dir/gamectl-${safe_title}.desktop"

    cat <<EOF > "$desk_file"
[Desktop Entry]
Type=Application
Name=$title
Comment=Launched via gamectl
Exec=$gamectl_bin launch "$game_dir" --hud
Icon=$icon_path
Terminal=false
Categories=Game;
Path=$game_dir
StartupNotify=true
EOF

    chmod +x "$desk_file"
    if command -v update-desktop-database >/dev/null 2>&1; then
        update-desktop-database "$desk_dir" 2>/dev/null || true
    fi

    echo "[VERIFIED] Desktop entry berhasil dibuat: $desk_file"
    echo "[INFO] Judul    : $title"
    echo "[INFO] Exec     : $gamectl_bin launch \"$game_dir\" --hud"
    echo "[INFO] Icon     : $icon_path"
    return 0
}


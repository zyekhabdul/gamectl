
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
        echo "[ERROR] Game directory not found or invalid: $game_dir" >&2
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
        echo "[WARN] Game executable binary not detected automatically in $game_dir" >&2
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

    echo "[VERIFIED] Desktop entry created successfully: $desk_file"
    echo "[INFO] Title    : $title"
    echo "[INFO] Exec     : $gamectl_bin launch \"$game_dir\" --hud"
    echo "[INFO] Icon     : $icon_path"
    return 0
}

# Resolve active Steam user grid directory (~/.local/share/Steam/userdata/<account_id>/config/grid)
get_steam_grid_dir() {
    if [ -n "${GAMECTL_GRID_DIR:-}" ]; then
        echo "$GAMECTL_GRID_DIR"
        return 0
    fi

    local s_roots=(
        "$HOME/.local/share/Steam"
        "$HOME/.steam/steam"
        "$HOME/.steam/root"
        "$HOME/.var/app/com.valvesoftware.Steam/.local/share/Steam"
        "$HOME/snap/steam/common/.local/share/Steam"
    )
    for s_root in "${s_roots[@]}"; do
        if [ -d "$s_root/userdata" ]; then
            for udir in "$s_root/userdata"/*; do
                [ -d "$udir" ] || continue
                local u_id
                u_id=$(basename "$udir")
                if [[ "$u_id" =~ ^[0-9]+$ ]] && [ "$u_id" -gt 0 ] 2>/dev/null; then
                    echo "$udir/config/grid"
                    return 0
                fi
            done
        fi
    done

    # Fallback to default
    echo "$HOME/.local/share/Steam/userdata/0/config/grid"
}

# Fetch official artwork (portrait, banner, hero, logo) from Steam CDN
fetch_steam_artwork() {
    local target="${1:-}"
    local appid="${2:-}"

    if [ -z "$target" ]; then
        echo "Usage: gamectl fetch-art <game_dir|appid> [appid]" >&2
        return 1
    fi

    local game_dir=""
    if [[ "$target" =~ ^[0-9]+$ ]] && [ -z "$appid" ]; then
        appid="$target"
    elif [ -d "$target" ]; then
        game_dir="$target"
    elif [ -f "$target" ]; then
        game_dir="$(dirname "$target")"
    fi

    # Resolve AppID from directory if not explicitly provided
    if [ -z "$appid" ] && [ -n "$game_dir" ]; then
        if [ -f "$game_dir/steam_appid.txt" ]; then
            appid=$(grep -oE '^[0-9]+' "$game_dir/steam_appid.txt" 2>/dev/null | head -n 1 || true)
        elif [ -f "$game_dir/steam_settings/steam_appid.txt" ]; then
            appid=$(grep -oE '^[0-9]+' "$game_dir/steam_settings/steam_appid.txt" 2>/dev/null | head -n 1 || true)
        fi
    fi

    if [ -z "$appid" ]; then
        echo "[ERROR] Cannot resolve Steam AppID for target: $target" >&2
        echo "        Provide a numeric AppID: gamectl fetch-art <dir> <appid>" >&2
        return 1
    fi

    local grid_dir
    grid_dir=$(get_steam_grid_dir)
    mkdir -p "$grid_dir"

    # Identify target shortcut and artwork IDs
    local target_ids=("$appid")
    if [ -n "$game_dir" ]; then
        local g_bin
        g_bin=$(find_game_binary "$game_dir" 2>/dev/null || true)
        local g_title
        g_title=$(basename "$game_dir")
        if [ -n "$g_bin" ]; then
            local sc_id
            sc_id=$(python3 -c "import binascii, sys; p = sys.argv[1]; t = sys.argv[2]; print((binascii.crc32((p + t).encode('utf-8')) | 0x80000000))" "$game_dir/$g_bin" "$g_title" 2>/dev/null || true)
            if [ -n "$sc_id" ] && [ "$sc_id" != "$appid" ]; then
                target_ids+=("$sc_id")
            fi
        fi
    fi

    echo "[INFO] Fetching Steam artwork for AppID: $appid"
    echo "[INFO] Destination Steam grid directory: $grid_dir"

    local tmp_dir
    tmp_dir=$(mktemp -d)
    local downloaded_count=0

    # Helper function to download and convert image to PNG
    _download_asset() {
        local asset_type="$1"
        local asset_suffix="$2"
        shift 2
        local urls=("$@")

        local tmp_file="$tmp_dir/${asset_type// /_}.raw"
        rm -f "$tmp_file"

        local url
        for url in "${urls[@]}"; do
            if curl -fsSL --connect-timeout 5 --max-time 15 "$url" -o "$tmp_file" 2>/dev/null && [ -s "$tmp_file" ]; then
                break
            fi
        done

        if [ ! -s "$tmp_file" ]; then
            echo "    • $(printf '%-18s' "$asset_type") : [WARN] Not available on CDN"
            return 1
        fi

        local tid
        for tid in "${target_ids[@]}"; do
            local dest_png="$grid_dir/${tid}${asset_suffix}.png"
            if command -v magick >/dev/null 2>&1; then
                magick "$tmp_file" "$dest_png" 2>/dev/null || cp "$tmp_file" "$dest_png"
            elif command -v convert >/dev/null 2>&1; then
                convert "$tmp_file" "$dest_png" 2>/dev/null || cp "$tmp_file" "$dest_png"
            elif command -v ffmpeg >/dev/null 2>&1; then
                ffmpeg -v error -y -i "$tmp_file" "$dest_png" 2>/dev/null || cp "$tmp_file" "$dest_png"
            else
                cp "$tmp_file" "$dest_png"
            fi
        done

        echo "    • $(printf '%-18s' "$asset_type") : [VERIFIED] Saved as <id>${asset_suffix}.png"
        downloaded_count=$((downloaded_count + 1))
        return 0
    }

    # 1. Portrait capsule (600x900) -> <shortcut_id>p.png
    _download_asset "Portrait Capsule" "p" \
        "https://cdn.akamai.steamstatic.com/steam/apps/$appid/library_600x900_2x.jpg" \
        "https://shared.fastly.steamstatic.com/store_item_assets/steam/apps/$appid/library_600x900_2x.jpg" \
        "https://cdn.cloudflare.steamstatic.com/steam/apps/$appid/library_600x900_2x.jpg" \
        "https://cdn.akamai.steamstatic.com/steam/apps/$appid/library_600x900.jpg" || true

    # 2. Horizontal banner (920x430 or 460x215) -> <shortcut_id>.png
    _download_asset "Horizontal Banner" "" \
        "https://cdn.akamai.steamstatic.com/steam/apps/$appid/header.jpg" \
        "https://shared.fastly.steamstatic.com/store_item_assets/steam/apps/$appid/header.jpg" \
        "https://cdn.cloudflare.steamstatic.com/steam/apps/$appid/header.jpg" || true

    # 3. Hero background (1920x620) -> <shortcut_id>_hero.png
    _download_asset "Hero Background" "_hero" \
        "https://cdn.akamai.steamstatic.com/steam/apps/$appid/library_hero.jpg" \
        "https://shared.fastly.steamstatic.com/store_item_assets/steam/apps/$appid/library_hero.jpg" \
        "https://cdn.cloudflare.steamstatic.com/steam/apps/$appid/library_hero.jpg" || true

    # 4. Logo transparent overlay -> <shortcut_id>_logo.png
    _download_asset "Logo Overlay" "_logo" \
        "https://cdn.akamai.steamstatic.com/steam/apps/$appid/logo.png" \
        "https://shared.fastly.steamstatic.com/store_item_assets/steam/apps/$appid/logo.png" \
        "https://cdn.cloudflare.steamstatic.com/steam/apps/$appid/logo.png" || true

    rm -rf "$tmp_dir"

    if [ "$downloaded_count" -gt 0 ]; then
        echo "[VERIFIED] Successfully fetched $downloaded_count artwork asset(s) for AppID: $appid"
        return 0
    else
        echo "[ERROR] Failed to fetch any artwork assets for AppID: $appid" >&2
        return 1
    fi
}

# Resolve active Steam user shortcuts.vdf path (~/.local/share/Steam/userdata/<account_id>/config/shortcuts.vdf)
get_steam_shortcuts_vdf() {
    if [ -n "${GAMECTL_SHORTCUTS_VDF:-}" ]; then
        echo "$GAMECTL_SHORTCUTS_VDF"
        return 0
    fi

    local s_roots=(
        "$HOME/.local/share/Steam"
        "$HOME/.steam/steam"
        "$HOME/.steam/root"
        "$HOME/.var/app/com.valvesoftware.Steam/.local/share/Steam"
        "$HOME/snap/steam/common/.local/share/Steam"
    )
    for s_root in "${s_roots[@]}"; do
        if [ -d "$s_root/userdata" ]; then
            for udir in "$s_root/userdata"/*; do
                [ -d "$udir" ] || continue
                local u_id
                u_id=$(basename "$udir")
                if [[ "$u_id" =~ ^[0-9]+$ ]] && [ "$u_id" -gt 0 ] 2>/dev/null; then
                    echo "$udir/config/shortcuts.vdf"
                    return 0
                fi
            done
        fi
    done

    # Default fallback
    echo "$HOME/.local/share/Steam/userdata/0/config/shortcuts.vdf"
}

# Check if Steam client process is actively running and warn about memory lock
check_steam_active() {
    local context="${1:-Steam operations}"
    if pgrep -x steam >/dev/null 2>&1; then
        echo "[WARN] Steam client is currently running! $context while Steam is active may cause file lock conflicts or get overwritten upon client exit." >&2
        echo "[WARN] Recommendation: Exit Steam or restart it after this operation to reload shortcuts and manifests cleanly." >&2
        return 0
    fi
    return 1
}

# Add or update a non-Steam shortcut in Steam Deck Game Mode (binary shortcuts.vdf)
add_steam_shortcut() {
    local game_dir="${1:-}"
    local title="${2:-}"

    if [ -z "$game_dir" ]; then
        echo "Usage: gamectl add-to-steam <game_dir> [title]" >&2
        return 1
    fi

    if [ ! -d "$game_dir" ]; then
        echo "[ERROR] Game directory does not exist: $game_dir" >&2
        return 1
    fi

    # Guard against concurrent Steam client memory lock on shortcuts.vdf
    check_steam_active "Registering non-Steam shortcut in shortcuts.vdf" || true

    game_dir="$(cd "$game_dir" && pwd)"

    if [ -z "$title" ]; then
        title="$(basename "$game_dir")"
    fi

    # Locate game icon
    local icon_path=""
    for candidate in "icon.png" "icon.ico" "logo.png" "app.png" "banner.png"; do
        if [ -f "$game_dir/$candidate" ]; then
            icon_path="$game_dir/$candidate"
            break
        fi
    done
    if [ -z "$icon_path" ]; then
        icon_path=$(find "$game_dir" -maxdepth 2 \( -name "*.ico" -o -name "*.png" \) 2>/dev/null | head -n 1 || true)
    fi

    # Resolve gamectl binary
    local gamectl_bin
    gamectl_bin="$(command -v gamectl 2>/dev/null || true)"
    if [ -z "$gamectl_bin" ]; then
        if [ -x "$HOME/.local/bin/gamectl" ]; then
            gamectl_bin="$HOME/.local/bin/gamectl"
        elif [ -x "/usr/local/bin/gamectl" ]; then
            gamectl_bin="/usr/local/bin/gamectl"
        elif [ -x "$REPO_ROOT/bin/gamectl" ]; then
            gamectl_bin="$REPO_ROOT/bin/gamectl"
        else
            gamectl_bin="gamectl"
        fi
    fi

    local shortcuts_file
    shortcuts_file="$(get_steam_shortcuts_vdf)"
    local vdf_dir
    vdf_dir="$(dirname "$shortcuts_file")"
    mkdir -p "$vdf_dir"

    # Create atomic backup if file already exists
    if [ -f "$shortcuts_file" ]; then
        cp -f "$shortcuts_file" "${shortcuts_file}.bak"
    fi

    python3 - "$shortcuts_file" "$title" "$game_dir" "$gamectl_bin" "$icon_path" << 'PYEOF'
import sys, os, struct, binascii

shortcuts_path = sys.argv[1]
title = sys.argv[2]
game_dir = os.path.abspath(sys.argv[3])
gamectl_bin = sys.argv[4]
icon_path = sys.argv[5]

exe_field = f'"{gamectl_bin}"'
startdir_field = f'"{game_dir}"'
launch_opts = f'launch "{game_dir}" --hud'

raw_crc = (binascii.crc32((exe_field + title).encode('utf-8')) | 0x80000000) & 0xffffffff
signed_appid = struct.unpack('<i', struct.pack('<I', raw_crc))[0]

def parse_binary_vdf(data):
    pos = 0
    def read_str():
        nonlocal pos
        end = data.find(b'\x00', pos)
        if end == -1: return ''
        s = data[pos:end].decode('utf-8', errors='replace')
        pos = end + 1
        return s
    def parse_map():
        nonlocal pos
        res = {}
        while pos < len(data):
            b = data[pos]
            pos += 1
            if b == 8: break
            key = read_str()
            if b == 0: res[key] = parse_map()
            elif b == 1: res[key] = read_str()
            elif b == 2:
                if pos + 4 <= len(data):
                    val = struct.unpack('<i', data[pos:pos+4])[0]
                    pos += 4
                    res[key] = val
        return res
    if data.startswith(b'\x00shortcuts\x00'):
        pos = len(b'\x00shortcuts\x00')
        root = parse_map()
        shortcuts = []
        for k in sorted(root.keys(), key=lambda x: int(x) if x.isdigit() else 9999):
            if isinstance(root[k], dict): shortcuts.append(root[k])
        return shortcuts
    return []

def serialize_shortcuts(shortcuts):
    buf = bytearray(b'\x00shortcuts\x00')
    for idx, s in enumerate(shortcuts):
        buf.append(0)
        buf.extend(str(idx).encode('utf-8') + b'\x00')
        for k, v in s.items():
            if isinstance(v, int):
                buf.append(2)
                buf.extend(k.encode('utf-8') + b'\x00')
                buf.extend(struct.pack('<i', v))
            elif isinstance(v, str):
                buf.append(1)
                buf.extend(k.encode('utf-8') + b'\x00')
                buf.extend(v.encode('utf-8') + b'\x00')
            elif isinstance(v, dict):
                buf.append(0)
                buf.extend(k.encode('utf-8') + b'\x00')
                for tk, tv in v.items():
                    buf.append(1)
                    buf.extend(str(tk).encode('utf-8') + b'\x00')
                    buf.extend(str(tv).encode('utf-8') + b'\x00')
                buf.append(8)
        buf.append(8)
    buf.append(8)
    buf.append(8)
    return bytes(buf)

shortcuts = []
if os.path.exists(shortcuts_path):
    try:
        with open(shortcuts_path, 'rb') as f:
            shortcuts = parse_binary_vdf(f.read())
    except Exception:
        shortcuts = []

existing_idx = -1
for i, sc in enumerate(shortcuts):
    if sc.get('AppName') == title or sc.get('StartDir', '').strip('"') == game_dir:
        existing_idx = i
        break

new_entry = {
    'appid': signed_appid,
    'AppName': title,
    'Exe': exe_field,
    'StartDir': startdir_field,
    'icon': icon_path,
    'ShortcutPath': '',
    'LaunchOptions': launch_opts,
    'IsHidden': 0,
    'AllowDesktopConfig': 1,
    'AllowOverlay': 1,
    'OpenVR': 0,
    'Devkit': 0,
    'DevkitGameID': '',
    'DevkitOverrideAppID': 0,
    'LastPlayTime': 0,
    'FlatpakAppID': '',
    'tags': {}
}

if existing_idx >= 0:
    shortcuts[existing_idx] = new_entry
    action = "updated"
else:
    shortcuts.append(new_entry)
    action = "registered"

out_data = serialize_shortcuts(shortcuts)
tmp_path = shortcuts_path + f'.tmp.{os.getpid()}'
with open(tmp_path, 'wb') as f:
    f.write(out_data)
os.replace(tmp_path, shortcuts_path)

print(f'[VERIFIED] Steam shortcut {action} successfully: {title}')
print(f'[INFO] Target 32-bit AppID : {raw_crc}')
print(f'[INFO] Shortcuts file      : {shortcuts_path}')
print(f'[INFO] Launch Options      : {launch_opts}')
PYEOF

    # Optionally attempt artwork synchronization if an AppID is available
    if [ -f "$game_dir/steam_appid.txt" ] || [ -f "$game_dir/steam_settings/steam_appid.txt" ]; then
        fetch_steam_artwork "$game_dir" >/dev/null 2>&1 || true
    fi

    return 0
}


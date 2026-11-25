
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

# Discover active SLSsteam configuration directory
get_sls_root() {
    local xdg="${XDG_CONFIG_HOME:-$HOME/.config}"
    echo "$xdg/SLSsteam"
}

# Discover active SLSsteam manifests storage directory
get_sls_manifests_dir() {
    local sls_root
    sls_root="$(get_sls_root)"
    echo "$sls_root/manifests"
}

# Discover active Steam stplug-in Lua directory
get_steam_stplug_in_dir() {
    local s_root
    s_root="$(get_steam_root 2>/dev/null || echo "$HOME/.local/share/Steam")"
    echo "$s_root/config/stplug-in"
}

# Discover active Steam depotcache directory
get_steam_depotcache_dir() {
    local s_root
    s_root="$(get_steam_root 2>/dev/null || echo "$HOME/.local/share/Steam")"
    echo "$s_root/depotcache"
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

# Scan installed games dynamically in standard & custom paths (v3 6-column schema)
scan_installed_games() {
    local is_formatted=false
    local force_refresh=false
    local store_filter="ALL"

    while [ $# -gt 0 ]; do
        case "$1" in
            --formatted|-f) is_formatted=true ;;
            --refresh|--no-cache|-r) force_refresh=true ;;
            --store)
                shift
                store_filter="${1:-ALL}"
                ;;
            --store=*)
                store_filter="${1#--store=}"
                ;;
        esac
        shift || true
    done
    store_filter="${store_filter^^}"
    [ -n "$store_filter" ] || store_filter="ALL"

    local cache_dir
    cache_dir="$(get_runtime_dir)"
    local cache_file="$cache_dir/scancache.tab"

    local epic_cfg_dir="${LEGENDARY_CONFIG_PATH:-${XDG_CONFIG_HOME:-$HOME/.config}/legendary}"
    declare -F _epic_config_dir >/dev/null 2>&1 && epic_cfg_dir="$(_epic_config_dir)"
    local epic_installed="$epic_cfg_dir/installed.json"

    local amazon_cfg_dir="${NILE_CONFIG_PATH:-${XDG_CONFIG_HOME:-$HOME/.config}/nile}"
    declare -F _amazon_config_dir >/dev/null 2>&1 && amazon_cfg_dir="$(_amazon_config_dir)"
    local amazon_installed="$amazon_cfg_dir/installed.json"

    # Fast-path: Check cache validity (TTL: 60s, invalidated if candidate library directories are newer)
    local use_cached=false
    if [ "$force_refresh" = false ] && [ -f "$cache_file" ] &&
       [ "$(head -n 1 "$cache_file")" = "# gamectl scanner v3" ]; then
        local now mtime
        now=$(date +%s)
        mtime=$(stat -c%Y "$cache_file" 2>/dev/null || echo 0)
        if [ $((now - mtime)) -lt 60 ]; then
            use_cached=true
            local lib_check
            for lib_check in "$HOME/Games" "$HOME/GOG Games" "$HOME/.local/share/Steam/steamapps" "$HOME/.local/share/lutris/games"; do
                if [ -d "$lib_check" ] && [ "$lib_check" -nt "$cache_file" ]; then
                    use_cached=false
                    break
                fi
            done
            if [ "$use_cached" = true ] && [ -f "$epic_installed" ] && [ "$epic_installed" -nt "$cache_file" ]; then
                use_cached=false
            fi
            if [ "$use_cached" = true ] && [ -f "$amazon_installed" ] && [ "$amazon_installed" -nt "$cache_file" ]; then
                use_cached=false
            fi
        fi
    fi

    if [ "$use_cached" = false ]; then
        printf '%s\n' '# gamectl scanner v3' > "$cache_file.tmp"
        declare -A seen_dirs=()
        declare -A seen_appids=()

        # 1. Scan Steam Libraries
        local steam_lib
        local re_appid='"appid"[[:space:]]+"([0-9]+)"'
        local re_name='"name"[[:space:]]+"([^"]+)"'
        local re_installdir='"installdir"[[:space:]]+"([^"]+)"'
        while IFS= read -r steam_lib; do
            [ -d "$steam_lib" ] || continue
            for acf in "$steam_lib"/appmanifest_*.acf; do
                [ -f "$acf" ] || continue

                # Single-pass regex parse of ACF manifest without subshell forks
                local appid="" name="" installdir=""
                while IFS= read -r acf_line; do
                    if [[ "$acf_line" =~ $re_appid ]]; then
                        appid="${BASH_REMATCH[1]}"
                    elif [[ "$acf_line" =~ $re_name ]]; then
                        name="${BASH_REMATCH[1]}"
                    elif [[ "$acf_line" =~ $re_installdir ]]; then
                        installdir="${BASH_REMATCH[1]}"
                    fi
                    [ -n "$appid" ] && [ -n "$name" ] && [ -n "$installdir" ] && break
                done < "$acf"

                # Filter out Proton, Steam Linux Runtimes, and tools
                [[ "$name" =~ ^(Steam Linux Runtime|Proton|Steamworks) ]] && continue
                [ -z "$installdir" ] && continue

                local gdir="$steam_lib/common/$installdir"
                validate_tui_fields "$appid" "$name" "$gdir" || continue
                [ -d "$gdir" ] || continue

                local canon_gdir
                canon_gdir=$(realpath -e "$gdir" 2>/dev/null || echo "$gdir")
                [[ -v seen_dirs["$canon_gdir"] ]] && continue
                [[ -v seen_dirs["$gdir"] ]] && continue
                seen_dirs["$canon_gdir"]=1
                seen_dirs["$gdir"]=1
                [ -n "$appid" ] && [ "$appid" != "STANDALONE" ] && seen_appids["$appid"]=1

                local gbin
                gbin=$(find_game_binary "$gdir") || continue
                [ -z "$gbin" ] && continue

                local status
                status=$(resolve_game_drm_status "$gdir" "" "$gbin")

                [ -z "$appid" ] && appid="STANDALONE"
                printf "%s\t%s\t%s\t%s\t%s\tSTEAM\n" "$appid" "$name" "$status" "$gdir" "$gbin" >> "$cache_file.tmp"
            done
        done < <(get_steam_libraries)

        # 1b. Scan Epic Games (Legendary installed.json) before custom dirs to deduplicate ~/Games/
        if [ -f "$epic_installed" ] && command -v jq >/dev/null 2>&1; then
            local epic_rows=""
            if epic_rows=$(jq -r '
                (if type == "object" then . else error("invalid") end) |
                to_entries[] |
                (.key | tostring) as $k |
                if (.value | type) != "object" then
                    "ERR\t" + ($k | gsub("[\\t\\r\\n]"; "_"))
                else
                    ((.value.app_name // $k) | tostring) as $id |
                    ((.value.title // $id) | tostring) as $title |
                    ((.value.install_path // "") | tostring) as $ipath |
                    ((.value.executable // "") | tostring) as $exe |
                    if ($id | test("[\\t\\r\\n]")) or ($title | test("[\\t\\r\\n]")) or
                       ($ipath | test("[\\t\\r\\n]")) or ($exe | test("[\\t\\r\\n]")) or
                       ($id == "") or ($ipath == "") then
                        "ERR\t" + ($k | gsub("[\\t\\r\\n]"; "_"))
                    else
                        ["OK", $id, $title, $ipath, $exe] | @tsv
                    end
                end' "$epic_installed" 2>/dev/null); then
                local e_kind e_id e_title e_path e_exe
                while IFS=$'\t' read -r e_kind e_id e_title e_path e_exe; do
                    [ -n "$e_kind" ] || continue
                    if [ "$e_kind" = "ERR" ]; then
                        printf '[ERROR] Invalid Epic metadata entry (%s) in %s\n' "${e_id:-unknown}" "$epic_installed" >&2
                        continue
                    fi
                    [ -d "$e_path" ] || continue
                    local canon_edir
                    canon_edir=$(realpath -e "$e_path" 2>/dev/null || echo "$e_path")
                    [[ -v seen_dirs["$canon_edir"] ]] && continue
                    [[ -v seen_dirs["$e_path"] ]] && continue
                    seen_dirs["$canon_edir"]=1
                    seen_dirs["$e_path"]=1

                    local e_gbin=""
                    if [ -n "$e_exe" ] && [[ "$e_exe" != /* ]] && [[ "$e_exe" != *".."* ]] && [ -f "$e_path/$e_exe" ]; then
                        e_gbin="$e_exe"
                    else
                        e_gbin=$(find_game_binary "$e_path") || continue
                    fi
                    [ -n "$e_gbin" ] || continue
                    validate_tui_fields "$e_id" "$e_title" "$e_path" "$e_gbin" || continue

                    local e_status
                    e_status=$(resolve_game_drm_status "$e_path" "" "$e_gbin")
                    [ "$e_status" = "STANDALONE" ] && e_status="EPIC"
                    printf "%s\t%s\t%s\t%s\t%s\tEPIC\n" "$e_id" "$e_title" "$e_status" "$e_path" "$e_gbin" >> "$cache_file.tmp"
                done <<< "$epic_rows"
            else
                printf '[ERROR] Invalid Epic installed.json payload in %s\n' "$epic_installed" >&2
            fi
        fi

        # 1c. Scan Amazon Games (Nile installed.json) before custom dirs to deduplicate ~/Games/
        if [ -f "$amazon_installed" ] && command -v jq >/dev/null 2>&1; then
            local amazon_rows=""
            if amazon_rows=$(jq -r '
                (if type == "array" then to_entries | map({k:(.key|tostring), v:.value})
                 elif type == "object" then to_entries | map({k:.key, v:.value})
                 else error("invalid") end)[] |
                (.k | tostring) as $k |
                if (.v | type) != "object" then "ERR\t" + ($k | gsub("[\\t\\r\\n]"; "_"))
                else
                    ((.v.id // .v.product.id // (if ($k | test("^[0-9]+$")) then "" else $k end)) | tostring) as $id |
                    ((.v.title // .v.product.title // $id) | tostring) as $title |
                    ((.v.path // .v.install_path // "") | tostring) as $ipath |
                    ((.v.executable // "") | tostring) as $exe |
                    if ($id == "") or ($ipath == "") or ($id | test("[\\t\\r\\n]")) or ($title | test("[\\t\\r\\n]")) or ($ipath | test("[\\t\\r\\n]")) or ($exe | test("[\\t\\r\\n]")) then
                        "ERR\t" + ($k | gsub("[\\t\\r\\n]"; "_"))
                    else ["OK", $id, $title, $ipath, $exe] | @tsv end
                end' "$amazon_installed" 2>/dev/null); then
                local a_kind a_id a_title a_path a_exe
                while IFS=$'\t' read -r a_kind a_id a_title a_path a_exe; do
                    [ -n "$a_kind" ] || continue
                    if [ "$a_kind" = "ERR" ]; then
                        printf '[ERROR] Invalid Amazon metadata entry (%s) in %s\n' "${a_id:-unknown}" "$amazon_installed" >&2
                        continue
                    fi
                    [ -d "$a_path" ] || continue
                    local canon_adir
                    canon_adir=$(realpath -e "$a_path" 2>/dev/null || echo "$a_path")
                    [[ -v seen_dirs["$canon_adir"] ]] && continue
                    [[ -v seen_dirs["$a_path"] ]] && continue
                    seen_dirs["$canon_adir"]=1
                    seen_dirs["$a_path"]=1
                    local a_gbin=""
                    if [ -n "$a_exe" ] && [[ "$a_exe" != /* ]] && [[ "$a_exe" != *".."* ]] && [ -f "$a_path/$a_exe" ]; then
                        a_gbin="$a_exe"
                    else
                        a_gbin=$(find_game_binary "$a_path") || continue
                    fi
                    [ -n "$a_gbin" ] || continue
                    validate_tui_fields "$a_id" "$a_title" "$a_path" "$a_gbin" || continue
                    local a_status
                    a_status=$(resolve_game_drm_status "$a_path" "" "$a_gbin")
                    [ "$a_status" = "STANDALONE" ] && a_status="AMAZON"
                    printf "%s\t%s\t%s\t%s\t%s\tAMAZON\n" "$a_id" "$a_title" "$a_status" "$a_path" "$a_gbin" >> "$cache_file.tmp"
                done <<< "$amazon_rows"
            else
                printf '[ERROR] Invalid Amazon installed.json payload in %s\n' "$amazon_installed" >&2
            fi
        fi

        # 2. Scan Custom & Standalone Directories
        local custom_search_dirs=(
            "$HOME/Games"
            "$HOME/GOG Games"
            "$HOME/.local/share/lutris/games"
        )

        # Allow extending library directories via ~/.config/gamectl/libraries or env
        if [ -f "$HOME/.config/gamectl/library_dir" ]; then
            local p_lib
            p_lib=$(head -n 1 "$HOME/.config/gamectl/library_dir" 2>/dev/null | tr -d '\r\n' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
            [ -n "$p_lib" ] && custom_search_dirs+=("${p_lib/#\~/$HOME}")
        fi
        if [ -f "$HOME/.config/gamectl/libraries" ]; then
            while IFS= read -r line || [ -n "$line" ]; do
                line="${line#"${line%%[![:space:]]*}"}" # trim leading
                line="${line%"${line##*[![:space:]]}"}" # trim trailing
                [ -z "$line" ] && continue
                [[ "$line" =~ ^# ]] && continue
                custom_search_dirs+=("${line/#\~/$HOME}")
            done < "$HOME/.config/gamectl/libraries"
        fi

        if [ -n "${GAMECTL_LIBRARY_DIR:-}" ]; then
            custom_search_dirs+=("${GAMECTL_LIBRARY_DIR/#\~/$HOME}")
        fi
        if [ -n "${GAMECTL_LIBRARY_DIRS:-}" ]; then
            IFS=":" read -r -a extra_dirs <<< "$GAMECTL_LIBRARY_DIRS"
            custom_search_dirs+=("${extra_dirs[@]}")
        fi

        for base_dir in "${custom_search_dirs[@]}"; do
            [ -d "$base_dir" ] || continue
            for gdir in "$base_dir"/*; do
                [ -d "$gdir" ] || continue
                validate_tui_fields "$gdir" || continue

                local canon_gdir
                canon_gdir=$(realpath -e "$gdir" 2>/dev/null || echo "$gdir")
                [[ -v seen_dirs["$canon_gdir"] ]] && continue
                [[ -v seen_dirs["$gdir"] ]] && continue
                seen_dirs["$canon_gdir"]=1
                seen_dirs["$gdir"]=1

                local folder_name="${gdir##*/}"
                [[ "$folder_name" =~ ^\. ]] && continue

                local gbin
                gbin=$(find_game_binary "$gdir") || continue
                [ -z "$gbin" ] && continue

                local row_store="STANDALONE" gog_info="" gog_id="" gog_name="" _gf
                for _gf in "$gdir"/goggame-*.info; do
                    [ -f "$_gf" ] && gog_info="$_gf" && break
                done
                if [ -n "$gog_info" ]; then
                    local gog_tsv=""
                    if ! gog_tsv=$(jq -r '[((.gameId // .rootGameId // "") | tostring), ((.name // "") | tostring)] | if any(test("[\\t\\r\\n]")) then error("invalid") else @tsv end' "$gog_info" 2>/dev/null); then
                        printf '[ERROR] Invalid GOG metadata in %s\n' "$gdir" >&2
                        continue
                    fi
                    IFS=$'\t' read -r gog_id gog_name <<< "$gog_tsv"
                    if [ -z "$gog_id" ]; then
                        local _gbase="${gog_info##*/}"
                        _gbase="${_gbase#goggame-}"
                        gog_id="${_gbase%.info}"
                    fi
                    row_store="GOG"
                elif [ -f "$gdir/.gog_id" ]; then
                    gog_id=$(cat "$gdir/.gog_id" 2>/dev/null) || gog_id=""
                    if [ -f "$gdir/gameinfo" ]; then
                        gog_name=$(head -n 1 "$gdir/gameinfo" 2>/dev/null) || gog_name=""
                    fi
                    [ -n "$gog_id" ] && row_store="GOG"
                fi

                local appid
                if [ "$row_store" = "GOG" ]; then
                    appid="${gog_id:-STANDALONE}"
                else
                    appid="$(resolve_game_appid "$gdir" "STANDALONE")"
                fi

                # AppID collision precedence: skip duplicate Steam AppID if already discovered in Steam library
                if [ "$row_store" != "GOG" ] && [ "$appid" != "STANDALONE" ] && [[ -v seen_appids["$appid"] ]]; then
                    continue
                fi
                [ "$row_store" != "GOG" ] && [ "$appid" != "STANDALONE" ] && seen_appids["$appid"]=1

                local title="${gog_name:-$folder_name}"
                if [ -f "$gdir/.gamectl_title" ]; then
                    title=$(cat "$gdir/.gamectl_title" 2>/dev/null) || title="$folder_name"
                fi
                [ -n "$title" ] || title="$folder_name"
                validate_tui_fields "$appid" "$title" "$gbin" || continue

                local status
                status=$(resolve_game_drm_status "$gdir" "" "$gbin")
                [ "$row_store" = "GOG" ] && [ "$status" = "STANDALONE" ] && status="GOG"

                printf "%s\t%s\t%s\t%s\t%s\t%s\n" "$appid" "$title" "$status" "$gdir" "$gbin" "$row_store" >> "$cache_file.tmp"
            done
        done
        mv -f "$cache_file.tmp" "$cache_file"
    fi

    # Render formatted or raw tab entries (6-column v3 TSV: APPID, TITLE, STATUS, GAME_DIR, GAME_BIN, STORE)
    if [ "$is_formatted" = true ]; then
        while IFS=$'\t' read -r c_appid c_title c_status c_gdir c_gbin c_store; do
            [[ "$c_appid" == \#* ]] && continue
            [ -z "$c_gdir" ] && continue
            c_store="${c_store:-STANDALONE}"
            [ "$store_filter" != "ALL" ] && [ "${c_store^^}" != "$store_filter" ] && continue
            local c_badge=""
            case "$c_status" in
                *GBE_FORK*)   c_badge="${UI_GREEN}[GBE_FORK]  ${UI_RST}" ;;
                *VALVE_SO*)   c_badge="${UI_AMBER}[VALVE_SO]  ${UI_RST}" ;;
                *VALVE_DLL*)  c_badge="${UI_CYAN}[VALVE_DLL] ${UI_RST}" ;;
                *GOG*)        c_badge="${UI_PURPLE}[GOG]       ${UI_RST}" ;;
                *EPIC*)       c_badge="${UI_CYAN}[EPIC]      ${UI_RST}" ;;
                *AMAZON*)     c_badge="${UI_AMBER}[AMAZON]    ${UI_RST}" ;;
                *)            c_badge="${UI_ICE}[STANDALONE]${UI_RST}" ;;
            esac
            printf "%s\t%s\t%s\t%s\t%s\t%s\n" "${UI_DIM}${c_appid}${UI_RST}" "${UI_BOLD}${c_title}${UI_RST}" "$c_badge" "$c_gdir" "$c_gbin" "$c_store"
        done < "$cache_file"
    else
        while IFS=$'\t' read -r c_appid c_title c_status c_gdir c_gbin c_store; do
            [[ "$c_appid" == \#* ]] && continue
            [ -z "$c_gdir" ] && continue
            c_store="${c_store:-STANDALONE}"
            [ "$store_filter" != "ALL" ] && [ "${c_store^^}" != "$store_filter" ] && continue
            local clean_stat="$c_status"
            [[ "$clean_stat" != \[*\] ]] && clean_stat="[$clean_stat]"
            printf "%-8s\t%-22s\t%-12s\t%s\t%s\t%s\n" "$c_appid" "$c_title" "$clean_stat" "$c_gdir" "$c_gbin" "$c_store"
        done < "$cache_file"
    fi
}

# Standalone-source compatibility: load split discovery submodules when sourced directly outside bin/gamectl
if [ -z "${GAMECTL_BUNDLED:-}" ] && [ -n "${BASH_SOURCE[0]:-}" ]; then
    _disc_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd)"
    for _disc_sub in 21_shortcuts_artwork.sh; do
        if [ -f "$_disc_dir/$_disc_sub" ]; then
            # shellcheck source=/dev/null
            source "$_disc_dir/$_disc_sub"
        fi
    done
    unset _disc_dir _disc_sub
fi

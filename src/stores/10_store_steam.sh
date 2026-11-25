# ==============================================================================
# Built-in Steam Store Adapter (Standalone CDN + GBE Fork + Offline Metadata)
# ==============================================================================

# Offline availability probe for built-in Steam standalone adapter.
store_steam_available() {
    if declare -F resolve_depot_dl_bin >/dev/null 2>&1 && resolve_depot_dl_bin >/dev/null 2>&1; then
        return 0
    fi
    if command -v curl >/dev/null 2>&1 && command -v jq >/dev/null 2>&1; then
        return 0
    fi
    return 1
}

# Report offline-safe capability status for built-in Steam adapter.
store_steam_status() {
    local dl_bin="" dl_status="missing"
    if declare -F resolve_depot_dl_bin >/dev/null 2>&1; then
        dl_bin="$(resolve_depot_dl_bin 2>/dev/null || true)"
    fi
    if [ -n "$dl_bin" ]; then
        dl_status="ready ($dl_bin)"
    fi

    local gbe_linux="" gbe_win="" gbe_status="missing"
    if declare -F get_gbe_template >/dev/null 2>&1; then
        gbe_linux="$(get_gbe_template linux x64 2>/dev/null || true)"
        gbe_win="$(get_gbe_template windows x64 2>/dev/null || true)"
    fi
    if [ -n "$gbe_linux" ] && [ -n "$gbe_win" ]; then
        gbe_status="ready (linux+windows)"
    elif [ -n "$gbe_linux" ] || [ -n "$gbe_win" ]; then
        gbe_status="partial"
    fi

    local lua_status="unconfigured"
    if [ -s "$HOME/.config/gamectl/lua_tools_auth.json" ]; then
        lua_status="session present"
    fi

    local hubcap_key="" hubcap_status="unconfigured"
    if declare -F get_hubcap_api_key >/dev/null 2>&1; then
        hubcap_key="$(get_hubcap_api_key 2>/dev/null || true)"
    fi
    [ -n "$hubcap_key" ] && hubcap_status="configured"

    echo "store=steam"
    echo "  depot_dl : $dl_status"
    echo "  gbe_fork : $gbe_status"
    echo "  luatools : $lua_status"
    echo "  hubcap   : $hubcap_status"
    return 0
}

# Search Steam Store catalog and emit sanitized TSV:
#   STEAM<TAB>APP_ID<TAB>TITLE<TAB>PLATFORMS<TAB>STATUS
store_steam_search() {
    local query="${1:-}"
    if [ -z "$query" ]; then
        echo "[ERROR] Usage: store_steam_search <query>" >&2
        return 1
    fi

    local encoded_query raw_results parsed_rows
    encoded_query=$(python3 -c "import urllib.parse, sys; print(urllib.parse.quote(sys.argv[1]))" "$query")
    raw_results=$(curl -s --connect-timeout 5 --max-time 15 \
        "https://store.steampowered.com/api/storesearch/?term=${encoded_query}&l=english&cc=US" 2>/dev/null || true)

    if [ -z "$raw_results" ]; then
        echo "[ERROR] Steam Store search failed or returned an empty response." >&2
        return 1
    fi

    if ! parsed_rows=$(printf '%s' "$raw_results" | jq -r '
        if (.items | type) != "array" then
            error("Invalid Steam search payload")
        elif any(.items[]?; (.id | tostring | test("[\\t\\r\\n]")) or (.name | tostring | test("[\\t\\r\\n]"))) then
            error("TUI catalog contains TAB, CR or newline")
        else
            .items[] |
            [
                (.id | tostring),
                (.name | tostring),
                (
                    [
                        (if (.platforms.linux // false) then "linux" else empty end),
                        (if (.platforms.windows // false) then "windows" else empty end),
                        (if (.platforms.mac // false) then "mac" else empty end)
                    ] | join(",") | if length == 0 then "unknown" else . end
                )
            ] | @tsv
        end
    ' 2>/dev/null); then
        echo "[ERROR] Invalid Steam search catalog." >&2
        return 1
    fi

    declare -A installed_ids=()
    if declare -F scan_installed_games >/dev/null 2>&1; then
        local ins_id
        while IFS=$'\t' read -r ins_id _; do
            ins_id="${ins_id//[[:space:]]/}"
            [ -n "$ins_id" ] && installed_ids["$ins_id"]=1
        done < <(scan_installed_games 2>/dev/null || true)
    fi

    local app_id title platforms row_status
    while IFS=$'\t' read -r app_id title platforms; do
        [ -n "$app_id" ] || continue
        if declare -F validate_tui_fields >/dev/null 2>&1; then
            validate_tui_fields "$app_id" "$title" "$platforms" || return 1
        fi
        row_status="AVAILABLE"
        [ -n "${installed_ids["$app_id"]:-}" ] && row_status="INSTALLED"
        printf 'STEAM\t%s\t%s\t%s\t%s\n' "$app_id" "$title" "$platforms" "$row_status"
    done <<< "$parsed_rows"
    return 0
}

# List installed games belonging to Steam or Standalone libraries (v3 6-col TSV).
store_steam_list_installed() {
    if ! declare -F scan_installed_games >/dev/null 2>&1; then
        echo "[ERROR] scan_installed_games is unavailable." >&2
        return 1
    fi
    scan_installed_games "$@" | awk -F'\t' '{ st = ($6 == "" ? "STANDALONE" : $6); if (st == "STEAM" || st == "STANDALONE") print }'
}

# Delegate Steam/Standalone download to headless downloader engine.
store_steam_download() {
    local app_id="${1:-}"
    if [ -z "$app_id" ]; then
        echo "Usage: store_steam_download <appid> [target_dir] [title] [options...]" >&2
        return 1
    fi
    download_game "$@"
}

# Synchronize offline DLC manifest metadata without invoking Steam Client.
store_steam_sync() {
    local app_id="${1:-}"
    local game_dir="${2:-}"
    if [ -z "$app_id" ] || [ -z "$game_dir" ] || [ ! -d "$game_dir" ]; then
        echo "[ERROR] Usage: store_steam_sync <appid> <existing_game_dir>" >&2
        return 1
    fi
    fetch_dlc "$game_dir" "$app_id"
}

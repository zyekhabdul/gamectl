# ==============================================================================
# Optional Epic Games Store Adapter (legendary)
# ==============================================================================

_epic_config_dir() {
    printf '%s\n' "${LEGENDARY_CONFIG_PATH:-${XDG_CONFIG_HOME:-$HOME/.config}/legendary}"
}

_epic_resolve_cli() {
    command -v legendary >/dev/null 2>&1 && { echo "legendary"; return 0; }
    return 1
}

_epic_auth_session_present() {
    [ -s "$(_epic_config_dir)/user.json" ]
}

store_epic_available() { _epic_resolve_cli >/dev/null 2>&1; }

store_epic_status() {
    local cli_path="" cli_status="missing (optional: install legendary)"
    if _epic_resolve_cli >/dev/null 2>&1; then
        cli_path="$(command -v legendary 2>/dev/null || echo "legendary")"
        cli_status="ready (legendary: $cli_path)"
    fi
    local auth_status="unconfigured (run 'gamectl epic auth')"
    _epic_auth_session_present && auth_status="session present (external tool-managed)"
    printf 'store=epic\n  cli      : %s\n  auth     : %s\n' "$cli_status" "$auth_status"
    return 0
}

_epic_parse_catalog_json() {
    local query="${1:-}"
    jq -r --arg q "$query" '
        (if type == "array" then . else error("invalid") end) as $items |
        ($q | ascii_downcase) as $ql |
        $items[] |
        ((.app_name // "") | tostring) as $id |
        ((.app_title // .title // $id) | tostring) as $title |
        (if (.asset_infos | type) == "object" then
            ([(.asset_infos | keys[] | ascii_downcase |
                if . == "windows" then "windows"
                elif . == "linux" then "linux"
                elif . == "mac" or . == "macos" then "mac"
                else empty end)] | unique | join(","))
         elif (.platforms | type) == "string" then .platforms
         else "windows" end | if length == 0 then "windows" else . end) as $plats |
        if ($id | test("[\\t\\r\\n]")) or ($title | test("[\\t\\r\\n]")) or ($plats | test("[\\t\\r\\n]")) then
            error("TUI catalog contains TAB, CR or newline")
        else
            select(($id | ascii_downcase | contains($ql)) or ($title | ascii_downcase | contains($ql))) |
            [$id, $title, $plats] | @tsv
        end' 2>/dev/null
}

store_epic_search() {
    local query="${1:-}" raw_out="" parsed_rows=""
    [ -n "$query" ] || { echo "[ERROR] Usage: store_epic_search <query>" >&2; return 1; }
    _epic_resolve_cli >/dev/null 2>&1 || { echo "[ERROR] Epic CLI not installed (optional: install legendary)." >&2; return 1; }

    raw_out=$(legendary list --json 2>/dev/null) || { echo "[ERROR] Epic catalog query failed (legendary list --json)." >&2; return 1; }
    local trimmed="${raw_out#"${raw_out%%[![:space:]]*}"}"
    if [ -z "$trimmed" ] || [[ "$trimmed" != "["* ]]; then
        echo "[ERROR] Invalid Epic search catalog JSON." >&2
        return 1
    fi
    parsed_rows=$(printf '%s' "$raw_out" | _epic_parse_catalog_json "$query") || {
        echo "[ERROR] Invalid Epic search catalog JSON." >&2
        return 1
    }
    [ -n "$parsed_rows" ] || { echo "[ERROR] Epic catalog search returned no matches for '$query'." >&2; return 1; }

    declare -A installed_ids=()
    if declare -F scan_installed_games >/dev/null 2>&1; then
        local ins_id
        while IFS=$'\t' read -r ins_id _; do
            ins_id="${ins_id//[[:space:]]/}"
            [ -n "$ins_id" ] && installed_ids["$ins_id"]=1
        done < <(scan_installed_games --store EPIC 2>/dev/null || true)
    fi

    local app_name title platforms row_status
    while IFS=$'\t' read -r app_name title platforms; do
        [ -n "$app_name" ] || continue
        declare -F validate_tui_fields >/dev/null 2>&1 && { validate_tui_fields "$app_name" "$title" "$platforms" || return 1; }
        row_status="AVAILABLE"
        [ -n "${installed_ids["$app_name"]:-}" ] && row_status="INSTALLED"
        printf 'EPIC\t%s\t%s\t%s\t%s\n' "$app_name" "$title" "${platforms:-windows}" "$row_status"
    done <<< "$parsed_rows"
}

store_epic_list_installed() {
    declare -F scan_installed_games >/dev/null 2>&1 || { echo "[ERROR] scan_installed_games is unavailable." >&2; return 1; }
    scan_installed_games --store EPIC "$@"
}

store_epic_download() {
    local app_name="${1:-}"
    if [ -z "$app_name" ] || [[ ! "$app_name" =~ ^[0-9A-Za-z._-]+$ ]] || [[ "$app_name" == *".."* ]]; then
        echo "[ERROR] Usage: store_epic_download <app_name> [target_dir] [options...]" >&2
        return 1
    fi
    _epic_resolve_cli >/dev/null 2>&1 || { echo "[ERROR] Epic CLI not installed (optional: install legendary)." >&2; return 1; }
    local target_dir="${GAMECTL_LIBRARY_DIR:-$HOME/Games}/$app_name"
    if [ -n "${2:-}" ] && [[ "${2:-}" != -* ]]; then target_dir="$2"; shift 2; else shift; fi
    mkdir -p "$target_dir" || return 1
    legendary install "$app_name" --game-folder "$target_dir" -y "$@" || return $?
    declare -F invalidate_scan_cache >/dev/null 2>&1 && invalidate_scan_cache || true
}

store_epic_sync() {
    local app_name="${1:-}" game_dir="${2:-}"
    if [ -z "$app_name" ] || [[ ! "$app_name" =~ ^[0-9A-Za-z._-]+$ ]] || [[ "$app_name" == *".."* ]] || [ -z "$game_dir" ] || [ ! -d "$game_dir" ]; then
        echo "[ERROR] Usage: store_epic_sync <app_name> <existing_game_dir> [options...]" >&2
        return 1
    fi
    shift 2
    _epic_resolve_cli >/dev/null 2>&1 || { echo "[ERROR] Epic CLI not installed (optional: install legendary)." >&2; return 1; }
    declare -F backup_save >/dev/null 2>&1 && { backup_save "$game_dir" true || return $?; }
    legendary sync-saves "$app_name" --save-path "$game_dir/saves" "$@"
}

epic_cli() {
    local action="${1:-status}"
    [ $# -gt 0 ] && shift
    case "$action" in
        status) store_dispatch epic status ;;
        auth)
            _epic_resolve_cli >/dev/null 2>&1 || { echo "[ERROR] Epic auth requires legendary." >&2; return 1; }
            legendary auth "$@" ;;
        search) store_dispatch epic search "$@" ;;
        download) store_dispatch epic download "$@" ;;
        sync) store_dispatch epic sync "$@" ;;
        launch)
            _epic_resolve_cli >/dev/null 2>&1 || { echo "[ERROR] Epic launch requires legendary." >&2; return 1; }
            [ -n "${1:-}" ] || { echo "[ERROR] Usage: gamectl epic launch <app_name> [args...]" >&2; return 1; }
            legendary launch "$@" ;;
        --help|-h|help) echo "Usage: gamectl epic <status|auth|search|download|sync|launch> [args...]" ;;
        *) echo "[ERROR] Unknown epic subcommand '$action'. Usage: gamectl epic <status|auth|search|download|sync|launch> [args...]" >&2; return 1 ;;
    esac
}
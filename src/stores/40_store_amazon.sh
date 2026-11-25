# ==============================================================================
# Optional Amazon Prime Gaming Store Adapter (nile)
# ==============================================================================

_amazon_config_dir() {
    printf '%s\n' "${NILE_CONFIG_PATH:-${XDG_CONFIG_HOME:-$HOME/.config}/nile}"
}

_amazon_resolve_cli() {
    command -v nile >/dev/null 2>&1 && { echo "nile"; return 0; }
    return 1
}

_amazon_auth_session_present() {
    [ -s "$(_amazon_config_dir)/user.json" ]
}

store_amazon_available() { _amazon_resolve_cli >/dev/null 2>&1; }

store_amazon_status() {
    local cli_path="" cli_status="missing (optional: install nile)"
    if _amazon_resolve_cli >/dev/null 2>&1; then
        cli_path="$(command -v nile 2>/dev/null || echo "nile")"
        cli_status="ready (nile: $cli_path)"
    fi
    local auth_status="unconfigured (run 'gamectl amazon auth')"
    _amazon_auth_session_present && auth_status="session present (external tool-managed)"
    printf 'store=amazon\n  cli      : %s\n  auth     : %s\n' "$cli_status" "$auth_status"
    return 0
}

_amazon_parse_catalog_json() {
    local query="${1:-}"
    jq -r --arg q "$query" '
        (if type == "array" then . else error("invalid") end) as $items |
        ($q | ascii_downcase) as $ql |
        $items[] |
        ((.product.id // .id // "") | tostring) as $id |
        ((.product.title // .title // $id) | tostring) as $title |
        (if (.platforms | type) == "string" then .platforms
         elif (.platforms | type) == "array" then ([.platforms[] | tostring | ascii_downcase] | join(","))
         else "windows" end | if length == 0 then "windows" else . end) as $plats |
        if ($id == "") or ($id | test("[\\t\\r\\n]")) or ($title | test("[\\t\\r\\n]")) or ($plats | test("[\\t\\r\\n]")) then
            error("TUI catalog contains TAB, CR or newline")
        else
            select(($id | ascii_downcase | contains($ql)) or ($title | ascii_downcase | contains($ql))) |
            [$id, $title, $plats] | @tsv
        end' 2>/dev/null
}

store_amazon_search() {
    local query="${1:-}" raw_out="" parsed_rows=""
    [ -n "$query" ] || { echo "[ERROR] Usage: store_amazon_search <query>" >&2; return 1; }
    _amazon_resolve_cli >/dev/null 2>&1 || { echo "[ERROR] Amazon CLI not installed (optional: install nile)." >&2; return 1; }

    raw_out=$(nile library list --json 2>/dev/null || nile list-games --json 2>/dev/null || true)
    local trimmed="${raw_out#"${raw_out%%[![:space:]]*}"}"
    if [ -z "$trimmed" ] || [[ "$trimmed" != "["* ]]; then
        echo "[ERROR] Invalid Amazon search catalog JSON." >&2
        return 1
    fi
    parsed_rows=$(printf '%s' "$raw_out" | _amazon_parse_catalog_json "$query") || {
        echo "[ERROR] Invalid Amazon search catalog JSON." >&2
        return 1
    }
    [ -n "$parsed_rows" ] || { echo "[ERROR] Amazon catalog search returned no matches for '$query'." >&2; return 1; }

    declare -A installed_ids=()
    if declare -F scan_installed_games >/dev/null 2>&1; then
        local ins_id
        while IFS=$'\t' read -r ins_id _; do
            ins_id="${ins_id//[[:space:]]/}"
            [ -n "$ins_id" ] && installed_ids["$ins_id"]=1
        done < <(scan_installed_games --store AMAZON 2>/dev/null || true)
    fi

    local app_id title platforms row_status
    while IFS=$'\t' read -r app_id title platforms; do
        [ -n "$app_id" ] || continue
        declare -F validate_tui_fields >/dev/null 2>&1 && { validate_tui_fields "$app_id" "$title" "$platforms" || return 1; }
        row_status="AVAILABLE"
        [ -n "${installed_ids["$app_id"]:-}" ] && row_status="INSTALLED"
        printf 'AMAZON\t%s\t%s\t%s\t%s\n' "$app_id" "$title" "${platforms:-windows}" "$row_status"
    done <<< "$parsed_rows"
}

store_amazon_list_installed() {
    declare -F scan_installed_games >/dev/null 2>&1 || { echo "[ERROR] scan_installed_games is unavailable." >&2; return 1; }
    scan_installed_games --store AMAZON "$@"
}

store_amazon_download() {
    local app_id="${1:-}"
    if [ -z "$app_id" ] || [[ ! "$app_id" =~ ^[0-9A-Za-z._-]+$ ]] || [[ "$app_id" == *".."* ]]; then
        echo "[ERROR] Usage: store_amazon_download <app_id> [target_dir] [options...]" >&2
        return 1
    fi
    _amazon_resolve_cli >/dev/null 2>&1 || { echo "[ERROR] Amazon CLI not installed (optional: install nile)." >&2; return 1; }
    local target_dir="${GAMECTL_LIBRARY_DIR:-$HOME/Games}/$app_id"
    if [ -n "${2:-}" ] && [[ "${2:-}" != -* ]]; then target_dir="$2"; shift 2; else shift; fi
    mkdir -p "$target_dir" || return 1
    nile install "$app_id" --path "$target_dir" "$@" || return $?
    declare -F invalidate_scan_cache >/dev/null 2>&1 && invalidate_scan_cache || true
}

store_amazon_sync() {
    local app_id="${1:-}" game_dir="${2:-}"
    if [ -z "$app_id" ] || [[ ! "$app_id" =~ ^[0-9A-Za-z._-]+$ ]] || [[ "$app_id" == *".."* ]] || [ -z "$game_dir" ] || [ ! -d "$game_dir" ]; then
        echo "[ERROR] Usage: store_amazon_sync <app_id> <existing_game_dir> [options...]" >&2
        return 1
    fi
    shift 2
    _amazon_resolve_cli >/dev/null 2>&1 || { echo "[ERROR] Amazon CLI not installed (optional: install nile)." >&2; return 1; }
    declare -F backup_save >/dev/null 2>&1 && { backup_save "$game_dir" true || return $?; }
    nile verify "$app_id" --path "$game_dir" "$@"
}

amazon_cli() {
    local action="${1:-status}"
    [ $# -gt 0 ] && shift
    case "$action" in
        status) store_dispatch amazon status ;;
        auth)
            _amazon_resolve_cli >/dev/null 2>&1 || { echo "[ERROR] Amazon auth requires nile." >&2; return 1; }
            nile auth "$@" ;;
        search) store_dispatch amazon search "$@" ;;
        download) store_dispatch amazon download "$@" ;;
        sync) store_dispatch amazon sync "$@" ;;
        --help|-h|help) echo "Usage: gamectl amazon <status|auth|search|download|sync> [args...]" ;;
        *) echo "[ERROR] Unknown amazon subcommand '$action'. Usage: gamectl amazon <status|auth|search|download|sync> [args...]" >&2; return 1 ;;
    esac
}

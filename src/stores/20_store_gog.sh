# ==============================================================================
# Optional DRM-Free GOG Store Adapter (gogdl / lgogdownloader)
# ==============================================================================

_gog_resolve_cli() {
    command -v gogdl >/dev/null 2>&1 && { echo "gogdl"; return 0; }
    command -v lgogdownloader >/dev/null 2>&1 && { echo "lgogdownloader"; return 0; }
    return 1
}

_gog_auth_session_present() {
    local xdg_cfg="${XDG_CONFIG_HOME:-$HOME/.config}"
    [ -s "${GAMECTL_GOGDL_AUTH_FILE:-$xdg_cfg/gogdl/auth.json}" ] || [ -s "$xdg_cfg/lgogdownloader/cookies.txt" ]
}

store_gog_available() { _gog_resolve_cli >/dev/null 2>&1; }

store_gog_status() {
    local cli_name="" cli_path="" cli_status="missing (optional: install gogdl or lgogdownloader)"
    cli_name="$(_gog_resolve_cli 2>/dev/null || true)"
    if [ -n "$cli_name" ]; then
        cli_path="$(command -v "$cli_name" 2>/dev/null || echo "$cli_name")"
        cli_status="ready ($cli_name: $cli_path)"
    fi
    local auth_status="unconfigured (run 'gamectl gog auth')"
    _gog_auth_session_present && auth_status="session present (external tool-managed)"
    printf 'store=gog\n  cli      : %s\n  auth     : %s\n' "$cli_status" "$auth_status"
    return 0
}

_gog_parse_catalog_json() {
    jq -r '
        (if type == "array" then . elif (.products | type) == "array" then .products else error("invalid") end) as $items |
        if any($items[]?; ((.id // "") | tostring | test("[\\t\\r\\n]")) or ((.title // .name // "") | tostring | test("[\\t\\r\\n]"))) then
            error("TUI catalog contains TAB, CR or newline")
        else
            $items[] | [
                ((.id // "") | tostring), ((.title // .name // "") | tostring),
                (if (.platforms | type) == "string" then .platforms else
                    ([ (if (.worksOn.Linux // .worksOn.linux // false) then "linux" else empty end),
                       (if (.worksOn.Windows // .worksOn.windows // false) then "windows" else empty end),
                       (if (.worksOn.Mac // .worksOn.mac // false) then "mac" else empty end)
                     ] | join(",") | if length == 0 then "unknown" else . end)
                end)
            ] | @tsv
        end' 2>/dev/null
}

store_gog_search() {
    local query="${1:-}" cli_name="" raw_out="" parsed_rows=""
    [ -n "$query" ] || { echo "[ERROR] Usage: store_gog_search <query>" >&2; return 1; }
    cli_name="$(_gog_resolve_cli 2>/dev/null || true)"
    [ -n "$cli_name" ] || { echo "[ERROR] GOG CLI not installed (optional: install gogdl or lgogdownloader)." >&2; return 1; }

    if [ "$cli_name" = "gogdl" ]; then
        raw_out=$(gogdl search "$query" 2>/dev/null || true)
    else
        raw_out=$(lgogdownloader --list-details --game "$query" 2>/dev/null || true)
    fi

    local trimmed_out="${raw_out#"${raw_out%%[![:space:]]*}"}"
    if [ -n "$trimmed_out" ] && { [[ "$trimmed_out" == "{"* ]] || [[ "$trimmed_out" == "["* ]]; }; then
        parsed_rows=$(printf '%s' "$raw_out" | _gog_parse_catalog_json) || { echo "[ERROR] Invalid GOG search catalog." >&2; return 1; }
    elif [ -n "$raw_out" ] && [[ "$raw_out" == *$'\t'* ]]; then
        parsed_rows="$raw_out"
    elif command -v curl >/dev/null 2>&1 && command -v jq >/dev/null 2>&1; then
        local enc_q api_raw
        enc_q=$(python3 -c "import urllib.parse, sys; print(urllib.parse.quote(sys.argv[1]))" "$query")
        api_raw=$(curl -fsS --connect-timeout 5 --max-time 15 "https://embed.gog.com/games/ajax/filtered?mediaType=game&search=${enc_q}" 2>/dev/null || true)
        [ -n "$api_raw" ] && { parsed_rows=$(printf '%s' "$api_raw" | _gog_parse_catalog_json) || { echo "[ERROR] Invalid GOG search catalog." >&2; return 1; }; }
    fi
    [ -n "$parsed_rows" ] || { echo "[ERROR] GOG catalog search failed or returned no results." >&2; return 1; }

    declare -A installed_ids=()
    if declare -F scan_installed_games >/dev/null 2>&1; then
        local ins_id
        while IFS=$'\t' read -r ins_id _; do
            ins_id="${ins_id//[[:space:]]/}"
            [ -n "$ins_id" ] && installed_ids["$ins_id"]=1
        done < <(scan_installed_games --store GOG 2>/dev/null || true)
    fi

    local prod_id title platforms row_status
    while IFS=$'\t' read -r prod_id title platforms; do
        [ -n "$prod_id" ] || continue
        declare -F validate_tui_fields >/dev/null 2>&1 && { validate_tui_fields "$prod_id" "$title" "$platforms" || return 1; }
        row_status="AVAILABLE"
        [ -n "${installed_ids["$prod_id"]:-}" ] && row_status="INSTALLED"
        printf 'GOG\t%s\t%s\t%s\t%s\n' "$prod_id" "$title" "${platforms:-unknown}" "$row_status"
    done <<< "$parsed_rows"
}

store_gog_list_installed() {
    declare -F scan_installed_games >/dev/null 2>&1 || { echo "[ERROR] scan_installed_games is unavailable." >&2; return 1; }
    scan_installed_games --store GOG "$@"
}

store_gog_download() {
    local product_id="${1:-}" cli_name=""
    if [ -z "$product_id" ] || [[ ! "$product_id" =~ ^[0-9A-Za-z_-]+$ ]]; then
        echo "[ERROR] Usage: store_gog_download <product_id> [target_dir] [options...]" >&2
        return 1
    fi
    cli_name="$(_gog_resolve_cli 2>/dev/null || true)"
    [ -n "$cli_name" ] || { echo "[ERROR] GOG CLI not installed (optional: install gogdl or lgogdownloader)." >&2; return 1; }
    local target_dir="${GAMECTL_LIBRARY_DIR:-$HOME/GOG Games}/gog_${product_id}"
    if [ -n "${2:-}" ] && [[ "${2:-}" != -* ]]; then target_dir="$2"; shift 2; else shift; fi
    mkdir -p "$target_dir" || return 1
    if [ "$cli_name" = "gogdl" ]; then
        gogdl download "$product_id" --path "$target_dir" "$@" || return $?
    else
        lgogdownloader --download --game "$product_id" --directory "$target_dir" "$@" || return $?
    fi
    declare -F invalidate_scan_cache >/dev/null 2>&1 && invalidate_scan_cache || true
}

store_gog_sync() {
    local product_id="${1:-}" game_dir="${2:-}"
    if [ -z "$product_id" ] || [ -z "$game_dir" ] || [ ! -d "$game_dir" ]; then
        echo "[ERROR] Usage: store_gog_sync <product_id> <existing_game_dir> [options...]" >&2
        return 1
    fi
    shift 2
    command -v gogdl >/dev/null 2>&1 || { echo "[ERROR] GOG cloud save sync requires gogdl." >&2; return 1; }
    declare -F backup_save >/dev/null 2>&1 && { backup_save "$game_dir" true || return $?; }
    gogdl save-sync "$game_dir" "$product_id" "$@"
}

gog_cli() {
    local action="${1:-status}" cli_name=""
    [ $# -gt 0 ] && shift
    case "$action" in
        status) store_dispatch gog status ;;
        auth)
            cli_name="$(_gog_resolve_cli 2>/dev/null || true)"
            if [ "$cli_name" = "gogdl" ]; then gogdl auth "$@"
            elif [ "$cli_name" = "lgogdownloader" ]; then lgogdownloader --login "$@"
            else echo "[ERROR] GOG auth requires gogdl or lgogdownloader." >&2; return 1; fi ;;
        search) store_dispatch gog search "$@" ;;
        download) store_dispatch gog download "$@" ;;
        sync) store_dispatch gog sync "$@" ;;
        --help|-h|help) echo "Usage: gamectl gog <status|auth|search|download|sync> [args...]" ;;
        *) echo "[ERROR] Unknown gog subcommand '$action'. Usage: gamectl gog <status|auth|search|download|sync> [args...]" >&2; return 1 ;;
    esac
}

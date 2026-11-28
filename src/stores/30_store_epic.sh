# ==============================================================================
# Optional Epic Games Store Adapter (legendary)
# ==============================================================================

_epic_config_dir() {
    printf '%s\n' "${LEGENDARY_CONFIG_PATH:-${XDG_CONFIG_HOME:-$HOME/.config}/legendary}"
}

resolve_gamectl_core_bin() {
    if [ -n "${GAMECTL_CORE_BIN:-}" ] && [ -x "$GAMECTL_CORE_BIN" ]; then
        echo "$GAMECTL_CORE_BIN"
        return 0
    fi
    if command -v gamectl-core >/dev/null 2>&1; then
        command -v gamectl-core
        return 0
    fi
    local candidate
    for candidate in \
        "$HOME/.local/bin/gamectl-core" \
        "/usr/local/bin/gamectl-core" \
        "/usr/bin/gamectl-core"; do
        if [ -x "$candidate" ]; then
            echo "$candidate"
            return 0
        fi
    done
    if [ "${GAMECTL_BUNDLED:-0}" = "1" ] || [ "${GAMECTL_CORE_ALLOW_REPO_BIN:-0}" = "1" ]; then
        local self_dir=""
        [ -n "${SELF_BIN:-}" ] && self_dir="$(dirname "$SELF_BIN")"
        for candidate in \
            "${self_dir:+$self_dir/gamectl-core}" \
            "${self_dir:+$self_dir/../bin/gamectl-core}"; do
            if [ -n "$candidate" ] && [ -x "$candidate" ]; then
                echo "$candidate"
                return 0
            fi
        done
    fi
    return 1
}

_epic_resolve_cli() {
    if [ "${GAMECTL_EPIC_ENGINE:-auto}" = "core" ]; then
        resolve_gamectl_core_bin >/dev/null 2>&1 && { echo "gamectl-core"; return 0; }
        return 1
    fi
    command -v legendary >/dev/null 2>&1 && { echo "legendary"; return 0; }
    resolve_gamectl_core_bin >/dev/null 2>&1 && { echo "gamectl-core"; return 0; }
    return 1
}

_epic_auth_session_present() {
    local native_auth="${GAMECTL_EPIC_AUTH_FILE:-${XDG_CONFIG_HOME:-$HOME/.config}/gamectl/epic_auth.json}"
    [ -s "$native_auth" ] || [ -s "$(_epic_config_dir)/user.json" ]
}

store_epic_available() { _epic_resolve_cli >/dev/null 2>&1; }

store_epic_status() {
    local cli_name="" cli_path="" cli_status="missing (optional: build gamectl-core or install legendary)"
    cli_name="$(_epic_resolve_cli 2>/dev/null || true)"
    if [ "$cli_name" = "legendary" ]; then
        cli_path="$(command -v legendary 2>/dev/null || echo "legendary")"
        cli_status="ready (legendary: $cli_path)"
    elif [ "$cli_name" = "gamectl-core" ]; then
        cli_path="$(resolve_gamectl_core_bin 2>/dev/null || echo "gamectl-core")"
        cli_status="ready (gamectl-core: $cli_path)"
    fi
    local auth_status="unconfigured (run 'gamectl epic auth')"
    if [ "$cli_name" = "gamectl-core" ] && [ -x "$cli_path" ]; then
        auth_status="$("$cli_path" epic status 2>/dev/null || echo "$auth_status")"
    elif _epic_auth_session_present; then
        auth_status="session present (external tool-managed)"
    fi
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
    local query="${1:-}" cli_name="" raw_out="" parsed_rows=""
    [ -n "$query" ] || { echo "[ERROR] Usage: store_epic_search <query>" >&2; return 1; }
    cli_name="$(_epic_resolve_cli 2>/dev/null || true)"
    [ -n "$cli_name" ] || { echo "[ERROR] Epic engine not available (build gamectl-core or install legendary)." >&2; return 1; }

    if [ "$cli_name" = "gamectl-core" ]; then
        local core_bin
        core_bin="$(resolve_gamectl_core_bin)"
        raw_out=$("$core_bin" epic list --json 2>/dev/null) || { echo "[ERROR] Epic catalog query failed (gamectl-core epic list --json)." >&2; return 1; }
    else
        raw_out=$(legendary list --json 2>/dev/null) || { echo "[ERROR] Epic catalog query failed (legendary list --json)." >&2; return 1; }
    fi
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
    local app_name="${1:-}" cli_name=""
    if [ -z "$app_name" ] || [[ ! "$app_name" =~ ^[0-9A-Za-z._-]+$ ]] || [[ "$app_name" == *".."* ]]; then
        echo "[ERROR] Usage: store_epic_download <app_name> [target_dir] [options...]" >&2
        return 1
    fi
    cli_name="$(_epic_resolve_cli 2>/dev/null || true)"
    [ -n "$cli_name" ] || { echo "[ERROR] Epic engine not available (build gamectl-core or install legendary)." >&2; return 1; }
    local target_dir="${GAMECTL_LIBRARY_DIR:-$HOME/Games}/$app_name"
    if [ -n "${2:-}" ] && [[ "${2:-}" != -* ]]; then target_dir="$2"; shift 2; else shift; fi
    mkdir -p "$target_dir" || return 1
    if [ "$cli_name" = "gamectl-core" ]; then
        local core_bin
        core_bin="$(resolve_gamectl_core_bin)"
        "$core_bin" epic install "$app_name" --dir "$target_dir" "$@" || return $?
    else
        legendary install "$app_name" --game-folder "$target_dir" -y "$@" || return $?
    fi
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
    local action="${1:-status}" cli_name=""
    [ $# -gt 0 ] && shift
    cli_name="$(_epic_resolve_cli 2>/dev/null || true)"
    case "$action" in
        status) store_dispatch epic status ;;
        auth)
            if [ "$cli_name" = "gamectl-core" ]; then
                "$(resolve_gamectl_core_bin)" epic auth "$@"
            elif [ "$cli_name" = "legendary" ]; then
                legendary auth "$@"
            else
                echo "[ERROR] Epic auth requires gamectl-core or legendary." >&2; return 1
            fi ;;
        search) store_dispatch epic search "$@" ;;
        download) store_dispatch epic download "$@" ;;
        sync) store_dispatch epic sync "$@" ;;
        launch)
            if [ "$cli_name" = "legendary" ]; then
                [ -n "${1:-}" ] || { echo "[ERROR] Usage: gamectl epic launch <app_name> [args...]" >&2; return 1; }
                legendary launch "$@"
            elif [ "$cli_name" = "gamectl-core" ]; then
                local app_arg="${1:-}" row_id row_title _row_st row_dir row_bin _rest
                [ -n "$app_arg" ] || { echo "[ERROR] Usage: gamectl epic launch <app_name>" >&2; return 1; }
                while IFS=$'\t' read -r row_id row_title _row_st row_dir row_bin _rest; do
                    row_id="${row_id//[[:space:]]/}"
                    if [ "$row_id" = "$app_arg" ] && [ -d "$row_dir" ]; then
                        launch_game "$row_dir" "$row_bin" "$row_title"
                        return $?
                    fi
                done < <(scan_installed_games --store EPIC 2>/dev/null || true)
                echo "[ERROR] Epic game '$app_arg' is not installed locally." >&2
                return 1
            else
                echo "[ERROR] Epic launch requires gamectl-core or legendary." >&2; return 1
            fi ;;
        --help|-h|help) echo "Usage: gamectl epic <status|auth|search|download|sync|launch> [args...]" ;;
        *) echo "[ERROR] Unknown epic subcommand '$action'. Usage: gamectl epic <status|auth|search|download|sync|launch> [args...]" >&2; return 1 ;;
    esac
}

# Cached Epic metadata helper via legendary info --json (dl_bytes\x1fdisk_bytes\x1fdev\x1fdlc_count\x1fversion\x1f1)
fetch_epic_app_metadata() {
    local app_name="${1:-}"
    if [ -z "$app_name" ] || [[ ! "$app_name" =~ ^[0-9A-Za-z._-]+$ ]] || [[ "$app_name" == *".."* ]]; then
        return 1
    fi

    local cache_dir="${XDG_CACHE_HOME:-$HOME/.cache}/gamectl"
    local safe_key
    safe_key=$(printf '%s' "$app_name" | tr -cd '[:alnum:]_-')
    local cache_file="$cache_dir/epic_info_${safe_key}.json"
    local raw_json="" now mtime age

    now=$(date +%s)
    if [ -s "$cache_file" ]; then
        mtime=$(stat -c %Y "$cache_file" 2>/dev/null || stat -f %m "$cache_file" 2>/dev/null || echo 0)
        age=$(( now - mtime ))
        if [ "$age" -ge 0 ] && [ "$age" -lt 3600 ]; then
            raw_json=$(cat "$cache_file" 2>/dev/null || true)
        fi
    fi

    if [ -z "$raw_json" ]; then
        local cli_name fetched tmp_file="${cache_file}.tmp.$$"
        cli_name="$(_epic_resolve_cli 2>/dev/null || true)"
        if [ "$cli_name" = "gamectl-core" ]; then
            fetched=$("$(resolve_gamectl_core_bin)" epic info "$app_name" --json 2>/dev/null || true)
        elif [ "$cli_name" = "legendary" ]; then
            fetched=$(legendary info "$app_name" --json 2>/dev/null || true)
        fi
        if [ -n "${fetched:-}" ] && [ "$fetched" != "null" ] && printf '%s' "$fetched" | jq . >/dev/null 2>&1; then
            mkdir -p "$cache_dir" 2>/dev/null || true
            printf '%s\n' "$fetched" > "$tmp_file" 2>/dev/null && mv -f "$tmp_file" "$cache_file" 2>/dev/null || rm -f "$tmp_file" 2>/dev/null
            raw_json="$fetched"
        fi
        rm -f "$tmp_file" 2>/dev/null || true
    fi

    if [ -z "$raw_json" ] && [ -s "$cache_file" ]; then
        raw_json=$(cat "$cache_file" 2>/dev/null || true)
    fi
    [ -n "$raw_json" ] && [ "$raw_json" != "null" ] || return 1

    printf '%s' "$raw_json" | jq -r '
        select(type == "object") |
        (.manifest.download_size // .download_size // 0 | tonumber? // 0 | floor | tostring) as $dl |
        (.manifest.disk_size // .install_size // 0 | tonumber? // 0 | floor | tostring) as $disk |
        ((.game.developer // .metadata.developer // "") | tostring | gsub("[\\t\\r\\n]+"; " ")) as $dev |
        (if (.game.dlc_list | type) == "array" then (.game.dlc_list | length | tostring) else "0" end) as $dlc |
        ((.manifest.version // .game.app_version // "") | tostring | gsub("[\\t\\r\\n]+"; " ")) as $ver |
        [$dl, $disk, $dev, $dlc, $ver, "1"] | join("\u001f")
    ' 2>/dev/null
}
# ==============================================================================
# Steam Catalog App-Type Canonical SSoT, Batch Classifier & Details Parser
# ==============================================================================

# Normalize Steam app type values (IStoreBrowseService integer enum or appdetails string)
# into closed 7-token canonical vocabulary: GAME, DLC, DEMO, MOD, SOUNDTRACK, TOOL, APP.
normalize_steam_app_type() {
    local raw="${1:-}"
    raw="${raw,,}"
    raw="${raw//[[:space:]]/}"
    case "$raw" in
        0|game)
            printf 'GAME\n'
            ;;
        4|dlc)
            printf 'DLC\n'
            ;;
        1|demo)
            printf 'DEMO\n'
            ;;
        2|mod)
            printf 'MOD\n'
            ;;
        11|music|soundtrack|ost)
            printf 'SOUNDTRACK\n'
            ;;
        3|10|tool|application|software)
            printf 'TOOL\n'
            ;;
        *)
            printf 'APP\n'
            ;;
    esac
}

# Render standardized ANSI badge from canonical Steam app type token.
format_app_type_badge() {
    local norm_type
    norm_type="$(normalize_steam_app_type "${1:-APP}")"
    case "$norm_type" in
        GAME)       printf '%s\n' "${UI_GREEN:-}[GAME]${UI_RST:-}" ;;
        DLC)        printf '%s\n' "${UI_AMBER:-}[DLC]${UI_RST:-}" ;;
        DEMO)       printf '%s\n' "${UI_CYAN:-}[DEMO]${UI_RST:-}" ;;
        MOD)        printf '%s\n' "${UI_PURPLE:-}[MOD]${UI_RST:-}" ;;
        SOUNDTRACK) printf '%s\n' "${UI_ICE:-}[OST]${UI_RST:-}" ;;
        TOOL)       printf '%s\n' "${UI_DIM:-}[TOOL]${UI_RST:-}" ;;
        *)          printf '%s\n' "${UI_DIM:-}[APP]${UI_RST:-}" ;;
    esac
}

# Batch-classify Steam AppIDs via IStoreBrowseService/GetItems/v1 (single HTTP call).
# Emits sanitized TSV rows: <APPID><TAB><TYPE><TAB><PARENT_APPID> (offline fallback: APP).
classify_steam_app_types() {
    local -a unique_ids=()
    declare -A seen_ids=()
    local arg
    for arg in "$@"; do
        arg="${arg//[[:space:]]/}"
        [[ "$arg" =~ ^[0-9]+$ ]] || continue
        [[ -v seen_ids["$arg"] ]] && continue
        seen_ids["$arg"]=1
        unique_ids+=("$arg")
    done

    [ "${#unique_ids[@]}" -eq 0 ] && return 0

    declare -A type_map=()
    declare -A parent_map=()

    local ids_json req_json resp parsed_rows
    ids_json=$(printf '%s\n' "${unique_ids[@]}" | jq -Rc '{appid: tonumber}' | jq -sc '.') || ids_json=""
    if [ -n "$ids_json" ] && [ "$ids_json" != "[]" ]; then
        req_json=$(jq -nc --argjson ids "$ids_json" \
            '{ids:$ids, context:{language:"english",country_code:"US"}, data_request:{include_basic_info:true}}')
        resp=$(curl -s --connect-timeout 5 --max-time 10 --get \
            --data-urlencode "input_json=${req_json}" \
            "https://api.steampowered.com/IStoreBrowseService/GetItems/v1/" 2>/dev/null || true)

        if [ -n "$resp" ]; then
            parsed_rows=$(printf '%s' "$resp" | jq -r '
                .response.store_items[]? |
                [
                    (.appid // "-" | tostring),
                    ((.type // "-") | tostring | if length == 0 then "-" else . end),
                    ((.related_items.parent_appid // "-") | tostring | if length == 0 then "-" else . end)
                ] |
                if any(.[]; test("[\\t\\r\\n]")) then empty else @tsv end
            ' 2>/dev/null || true)

            local r_id r_raw_type r_parent
            while IFS=$'\t' read -r r_id r_raw_type r_parent; do
                [[ "$r_id" =~ ^[0-9]+$ ]] || continue
                [ "$r_raw_type" = "-" ] && r_raw_type=""
                [ "$r_parent" = "-" ] && r_parent=""
                type_map["$r_id"]="$(normalize_steam_app_type "$r_raw_type")"
                if [[ "$r_parent" =~ ^[0-9]+$ ]]; then
                    parent_map["$r_id"]="$r_parent"
                else
                    parent_map["$r_id"]=""
                fi
            done <<< "$parsed_rows"
        fi
    fi

    local id out_type out_parent
    for id in "${unique_ids[@]}"; do
        out_type="${type_map[$id]:-APP}"
        out_parent="${parent_map[$id]:-}"
        if declare -F validate_tui_fields >/dev/null 2>&1; then
            validate_tui_fields "$id" "$out_type" "$out_parent" 2>/dev/null || {
                out_type="APP"
                out_parent=""
            }
        elif [[ "$id$out_type$out_parent" == *[$'\t\r\n']* ]]; then
            out_type="APP"
            out_parent=""
        fi
        printf '%s\t%s\t%s\n' "$id" "$out_type" "$out_parent"
    done
    return 0
}

# Fetch and unwrap Steam appdetails data object using canonical cache key steam_details_<appid>.
fetch_steam_app_details() {
    local appid="${1:-}"
    appid="${appid//[[:space:]]/}"
    [[ "$appid" =~ ^[0-9]+$ ]] || return 1

    local raw_json details
    raw_json=$(fetch_cached_json \
        "https://store.steampowered.com/api/appdetails?appids=${appid}&filters=basic,platforms,genres" \
        "steam_details_${appid}" 3600 2>/dev/null || true)
    [ -n "$raw_json" ] || return 1

    details=$(printf '%s' "$raw_json" | jq -ce --arg id "$appid" \
        'if type == "object" and (.[$id] | type == "object") and (.[$id].data | type == "object") then .[$id].data else empty end' \
        2>/dev/null || true)
    [ -n "$details" ] || return 1

    printf '%s\n' "$details"
    return 0
}

# Parse Steam appdetails data JSON into validated 4-column TSV:
# <HAS_TYPE><TAB><TYPE><TAB><PARENT_APPID><TAB><PARENT_NAME>
parse_steam_app_type_json() {
    local details="${1:-}"
    if [ -z "$details" ] || [ "$details" = "null" ]; then
        printf '0\tAPP\t\t\n'
        return 0
    fi

    local parsed raw_type="" parent_id="" parent_name=""
    parsed=$(printf '%s' "$details" | jq -r '
        [
            (.type // "-" | tostring | gsub("[\\t\\r\\n]"; "") | if length == 0 then "-" else . end),
            (.fullgame.appid // "-" | tostring | gsub("[^0-9]"; "") | if length == 0 then "-" else . end),
            (.fullgame.name // "" | tostring | gsub("[\\t\\r\\n]"; " "))
        ] | @tsv
    ' 2>/dev/null || true)
    if [ -z "$parsed" ]; then
        printf '0\tAPP\t\t\n'
        return 0
    fi

    IFS=$'\t' read -r raw_type parent_id parent_name <<< "$parsed"
    local has_type="1"
    if [ -z "$raw_type" ] || [ "$raw_type" = "-" ]; then
        raw_type=""
        has_type="0"
    fi
    [ "$parent_id" = "-" ] && parent_id=""

    local norm_type
    norm_type="$(normalize_steam_app_type "$raw_type")"
    if ! [[ "$parent_id" =~ ^[0-9]+$ ]]; then
        parent_id=""
        parent_name=""
    fi

    if declare -F validate_tui_fields >/dev/null 2>&1; then
        validate_tui_fields "$has_type" "$norm_type" "$parent_id" "$parent_name" 2>/dev/null || {
            has_type="0"
            norm_type="APP"
            parent_id=""
            parent_name=""
        }
    fi

    printf '%s\t%s\t%s\t%s\n' "$has_type" "$norm_type" "$parent_id" "$parent_name"
    return 0
}

# Resolve canonical type and parent base game metadata for a single AppID.
# Emits sanitized TSV: <TYPE><TAB><PARENT_APPID><TAB><PARENT_NAME>
resolve_steam_app_type() {
    local appid="${1:-}"
    appid="${appid//[[:space:]]/}"
    if ! [[ "$appid" =~ ^[0-9]+$ ]]; then
        printf 'APP\t\t\n'
        return 0
    fi

    local details
    details=$(fetch_steam_app_details "$appid" 2>/dev/null || true)
    if [ -z "$details" ]; then
        printf 'APP\t\t\n'
        return 0
    fi

    local parsed has_type="" norm_type="APP" parent_id="" parent_name=""
    parsed=$(parse_steam_app_type_json "$details")
    IFS=$'\t' read -r has_type norm_type parent_id parent_name <<< "$parsed"
    if ! [[ "$parent_id" =~ ^[0-9]+$ ]]; then
        parent_id=""
        parent_name=""
    fi
    printf '%s\t%s\t%s\n' "${norm_type:-APP}" "$parent_id" "$parent_name"
    return 0
}


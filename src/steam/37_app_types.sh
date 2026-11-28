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
        "https://store.steampowered.com/api/appdetails?appids=${appid}&filters=basic,platforms,genres,release_date,developers,publishers,price_overview,metacritic,recommendations,categories" \
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

# Parse extended Steam appdetails data JSON into an 18-field \x1f-delimited metadata row
# (plus trailing sentinel "1"):
# storage_linux, storage_win, storage_mac, release_str, price_str, devs, pubs,
# dlc_count, controller, metacritic, recs, short_desc, has_req_obj,
# drm_warn, min_specs, modes, cat_ctrl, st_req_bytes, sentinel
parse_steam_app_metadata_json() {
    local details="${1:-}"
    if [ -z "$details" ] || [ "$details" = "null" ]; then
        return 1
    fi

    printf '%s' "$details" | jq -r '
        def clean_txt:
            tostring
            | gsub("<br\\s*/?>"; " ")
            | gsub("<[^>]+>"; " ")
            | gsub("&amp;"; "&")
            | gsub("&quot;"; "\"")
            | gsub("&#39;"; "'"'"'")
            | gsub("&lt;"; "<")
            | gsub("&gt;"; ">")
            | gsub("&nbsp;"; " ")
            | gsub("[\\t\\r\\n]+"; " ")
            | gsub("  +"; " ")
            | sub("^ +"; "")
            | sub(" +$"; "");
        def first_cap($txt; $re):
            try ([$txt | match($re; "i") | .captures[0].string] | .[0] // "") catch "";
        def extract_storage($req):
            if ($req | type) == "object" then
                ([$req.minimum, $req.recommended] | map(select(. != null and . != "") | clean_txt) | join(" ")) as $t |
                first_cap($t; "(?:storage|hard\\s*drive|disk\\s*space|hard\\s*disk(?:\\s*space)?)[^0-9]{0,30}([0-9]+(?:[.,][0-9]+)?\\s*(?:TB|GB|MB|KB))")
            else "" end;
        (extract_storage(.linux_requirements)) as $st_lin |
        (extract_storage(.pc_requirements)) as $st_win |
        (extract_storage(.mac_requirements)) as $st_mac |
        (if (.release_date | type) == "object" then
            ((.release_date.date // "") | clean_txt) as $d |
            if (.release_date.coming_soon // false) == true then
                "Coming Soon" + (if $d != "" then " (" + $d + ")" else "" end)
            else $d end
         else "" end) as $rel |
        (if (.is_free // false) == true then "Free"
         elif (.price_overview | type) == "object" then
            ((.price_overview.final_formatted // "") | clean_txt) as $fin |
            ((.price_overview.initial_formatted // "") | clean_txt) as $init |
            (.price_overview.discount_percent // 0) as $disc |
            if ($disc | tonumber? // 0) > 0 and $fin != "" then
                $fin + " (-" + ($disc | tostring) + "%" + (if $init != "" then " from " + $init else "" end) + ")"
            else $fin end
         else "" end) as $price |
        (if (.developers | type) == "array" then ([.developers[]? | clean_txt | select(. != "")] | join(", ")) else "" end) as $devs |
        (if (.publishers | type) == "array" then ([.publishers[]? | clean_txt | select(. != "")] | join(", ")) else "" end) as $pubs |
        (if (.dlc | type) == "array" then (.dlc | length | tostring) else "0" end) as $dlc_cnt |
        ((.controller_support // "") | clean_txt) as $ctrl |
        (if (.metacritic | type) == "object" and (.metacritic.score != null) then (.metacritic.score | tostring) else "" end) as $meta |
        (if (.recommendations | type) == "object" and (.recommendations.total != null) then (.recommendations.total | tostring) else "" end) as $recs |
        ((.short_description // "") | clean_txt | if length > 180 then .[0:177] + "..." else . end) as $desc |
        (if ((.pc_requirements != null) or (.linux_requirements != null) or (.mac_requirements != null)) then "1" else "0" end) as $has_req |
        ([(.drm_notice // ""), (.ext_user_account_notice // "")] | map(select(. != null and . != "") | clean_txt | select(. != "")) | unique | join(" • ") | if length > 110 then .[0:107] + "..." else . end) as $drm_warn |
        ((if (.linux_requirements | type) == "object" then (.linux_requirements.minimum // "" | clean_txt) else "" end) as $lin_min |
         (if (.pc_requirements | type) == "object" then (.pc_requirements.minimum // "" | clean_txt) else "" end) as $pc_min |
         (if ($lin_min | test("(?:memory|ram|graphics|video)"; "i")) then $lin_min else $pc_min end) as $min_txt |
         (first_cap($min_txt; "(?:memory|ram)[^0-9]{0,20}([0-9]+(?:[.,][0-9]+)?\\s*(?:GB|MB)(?:\\s*RAM)?)") | clean_txt | if . != "" and (test("RAM$"; "i") | not) then . + " RAM" else . end) as $ram |
         (first_cap($min_txt; "(?:graphics|video\\s*card)[^:]{0,12}:\\s*([^;\\n]{3,65})") | sub("\\s*(?:DirectX|Storage|Hard\\s*Disk|Sound|Network|Additional|OS:|Processor:|Memory:).*$"; ""; "i") | clean_txt | if length > 42 then .[0:39] + "..." else . end) as $gpu |
         ([(.linux_requirements.minimum? // ""), (.linux_requirements.recommended? // ""), (.pc_requirements.minimum? // ""), (.pc_requirements.recommended? // "")] | map(select(. != null) | clean_txt) | join(" ")) as $all_req |
         (if ($all_req | test("SSD[^.,;]{0,20}(?:required|mandatory)|requires?[^.,;]{0,15}SSD"; "i")) then "SSD Req"
          elif ($all_req | test("\\bSSD\\b"; "i")) then "SSD"
          else "" end) as $ssd |
         [$ram, $gpu, $ssd] | map(select(. != "")) | join(" • ")) as $min_specs |
        (if (.categories | type) == "array" then
            (reduce (.categories[]?.description // empty | clean_txt) as $c ([];
                if ($c == "Single-player" or $c == "Multi-player" or $c == "Co-op" or $c == "Online Co-op" or $c == "LAN Co-op" or $c == "Shared/Split Screen Co-op" or $c == "PvP" or $c == "Online PvP" or $c == "LAN PvP" or $c == "Cross-Platform Multiplayer") and (index($c) == null) then
                    . + [$c]
                else . end) | .[0:4] | join(", "))
         else "" end) as $modes |
        (if (.categories | type) == "array" then
            if any(.categories[]?; (.description // "") == "Full controller support") then "full"
            elif any(.categories[]?; (.description // "") == "Partial Controller Support") then "partial"
            else "" end
         else "" end) as $cat_ctrl |
        ((if $st_lin != "" then $st_lin elif $st_win != "" then $st_win else $st_mac end) as $st_prim |
         (try ([$st_prim | match("([0-9]+(?:[.,][0-9]+)?)\\s*(TB|GB|MB|KB)"; "i") | .captures] | .[0]) catch null) as $m |
         if $m != null then
            ($m[0].string | gsub(","; ".") | tonumber? // 0) as $num |
            ($m[1].string | ascii_upcase) as $unit |
            (($num * (if $unit == "TB" then 1099511627776 elif $unit == "GB" then 1073741824 elif $unit == "MB" then 1048576 else 1024 end)) | floor | tostring)
         else "" end) as $st_req_bytes |
        [$st_lin, $st_win, $st_mac, $rel, $price, $devs, $pubs, $dlc_cnt, $ctrl, $meta, $recs, $desc, $has_req, $drm_warn, $min_specs, $modes, $cat_ctrl, $st_req_bytes, "1"] | join("\u001f")
    ' 2>/dev/null
}

# Fetch cached SteamOS / Steam Deck compatibility summary (<CAT_LABEL>\t<NOTE>).
fetch_steam_deck_compat() {
    local appid="${1:-}"
    appid="${appid//[[:space:]]/}"
    [[ "$appid" =~ ^[0-9]+$ ]] || return 1

    local raw_json
    raw_json=$(fetch_cached_json \
        "https://store.steampowered.com/saleaction/ajaxgetdeckappcompatibilityreport?nAppID=${appid}" \
        "steam_deck_${appid}" 86400 2>/dev/null || true)
    [ -n "$raw_json" ] && [ "$raw_json" != "null" ] || return 1

    local out cat_label="" note=""
    out=$(printf '%s' "$raw_json" | jq -r '
        select((.success // 0) == 1 and (.results | type) == "object") |
        (.results.steamos_resolved_category // .results.resolved_category // 0) as $cat |
        (if $cat == 3 then "VERIFIED"
         elif $cat == 2 then "PLAYABLE"
         elif $cat == 1 then "UNSUPPORTED"
         else empty end) as $lbl |
        ([(.results.steamos_resolved_items // .results.resolved_items // [])[]?.loc_token // "" |
          if test("UnsupportedAntiCheat"; "i") then "Unsupported Anti-Cheat"
          elif test("UnsupportedGraphics"; "i") then "Unsupported Graphics/API"
          elif test("Launcher"; "i") then "3rd-Party Launcher"
          elif test("UnsupportedByDeveloper"; "i") then "Unsupported by Developer"
          elif test("VR"; "i") then "VR Required"
          else empty end] | unique | .[0:2] | join(", ")) as $note |
        [$lbl, $note] | @tsv
    ' 2>/dev/null || true)
    [ -n "$out" ] || return 1

    IFS=$'\t' read -r cat_label note <<< "$out"
    if declare -F validate_tui_fields >/dev/null 2>&1; then
        validate_tui_fields "$cat_label" "$note" 2>/dev/null || return 1
    fi
    printf '%s\t%s\n' "$cat_label" "$note"
    return 0
}

# Check local free disk space for target library path (<FREE_HUMAN>\t<IS_LOW>).
get_library_disk_free_info() {
    local req_bytes="${1:-0}"
    local base_dir=""
    if declare -F resolve_standalone_library_dir >/dev/null 2>&1; then
        base_dir=$(resolve_standalone_library_dir "" 2>/dev/null || true)
    fi
    [ -n "$base_dir" ] || base_dir="${GAMECTL_LIBRARY_DIR:-$HOME/Games}"

    local probe="$base_dir"
    while [ ! -e "$probe" ] && [ "$probe" != "/" ] && [ -n "$probe" ]; do
        probe=$(dirname "$probe")
    done
    [ -e "$probe" ] || probe="/"

    local free_bytes
    free_bytes=$(df -PB1 "$probe" 2>/dev/null | awk 'NR==2 {print $4}' | tr -d '[:space:]')
    [[ "$free_bytes" =~ ^[0-9]+$ ]] || return 1

    local free_human="${free_bytes} B"
    if declare -F format_bytes >/dev/null 2>&1; then
        free_human=$(format_bytes "$free_bytes")
    fi

    local is_low="0"
    if [[ "$req_bytes" =~ ^[0-9]+$ ]] && [ "$req_bytes" -gt 0 ] && [ "$free_bytes" -lt "$req_bytes" ]; then
        is_low="1"
    fi
    printf '%s\t%s\n' "$free_human" "$is_low"
    return 0
}


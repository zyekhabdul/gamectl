# Fetch and generate steam_settings/DLC.txt for GBE Fork
fetch_dlc() {
    local target_dir="$1"
    local appid="${2:-}"

    if [ ! -d "$target_dir" ]; then
        echo "[ERROR] Target directory not found: $target_dir" >&2
        return 1
    fi

    target_dir="$(cd "$target_dir" && pwd)"

    # Resolve AppID if not provided
    if [ -z "$appid" ]; then
        appid="$(resolve_game_appid "$target_dir")"
    fi

    if [ -z "$appid" ] || [ "$appid" = "STANDALONE" ]; then
        echo "[WARN] Numeric AppID not found. Skipping DLC.txt generation." >&2
        return 0
    fi

    echo "[INFO] Fetching DLC list for AppID $appid from Steam API..."
    local dlc_file="$target_dir/steam_settings/DLC.txt"
    mkdir -p "$target_dir/steam_settings"

    # Primary: dlcforapp endpoint (names & IDs in single call, disk-cached 3600s)
    local dlc_data=""
    dlc_data=$(fetch_cached_json "https://store.steampowered.com/api/dlcforapp/?appid=${appid}" "steam_dlc_${appid}" 3600 2>/dev/null | jq -r '.dlc[]? | "\(.id)=\(.name)"' 2>/dev/null || true)

    # Fallback: appdetails basic,dlc (disk-cached 3600s)
    if [ -z "$dlc_data" ]; then
        local dlc_ids
        dlc_ids=$(fetch_cached_json "https://store.steampowered.com/api/appdetails?appids=${appid}&filters=basic,dlc" "steam_basic_dlc_${appid}" 3600 2>/dev/null | jq -r ".\"${appid}\".data.dlc[]?" 2>/dev/null || true)
        if [ -n "$dlc_ids" ]; then
            dlc_data=""
            while read -r did; do
                [ -n "$did" ] && dlc_data+="${did}=DLC_${did}"$'\n'
            done <<< "$dlc_ids"
        fi
    fi

    # Fallback 2: Offline local Lua manifest harvesting
    if [ -z "$dlc_data" ]; then
        local lua_candidates=()
        [ -f "$target_dir/${appid}.lua" ] && lua_candidates+=("$target_dir/${appid}.lua")
        shopt -s nullglob globstar
        for f in "$target_dir"/**/"${appid}.lua" "$target_dir"/**/*.lua "$target_dir"/*.lua; do [ -f "$f" ] && lua_candidates+=("$f"); done
        shopt -u nullglob globstar
        local stplug_dir
        stplug_dir="$(get_steam_stplug_in_dir 2>/dev/null || echo "$HOME/.local/share/Steam/config/stplug-in")"
        [ -f "$stplug_dir/${appid}.lua" ] && lua_candidates+=("$stplug_dir/${appid}.lua")
        [ -f "$HOME/.config/SLSsteam/manifests/${appid}.lua" ] && lua_candidates+=("$HOME/.config/SLSsteam/manifests/${appid}.lua")
        local run_dir
        run_dir="$(get_runtime_dir)"
        [ -f "$run_dir/${appid}.lua" ] && lua_candidates+=("$run_dir/${appid}.lua")

        declare -A seen_dlc=()
        for cand_lua in "${lua_candidates[@]}"; do
            [ -f "$cand_lua" ] || continue
            while read -r parsed_id; do
                [ -n "$parsed_id" ] || continue
                [ "$parsed_id" = "$appid" ] && continue
                [[ -v seen_dlc["$parsed_id"] ]] && continue
                seen_dlc["$parsed_id"]=1
                dlc_data+="${parsed_id}=DLC_${parsed_id}"$'\n'
            done < <(grep -E 'addappid[[:space:]]*\([[:space:]]*[0-9]+' "$cand_lua" 2>/dev/null | sed -E 's/.*addappid[[:space:]]*\([[:space:]]*([0-9]+).*/\1/')
        done
        if [ -n "$dlc_data" ]; then
            echo "[INFO] Offline fallback: Discovered $(( ${#seen_dlc[@]} )) DLC(s) from local Lua manifests."
        fi
    fi

    if [ -n "$dlc_data" ]; then
        echo -n "$dlc_data" > "$dlc_file"
        # Ensure trailing newline
        [ -s "$dlc_file" ] && echo "" >> "$dlc_file"
        local count
        count=$(grep -c "=" "$dlc_file" || echo 0)
        echo "[VERIFIED] Successfully wrote $count DLC(s) to: $dlc_file"
    else
        touch "$dlc_file"
        echo "[INFO] No DLC found in Steam API. Created empty file: $dlc_file"
    fi
}

# Verify Valve manifest payload magic signature (0xd017f671)
manifest_has_payload_magic() {
    local m_file="$1"
    [ -f "$m_file" ] || return 1
    local sig
    sig=$(od -An -tx1 -N4 "$m_file" 2>/dev/null | tr -d " \n")
    [ "$sig" = "d017f671" ]
}

# Validate downloaded manifest ZIP archive for safety and payload contents
validate_manifest_zip() {
    local z_file="$1"
    local appid="${2:-}"
    local require_depots="${3:-false}"
    audit_zip_safety "$z_file" || return 1

    local entries
    entries=$(unzip -Z1 "$z_file" 2>/dev/null) || return 1
    [ -n "$entries" ] || return 1

    # Content check: must contain at least one .manifest or .lua file
    if ! echo "$entries" | grep -Eq '(\.manifest|\.lua)$'; then
        echo "[ERROR] Manifest zip does not contain any .manifest or .lua files." >&2
        return 1
    fi

    # Payload magic audit on contained manifests
    local run_dir
    run_dir="$(get_runtime_dir)"
    local audit_tmp="$run_dir/manifest_audit_$$"
    mkdir -p -m 700 "$audit_tmp"
    local has_valid_manifest=0

    # Extract only .manifest files to temporary audit sandbox
    unzip -q -j "$z_file" "*.manifest" -d "$audit_tmp" 2>/dev/null || true
    for mf in "$audit_tmp"/*.manifest; do
        [ -f "$mf" ] || continue
        if manifest_has_payload_magic "$mf"; then
            has_valid_manifest=1
            break
        fi
    done
    rm -rf "$audit_tmp"

    # Lua-only archives serve the explicit bridge, but cannot supply CDN file lists.
    if [ "$has_valid_manifest" -eq 0 ] && [ "$require_depots" != true ]; then
        if echo "$entries" | grep -Eq '\.lua$'; then
            has_valid_manifest=1
        fi
    fi

    [ "$has_valid_manifest" -eq 1 ]
}

# Check if file is a valid Lua manifest / stplugin payload
is_valid_lua_manifest() {
    local lua_file="$1"
    local appid="${2:-}"
    [ -f "$lua_file" ] || return 1
    local sz
    sz=$(stat -c %s "$lua_file" 2>/dev/null || wc -c < "$lua_file" 2>/dev/null || echo 0)
    [ "$sz" -gt 0 ] && [ "$sz" -le 16777216 ] || return 1

    local clean
    clean=$(sed 's/--.*$//' "$lua_file" 2>/dev/null || true)
    if [ -n "$appid" ]; then
        echo "$clean" | grep -Eq "^[[:space:]]*addappid[[:space:]]*\([[:space:]]*${appid}([[:space:]]*\)|[[:space:]]*,)" || \
        echo "$clean" | grep -Eq "^[[:space:]]*addappid[[:space:]]*\("
    else
        echo "$clean" | grep -Eq "^[[:space:]]*addappid[[:space:]]*\("
    fi
}

# Fail-fast offline credential preflight for explicit gated manifest providers
# when no valid local cached/stashed manifest archive exists.
preflight_manifest_source() {
    local appid="${1:-}"
    local pref_source="${2:-auto}"
    local require_depots="${3:-false}"
    local src_lc="${pref_source,,}"

    case "$src_lc" in
        luatools|hubcap) ;;
        *) return 0 ;;
    esac

    appid=$(strip_ansi "$appid" | tr -dc "0-9")
    if [ -n "$appid" ]; then
        local cache_zip="${XDG_CACHE_HOME:-$HOME/.cache}/gamectl/manifests/${appid}.zip"
        local stash_zip="$HOME/.local/share/gamectl/manifests/${appid}.zip"
        if [ -f "$cache_zip" ] && validate_manifest_zip "$cache_zip" "$appid" "$require_depots" >/dev/null 2>&1; then
            return 0
        fi
        if [ -f "$stash_zip" ] && validate_manifest_zip "$stash_zip" "$appid" "$require_depots" >/dev/null 2>&1; then
            return 0
        fi
    fi

    if [ "$src_lc" = "luatools" ] && ! get_valid_luatools_token >/dev/null 2>&1; then
        echo "[ERROR] LuaTools session unavailable. Authenticate with 'gamectl login-luatools <code | session.json>' and retry." >&2
        return 1
    elif [ "$src_lc" = "hubcap" ] && [ -z "$(get_hubcap_api_key 2>/dev/null || true)" ]; then
        echo "[ERROR] Hubcap API key is not configured. Run 'gamectl config set hubcap_key <smm_key>' and retry." >&2
        return 1
    fi
    return 0
}

# Multi-Provider Manifest & Key Harvester
fetch_manifest() {
    local appid="$1"
    local dest_file="${2:-}"
    local pref_source="${3:-auto}"
    local require_depots="${4:-false}"

    # Strip any ANSI escape sequences
    appid=$(strip_ansi "$appid" | tr -dc "0-9")
    if [ -z "$appid" ]; then
        echo "[ERROR] fetch_manifest: Invalid numeric AppID." >&2
        return 1
    fi

    local cache_dir="${XDG_CACHE_HOME:-$HOME/.cache}/gamectl/manifests"
    mkdir -p -m 700 "$cache_dir"
    local cached_zip="$cache_dir/${appid}.zip"

    # 1. Check valid persistent cache
    if [ -f "$cached_zip" ] && validate_manifest_zip "$cached_zip" "$appid" "$require_depots"; then
        echo "[INFO] Using cached manifest archive: $cached_zip" >&2
        if [ -n "$dest_file" ]; then
            cp -f "$cached_zip" "$dest_file"
            echo "$dest_file"
        else
            echo "$cached_zip"
        fi
        return 0
    fi

    # 2. Check local repository stash (~/.local/share/gamectl/manifests/)
    local stash_zip="$HOME/.local/share/gamectl/manifests/${appid}.zip"
    if [ -f "$stash_zip" ] && validate_manifest_zip "$stash_zip" "$appid" "$require_depots"; then
        echo "[INFO] Using local stash manifest archive: $stash_zip" >&2
        cp -f "$stash_zip" "$cached_zip"
        if [ -n "$dest_file" ]; then
            cp -f "$stash_zip" "$dest_file"
            echo "$dest_file"
        else
            echo "$stash_zip"
        fi
        return 0
    fi

    preflight_manifest_source "$appid" "$pref_source" "$require_depots" || return 1

    echo "[INFO] Harvesting manifest archive for AppID $appid across multi-provider network..." >&2

    local run_dir
    run_dir="$(get_runtime_dir)"
    local dl_tmp="$run_dir/fetch_manifest_${appid}_$$.zip"
    rm -f "$dl_tmp"

    declare -a src_names src_urls src_headers
    local src_count=0

    # Source 1: ManifestHub (Official GitHub archive per AppID branch)
    src_names[src_count]="ManifestHub"
    src_urls[src_count]="https://codeload.github.com/steamtoolsapp/ManifestHub/zip/refs/heads/${appid}"
    src_headers[src_count]=""
    src_count=$((src_count + 1))

    # Source 2: Hubcap Manifest REST API (Community Discord key-gated database)
    local hubcap_key
    hubcap_key=$(get_hubcap_api_key 2>/dev/null || true)
    if [ -n "$hubcap_key" ]; then
        src_names[src_count]="Hubcap"
        src_urls[src_count]="https://hubcapmanifest.com/api/v1/manifest/${appid}"
        src_headers[src_count]="Authorization: Bearer $hubcap_key"
        src_count=$((src_count + 1))
    fi

    # Source 3: Ryuu direct mirror
    src_names[src_count]="Ryuu"
    src_urls[src_count]="http://167.235.229.108/${appid}"
    src_headers[src_count]=""
    src_count=$((src_count + 1))

    # Source 3: Sushi GitHub repository (alt)
    src_names[src_count]="Sushi"
    src_urls[src_count]="https://raw.githubusercontent.com/sushi-dev55-alt/sushitools-games-repo-alt/refs/heads/main/${appid}.zip"
    src_headers[src_count]=""
    src_count=$((src_count + 1))

    # Source 4: Sushi GitHub repository (main)
    src_names[src_count]="SushiMain"
    src_urls[src_count]="https://raw.githubusercontent.com/sushi-dev55/sushitools-games-repo/main/${appid}.zip"
    src_headers[src_count]=""
    src_count=$((src_count + 1))

    # Source 5: Lua.tools managed API (if auth session exists)
    local token
    token=$(get_valid_luatools_token 2>/dev/null || true)
    if [ -n "$token" ]; then
        src_names[src_count]="LuaTools"
        src_urls[src_count]="https://lua.tools/api/manifest/download?appid=${appid}&source=Luie"
        src_headers[src_count]="Authorization: Bearer $token"
        src_count=$((src_count + 1))
    fi

    local found=0
    for ((i=0; i<src_count; i++)); do
        local name="${src_names[i]}"
        local url="${src_urls[i]}"
        local hdr="${src_headers[i]}"

        if [ "$pref_source" != "auto" ] && [ "${pref_source,,}" != "${name,,}" ]; then
            continue
        fi

        echo "[INFO] Querying provider: $name ($url)..." >&2
        local curl_args=("-sSL" "--connect-timeout" "5" "--max-time" "25" "-A" "discord(dot)gg/luatools" "-o" "$dl_tmp" "-w" "%{http_code}")
        if [ -n "$hdr" ]; then
            curl_args+=("-H" "$hdr")
        fi

        local http_code
        http_code=$(curl "${curl_args[@]}" "$url" 2>/dev/null || echo "000")

        if [ "$http_code" = "200" ] && [ -s "$dl_tmp" ]; then
            # Format adaptation: If payload is a raw Lua script, encapsulate into standardized ZIP
            if ! unzip -tq "$dl_tmp" >/dev/null 2>&1 && is_valid_lua_manifest "$dl_tmp" "$appid"; then
                local stage_lua="$run_dir/${appid}.lua"
                cp -f "$dl_tmp" "$stage_lua"
                local zip_tmp="$run_dir/wrap_${appid}_$$.zip"
                (cd "$run_dir" && zip -q -0 "$zip_tmp" "${appid}.lua") 2>/dev/null || true
                rm -f "$stage_lua"
                if [ -f "$zip_tmp" ]; then
                    mv -f "$zip_tmp" "$dl_tmp"
                fi
            fi

            if validate_manifest_zip "$dl_tmp" "$appid" "$require_depots"; then
                echo "[VERIFIED] Manifest archive acquired from $name." >&2
                cp -f "$dl_tmp" "$cached_zip"
                if [ -n "$dest_file" ]; then
                    cp -f "$dl_tmp" "$dest_file"
                    echo "$dest_file"
                else
                    echo "$cached_zip"
                fi
                found=1
                rm -f "$dl_tmp"
                break
            else
                echo "[WARN] Provider $name returned an invalid archive or lacks the required depot manifests." >&2
                rm -f "$dl_tmp"
            fi
        else
            echo "[INFO] Provider $name returned HTTP $http_code." >&2
            rm -f "$dl_tmp"
        fi
    done

    if [ "$found" -eq 1 ]; then
        return 0
    else
        echo "[ERROR] Manifest archive for AppID $appid not found across available providers." >&2
        if [ -z "$hubcap_key" ]; then
            echo "[NOTE] Hubcap provider was skipped (no API key configured)." >&2
            echo "[NOTE] To configure Hubcap key: run 'gamectl config set hubcap_key smm_...' or open Master Dashboard -> Global Settings." >&2
        fi
        local token
        token=$(get_valid_luatools_token 2>/dev/null || true)
        if [ -z "$token" ]; then
            echo "[NOTE] LuaTools extended catalog was skipped (no active session)." >&2
            echo "[NOTE] To authenticate with LuaTools: run 'gamectl login-luatools' or open Master Dashboard -> Global Settings -> LuaTools Session." >&2
        fi
        return 1
    fi
}

# Harvest and integrate additional DLC manifest archives for an AppID into stage directory
harvest_dlc_manifests() {
    local base_appid="$1"
    local stage_dir="$2"
    local source="${3:-auto}"
    [ -d "$stage_dir" ] || return 0

    local lua_file="$stage_dir/${base_appid}.lua"
    if [ ! -f "$lua_file" ]; then
        shopt -s nullglob globstar
        local found_luas=("$stage_dir"/**/"${base_appid}.lua" "$stage_dir"/**/*.lua "$stage_dir"/*.lua)
        shopt -u nullglob globstar
        [ ${#found_luas[@]} -gt 0 ] && lua_file="${found_luas[0]}"
    fi
    [ -f "$lua_file" ] || return 0

    # Discover candidate DLC AppIDs from addappid(<id>)
    local dlc_appids=()
    while read -r cand_id; do
        [ -n "$cand_id" ] || continue
        [ "$cand_id" = "$base_appid" ] && continue
        dlc_appids+=("$cand_id")
    done < <(grep -E '^[[:space:]]*addappid\([[:space:]]*[0-9]+[[:space:]]*\)' "$lua_file" 2>/dev/null | sed -E 's/.*addappid\([[:space:]]*([0-9]+).*/\1/')

    if [ ${#dlc_appids[@]} -eq 0 ]; then
        return 0
    fi

    echo "[INFO] Discovered ${#dlc_appids[@]} candidate DLC AppID(s) in Lua manifest: ${dlc_appids[*]}" >&2

    local harvested=0
    for dlc_id in "${dlc_appids[@]}"; do
        # Avoid re-harvesting if already staged
        shopt -s nullglob globstar
        local existing_dlc_lua=("$stage_dir"/**/"${dlc_id}.lua" "$stage_dir"/*"${dlc_id}.lua")
        shopt -u nullglob globstar
        if [ ${#existing_dlc_lua[@]} -gt 0 ]; then
            continue
        fi

        local dlc_zip
        dlc_zip=$(fetch_manifest "$dlc_id" "" "$source" 2>/dev/null || true)
        if [ -n "$dlc_zip" ] && [ -f "$dlc_zip" ] && validate_manifest_zip "$dlc_zip" "$dlc_id"; then
            if unzip -qo "$dlc_zip" -d "$stage_dir" 2>/dev/null; then
                echo "  [INFO] Successfully integrated DLC manifest archive: AppID $dlc_id" >&2
                harvested=$((harvested + 1))
            fi
        fi
    done

    if [ "$harvested" -gt 0 ]; then
        echo "[VERIFIED] Integrated $harvested additional DLC manifest archive(s) into stage directory." >&2
    fi
    return 0
}

# Standalone-source compatibility: load split manifest submodules when sourced directly outside bin/gamectl
if [ -z "${GAMECTL_BUNDLED:-}" ] && [ -n "${BASH_SOURCE[0]:-}" ]; then
    _manifests_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd)"
    for _manifests_sub in 36_luatools_auth.sh 37_app_types.sh; do
        if [ -f "$_manifests_dir/$_manifests_sub" ]; then
            # shellcheck source=/dev/null
            source "$_manifests_dir/$_manifests_sub"
        fi
    done
    unset _manifests_dir _manifests_sub
fi

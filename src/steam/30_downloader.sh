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
        if [ -f "$target_dir/steam_appid.txt" ]; then
            appid=$(tr -dc '0-9' < "$target_dir/steam_appid.txt")
        fi
    fi

    if [ -z "$appid" ] || [ "$appid" = "STANDALONE" ]; then
        echo "[WARN] Numeric AppID not found. Skipping DLC.txt generation."
        return 0
    fi

    echo "[INFO] Fetching DLC list for AppID $appid from Steam API..."
    local dlc_file="$target_dir/steam_settings/DLC.txt"
    mkdir -p "$target_dir/steam_settings"

    # Primary: dlcforapp endpoint (names & IDs in single call)
    local dlc_data=""
    dlc_data=$(curl -s --connect-timeout 4 "https://store.steampowered.com/api/dlcforapp/?appid=${appid}" | jq -r '.dlc[]? | "\(.id)=\(.name)"' 2>/dev/null || true)

    # Fallback: appdetails basic,dlc
    if [ -z "$dlc_data" ]; then
        local dlc_ids
        dlc_ids=$(curl -s --connect-timeout 4 "https://store.steampowered.com/api/appdetails?appids=${appid}&filters=basic,dlc" | jq -r ".\"${appid}\".data.dlc[]?" 2>/dev/null || true)
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
        shopt -s nullglob
        for f in "$target_dir"/*.lua; do [ -f "$f" ] && lua_candidates+=("$f"); done
        shopt -u nullglob
        local stplug_dir
        stplug_dir="$(get_steam_stplug_in_dir 2>/dev/null || echo "$HOME/.local/share/Steam/config/stplug-in")"
        [ -f "$stplug_dir/${appid}.lua" ] && lua_candidates+=("$stplug_dir/${appid}.lua")
        [ -f "$HOME/.config/SLSsteam/manifests/${appid}.lua" ] && lua_candidates+=("$HOME/.config/SLSsteam/manifests/${appid}.lua")
        local run_dir="${XDG_RUNTIME_DIR:-/tmp/gamectl-$UID}"
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
    [ -f "$z_file" ] || return 1
    unzip -tq "$z_file" >/dev/null 2>&1 || return 1

    local entries
    entries=$(unzip -Z1 "$z_file" 2>/dev/null) || return 1
    [ -n "$entries" ] || return 1

    # Security: Path traversal & absolute path rejection
    if echo "$entries" | grep -Eq '(^/|^[A-Za-z]:|(^|[/\\])\.\.([/\\]|$)|\\)'; then
        echo "[ERROR] Manifest zip contains unsafe paths (path traversal rejected)." >&2
        return 1
    fi

    # Content check: must contain at least one .manifest or .lua file
    if ! echo "$entries" | grep -Eq '(\.manifest|\.lua)$'; then
        echo "[ERROR] Manifest zip does not contain any .manifest or .lua files." >&2
        return 1
    fi

    # Payload magic audit on contained manifests
    local run_dir="${XDG_RUNTIME_DIR:-/tmp/gamectl-$UID}"
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

    # If no .manifest was found or .lua only, check if .lua has addappid
    if [ "$has_valid_manifest" -eq 0 ]; then
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

# Acquire or auto-refresh LuaTools bearer access token
get_valid_luatools_token() {
    local lumen_auth="${XDG_DATA_HOME:-$HOME/.local/share}/Lumen/luatools/backend/data/lua_tools_auth.json"
    local cfg_auth="$HOME/.config/gamectl/lua_tools_auth.json"
    local target_auth=""

    if [ -f "$cfg_auth" ]; then
        target_auth="$cfg_auth"
    elif [ -f "$lumen_auth" ]; then
        target_auth="$lumen_auth"
        # Seed into ~/.config/gamectl for standalone sovereign operation
        mkdir -p "$HOME/.config/gamectl"
        cp -f "$lumen_auth" "$cfg_auth" 2>/dev/null || true
        chmod 600 "$cfg_auth" 2>/dev/null || true
        target_auth="$cfg_auth"
    fi

    [ -n "$target_auth" ] && [ -f "$target_auth" ] || return 1

    local access_token refresh_token expires_at now
    access_token=$(jq -r '.access_token // empty' "$target_auth" 2>/dev/null || true)
    refresh_token=$(jq -r '.refresh_token // empty' "$target_auth" 2>/dev/null || true)
    expires_at=$(jq -r '.expires_at // 0' "$target_auth" 2>/dev/null || echo 0)
    now=$(date +%s)

    # Return valid cached token if at least 60 seconds remain before expiration
    if [ -n "$access_token" ] && [ "$((expires_at - now))" -gt 60 ]; then
        printf "%s" "$access_token"
        return 0
    fi

    # Trigger token auto-refresh via Supabase auth endpoint
    if [ -n "$refresh_token" ]; then
        local supabase_key="eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpYXQiOjE3NzYwMzkzNzYsImV4cCI6MTg5MzQ1NjAwMCwicm9sZSI6ImFub24iLCJpc3MiOiJzdXBhYmFzZSJ9.f_-K38u3odjltP-g_67FVmG32Vg-_-k-lNBvIaVUVBM"
        local refresh_resp
        refresh_resp=$(curl -sSL --connect-timeout 5 --max-time 15 \
            -X POST "https://db.lua.tools/auth/v1/token?grant_type=refresh_token" \
            -H "Content-Type: application/json" \
            -H "apikey: $supabase_key" \
            -H "User-Agent: discord(dot)gg/luatools" \
            -d "{\"refresh_token\":\"$refresh_token\"}" 2>/dev/null || true)

        local new_token new_expires_in new_refresh
        new_token=$(echo "$refresh_resp" | jq -r '.access_token // empty' 2>/dev/null || true)
        new_expires_in=$(echo "$refresh_resp" | jq -r '.expires_in // 3600' 2>/dev/null || echo 3600)
        new_refresh=$(echo "$refresh_resp" | jq -r '.refresh_token // empty' 2>/dev/null || true)

        if [ -n "$new_token" ]; then
            local new_expires_at=$((now + new_expires_in))
            [ -z "$new_refresh" ] && new_refresh="$refresh_token"

            local tmp_json="${target_auth}.tmp.$$"
            jq --arg at "$new_token" \
               --arg rt "$new_refresh" \
               --argjson exp "$new_expires_at" \
               '.access_token = $at | .refresh_token = $rt | .expires_at = $exp' \
               "$target_auth" > "$tmp_json" 2>/dev/null && mv -f "$tmp_json" "$target_auth"
            chmod 600 "$target_auth" 2>/dev/null || true

            # Also synchronize back to Lumen backend auth file if present
            if [ -f "$lumen_auth" ] && [ "$target_auth" != "$lumen_auth" ]; then
                cp -f "$target_auth" "$lumen_auth" 2>/dev/null || true
                chmod 600 "$lumen_auth" 2>/dev/null || true
            fi

            printf "%s" "$new_token"
            return 0
        fi
    fi

    # Fallback to existing access_token if network refresh fails
    if [ -n "$access_token" ]; then
        printf "%s" "$access_token"
        return 0
    fi

    return 1
}

# Authenticate or import standalone LuaTools session
login_luatools() {
    local input="${1:-}"
    local cfg_auth="$HOME/.config/gamectl/lua_tools_auth.json"
    mkdir -p "$HOME/.config/gamectl"

    if [ -z "$input" ]; then
        echo "Usage: gamectl login-luatools <6-character-code | refresh_token | session.json>"
        echo "Tip: Generate a 6-character code at https://lua.tools/ or Discord bot (/login)"
        return 1
    fi

    local supabase_key="eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpYXQiOjE3NzYwMzkzNzYsImV4cCI6MTg5MzQ1NjAwMCwicm9sZSI6ImFub24iLCJpc3MiOiJzdXBhYmFzZSJ9.f_-K38u3odjltP-g_67FVmG32Vg-_-k-lNBvIaVUVBM"
    local now
    now=$(date +%s)

    # Mode 1: 6-Character Redeem Code (e.g. A1B2C3)
    if [[ "$input" =~ ^[A-Za-z0-9]{6}$ ]]; then
        local code="${input^^}"
        echo "[INFO] Redeeming 6-character code '$code' at lua.tools API..."
        local redeem_resp
        redeem_resp=$(curl -sSL --connect-timeout 5 --max-time 15 \
            -X POST "https://lua.tools/api/auth/code/redeem" \
            -H "Content-Type: application/json" \
            -H "User-Agent: discord(dot)gg/luatools" \
            -d "{"code":"$code"}" 2>/dev/null || true)

        local token_hash
        token_hash=$(echo "$redeem_resp" | jq -r '.token // empty' 2>/dev/null || true)
        if [ -z "$token_hash" ]; then
            echo "[ERROR] Failed to redeem code: $(echo "$redeem_resp" | jq -r '.error // "Unknown error"' 2>/dev/null || echo "$redeem_resp")" >&2
            return 1
        fi

        echo "[INFO] Verifying authentication token with Supabase..."
        local verify_resp
        verify_resp=$(curl -sSL --connect-timeout 5 --max-time 15 \
            -X POST "https://db.lua.tools/auth/v1/verify" \
            -H "Content-Type: application/json" \
            -H "apikey: $supabase_key" \
            -H "User-Agent: discord(dot)gg/luatools" \
            -d "{"type":"magiclink","token_hash":"$token_hash"}" 2>/dev/null || true)

        local access_token refresh_token expires_in
        access_token=$(echo "$verify_resp" | jq -r '.access_token // empty' 2>/dev/null || true)
        refresh_token=$(echo "$verify_resp" | jq -r '.refresh_token // empty' 2>/dev/null || true)
        expires_in=$(echo "$verify_resp" | jq -r '.expires_in // 3600' 2>/dev/null || echo 3600)

        if [ -n "$access_token" ] && [ -n "$refresh_token" ]; then
            local expires_at=$((now + expires_in))
            echo "$verify_resp" | jq --argjson exp "$expires_at" '.expires_at = $exp' > "$cfg_auth"
            chmod 600 "$cfg_auth"
            local user_name
            user_name=$(echo "$verify_resp" | jq -r '.user.user_metadata.custom_claims.global_name // .user.user_metadata.full_name // .user.email // "User"' 2>/dev/null || echo "User")
            echo "[VERIFIED] Successfully authenticated as $user_name. Sesi disimpan di $cfg_auth"
            return 0
        else
            echo "[ERROR] Verification failed: $(echo "$verify_resp" | jq -r '.error_description // .message // "Invalid session response"')" >&2
            return 1
        fi

    # Mode 2: Existing JSON session file (e.g. from Lumen or backup)
    elif [ -f "$input" ]; then
        if jq -e '.refresh_token' "$input" >/dev/null 2>&1; then
            cp -f "$input" "$cfg_auth"
            chmod 600 "$cfg_auth"
            echo "[VERIFIED] Imported session file from $input -> $cfg_auth"
            get_valid_luatools_token >/dev/null 2>&1 || true
            return 0
        else
            echo "[ERROR] File does not contain a valid .refresh_token JSON field." >&2
            return 1
        fi

    # Mode 3: Raw refresh_token or JWT string
    else
        echo "[INFO] Attempting refresh exchange using provided raw token..."
        local refresh_resp
        refresh_resp=$(curl -sSL --connect-timeout 5 --max-time 15 \
            -X POST "https://db.lua.tools/auth/v1/token?grant_type=refresh_token" \
            -H "Content-Type: application/json" \
            -H "apikey: $supabase_key" \
            -H "User-Agent: discord(dot)gg/luatools" \
            -d "{"refresh_token":"$input"}" 2>/dev/null || true)

        local access_token new_refresh expires_in
        access_token=$(echo "$refresh_resp" | jq -r '.access_token // empty' 2>/dev/null || true)
        new_refresh=$(echo "$refresh_resp" | jq -r '.refresh_token // empty' 2>/dev/null || echo "$input")
        expires_in=$(echo "$refresh_resp" | jq -r '.expires_in // 3600' 2>/dev/null || echo 3600)

        if [ -n "$access_token" ]; then
            local expires_at=$((now + expires_in))
            echo "$refresh_resp" | jq --argjson exp "$expires_at" --arg rt "$new_refresh" '.expires_at = $exp | .refresh_token = $rt' > "$cfg_auth"
            chmod 600 "$cfg_auth"
            echo "[VERIFIED] Successfully authenticated via token. Sesi disimpan di $cfg_auth"
            return 0
        else
            echo "[ERROR] Token exchange failed: $(echo "$refresh_resp" | jq -r '.error_description // .error // "Invalid token"')" >&2
            return 1
        fi
    fi
}

# Display LuaTools authentication session status
luatools_status() {
    local cfg_auth="$HOME/.config/gamectl/lua_tools_auth.json"
    local lumen_auth="${XDG_DATA_HOME:-$HOME/.local/share}/Lumen/luatools/backend/data/lua_tools_auth.json"
    local target_auth=""

    if [ -f "$cfg_auth" ]; then target_auth="$cfg_auth"; elif [ -f "$lumen_auth" ]; then target_auth="$lumen_auth"; fi

    if [ -n "$target_auth" ] && [ -f "$target_auth" ]; then
        local user_name expires_at now remaining
        user_name=$(jq -r '.user.user_metadata.custom_claims.global_name // .user.user_metadata.full_name // .user.email // "Authenticated User"' "$target_auth" 2>/dev/null || echo "Authenticated User")
        expires_at=$(jq -r '.expires_at // 0' "$target_auth" 2>/dev/null || echo 0)
        now=$(date +%s)
        remaining=$((expires_at - now))
        echo "[STATUS] LuaTools Session: ACTIVE (${target_auth})"
        echo "  • User     : $user_name"
        if [ "$remaining" -gt 0 ]; then
            echo "  • Lifetime : Token valid ($((remaining / 60)) min remaining, auto-refreshed by gamectl)"
        else
            echo "  • Lifetime : Expired (will auto-refresh on next download)"
        fi
    else
        echo "[STATUS] LuaTools Session: NOT CONFIGURED"
        echo "  • Public providers (Ryuu, Sushi) are ACTIVE (Zero login required)."
        echo "  • To unlock LuaTools provider: gamectl login-luatools <6-character-code | token>"
    fi
}

# Multi-Provider Manifest & Key Harvester
fetch_manifest() {
    local appid="$1"
    local dest_file="${2:-}"
    local pref_source="${3:-auto}"

    # Strip any ANSI escape sequences
    appid=$(printf "%s" "$appid" | sed -r "s/\x1B\[[0-9;]*[a-zA-Z]//g" | tr -dc "0-9")
    if [ -z "$appid" ]; then
        echo "[ERROR] fetch_manifest: Invalid numeric AppID." >&2
        return 1
    fi

    local cache_dir="${XDG_CACHE_HOME:-$HOME/.cache}/gamectl/manifests"
    mkdir -p -m 700 "$cache_dir"
    local cached_zip="$cache_dir/${appid}.zip"

    # 1. Check valid persistent cache
    if [ -f "$cached_zip" ] && validate_manifest_zip "$cached_zip" "$appid"; then
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
    if [ -f "$stash_zip" ] && validate_manifest_zip "$stash_zip" "$appid"; then
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

    echo "[INFO] Harvesting manifest archive for AppID $appid across multi-provider network..." >&2

    local run_dir="${XDG_RUNTIME_DIR:-/tmp/gamectl-$UID}"
    mkdir -p -m 700 "$run_dir"
    local dl_tmp="$run_dir/fetch_manifest_${appid}_$$.zip"
    rm -f "$dl_tmp"

    declare -a src_names src_urls src_headers
    local src_count=0

    # Source 1: Ryuu direct mirror
    src_names[src_count]="Ryuu"
    src_urls[src_count]="http://167.235.229.108/${appid}"
    src_headers[src_count]=""
    src_count=$((src_count + 1))

    # Source 2: Sushi GitHub repository
    src_names[src_count]="Sushi"
    src_urls[src_count]="https://raw.githubusercontent.com/sushi-dev55-alt/sushitools-games-repo-alt/refs/heads/main/${appid}.zip"
    src_headers[src_count]=""
    src_count=$((src_count + 1))

    # Source 3: Lua.tools managed API (if auth session exists)
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

            if validate_manifest_zip "$dl_tmp" "$appid"; then
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
                echo "[WARN] Provider $name returned corrupt or invalid manifest zip." >&2
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
        shopt -s nullglob
        local found_luas=("$stage_dir"/*.lua)
        shopt -u nullglob
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
        if [ -f "$stage_dir/${dlc_id}.lua" ]; then
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

# Deploy manifest archive into SLSsteam manifests, stplug-in Lua, and config.yaml
deploy_sls_manifest() {
    local appid="$1"
    local manifest_zip="${2:-}"
    local title="${3:-}"
    local source="${4:-auto}"

    # Strip ANSI escape sequences
    appid=$(printf "%s" "$appid" | sed -r "s/\x1B\[[0-9;]*[a-zA-Z]//g" | tr -dc "0-9")
    title=$(printf "%s" "$title" | sed -r "s/\x1B\[[0-9;]*[a-zA-Z]//g")

    if [ -z "$appid" ]; then
        echo "[ERROR] deploy_sls_manifest: Invalid numeric AppID." >&2
        return 1
    fi

    # 1. Acquire manifest archive if not provided
    if [ -z "$manifest_zip" ] || [ ! -f "$manifest_zip" ]; then
        echo "[INFO] Manifest archive not provided. Attempting automatic harvest (source: $source)..." >&2
        manifest_zip=$(fetch_manifest "$appid" "" "$source" 2>/dev/null || true)
        if [ -z "$manifest_zip" ] || [ ! -f "$manifest_zip" ]; then
            echo "[ERROR] Could not acquire manifest archive for AppID $appid." >&2
            return 1
        fi
    fi

    if ! validate_manifest_zip "$manifest_zip" "$appid"; then
        echo "[ERROR] Manifest zip validation failed: $manifest_zip" >&2
        return 1
    fi

    local run_dir="${XDG_RUNTIME_DIR:-/tmp/gamectl-$UID}"
    local stage_dir="$run_dir/sls_deploy_${appid}_$$"
    mkdir -p -m 700 "$stage_dir"
    trap 'rm -rf "$stage_dir" 2>/dev/null || true' RETURN

    if ! unzip -q "$manifest_zip" -d "$stage_dir" 2>/dev/null; then
        echo "[ERROR] Failed to unpack manifest archive: $manifest_zip" >&2
        return 1
    fi

    local sls_mf_dir
    sls_mf_dir="$(get_sls_manifests_dir 2>/dev/null || echo "$HOME/.config/SLSsteam/manifests")"
    local steam_depot_dir
    steam_depot_dir="$(get_steam_depotcache_dir 2>/dev/null || echo "$HOME/.local/share/Steam/depotcache")"
    local stplug_dir
    stplug_dir="$(get_steam_stplug_in_dir 2>/dev/null || echo "$HOME/.local/share/Steam/config/stplug-in")"

    mkdir -p -m 700 "$sls_mf_dir" "$steam_depot_dir" "$stplug_dir"

    local manifest_count=0
    declare -A pinned_depots=()

    # 2. Process and deploy binary manifests
    shopt -s nullglob globstar
    local mf_files=("$stage_dir"/**/*.manifest "$stage_dir"/*.manifest)
    declare -A seen_mf=()
    for mf in "${mf_files[@]}"; do
        [ -f "$mf" ] || continue
        local mf_name
        mf_name="$(basename "$mf")"
        [[ -v seen_mf["$mf_name"] ]] && continue
        seen_mf["$mf_name"]=1

        if manifest_has_payload_magic "$mf"; then
            cp -f "$mf" "$sls_mf_dir/$mf_name"
            chmod 600 "$sls_mf_dir/$mf_name"

            # Mirror to Steam internal depotcache
            cp -f "$mf" "$steam_depot_dir/$mf_name"
            chmod 600 "$steam_depot_dir/$mf_name"

            # Parse depot and GID from <depot>_<gid>.manifest
            if [[ "$mf_name" =~ ^([0-9]+)_([0-9]+)\.manifest$ ]]; then
                local depot_id="${BASH_REMATCH[1]}"
                local gid="${BASH_REMATCH[2]}"
                echo "$gid" > "$sls_mf_dir/.preferred_${depot_id}"
                chmod 600 "$sls_mf_dir/.preferred_${depot_id}"
                pinned_depots["$depot_id"]="$gid"
            fi
            manifest_count=$((manifest_count + 1))
        fi
    done
    shopt -u nullglob globstar

    # 3. Extract or synthesize stplug-in Lua script
    local target_lua="$stplug_dir/${appid}.lua"
    local staged_lua=""
    if [ -f "$stage_dir/${appid}.lua" ]; then
        staged_lua="$stage_dir/${appid}.lua"
    else
        shopt -s nullglob globstar
        local candidate_luas=("$stage_dir"/**/*.lua "$stage_dir"/*.lua)
        shopt -u nullglob globstar
        if [ "${#candidate_luas[@]}" -eq 1 ]; then
            staged_lua="${candidate_luas[0]}"
        fi
    fi

    if [ -n "$staged_lua" ] && [ -f "$staged_lua" ]; then
        cp -f "$staged_lua" "$target_lua"
        if ! grep -Eq "^[[:space:]]*addappid[[:space:]]*\([[:space:]]*${appid}[[:space:]]*\)" "$target_lua"; then
            sed -i "1i addappid(${appid})" "$target_lua"
        fi
        chmod 600 "$target_lua"
        echo "[VERIFIED] Stplug-in Lua deployed from archive: $target_lua" >&2
    else
        echo "[INFO] Synthesizing stplug-in Lua script for AppID $appid..." >&2
        local synth_lua="addappid($appid)\n"
        for d_id in "${!pinned_depots[@]}"; do
            synth_lua+="addappid($d_id)\n"
        done
        printf "%b" "$synth_lua" > "$target_lua"
        chmod 600 "$target_lua"
        echo "[VERIFIED] Synthesized stplug-in Lua: $target_lua" >&2
    fi

    # 4. Synchronize entitlement in SLSsteam config.yaml (skipping ACF creation)
    sync_steam "$appid" "$title" "--no-acf"

    echo "[VERIFIED] SLSsteam deployment complete for AppID $appid ($manifest_count manifest(s) linked)." >&2
    return 0
}

# Resolve path to standalone Steam CDN depot downloader binary (gamectl-depot-dl)
resolve_depot_dl_bin() {
    if [ -n "${GAMECTL_DEPOT_DL_BIN:-}" ] && [ -x "$GAMECTL_DEPOT_DL_BIN" ]; then
        echo "$GAMECTL_DEPOT_DL_BIN"
        return 0
    fi
    local candidate
    local script_dir
    script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd 2>/dev/null || echo "")"
    for candidate in \
        "$script_dir/gamectl-depot-dl" \
        "$script_dir/../../bin/gamectl-depot-dl" \
        "$script_dir/../bin/gamectl-depot-dl" \
        "$script_dir/bin/gamectl-depot-dl" \
        "$HOME/.local/bin/gamectl-depot-dl" \
        "/usr/local/bin/gamectl-depot-dl" \
        "/usr/bin/gamectl-depot-dl"; do
        if [ -x "$candidate" ]; then
            echo "$candidate"
            return 0
        fi
    done
    if command -v gamectl-depot-dl >/dev/null 2>&1; then
        command -v gamectl-depot-dl
        return 0
    fi
    return 1
}

# Ensure Steam CDN depot downloader runtime is available
ensure_downloader() {
    if resolve_depot_dl_bin >/dev/null 2>&1; then
        return 0
    fi
    echo "[WARN] Standalone depot downloader binary (gamectl-depot-dl) not found." >&2
    return 1
}

# Resolve optimal destination directory based on configured libraries and available disk space
resolve_target_library_dir() {
    local safe_title="${1:-game}"
    local candidate_dirs=()

    # 0. Primary sovereign library override
    if [ -n "${GAMECTL_LIBRARY_DIR:-}" ]; then
        candidate_dirs+=("$GAMECTL_LIBRARY_DIR")
    elif [ -f "$HOME/.config/gamectl/library_dir" ]; then
        local p_lib
        p_lib=$(head -n 1 "$HOME/.config/gamectl/library_dir" 2>/dev/null | tr -d '\r\n' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
        [ -n "$p_lib" ] && candidate_dirs+=("${p_lib/#\~/$HOME}")
    fi

    # 1. Custom libraries from config
    local cfg_libs="$HOME/.config/gamectl/libraries"
    if [ -f "$cfg_libs" ]; then
        while IFS= read -r line || [ -n "$line" ]; do
            line="${line#"${line%%[![:space:]]*}"}" # trim leading
            line="${line%"${line##*[![:space:]]}"}" # trim trailing
            [ -z "$line" ] && continue
            [[ "$line" =~ ^# ]] && continue
            candidate_dirs+=("${line/#\~/$HOME}")
        done < "$cfg_libs"
    fi

    # 2. Extra libraries from environment
    if [ -n "${GAMECTL_LIBRARY_DIRS:-}" ]; then
        local extra_dirs=()
        IFS=":" read -r -a extra_dirs <<< "$GAMECTL_LIBRARY_DIRS"
        candidate_dirs+=("${extra_dirs[@]}")
    fi

    # 3. Default fallback directory
    candidate_dirs+=("$HOME/Games")

    local best_dir="$HOME/Games"
    local max_free=0
    declare -A seen_candidates=()

    for d in "${candidate_dirs[@]}"; do
        [ -n "$d" ] || continue
        [[ -v seen_candidates["$d"] ]] && continue
        seen_candidates["$d"]=1

        # If dir doesn't exist yet, probe parent dir
        local probe_target="$d"
        while [ ! -d "$probe_target" ] && [ "$probe_target" != "/" ] && [ "$probe_target" != "." ]; do
            probe_target="$(dirname "$probe_target")"
        done

        if [ -d "$probe_target" ]; then
            local free_space
            free_space=$(df -PB 1M "$probe_target" 2>/dev/null | awk 'NR==2 {print $4}' || echo "0")
            if [[ "$free_space" =~ ^[0-9]+$ ]] && [ "$free_space" -gt "$max_free" ]; then
                max_free="$free_space"
                best_dir="$d"
            fi
        fi
    done

    echo "$best_dir/$safe_title"
}

# Detect primary OS platform for AppID via Steam API (returns "windows" or "linux")
detect_app_platform_os() {
    local appid="${1:-}"
    [ -z "$appid" ] && echo "linux" && return 0

    local det_json
    det_json=$(fetch_cached_json "https://store.steampowered.com/api/appdetails?appids=${appid}&filters=platforms" "steam_platforms_${appid}" 3600 2>/dev/null || true)
    local is_linux is_win
    is_linux=$(echo "$det_json" | jq -r ".\"${appid}\".data.platforms.linux // false" 2>/dev/null || echo "false")
    is_win=$(echo "$det_json" | jq -r ".\"${appid}\".data.platforms.windows // false" 2>/dev/null || echo "false")
    if [ "$is_linux" != "true" ] && [ "$is_win" = "true" ]; then
        echo "windows"
    else
        echo "linux"
    fi
}

# Trigger Steam client native installation for AppID via URI protocol
trigger_steam_install() {
    local appid="$1"
    local uri="steam://install/${appid}"

    if [ -n "${GAMECTL_MOCK_STEAM_TRIGGER:-}" ]; then
        echo "[VERIFIED] Triggered Steam installation for AppID $appid (Mocked URI: $uri)."
        return 0
    fi

    if command -v steam >/dev/null 2>&1; then
        if pgrep -x steam >/dev/null 2>&1; then
            echo "[INFO] Steam client is running. Dispatching install command..."
            steam "$uri" >/dev/null 2>&1 &
            echo "[VERIFIED] Dispatched '$uri' to running Steam client."
        else
            echo "[INFO] Steam client is not running. Starting Steam client in background..."
            steam -silent "$uri" >/dev/null 2>&1 &
            echo "[VERIFIED] Launched Steam silently with install intent ($uri)."
        fi
    elif command -v flatpak >/dev/null 2>&1 && flatpak info com.valvesoftware.Steam >/dev/null 2>&1; then
        if pgrep -f com.valvesoftware.Steam >/dev/null 2>&1 || pgrep -x steam >/dev/null 2>&1; then
            echo "[INFO] Steam (Flatpak) is running. Dispatching install command..."
            flatpak run com.valvesoftware.Steam "$uri" >/dev/null 2>&1 &
            echo "[VERIFIED] Dispatched '$uri' to running Steam Flatpak client."
        else
            echo "[INFO] Steam (Flatpak) is not running. Starting Flatpak Steam in background..."
            flatpak run com.valvesoftware.Steam -silent "$uri" >/dev/null 2>&1 &
            echo "[VERIFIED] Launched Steam Flatpak silently with install intent ($uri)."
        fi
    else
        echo "[WARN] Steam executable not found on system PATH." >&2
        echo "[INFO] You can start the download manually by opening: $uri" >&2
    fi
    echo "[INFO] Monitor download progress with: gamectl downloads"
    return 0
}

# Steam Native Game Downloader & Provisioner (SLSsteam-Moon & Standalone CDN Engine)
download_game() {
    local appid="${1:-}"
    # Strip ANSI escape sequences & non-digits
    appid=$(printf "%s" "$appid" | sed -r "s/\x1B\[[0-9;]*[a-zA-Z]//g" | tr -dc "0-9")
    if [ -z "$appid" ]; then
        echo "Usage: gamectl download <appid> [target_dir] [title] [--source <auto|ryuu|sushi|luatools>] [--raw|--inject-only|--all|--standalone|--sls]" >&2
        return 1
    fi
    shift

    local target_dir=""
    local title=""
    local action="all"          # "all", "inject", "raw"
    local source="auto"         # "auto", "ryuu", "sushi", "luatools"
    local engine="standalone"   # Default to Pure Standalone CDN engine (Zero Steam Client)

    while [ $# -gt 0 ]; do
        case "$1" in
            --engine)
                shift
                case "${1:-}" in
                    depot)
                        echo "[WARN] DepotDownloader is deprecated and removed. Routing to native Steam CDN engine." >&2
                        ;;
                    steam|sls)
                        engine="sls"
                        ;;
                    standalone|direct)
                        engine="standalone"
                        ;;
                esac
                ;;
            --engine=*)
                local eng_val="${1#--engine=}"
                case "$eng_val" in
                    depot)
                        echo "[WARN] DepotDownloader is deprecated and removed. Routing to native Steam CDN engine." >&2
                        ;;
                    steam|sls)
                        engine="sls"
                        ;;
                    standalone|direct)
                        engine="standalone"
                        ;;
                esac
                ;;
            --sls|--steam)
                engine="sls"
                ;;
            --direct|--no-steam)
                engine="standalone"
                ;;
            --standalone)
                engine="standalone"
                ;;
            --headless)
                engine="standalone"
                ;;
            --source)
                shift
                source="${1:-auto}"
                ;;
            --source=*)
                source="${1#--source=}"
                ;;
            --raw|--download-only|--no-inject)
                action="raw"
                ;;
            --inject-only|--no-sync)
                action="inject"
                ;;
            --all)
                action="all"
                ;;
            --foreground|-f|foreground|--background|-b|background)
                # Preserved for CLI flag backwards-compatibility
                ;;
            --os|--os=*)
                [ "$1" = "--os" ] && shift
                ;;
            *)
                if [ -z "$target_dir" ]; then
                    target_dir="$1"
                elif [ -z "$title" ]; then
                    title="$1"
                fi
                ;;
        esac
        shift
    done

    if [ -z "$title" ]; then
        title=$(curl -s --connect-timeout 4 "https://store.steampowered.com/api/appdetails?appids=${appid}&filters=basic" | jq -r "."${appid}".data.name // empty" 2>/dev/null || true)
        [ -z "$title" ] && title="AppID_${appid}"
    fi

    # Auto-resolve engine preference
    if [ "$engine" = "auto" ]; then
        if [ "$action" = "inject" ]; then
            engine="sls"
        elif resolve_depot_dl_bin >/dev/null 2>&1; then
            engine="standalone"
        else
            engine="sls"
        fi
    fi

    # Verify standalone binary availability with graceful fallback
    if [ "$engine" = "standalone" ]; then
        local dl_bin
        dl_bin="$(resolve_depot_dl_bin 2>/dev/null || true)"
        if [ -z "$dl_bin" ] || [ ! -x "$dl_bin" ]; then
            echo "[WARN] Standalone downloader binary (gamectl-depot-dl) not found. Falling back to SLSsteam engine." >&2
            engine="sls"
        fi
    fi

    # Route 1: Standalone Native Steam CDN Engine (Zero Steam Client required)
    if [ "$engine" = "standalone" ]; then
        local manifest_zip
        echo "[INFO] Manifest archive not provided. Attempting automatic harvest (source: $source)..." >&2
        manifest_zip=$(fetch_manifest "$appid" "" "$source" 2>/dev/null || true)
        if [ -z "$manifest_zip" ] || [ ! -f "$manifest_zip" ]; then
            echo "[ERROR] Manifest archive for AppID $appid could not be acquired across providers." >&2
            return 1
        fi

        if ! validate_manifest_zip "$manifest_zip" "$appid"; then
            echo "[ERROR] Manifest zip validation failed: $manifest_zip" >&2
            return 1
        fi

        local run_dir="${XDG_RUNTIME_DIR:-/tmp/gamectl-$UID}"
        local stage_dir="$run_dir/depot_dl_${appid}_$$"
        mkdir -p -m 700 "$stage_dir"
        trap 'rm -rf "$stage_dir" 2>/dev/null || true' RETURN

        if ! unzip -q "$manifest_zip" -d "$stage_dir" 2>/dev/null; then
            echo "[ERROR] Failed to unpack manifest archive: $manifest_zip" >&2
            return 1
        fi

        # Integrate any physical DLC manifest archives
        harvest_dlc_manifests "$appid" "$stage_dir" "$source" 2>/dev/null || true

        declare -A depot_keys=()
        shopt -s nullglob globstar
        local cand_luas=("$stage_dir"/**/*.lua "$stage_dir"/*.lua)
        shopt -u nullglob globstar
        local re_key='addappid\([[:space:]]*([0-9]+)[[:space:]]*,[[:space:]]*[0-9]+[[:space:]]*,[[:space:]]*['\''"]([0-9a-fA-F]{64})['\''"]'
        declare -A seen_lua=()
        for clua in "${cand_luas[@]}"; do
            [ -f "$clua" ] || continue
            [[ -v seen_lua["$clua"] ]] && continue
            seen_lua["$clua"]=1
            while IFS= read -r line || [ -n "$line" ]; do
                if [[ "$line" =~ $re_key ]]; then
                    depot_keys["${BASH_REMATCH[1]}"]="${BASH_REMATCH[2]}"
                fi
            done < "$clua"
        done

        local depot_args=()
        shopt -s nullglob globstar
        local mf_files=("$stage_dir"/**/*.manifest "$stage_dir"/*.manifest)
        declare -A seen_mf=()
        for mf in "${mf_files[@]}"; do
            [ -f "$mf" ] || continue
            local mf_name="$(basename "$mf")"
            [[ -v seen_mf["$mf_name"] ]] && continue
            seen_mf["$mf_name"]=1

            if manifest_has_payload_magic "$mf"; then
                if [[ "$mf_name" =~ ^([0-9]+)_([0-9]+)\.manifest$ ]]; then
                    local did="${BASH_REMATCH[1]}"
                    local key="${depot_keys["$did"]:-}"
                    if [ -n "$key" ]; then
                        depot_args+=(--depot "$mf:$key")
                    else
                        echo "[WARN] No AES decryption key found for depot $did ($mf_name). Skipping." >&2
                    fi
                fi
            fi
        done
        shopt -u nullglob globstar

        if [ "${#depot_args[@]}" -eq 0 ]; then
            echo "[WARN] No encrypted manifests with valid AES keys found. Falling back to SLSsteam engine." >&2
            engine="sls"
        else
            if [ -z "$target_dir" ]; then
                target_dir="$(resolve_standalone_library_dir "$title")"
            fi
            mkdir -p "$target_dir"

            echo "=========================================="
            echo " STEAM STANDALONE CDN ENGINE (gamectl-depot-dl)"
            echo "=========================================="
            echo " AppID      : $appid"
            echo " Title      : $title"
            echo " Target Dir : $target_dir"
            echo " Depots     : $(( ${#depot_args[@]} / 2 ))"
            echo " Engine     : Native Rust Standalone (Zero Steam Client)"
            echo "=========================================="

            local dl_bin
            dl_bin="$(resolve_depot_dl_bin)"
            if ! "$dl_bin" --app "$appid" --dir "$target_dir" "${depot_args[@]}"; then
                echo "[ERROR] Standalone CDN download failed." >&2
                return 1
            fi

            # Preserve staged lua manifests in target_dir for offline DLC discovery
            shopt -s nullglob globstar
            for l in "$stage_dir"/**/*.lua "$stage_dir"/*.lua; do
                [ -f "$l" ] && cp -f "$l" "$target_dir/" 2>/dev/null || true
            done
            shopt -u nullglob globstar

            if [ "$action" != "raw" ]; then
                fetch_dlc "$target_dir" "$appid" 2>/dev/null || true
                inject_game "$target_dir" "$appid" --no-sync 2>/dev/null || true
            fi

            echo "[SUCCESS] Standalone download & provisioning complete for $title ($appid) in $target_dir."
            return 0
        fi
    fi

    # Route 2: SLSsteam Native Content Engine (Steam Client URI install)
    echo "=========================================="
    echo " STEAM NATIVE CONTENT ENGINE (SLSsteam-Moon)"
    echo "=========================================="
    echo " AppID      : $appid"
    echo " Title      : $title"
    echo " Engine     : SLSsteam (Valve High-Speed CDN)"
    echo " Source     : $source"
    echo " Mode       : $action"
    echo "=========================================="

    if deploy_sls_manifest "$appid" "" "$title" "$source"; then
        echo "[SUCCESS] SLSsteam manifests and stplug-in keys provisioned for $title ($appid)."
        if [ "$action" != "inject" ]; then
            trigger_steam_install "$appid"
        fi
        return 0
    else
        echo "[ERROR] Manifest archive and keys for AppID $appid could not be acquired across providers." >&2
        return 1
    fi
}
# Locate appmanifest_<appid>.acf across primary and secondary libraries
find_app_acf() {
    local appid="$1"
    [ -z "$appid" ] && return 1

    local primary_apps
    primary_apps="$(get_steam_primary_apps 2>/dev/null || echo "$HOME/.local/share/Steam/steamapps")"
    if [ -f "$primary_apps/appmanifest_${appid}.acf" ]; then
        echo "$primary_apps/appmanifest_${appid}.acf"
        return 0
    fi

    local lib
    while IFS= read -r lib; do
        [ -d "$lib" ] || continue
        if [ -f "$lib/appmanifest_${appid}.acf" ]; then
            echo "$lib/appmanifest_${appid}.acf"
            return 0
        fi
        if [ -f "$lib/steamapps/appmanifest_${appid}.acf" ]; then
            echo "$lib/steamapps/appmanifest_${appid}.acf"
            return 0
        fi
    done < <(get_steam_libraries 2>/dev/null || true)

    return 1
}

# Format byte integer into readable B, KB, MB, GB representation
format_bytes() {
    local b="${1:-0}"
    if [ "$b" -ge 1073741824 ] 2>/dev/null; then
        local gb=$(( b / 1073741824 ))
        local rem=$(( (b % 1073741824) / 104857600 ))
        echo "${gb}.${rem} GB"
    elif [ "$b" -ge 1048576 ] 2>/dev/null; then
        local mb=$(( b / 1048576 ))
        echo "${mb} MB"
    elif [ "$b" -ge 1024 ] 2>/dev/null; then
        local kb=$(( b / 1024 ))
        echo "${kb} KB"
    else
        echo "${b} B"
    fi
}

# Parse Steam appmanifest ACF file for download progress, state, and byte metrics
parse_acf_download_state() {
    local target="$1"
    local acf_file=""
    local appid=""

    if [ -f "$target" ]; then
        acf_file="$target"
    else
        appid=$(printf "%s" "$target" | sed -r "s/\x1B\[[0-9;]*[a-zA-Z]//g" | tr -dc "0-9")
        [ -z "$appid" ] && return 1
        acf_file=$(find_app_acf "$appid" 2>/dev/null || true)
    fi

    if [ -z "$acf_file" ] || [ ! -f "$acf_file" ]; then
        return 1
    fi

    local name="" state_flags="0" bytes_dl="0" bytes_total="0" installdir=""
    local re_appid='^[[:space:]]*"appid"[[:space:]]+"([0-9]+)"'
    local re_name='^[[:space:]]*"name"[[:space:]]+"([^"]+)"'
    local re_flags='^[[:space:]]*"StateFlags"[[:space:]]+"([0-9]+)"'
    local re_bytes_dl='^[[:space:]]*"BytesDownloaded"[[:space:]]+"([0-9]+)"'
    local re_bytes_total='^[[:space:]]*"BytesToDownload"[[:space:]]+"([0-9]+)"'
    local re_installdir='^[[:space:]]*"installdir"[[:space:]]+"([^"]+)"'

    while IFS= read -r line || [ -n "$line" ]; do
        if [[ "$line" =~ $re_appid ]] && [ -z "$appid" ]; then
            appid="${BASH_REMATCH[1]}"
        elif [[ "$line" =~ $re_name ]] && [ -z "$name" ]; then
            name="${BASH_REMATCH[1]}"
        elif [[ "$line" =~ $re_flags ]]; then
            state_flags="${BASH_REMATCH[1]}"
        elif [[ "$line" =~ $re_bytes_dl ]]; then
            bytes_dl="${BASH_REMATCH[1]}"
        elif [[ "$line" =~ $re_bytes_total ]]; then
            bytes_total="${BASH_REMATCH[1]}"
        elif [[ "$line" =~ $re_installdir ]] && [ -z "$installdir" ]; then
            installdir="${BASH_REMATCH[1]}"
        fi
    done < "$acf_file"

    [ -z "$appid" ] && return 1

    local status_str="[UNKNOWN]"
    if [ "$state_flags" -eq 4 ]; then
        status_str="[INSTALLED]"
    elif [ "$state_flags" -eq 512 ] || [ "$state_flags" -eq 514 ] || (( (state_flags & 512) != 0 )); then
        status_str="[PAUSED]"
    elif [ "$state_flags" -eq 1024 ] || [ "$state_flags" -eq 1026 ] || (( (state_flags & 1024) != 0 )); then
        status_str="[DOWNLOADING]"
    elif [ "$state_flags" -eq 2 ] || (( (state_flags & 2) != 0 )); then
        status_str="[UPDATE REQUIRED]"
    fi

    local pct="0%"
    if [ "$bytes_total" -gt 0 ] 2>/dev/null; then
        local calc_pct=$(( (bytes_dl * 100) / bytes_total ))
        [ "$calc_pct" -gt 100 ] && calc_pct=100
        pct="${calc_pct}%"
    elif [ "$state_flags" -eq 4 ]; then
        pct="100%"
    fi

    printf "%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n" \
        "$appid" "$name" "$status_str" "$pct" "$bytes_dl" "$bytes_total" "$state_flags" "$installdir" "$acf_file"
}

# List active and recent downloads
list_downloads() {
    echo "=========================================="
    echo " GAMECTL DOWNLOAD STATUS (Steam Native Engine)"
    echo "=========================================="
    local count=0

    # Inspect Steam Native ACF downloads
    local steam_apps
    steam_apps="$(get_steam_primary_apps 2>/dev/null || echo "$HOME/.local/share/Steam/steamapps")"
    shopt -s nullglob
    local acf_files=("$steam_apps"/appmanifest_*.acf)
    shopt -u nullglob

    for acf in "${acf_files[@]}"; do
        local state_data
        state_data=$(parse_acf_download_state "$acf" 2>/dev/null || true)
        [ -z "$state_data" ] && continue

        local a_id a_title a_status a_pct a_dl a_total a_flags a_dir a_path
        IFS=$'\t' read -r a_id a_title a_status a_pct a_dl a_total a_flags a_dir a_path <<< "$state_data"

        # Only display active downloads or paused/updating apps in download status
        if [ "$a_status" = "[DOWNLOADING]" ] || [ "$a_status" = "[PAUSED]" ] || [ "$a_status" = "[UPDATE REQUIRED]" ]; then
            count=$((count + 1))
            local dl_fmt tot_fmt
            dl_fmt=$(format_bytes "$a_dl")
            tot_fmt=$(format_bytes "$a_total")
            echo "$a_status AppID: $a_id | $a_title | Progress: $a_pct ($dl_fmt / $tot_fmt) [Steam Engine]"
            echo "------------------------------------------"
        fi
    done

    if [ $count -eq 0 ]; then
        echo "[INFO] No active download tasks in Steam client."
    fi
}

# Interactive Download Monitor TUI
list_downloads_interactive() {
    local run_dir="${XDG_RUNTIME_DIR:-/tmp/gamectl-$UID}"
    mkdir -p -m 700 "$run_dir"
    while true; do
        local entries=""
        local total_items=0

        # Scan Steam ACF entries
        local steam_apps
        steam_apps="$(get_steam_primary_apps 2>/dev/null || echo "$HOME/.local/share/Steam/steamapps")"
        shopt -s nullglob
        local acf_files=("$steam_apps"/appmanifest_*.acf)
        shopt -u nullglob

        for acf in "${acf_files[@]}"; do
            local state_data
            state_data=$(parse_acf_download_state "$acf" 2>/dev/null || true)
            [ -z "$state_data" ] && continue

            local a_id a_title a_status a_pct a_dl a_total a_flags a_dir a_path
            IFS=$'\t' read -r a_id a_title a_status a_pct a_dl a_total a_flags a_dir a_path <<< "$state_data"

            if [ "$a_status" = "[DOWNLOADING]" ] || [ "$a_status" = "[PAUSED]" ] || [ "$a_status" = "[UPDATE REQUIRED]" ] || [ "$a_status" = "[INSTALLED]" ]; then
                local ui_status="${UI_ICE}${a_status}${UI_RST}"
                [ "$a_status" = "[DOWNLOADING]" ] && ui_status="${UI_GREEN}[DOWNLOADING ${a_pct}]${UI_RST}"
                [ "$a_status" = "[PAUSED]" ] && ui_status="${UI_PURPLE}[PAUSED ${a_pct}]${UI_RST}"
                [ "$a_status" = "[INSTALLED]" ] && ui_status="${UI_CYAN}[INSTALLED]${UI_RST}"

                local dl_fmt tot_fmt
                dl_fmt=$(format_bytes "$a_dl")
                tot_fmt=$(format_bytes "$a_total")
                local detail="${a_title} (${dl_fmt}/${tot_fmt})"
                entries+="${a_id}\tSteam\t${ui_status}\t${a_pct}\t${detail}\t${a_path}\n"
                total_items=$((total_items + 1))
            fi
        done

        if [ "$total_items" -eq 0 ]; then
            clear
            echo "${UI_BOX}╭─ DOWNLOAD MANAGER (Steam Native) ───────────────────────────╮${UI_RST}"
            echo "│ ${UI_CYAN}No active or recent download tasks found in Steam client.${UI_RST}"
            echo "${UI_BOX}╰─────────────────────────────────────────────────────────────╯${UI_RST}"
            read -r -p "Press [ENTER] to return to Dashboard..."
            return 0
        fi

        local selection fzf_rc=0
        selection=$(printf "%b" "$entries" | fzf \
            --delimiter=$'\t' \
            --with-nth=1,2,3,5 \
            --border-label="  ╢ gamectl :: Download Manager ╟  " \
            --border-label-pos=2 \
            --header="DOWNLOADS (Enter: Actions │ Ctrl-K: Pause │ Esc: Back)" \
            --prompt="Downloads > " \
            --preview="echo -e '\033[38;5;60mSteam AppManifest: {6}\033[0m\n──────────────────────────────────────────'; grep -E '\"(appid|name|StateFlags|BytesDownloaded|BytesToDownload|installdir)\"' {6} 2>/dev/null" \
            --preview-window=right:60%:border-rounded:wrap \
            --bind="ctrl-k:execute(appid={1}; steam \"steam://pause/\$appid\" 2>/dev/null; echo \"[INFO] Dispatched pause to Steam client for AppID \$appid.\"; bash -c 'read -n 1 -s -r -p \"Press any key to continue...\"')" \
        ) || fzf_rc=$?

        [ "$fzf_rc" -eq 130 ] && break
        [ -z "$selection" ] && continue

        if [ -n "$selection" ]; then
            local sel_appid sel_engine sel_status sel_pct sel_title sel_ref
            sel_appid=$(echo "$selection" | awk -F'\t' '{print $1}')
            sel_engine=$(echo "$selection" | awk -F'\t' '{print $2}')
            sel_status=$(echo "$selection" | awk -F'\t' '{print $3}')
            sel_pct=$(echo "$selection" | awk -F'\t' '{print $4}')
            sel_title=$(echo "$selection" | awk -F'\t' '{print $5}')
            sel_ref=$(echo "$selection" | awk -F'\t' '{print $6}')

            clear
            echo "${UI_BOX}╭─ DOWNLOAD ACTIONS: AppID ${UI_BOLD}$sel_appid${UI_RST} $sel_status ─────────────╮${UI_RST}"
            echo "│ ${UI_CYAN}Manifest${UI_RST}: ${UI_DIM}$sel_ref${UI_RST}"
            echo "${UI_BOX}╰─────────────────────────────────────────────────────────────╯${UI_RST}"
            echo "  ${UI_PURPLE}1)${UI_RST} Pause download (steam://pause/$sel_appid)"
            echo "  ${UI_PURPLE}2)${UI_RST} Resume download (steam://resume/$sel_appid)"
            echo "  ${UI_PURPLE}3)${UI_RST} Inject Standalone GBE Fork LAN runtime"
            echo "  ${UI_DIM}4)${UI_RST} Return to download list"
            echo
            read -r -p "Select option [1-4]: " dl_opt

            case "$dl_opt" in
                1)
                    if command -v steam >/dev/null 2>&1; then
                        steam "steam://pause/$sel_appid" >/dev/null 2>&1 &
                        echo "  ${UI_GREEN}[SUCCESS] Dispatched steam://pause/$sel_appid${UI_RST}"
                    else
                        echo "  [WARN] Steam executable not found on PATH."
                    fi
                    read -r -p "Press [ENTER] to continue..."
                    ;;
                2)
                    if command -v steam >/dev/null 2>&1; then
                        steam "steam://resume/$sel_appid" >/dev/null 2>&1 &
                        echo "  ${UI_GREEN}[SUCCESS] Dispatched steam://resume/$sel_appid${UI_RST}"
                    else
                        echo "  [WARN] Steam executable not found on PATH."
                    fi
                    read -r -p "Press [ENTER] to continue..."
                    ;;
                3)
                    local g_dir
                    g_dir="$(dirname "$sel_ref")/common/$(grep -m1 '"installdir"' "$sel_ref" 2>/dev/null | awk -F'"' '{print $4}')"
                    if [ -d "$g_dir" ]; then
                        echo "[INFO] Injecting GBE Fork LAN runtime into: $g_dir"
                        "$SELF_BIN" inject "$g_dir" "$sel_appid"
                    else
                        echo "  [WARN] Game common directory does not exist yet: $g_dir"
                        echo "  [INFO] Please wait until the download finishes in Steam."
                    fi
                    read -r -p "Press [ENTER] to continue..."
                    ;;
                *)
                    ;;
            esac
        fi
    done
}
# Dual-Mode Steam Client & SLSsteam Full DLC Sync
sync_steam() {
    local appid="$1"
    local title="${2:-}"
    local game_dir="${3:-}"

    # Strip ANSI escape sequences
    appid=$(printf "%s" "$appid" | sed -r 's/\x1B\[[0-9;]*[a-zA-Z]//g' | tr -dc '0-9')
    title=$(printf "%s" "$title" | sed -r 's/\x1B\[[0-9;]*[a-zA-Z]//g')

    if [ -z "$appid" ] || [ "$appid" = "STANDALONE" ]; then
        echo "[WARN] Invalid numeric AppID. Skipping Steam synchronization." >&2
        return 0
    fi

    if [ -z "$title" ]; then
        title="AppID_${appid}"
    fi

    local safe_title
    safe_title=$(echo "$title" | tr -cd '[:alnum:] _-')
    [ -z "$safe_title" ] && safe_title="$appid"

    echo "[INFO] Synchronizing Steam Client & SLSsteam for: $title ($appid)..."

    # 1. Fetch DLC mapping via Steam API
    local dlc_json
    dlc_json=$(curl -s --connect-timeout 4 "https://store.steampowered.com/api/dlcforapp/?appid=${appid}" 2>/dev/null || echo "{}")

    # 2. Update ~/.config/SLSsteam/config.yaml using ruamel.yaml
    local sls_cfg="$(get_sls_root 2>/dev/null || echo "$HOME/.config/SLSsteam")/config.yaml"
    if [ -f "$sls_cfg" ]; then
        python3 -c "
import sys, json

cfg_path = sys.argv[1]
appid = int(sys.argv[2])
dlc_raw = sys.argv[3]

has_ruamel = False
try:
    from ruamel.yaml import YAML
    yaml_engine = YAML()
    yaml_engine.preserve_quotes = True
    has_ruamel = True
except Exception:
    try:
        import yaml as pyyaml
    except Exception:
        print('[ERROR] No YAML library found in Python (ruamel.yaml or pyyaml)', file=sys.stderr)
        sys.exit(1)

try:
    with open(cfg_path, 'r') as f:
        if has_ruamel:
            data = yaml_engine.load(f) or {}
        else:
            data = pyyaml.safe_load(f) or {}

    if 'AppIds' not in data or data['AppIds'] is None:
        data['AppIds'] = []
    if appid not in data['AppIds']:
        data['AppIds'].append(appid)

    if 'AdditionalApps' not in data or data['AdditionalApps'] is None:
        data['AdditionalApps'] = []
    if appid not in data['AdditionalApps']:
        data['AdditionalApps'].append(appid)

    dlc_obj = json.loads(dlc_raw)
    dlc_list = dlc_obj.get('dlc', [])
    if dlc_list:
        if 'DlcData' not in data or data['DlcData'] is None:
            data['DlcData'] = {}
        if appid not in data['DlcData'] or data['DlcData'][appid] is None:
            data['DlcData'][appid] = {}
        for item in dlc_list:
            d_id = int(item['id'])
            d_name = item.get('name', f'DLC {d_id}')
            data['DlcData'][appid][d_id] = d_name

    with open(cfg_path, 'w') as f:
        if has_ruamel:
            yaml_engine.dump(data, f)
        else:
            pyyaml.dump(data, f, default_flow_style=False, sort_keys=False)
    engine_name = 'ruamel.yaml' if has_ruamel else 'pyyaml (fallback)'
    print(f'[VERIFIED] SLSsteam config.yaml: AppID {appid} and {len(dlc_list)} DLC(s) registered ({engine_name}).')
except Exception as e:
    print(f'[WARN] SLSsteam config sync notice: {e}', file=sys.stderr)
" "$sls_cfg" "$appid" "$dlc_json" 2>/dev/null || true
    fi

    # 2b. Guarantee stplug-in Lua script has addappid($appid) entitlement
    local stplug_dir
    stplug_dir="$(get_steam_stplug_in_dir 2>/dev/null || echo "$HOME/.local/share/Steam/config/stplug-in")"
    if [ -d "$stplug_dir" ]; then
        local target_lua="$stplug_dir/${appid}.lua"
        if [ -f "$target_lua" ]; then
            if ! grep -Eq "^[[:space:]]*addappid[[:space:]]*\([[:space:]]*${appid}[[:space:]]*\)" "$target_lua"; then
                sed -i "1i addappid(${appid})" "$target_lua"
            fi
        else
            printf "addappid(%s)\n" "$appid" > "$target_lua"
            chmod 600 "$target_lua"
        fi
    fi

    # 3. Create appmanifest_<appid>.acf in Steam steamapps (unless --no-acf requested)
    if [ "${game_dir:-}" = "--no-acf" ] || [ "${4:-}" = "--no-acf" ]; then
        return 0
    fi

    local steam_apps
    steam_apps="$(get_steam_primary_apps)"
    if [ -d "$steam_apps" ]; then
        # Guard against concurrent Steam client memory lock on manifests
        check_steam_active "Writing appmanifest_${appid}.acf" || true

        local acf_file="$steam_apps/appmanifest_${appid}.acf"
        local install_name="$safe_title"
        local size_bytes="1000000000"
        local steamid
        steamid=$(resolve_active_steamid)

        if [ -n "$game_dir" ] && [ -d "$game_dir" ]; then
            install_name="$(basename "$game_dir")"
            local calc_sz
            calc_sz=$(du -sb "$game_dir" 2>/dev/null | awk '{print $1}')
            [ -n "$calc_sz" ] && [ "$calc_sz" -gt 0 ] && size_bytes="$calc_sz"
        fi

        cat <<ACF > "$acf_file"
"AppState"
{
	"appid"		"$appid"
	"Universe"		"1"
	"name"		"$safe_title"
	"StateFlags"		"4"
	"installdir"		"$install_name"
	"LastUpdated"		"$(date +%s)"
	"SizeOnDisk"		"$size_bytes"
	"buildid"		"1"
	"LastOwner"		"$steamid"
	"UserConfig"
	{
		"language"		"english"
	}
	"MountedConfig"
	{
		"language"		"english"
	}
}
ACF
        # Symlink in steamapps/common if game_dir is external, or ensure install dir exists
        mkdir -p "$steam_apps/common"
        if [ -n "$game_dir" ] && [ -d "$game_dir" ]; then
            local common_target="$steam_apps/common/$install_name"
            if [ ! -e "$common_target" ]; then
                ln -sf "$game_dir" "$common_target"
                echo "[INFO] Created common symlink: $common_target -> $game_dir"
            fi
        else
            mkdir -p "$steam_apps/common/$install_name"
        fi
        echo "[VERIFIED] appmanifest_${appid}.acf registered (Status: Installed in Steam, Size: $size_bytes bytes)."
    fi
}

# Entitle game and adopt assets in official Steam client without downloading
unlock_game() {
    local appid="${1:-}"
    local title="${2:-}"

    if [ -z "$appid" ]; then
        echo "Usage: gamectl entitle <appid> [title] (aliases: unlock, adopt-steam)" >&2
        return 1
    fi

    if [ -z "$title" ]; then
        echo "[INFO] Fetching game title for AppID $appid from Steam Store API..."
        title=$(curl -s --connect-timeout 4 "https://store.steampowered.com/api/appdetails?appids=${appid}&filters=basic" | jq -r ".\"${appid}\".data.name // empty" 2>/dev/null || true)
        [ -z "$title" ] && title="AppID_${appid}"
    fi

    echo "${UI_BOX}╭─ STEAM ENTITLEMENT & ACF ADOPTION ENGINE ───────────────────╮${UI_RST}"
    echo "│ ${UI_CYAN}Target Game${UI_RST}: ${UI_BOLD}$title${UI_RST} ${UI_DIM}(AppID: $appid)${UI_RST}"
    echo "│ ${UI_DIM}Adopts local files, community Steam Input & Vulkan shader caching${UI_RST}"
    echo "${UI_BOX}╰─────────────────────────────────────────────────────────────╯${UI_RST}"

    sync_steam "$appid" "$title" ""
    echo "  ${UI_GREEN}[SUCCESS] Game '$title' ($appid) entitled in Steam Client with Full DLC & ACF manifest.${UI_RST}"
}

# Aliases for entitlement engine
entitle_game() { unlock_game "$@"; }
adopt_steam() { unlock_game "$@"; }

# Interactive Steam Entitlement & ACF Adoption Wizard
unlock_interactive() {
    local u_appid_raw="" fzf_rc=0
    u_appid_raw=$(: | fzf \
        --print-query \
        --border-label="  ╢ Steam Entitlement & ACF Adoption Wizard ╟  " \
        --border-label-pos=2 \
        --header="Enter numeric AppID (Enter: Adopt │ Esc: Cancel)" \
        --prompt="Steam AppID > " \
        --height=20% \
        --reverse 2>/dev/null) || fzf_rc=$?

    # Only abort if user cancelled via ESC or Ctrl-C (exit status 130)
    [ "$fzf_rc" -eq 130 ] && return 0

    local u_appid
    u_appid=$(echo "$u_appid_raw" | head -n 1 | tr -d '[:space:]')
    [ -z "$u_appid" ] && return 0

    if [[ ! "$u_appid" =~ ^[0-9]+$ ]]; then
        echo "  ${UI_RED}[ERROR] AppID must be numeric characters (e.g. 105600).${UI_RST}"
        sleep 1.5
        return 1
    fi

    echo "  [INFO] Fetching title from Steam Store API for AppID $u_appid..."
    local u_title
    u_title=$(curl -s --connect-timeout 4 "https://store.steampowered.com/api/appdetails?appids=${u_appid}&filters=basic" | jq -r ".\"${u_appid}\".data.name // empty" 2>/dev/null || true)
    [ -z "$u_title" ] && u_title="AppID_${u_appid}"

    echo "  Registering: $u_title ($u_appid)..."
    unlock_game "$u_appid" "$u_title"
    sleep 1.2
}

entitle_interactive() { unlock_interactive "$@"; }


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
            -d "$(jq -nc --arg code "$code" '{code:$code}')" 2>/dev/null || true)

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
            -d "$(jq -nc --arg th "$token_hash" '{type:"magiclink",token_hash:$th}')" 2>/dev/null || true)

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
            -d "$(jq -nc --arg rt "$input" '{refresh_token:$rt}')" 2>/dev/null || true)

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
        echo "  • Public providers (ManifestHub, Ryuu, Sushi) are ACTIVE (Zero login required)."
        echo "  • To unlock LuaTools provider: gamectl login-luatools <6-character-code | token>"
    fi
}

# Interactive TUI Wizard for LuaTools Authentication
login_luatools_interactive() {
    require_tui "LuaTools Authentication" || return $?

    local cfg_auth="$HOME/.config/gamectl/lua_tools_auth.json"
    mkdir -p "$HOME/.config/gamectl"

    while true; do
        local status_desc="Not Configured"
        local user_name=""
        if [ -f "$cfg_auth" ]; then
            user_name=$(jq -r '.user.user_metadata.custom_claims.global_name // .user.user_metadata.full_name // .user.email // "Authenticated"' "$cfg_auth" 2>/dev/null || echo "Authenticated")
            status_desc="ACTIVE ($user_name)"
        fi

        local lt_menu
        lt_menu=$(cat <<EOF
1	Login via Discord (/login)	Join discord.gg/luatools -> type /login in bot chat -> enter 6-char code
2	Auto-Detect & Sync from Lumen	Import active session from Lumen client directory (~/.local/share/Lumen)
3	Open Discord Server in Browser	Launch https://discord.gg/luatools in default browser
4	Advanced: Manual Token / File	Paste refresh token or import custom JSON session file
5	Clear Session / Logout	Remove active session and deactivate provider
6	Check Session Status	View identity, token lifetime & provider health
7	Return / Back	Back
EOF
)

        flush_tty_input
        local sel rc=0
        sel=$(echo "$lt_menu" | fzf \
            --delimiter=$'\t' \
            --with-nth=2,3 \
            --border-label="  ╢ LuaTools Session Auth :: $status_desc ╟  " \
            --border-label-pos=2 \
            --header="LUATOOLS DISCORD AUTH (Enter: Select │ Esc: Return)" \
            --prompt="LuaTools > " \
            --reverse 2>/dev/null) || rc=$?

        check_fzf_status "$rc" || return $?
        [ "$rc" -eq 130 ] && break
        [ -z "$sel" ] && continue

        local opt
        opt=$(echo "$sel" | cut -f1 | tr -d '[:space:]')

        case "$opt" in
            1)
                local code rc=0
                code=$(tui_prompt_input "Discord Bot Login (/login)" $'1. Di server Discord (discord.gg/luatools), ketik: /login di #bot-spam\n2. Masukkan 6-karakter kode bot di bawah (atau ketik "open" untuk buka Discord):' "" "Code > ") || rc=$?
                [ "$rc" -eq 130 ] && continue
                [ "$rc" -ne 0 ] && return "$rc"
                code=$(echo "$code" | tr -d '[:space:]')
                if [ "${code,,}" = "open" ]; then
                    xdg-open "https://discord.gg/luatools" 2>/dev/null || sensible-browser "https://discord.gg/luatools" 2>/dev/null || true
                    continue
                fi
                if [ -n "$code" ]; then
                    tui_exec_action "LuaTools Discord Code Redeem" login_luatools "$code"
                fi
                ;;
            2)
                local lumen_candidates=(
                    "${XDG_DATA_HOME:-$HOME/.local/share}/Lumen/luatools/backend/data/lua_tools_auth.json"
                    "$HOME/.config/Lumen/luatools/backend/data/lua_tools_auth.json"
                    "$HOME/.local/share/Lumen/backend/data/lua_tools_auth.json"
                    "$HOME/.config/Lumen/backend/data/lua_tools_auth.json"
                )
                local found_lumen=""
                for cand in "${lumen_candidates[@]}"; do
                    if [ -f "$cand" ]; then
                        found_lumen="$cand"
                        break
                    fi
                done
                if [ -n "$found_lumen" ]; then
                    tui_exec_action "Import Lumen Session" login_luatools "$found_lumen"
                else
                    tui_modal_notice "Lumen Auto-Sync" "No Lumen session file found on this system.\nUse Option 1 to login with Discord /login code."
                fi
                ;;
            3)
                xdg-open "https://discord.gg/luatools" 2>/dev/null || sensible-browser "https://discord.gg/luatools" 2>/dev/null || true
                tui_modal_notice "Discord Server" "Opened https://discord.gg/luatools in your default browser.\nType /login in #bot-spam or any bot channel to get your 6-character code."
                ;;
            4)
                local adv_menu
                adv_menu=$(cat <<EOF
1	Login with Refresh Token	Paste raw refresh token / JWT string
2	Import session.json File	Specify custom filesystem path to session.json
3	Back	Return
EOF
)
                flush_tty_input
                local a_sel a_rc=0
                a_sel=$(echo "$adv_menu" | fzf \
                    --delimiter=$'\t' \
                    --with-nth=2 \
                    --border-label="  ╢ Advanced Authentication ╟  " \
                    --border-label-pos=2 \
                    --header="MANUAL AUTH (Enter: Select │ Esc: Return)" \
                    --prompt="Manual > " \
                    --reverse 2>/dev/null) || a_rc=$?
                check_fzf_status "$a_rc" || return $?
                [ "$a_rc" -eq 130 ] && continue
                local a_opt
                a_opt=$(echo "$a_sel" | cut -f1 | tr -d '[:space:]')
                if [ "$a_opt" = "1" ]; then
                    local tok rc=0
                    tok=$(tui_prompt_input "LuaTools Refresh Token" "Paste refresh token string (Enter: Submit │ Esc: Cancel)" "" "Token > ") || rc=$?
                    [ "$rc" -eq 130 ] && continue
                    [ "$rc" -ne 0 ] && return "$rc"
                    tok=$(echo "$tok" | tr -d '[:space:]')
                    [ -n "$tok" ] && tui_exec_action "LuaTools Token Exchange" login_luatools "$tok"
                elif [ "$a_opt" = "2" ]; then
                    local fpath rc=0
                    fpath=$(tui_prompt_input "Import session.json File" "Enter filesystem path to session.json (Enter: Import │ Esc: Cancel)" "" "File Path > ") || rc=$?
                    [ "$rc" -eq 130 ] && continue
                    [ "$rc" -ne 0 ] && return "$rc"
                    fpath=$(echo "$fpath" | tr -d '[:space:]')
                    [ -n "$fpath" ] && tui_exec_action "Import LuaTools Session" login_luatools "$fpath"
                fi
                ;;
            5)
                if [ -f "$cfg_auth" ]; then
                    rm -f "$cfg_auth"
                    tui_modal_notice "LuaTools Session" "Session file removed from ~/.config/gamectl/lua_tools_auth.json.\nLuaTools provider is now deactivated."
                else
                    tui_modal_notice "LuaTools Session" "No active session file found in ~/.config/gamectl/lua_tools_auth.json."
                fi
                ;;
            6)
                tui_exec_action "LuaTools Session Status" luatools_status
                ;;
            7|*)
                break
                ;;
        esac
    done
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


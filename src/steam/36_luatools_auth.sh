# ==============================================================================
# LuaTools Authentication Session, Token Auto-Refresh & Interactive Wizard
# ==============================================================================

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

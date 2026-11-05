# Generate a valid 17-digit SteamID64 for individual accounts (76561197960265728 + 31-bit random int)
generate_steamid64() {
    local base=76561197960265728
    local rand=""
    if [ -r /dev/urandom ] && command -v od >/dev/null 2>&1; then
        local raw
        raw=$(od -An -N4 -tu4 /dev/urandom 2>/dev/null | tr -d ' ')
        if [ -n "$raw" ] && [ "$raw" -gt 0 ] 2>/dev/null; then
            rand=$(( raw % 2000000000 + 100000 ))
        fi
    fi
    if [ -z "$rand" ]; then
        local r1=$(( (RANDOM << 16) | RANDOM ))
        rand=$(( (r1 & 0x7FFFFFFF) % 2000000000 + 100000 ))
    fi
    echo $(( base + rand ))
}

# Hierarchical SteamID64 resolver (Env -> Persona -> Steam client active user -> random SteamID64)
resolve_active_steamid() {
    # Priority 1: Environment override
    if [ -n "${GAMECTL_STEAMID:-}" ] && [[ "$GAMECTL_STEAMID" =~ ^7656119[0-9]{10}$ ]]; then
        echo "$GAMECTL_STEAMID"
        return 0
    fi

    # Priority 2: Global persona configuration
    if [ -f "$HOME/.config/gamectl/persona" ]; then
        local p_id
        p_id=$(grep -E '^[[:space:]]*account_steamid[[:space:]]*=' "$HOME/.config/gamectl/persona" 2>/dev/null | head -n 1 | sed -E 's/^[[:space:]]*account_steamid[[:space:]]*=[[:space:]]*//' | tr -d '\r[:space:]')
        if [ -n "$p_id" ] && [[ "$p_id" =~ ^7656119[0-9]{10}$ ]]; then
            echo "$p_id"
            return 0
        fi
    fi

    # Priority 3: Active Steam client login
    local s_roots=(
        "$HOME/.local/share/Steam"
        "$HOME/.steam/steam"
        "$HOME/.steam/root"
        "$HOME/.var/app/com.valvesoftware.Steam/.local/share/Steam"
        "$HOME/snap/steam/common/.local/share/Steam"
    )
    for s_root in "${s_roots[@]}"; do
        local vdf="$s_root/config/loginusers.vdf"
        if [ -f "$vdf" ]; then
            local sid
            sid=$(grep -E '^[[:space:]]*"7656119[0-9]{10}"' "$vdf" 2>/dev/null | head -n 1 | tr -dc '0-9')
            if [ -n "$sid" ] && [ ${#sid} -eq 17 ]; then
                echo "$sid"
                return 0
            fi
        fi

        if [ -d "$s_root/userdata" ]; then
            local udir
            for udir in "$s_root/userdata"/*; do
                [ -d "$udir" ] || continue
                local u_id
                u_id=$(basename "$udir")
                if [[ "$u_id" =~ ^[0-9]+$ ]] && [ "$u_id" -gt 0 ] 2>/dev/null; then
                    local sid64=$(( 76561197960265728 + u_id ))
                    if [[ "$sid64" =~ ^7656119[0-9]{10}$ ]]; then
                        echo "$sid64"
                        return 0
                    fi
                fi
            done
        fi
    done

    # Priority 4: Dynamic random SteamID64
    generate_steamid64
}

# Resolve game LAN persona (account_name, account_steamid, language)
get_game_persona() {
    local gdir="$1"
    local p_name=""
    local p_id=""
    local p_lang="english"

    if [ -f "$gdir/steam_settings/configs.user.ini" ]; then
        p_name=$(grep -E '^[[:space:]]*account_name[[:space:]]*=' "$gdir/steam_settings/configs.user.ini" 2>/dev/null | head -n 1 | sed -E 's/^[[:space:]]*account_name[[:space:]]*=[[:space:]]*//' | tr -d '\r')
        p_id=$(grep -E '^[[:space:]]*account_steamid[[:space:]]*=' "$gdir/steam_settings/configs.user.ini" 2>/dev/null | head -n 1 | sed -E 's/^[[:space:]]*account_steamid[[:space:]]*=[[:space:]]*//' | tr -d '\r')
        p_lang=$(grep -E '^[[:space:]]*language[[:space:]]*=' "$gdir/steam_settings/configs.user.ini" 2>/dev/null | head -n 1 | sed -E 's/^[[:space:]]*language[[:space:]]*=[[:space:]]*//' | tr -d '\r')
    fi

    if [ -z "$p_name" ] && [ -f "$HOME/.config/gamectl/persona" ]; then
        p_name=$(grep -E '^[[:space:]]*account_name[[:space:]]*=' "$HOME/.config/gamectl/persona" 2>/dev/null | head -n 1 | sed -E 's/^[[:space:]]*account_name[[:space:]]*=[[:space:]]*//' | tr -d '\r')
    fi
    if [ -z "$p_id" ] && [ -f "$HOME/.config/gamectl/persona" ]; then
        p_id=$(grep -E '^[[:space:]]*account_steamid[[:space:]]*=' "$HOME/.config/gamectl/persona" 2>/dev/null | head -n 1 | sed -E 's/^[[:space:]]*account_steamid[[:space:]]*=[[:space:]]*//' | tr -d '\r')
    fi

    [ -z "$p_name" ] && p_name="${USER:-Player}"
    [ -z "$p_id" ] && p_id=$(resolve_active_steamid)
    [ -z "$p_lang" ] && p_lang="english"

    echo "$p_name|$p_id|$p_lang"
}


# Set LAN Player Name, SteamID, and broadcast IPs for GBE Fork co-op
set_id() {
    local player_name="${1:-}"
    shift || true

    if [ -z "$player_name" ]; then
        echo "Usage: gamectl set-id <player_name> [steamid] [target_dir] [--broadcast <ip>] [--global]" >&2
        return 1
    fi

    local steamid=""
    local target_dir=""
    local broadcast_ips=()
    local save_global=false

    while [ $# -gt 0 ]; do
        case "$1" in
            --global)
                save_global=true
                shift
                ;;
            --broadcast)
                if [ -n "${2:-}" ]; then
                    broadcast_ips+=("$2")
                    shift 2
                else
                    shift
                fi
                ;;
            --broadcast=*)
                broadcast_ips+=("${1#*=}")
                shift
                ;;
            *)
                if [ -z "$steamid" ] && { [[ "$1" =~ ^7656119[0-9]{10}$ ]] || [ "$1" = "auto" ] || [ "$1" = "random" ]; }; then
                    if [ "$1" = "auto" ] || [ "$1" = "random" ]; then
                        steamid=$(generate_steamid64)
                    else
                        steamid="$1"
                    fi
                elif [ -z "$target_dir" ] && [ -d "$1" ]; then
                    target_dir="$1"
                elif [ -z "$steamid" ] && [[ "$1" =~ ^[0-9]+$ ]] && [ ${#1} -eq 17 ]; then
                    steamid="$1"
                else
                    if [ -z "$target_dir" ]; then
                        target_dir="$1"
                    fi
                fi
                shift
                ;;
        esac
    done

    # Generate steamid if still empty
    if [ -z "$steamid" ]; then
        steamid=$(generate_steamid64)
    fi

    # Determine target directory
    if [ -z "$target_dir" ]; then
        if [ -d "./steam_settings" ] || [ -f "./steam_appid.txt" ]; then
            target_dir="."
        else
            save_global=true
        fi
    fi

    # Save to global config if requested or if no game directory identified
    if [ "$save_global" = true ]; then
        mkdir -p "$HOME/.config/gamectl"
        cat <<EOF > "$HOME/.config/gamectl/persona"
# gamectl global persona
account_name=$player_name
account_steamid=$steamid
language=english
EOF
        echo "[INFO] Global persona saved to ~/.config/gamectl/persona ($player_name | $steamid)"
    fi

    if [ -n "$target_dir" ] && [ -d "$target_dir" ]; then
        target_dir="$(cd "$target_dir" && pwd)"
        mkdir -p "$target_dir/steam_settings"

        local ini_file="$target_dir/steam_settings/configs.user.ini"
        if [ -f "$ini_file" ]; then
            if grep -q -E '^[[:space:]]*account_name[[:space:]]*=' "$ini_file"; then
                sed -i -E "s/^[[:space:]]*account_name[[:space:]]*=.*/account_name=$player_name/" "$ini_file"
            else
                echo "account_name=$player_name" >> "$ini_file"
            fi
            if grep -q -E '^[[:space:]]*account_steamid[[:space:]]*=' "$ini_file"; then
                sed -i -E "s/^[[:space:]]*account_steamid[[:space:]]*=.*/account_steamid=$steamid/" "$ini_file"
            else
                echo "account_steamid=$steamid" >> "$ini_file"
            fi
        else
            cat <<EOF > "$ini_file"
[user::general]
account_name=$player_name
account_steamid=$steamid
language=english

[user::saves]
local_save_path=./saves
EOF
        fi

        # Handle custom_broadcasts.txt
        local bc_file="$target_dir/steam_settings/custom_broadcasts.txt"
        if [ ! -f "$bc_file" ]; then
            cat <<EOF > "$bc_file"
# GBE Fork LAN Custom Broadcast IP list
# Add peer IPs or broadcast subnets (one IP per line)
127.0.0.1
255.255.255.255
EOF
        fi

        if [ ${#broadcast_ips[@]} -gt 0 ]; then
            for ip in "${broadcast_ips[@]}"; do
                IFS=',' read -ra split_ips <<< "$ip"
                for s_ip in "${split_ips[@]}"; do
                    s_ip=$(echo "$s_ip" | tr -d ' ')
                    [ -z "$s_ip" ] && continue
                    if ! grep -q -F "$s_ip" "$bc_file" 2>/dev/null; then
                        echo "$s_ip" >> "$bc_file"
                        echo "[INFO] Added broadcast IP: $s_ip"
                    fi
                done
            done
        fi

        # Ensure symlinks to subfolders if shim exists in subdirectory
        for shim_candidate in "$target_dir"/*/*.dll "$target_dir"/*/*/*.dll "$target_dir"/*/*.so "$target_dir"/*/*/*.so; do
            if [ -f "$shim_candidate" ]; then
                local s_dir
                s_dir="$(dirname "$shim_candidate")"
                if [ "$s_dir" != "$target_dir" ] && [ -d "$s_dir" ]; then
                    ln -sfn "$target_dir/steam_settings" "$s_dir/steam_settings" 2>/dev/null || true
                fi
            fi
        done

        echo "[VERIFIED] Game LAN identity updated in $target_dir:"
        echo "           Player Name : $player_name"
        echo "           SteamID64   : $steamid"
        echo "           Config File : $ini_file"
        local is_gbe_check=false
        for api_c in "$target_dir/libsteam_api.so" "$target_dir/lib64/libsteam_api.so" "$target_dir/steam_api64.dll" "$target_dir/steam_api.dll"; do
            if [ -f "$api_c" ]; then
                local sz
                sz=$(stat -c%s "$api_c" 2>/dev/null || echo 0)
                [ "$sz" -gt 7000000 ] && is_gbe_check=true && break
            fi
        done
        if [ "$is_gbe_check" = false ]; then
            echo "           Note        : Game is not injected with GBE Fork yet. Press <CTRL-I> to enable."
        fi
    fi
}

# Interactive TUI configurator for LAN persona & SteamID
set_id_interactive() {
    local target_dir="${1:-}"
    local title="${2:-}"
    if [ -z "$target_dir" ] || [ ! -d "$target_dir" ]; then
        echo "[ERROR] Invalid game directory: $target_dir" >&2
        return 1
    fi
    target_dir="$(cd "$target_dir" && pwd)"
    [ -z "$title" ] && title="$(basename "$target_dir")"

    local p_info
    p_info=$(get_game_persona "$target_dir")
    local cur_name cur_id cur_lang
    cur_name=$(echo "$p_info" | cut -d'|' -f1)
    cur_id=$(echo "$p_info" | cut -d'|' -f2)
    cur_lang=$(echo "$p_info" | cut -d'|' -f3)

    local is_gbe=false
    local api_cand
    for api_cand in "$target_dir/libsteam_api.so" "$target_dir/lib64/libsteam_api.so" "$target_dir/steam_api64.dll" "$target_dir/steam_api.dll"; do
        if [ -f "$api_cand" ]; then
            local sz
            sz=$(stat -c%s "$api_cand" 2>/dev/null || echo 0)
            if [ "$sz" -gt 7000000 ]; then
                is_gbe=true
                break
            fi
        fi
    done
    if [ "$is_gbe" = false ]; then
        local deep_api
        deep_api=$(find "$target_dir" -maxdepth 3 \( -name "libsteam_api.so" -o -name "steam_api64.dll" -o -name "steam_api.dll" \) 2>/dev/null | head -n 1)
        if [ -n "$deep_api" ]; then
            local sz
            sz=$(stat -c%s "$deep_api" 2>/dev/null || echo 0)
            [ "$sz" -gt 7000000 ] && is_gbe=true
        fi
    fi

    echo
    echo "${UI_BOX}╭─ CONFIGURE LAN IDENTITY & STEAMID (GBE FORK) ───────────────╮${UI_RST}"
    echo "│ ${UI_CYAN}Target Game  ${UI_RST}: ${UI_BOLD}$title${UI_RST}"
    echo "│ ${UI_CYAN}Directory    ${UI_RST}: ${UI_DIM}$target_dir${UI_RST}"
    echo "│ ${UI_CYAN}Player Name  ${UI_RST}: ${UI_BOLD}${cur_name:-[Unset]}${UI_RST}"
    echo "│ ${UI_CYAN}SteamID64    ${UI_RST}: ${UI_BOLD}${cur_id:-[Unset]}${UI_RST}"
    echo "${UI_BOX}╰─────────────────────────────────────────────────────────────╯${UI_RST}"

    if [ "$is_gbe" = false ]; then
        echo "  ${UI_AMBER}[NOTE] This game is not injected with GBE Fork yet.${UI_RST}"
        echo "         Persona will be saved to steam_settings/configs.user.ini"
        echo "         and activates automatically once injected (<CTRL-I>)."
        echo
    fi

    echo -n "  Player Name [${cur_name:-Player}]: "; read -r in_name
    [ -z "$in_name" ] && in_name="$cur_name"
    [ -z "$in_name" ] && in_name="${USER:-Player}"

    local suggested_id
    suggested_id=$(generate_steamid64)
    echo -n "  SteamID64 ('gen' or 'random' to generate) [${cur_id:-$suggested_id}]: "; read -r in_id
    [ -z "$in_id" ] && in_id="${cur_id:-$suggested_id}"
    if [ "$in_id" = "random" ] || [ "$in_id" = "auto" ] || [ "$in_id" = "gen" ]; then
        in_id=$(generate_steamid64)
    fi

    echo
    echo "  LAN Custom Broadcast Peers (Optional):"
    echo "  Enter friend's LAN IP (e.g. 192.168.1.50) or press Enter to skip."
    echo -n "  Peer/Broadcast IP: "; read -r in_bc

    echo -n "  Also save as global default persona? (y/N): "; read -r in_glob

    local extra_args=()
    [ -n "$in_bc" ] && extra_args+=(--broadcast "$in_bc")
    case "$in_glob" in
        y|Y|yes|YES) extra_args+=(--global) ;;
    esac

    set_id "$in_name" "$in_id" "$target_dir" "${extra_args[@]}"
    echo
    read -r -p "Press [ENTER] to return to Library..."
}


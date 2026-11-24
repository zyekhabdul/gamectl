# Setup local P2P compatibility and mod DLL overrides without Steam registration.
setup_onlinefix() {
    local gdir="${1:-}"
    shift || true
    local auto_yes=false
    while [ $# -gt 0 ]; do
        case "$1" in
            -y|--yes|--non-interactive) auto_yes=true; shift ;;
            *) shift ;;
        esac
    done

    if [ -z "$gdir" ] || [ ! -d "$gdir" ]; then
        echo "[ERROR] Game directory not found: $gdir" >&2
        return 1
    fi
    gdir="$(cd "$gdir" && pwd)"

    echo "[INFO] Running local OnlineFix compatibility setup in: $gdir..."

    # 1. Discover OnlineFix signature files
    local of_files
    of_files=$(find "$gdir" -maxdepth 3 \( -name "pfx" -o -name ".git" -o -name ".save_snapshots" -o -name "saves" \) -prune -o \( \
        -iname "OnlineFix64.dll" -o -iname "OnlineFix.dll" -o -iname "OnlineFix.ini" -o \
        -iname "dnet.dll" -o -iname "SteamOverlay64.dll" \
    \) -print 2>/dev/null || true)

    if [ -z "$of_files" ]; then
        echo "[WARN] No OnlineFix signatures found in this game directory." >&2
        echo "       Neither OnlineFix64.dll, OnlineFix.dll, nor OnlineFix.ini was found." >&2
        return 1
    fi
    echo "[VERIFIED] OnlineFix signature detected."

    # Steam registration remains available through the explicit sync-steam command.
    # 2. Audit & Sync OnlineFix.ini PlayerName
    local ini_file
    ini_file=$(find "$gdir" -maxdepth 3 \( -name "pfx" -o -name ".git" \) -prune -o -iname "OnlineFix.ini" -print 2>/dev/null | head -n 1)
    if [ -n "$ini_file" ] && [ -f "$ini_file" ]; then
        local curr_pname
        curr_pname=$(grep -E '^[[:space:]]*PlayerName[[:space:]]*=' "$ini_file" 2>/dev/null | head -n 1 | sed -E 's/^[[:space:]]*PlayerName[[:space:]]*=[[:space:]]*//' | tr -d '\r')
        echo "[INFO] OnlineFix.ini detected: $ini_file"
        echo "       Current PlayerName: ${curr_pname:-[Unset]}"

        local persona_name=""
        if [ -f "$HOME/.config/gamectl/persona" ]; then
            persona_name=$(grep -E '^[[:space:]]*account_name[[:space:]]*=' "$HOME/.config/gamectl/persona" 2>/dev/null | head -n 1 | sed -E 's/^[[:space:]]*account_name[[:space:]]*=[[:space:]]*//' | tr -d '\r')
        fi
        [ -z "$persona_name" ] && persona_name="${USER:-Player}"

        if [ -n "$persona_name" ] && [ "$persona_name" != "$curr_pname" ]; then
            local should_sync=false
            if [ "$auto_yes" = true ]; then
                should_sync=true
            elif [ -t 0 ]; then
                echo -n "       Synchronize PlayerName to '$persona_name'? [Y/n] (Auto-yes in 5s): "
                local confirm_sync=""
                read -t 5 -r confirm_sync || confirm_sync="y"
                echo
                if [[ ! "$confirm_sync" =~ ^[nN] ]]; then
                    should_sync=true
                fi
            else
                should_sync=true
            fi

            if [ "$should_sync" = true ]; then
                if atomic_set_kv_file "$ini_file" "PlayerName" "$persona_name" " = "; then
                    echo "       ${UI_GREEN}[SUCCESS] PlayerName in OnlineFix.ini synchronized to: $persona_name${UI_RST}"
                else
                    echo "[ERROR] Failed to update PlayerName in $ini_file" >&2
                    return 1
                fi
            fi
        fi
    fi

    echo "[VERIFIED] OnlineFix setup completed for: $(basename "$gdir")"
    return 0
}

# Inject GBE Fork emulator and portable saves into a game folder
inject_game() {
    local target_dir="$1"
    local appid="${2:-}"
    local sync_mode="${3:---no-sync}"

    # Strip ANSI escape sequences
    target_dir=$(strip_ansi "$target_dir")
    [ -n "$appid" ] && appid=$(strip_ansi "$appid" | tr -dc '0-9')

    if [ ! -d "$target_dir" ]; then
        echo "[ERROR] Target directory not found: $target_dir" >&2
        return 1
    fi

    # Canonical path
    target_dir="$(cd "$target_dir" && pwd)"

    # Resolve AppID if not provided
    if [ -z "$appid" ]; then
        appid="$(resolve_game_appid "$target_dir")"
        if [ -z "$appid" ]; then
            local parent_dir
            parent_dir="$(dirname "$target_dir")"
            if [ "$(basename "$parent_dir")" = "common" ]; then
                local steamapps_dir
                steamapps_dir="$(dirname "$parent_dir")"
                local base_name
                base_name="$(basename "$target_dir")"
                for acf in "$steamapps_dir"/appmanifest_*.acf; do
                    [ -f "$acf" ] || continue
                    if grep -q "\"installdir\"[[:space:]]\+\"$base_name\"" "$acf" 2>/dev/null; then
                        appid=$(grep -E '^\s*"appid"' "$acf" | head -n 1 | sed -E 's/.*"appid"[[:space:]]+"([0-9]+)".*/\1/')
                        break
                    fi
                done
            fi
        fi
    fi

    echo "[INFO] Preparing GBE Fork injection in: $target_dir..."

    # 1. Identify Target Executable and Platform
    local gbin=""
    gbin=$(find_game_binary "$target_dir") || true

    local target_platform="linux"
    local arch="x64"
    local is_32bit=false

    # Check existing steam libraries in target folder
    local found_win64 found_win32 found_linux
    local api_targets=() api_file
    while IFS= read -r -d '' api_file; do
        [ -f "$api_file" ] && api_targets+=("$api_file")
    done < <(find "$target_dir" -maxdepth 4 \
        \( -name pfx -o -name .git -o -name saves -o -name .save_snapshots \) -prune \
        -o \( -name steam_api64.dll -o -name steam_api.dll -o -name libsteam_api.so \) -print0 2>/dev/null)
    found_win64="" found_win32="" found_linux=""
    for api_file in "${api_targets[@]}"; do
        case "${api_file##*/}" in
            steam_api64.dll) found_win64="${found_win64:-$api_file}" ;;
            steam_api.dll) found_win32="${found_win32:-$api_file}" ;;
            libsteam_api.so) found_linux="${found_linux:-$api_file}" ;;
        esac
    done

    if [ -n "$gbin" ] && [ -f "$target_dir/$gbin" ]; then
        local btype
        btype=$(file -b "$target_dir/$gbin" 2>/dev/null || echo "")
        if echo "$btype" | grep -qi -E "PE32|MS Windows|\.exe"; then
            target_platform="windows"
            if echo "$btype" | grep -qi "PE32+"; then
                arch="x64"
                is_32bit=false
            elif echo "$btype" | grep -qi "32-bit"; then
                arch="x86"
                is_32bit=true
            else
                arch="x64"
                is_32bit=false
            fi
        else
            target_platform="linux"
            if echo "$btype" | grep -qi "32-bit"; then
                arch="x86"
                is_32bit=true
            else
                arch="x64"
                is_32bit=false
            fi
        fi
    elif [ -n "$found_linux" ]; then
        target_platform="linux"
        if file -Lb "$found_linux" | grep -qi "32-bit"; then
            arch="x86"
            is_32bit=true
        else
            arch="x64"
            is_32bit=false
        fi
    elif [ -n "$found_win64" ] || [ -n "$found_win32" ]; then
        target_platform="windows"
        if [ -n "$found_win64" ]; then
            arch="x64"
            is_32bit=false
        else
            arch="x86"
            is_32bit=true
        fi
    fi

    # 2. Perform Shim Injections (with backup of originals)
    local shim_dirs=("$target_dir")

    # 2a. Windows Shim Injection (if windows steam files exist or target is windows)
    if [ -n "$found_win64" ] || [ -n "$found_win32" ] || [ "$target_platform" = "windows" ]; then
        local win_targets=()
        for api_file in "${api_targets[@]}"; do
            case "${api_file##*/}" in
                steam_api64.dll|steam_api.dll) win_targets+=("$api_file") ;;
            esac
        done

        # If neither found but target is windows, determine destination based on detected arch or gbin location
        if [ ${#win_targets[@]} -eq 0 ] && [ "$target_platform" = "windows" ]; then
            local bin_subdir="$target_dir"
            [ -n "$gbin" ] && [ -f "$target_dir/$gbin" ] && bin_subdir="$(dirname "$target_dir/$gbin")"
            if [ "$is_32bit" = true ]; then
                win_targets+=("$bin_subdir/steam_api.dll")
            else
                win_targets+=("$bin_subdir/steam_api64.dll")
            fi
        fi

        for entry in "${win_targets[@]}"; do
            local t_dll="$entry" t_arch=x64
            [ "${t_dll##*/}" = steam_api.dll ] && t_arch=x86
            local t_template
            t_template=$(get_gbe_template "windows" "$t_arch") || true

            if [ -z "$t_template" ] || [ ! -f "$t_template" ]; then
                echo "[WARN] Windows GBE Fork template ($t_arch) not found. Attempting automatic provisioning..." >&2
                setup_gbe_templates --yes --win-only >/dev/null 2>&1 || true
                t_template=$(get_gbe_template "windows" "$t_arch") || true
                if [ -z "$t_template" ] || [ ! -f "$t_template" ]; then
                    echo "[ERROR] Windows GBE Fork template ($t_arch) not found. Run 'gamectl setup-gbe' to install." >&2
                    return 1
                fi
            fi

            install_gbe_library "$t_template" "$t_dll" || return 1
            shim_dirs+=("$(dirname "$t_dll")")
            echo "[INFO] Windows GBE Fork DLL ($t_arch) installed at: $t_dll"
        done
    fi

    # 2b. Linux Shim Injection (if linux steam files exist or target is linux)
    if [ -n "$found_linux" ] || [ "$target_platform" = "linux" ]; then
        local linux_arch="x64"
        if [ -n "$found_linux" ]; then
            if file -Lb "$found_linux" | grep -qi "32-bit"; then
                linux_arch="x86"
            fi
        elif [ "$is_32bit" = true ]; then
            linux_arch="x86"
        fi

        local target_so="$target_dir/libsteam_api.so"
        if [ -n "$found_linux" ]; then
            target_so="$found_linux"
        elif [ -d "$target_dir/lib64" ] && [ "$linux_arch" = "x64" ]; then
            target_so="$target_dir/lib64/libsteam_api.so"
        elif [ -d "$target_dir/lib32" ] && [ "$linux_arch" = "x86" ]; then
            target_so="$target_dir/lib32/libsteam_api.so"
        fi

        local linux_targets=()
        for api_file in "${api_targets[@]}"; do
            [ "${api_file##*/}" = libsteam_api.so ] && linux_targets+=("$api_file")
        done
        [ ${#linux_targets[@]} -gt 0 ] || linux_targets+=("$target_so")
        for target_so in "${linux_targets[@]}"; do
            if [ -f "$target_so" ]; then
                linux_arch=x64
                if file -Lb "$target_so" | grep -qi '32-bit'; then linux_arch=x86; fi
            fi
            local src_so
            src_so=$(get_gbe_template "linux" "$linux_arch") || true
            if [ -z "$src_so" ] || [ ! -f "$src_so" ]; then
                echo "[WARN] Linux GBE Fork template ($linux_arch) not found. Attempting automatic provisioning..." >&2
                setup_gbe_templates --yes --linux-only >/dev/null 2>&1 || true
                src_so=$(get_gbe_template "linux" "$linux_arch") || true
            fi
            if [ -z "$src_so" ] || [ ! -f "$src_so" ]; then
                echo "[ERROR] Linux GBE Fork template ($linux_arch) not found at: ${src_so:-empty}" >&2
                return 1
            fi
            install_gbe_library "$src_so" "$target_so" || return 1
            shim_dirs+=("$(dirname "$target_so")")
            echo "[INFO] Linux GBE Fork ELF ($linux_arch) installed at: $target_so"
        done
    fi

    # 3. Setup steam_settings and configs.user.ini
    mkdir -p "$target_dir/steam_settings" || return 1
    local user_name=""
    local steamid=""

    # Check existing game persona or global persona
    if [ -f "$target_dir/steam_settings/configs.user.ini" ]; then
        user_name=$(grep -E '^[[:space:]]*account_name[[:space:]]*=' "$target_dir/steam_settings/configs.user.ini" 2>/dev/null | head -n 1 | sed -E 's/^[[:space:]]*account_name[[:space:]]*=[[:space:]]*//' | tr -d '\r')
        steamid=$(grep -E '^[[:space:]]*account_steamid[[:space:]]*=' "$target_dir/steam_settings/configs.user.ini" 2>/dev/null | head -n 1 | sed -E 's/^[[:space:]]*account_steamid[[:space:]]*=[[:space:]]*//' | tr -d '\r')
    fi
    if [ -z "$user_name" ] && [ -f "$HOME/.config/gamectl/persona" ]; then
        user_name=$(grep -E '^[[:space:]]*account_name[[:space:]]*=' "$HOME/.config/gamectl/persona" 2>/dev/null | head -n 1 | sed -E 's/^[[:space:]]*account_name[[:space:]]*=[[:space:]]*//' | tr -d '\r')
    fi
    if [ -z "$steamid" ] && [ -f "$HOME/.config/gamectl/persona" ]; then
        steamid=$(grep -E '^[[:space:]]*account_steamid[[:space:]]*=' "$HOME/.config/gamectl/persona" 2>/dev/null | head -n 1 | sed -E 's/^[[:space:]]*account_steamid[[:space:]]*=[[:space:]]*//' | tr -d '\r')
    fi
    [ -z "$user_name" ] && user_name="${USER:-Player}"
    if [ -z "$steamid" ]; then
        steamid=$(resolve_active_steamid)
    fi

    cat <<EOF > "$target_dir/steam_settings/configs.user.ini" || return 1
[user::general]
account_name=$user_name
account_steamid=$steamid
language=english

[user::saves]
local_save_path=./saves
EOF

    # Scaffold configs.app.ini to unlock all DLCs in GBE Fork
    if [ ! -f "$target_dir/steam_settings/configs.app.ini" ]; then
        cat <<EOF > "$target_dir/steam_settings/configs.app.ini" || return 1
[app::dlc]
unlock_all=1
EOF
    fi

    # Scaffold custom_broadcasts.txt if missing
    if [ ! -f "$target_dir/steam_settings/custom_broadcasts.txt" ]; then
        cat <<EOF > "$target_dir/steam_settings/custom_broadcasts.txt" || return 1
# GBE Fork LAN Custom Broadcast IP list
# Add peer IPs or broadcast subnets (one IP per line)
127.0.0.1
255.255.255.255
EOF
    fi

    # 4. Setup isolated portable saves folder and markers
    mkdir -p -m 700 "$target_dir/saves" || return 1
    chmod 700 "$target_dir/saves" || return 1
    local shim_dir
    for shim_dir in "${shim_dirs[@]}"; do
        printf saves > "$shim_dir/local_save.txt" || return 1
        if [ "$shim_dir" != "$target_dir" ]; then
            ln -sfn "$target_dir/steam_settings" "$shim_dir/steam_settings" || return 1
            ln -sfn "$target_dir/saves" "$shim_dir/saves" || return 1
        fi
        if [ -n "$appid" ] && [ "$appid" != STANDALONE ]; then
            printf '%s' "$appid" > "$shim_dir/steam_appid.txt" || return 1
        fi
    done

    # 5. Write steam_appid.txt if available
    if [ -n "$appid" ] && [ "$appid" != "STANDALONE" ]; then
        echo "[INFO] AppID $appid registered in: $target_dir/steam_appid.txt"
        fetch_dlc "$target_dir" "$appid"
        if [ "$sync_mode" = "--all" ] || [ "$sync_mode" = "all" ]; then
            sync_steam "$appid" "$(basename "$target_dir")" "$target_dir" || return $?
        else
            echo "[INFO] Standalone Mode active: Skipping Steam Client synchronization."
        fi
    fi

    invalidate_scan_cache
    echo "[VERIFIED] GBE Fork successfully injected (Platform: $target_platform, Arch: $arch, Save: ./saves, AppID: ${appid:-None})"
    log_msg "INFO" "INJECT" "GBE Fork successfully injected for $(basename "$target_dir") (Platform: $target_platform, Arch: $arch, Save: ./saves, AppID: ${appid:-None})"
}

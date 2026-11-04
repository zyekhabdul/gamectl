# Launch game with performance wrapping and runner isolation
launch_game() {
    local gdir="$1"
    local gbin="$2"
    local title="$3"
    shift 3 || true

    echo "[INFO] Menyiapkan peluncuran: $title..."
    backup_save "$gdir" true || true

    # Resolve wrappers and extra flags
    declare -a GAMECTL_WRAPPER_PREFIX=()
    declare -a GAMECTL_REMAINING_ARGS=()
    GAMECTL_ACTIVE_GLTHREAD=0
    build_wrapper_command "$gdir" "$@"
    local wrappers=("${GAMECTL_WRAPPER_PREFIX[@]}")
    local game_args=("${GAMECTL_REMAINING_ARGS[@]}")

    # Set Mesa performance env safely (only enable glthread if explicitly opted in)
    if [ "${GAMECTL_ACTIVE_GLTHREAD:-0}" = "1" ]; then
        export mesa_glthread=true
    else
        unset mesa_glthread
    fi
    export vblank_mode=0

    # Capture current CPU scaling governor for clean restoration
    local prev_governor=""
    if [ -f /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor ]; then
        prev_governor=$(cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor 2>/dev/null || echo "")
    fi

    # Attempt CPU scaling governor if permitted and not already in performance mode
    if [ -w /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor ]; then
        if [ "$prev_governor" != "performance" ]; then
            echo performance | tee /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor >/dev/null 2>&1 || true
        fi
    fi

    if [ ${#wrappers[@]} -gt 0 ]; then
        echo "[INFO] Wrapper aktif: ${wrappers[*]}"
    fi

    cd "$gdir"

    # Check if target is a Windows executable (.exe / PE)
    local is_win=false
    case "$gbin" in
        *.exe|*.EXE) is_win=true ;;
    esac
    if [ "$is_win" = false ] && [ -f "$gdir/$gbin" ]; then
        if file -b "$gdir/$gbin" 2>/dev/null | grep -qi -E "PE32|MS Windows"; then
            is_win=true
        fi
    fi

    local exit_code=0
    if [ "$is_win" = true ]; then
        local runner_bin
        runner_bin=$(find_runner "$gdir" 2>/dev/null || true)
        if [ -z "$runner_bin" ]; then
            echo "[ERROR] Runner Windows tidak ditemukan (umu-run, Proton, atau Wine belum terpasang)." >&2
            echo "        Pasang GE-Proton di ~/.local/share/Steam/compatibilitytools.d/ atau install wine." >&2
            exit_code=1
        else
            local pfx_dir="$gdir/pfx"
            mkdir -p "$pfx_dir"
            local appid=""
            if [ -f "$gdir/steam_appid.txt" ]; then
                appid=$(tr -dc '0-9' < "$gdir/steam_appid.txt")
            fi
            [ -z "$appid" ] && appid="0"

            echo "[INFO] Meluncurkan game Windows via $(basename "$runner_bin")..."
            echo "[INFO] Wine Prefix terisolasi: $pfx_dir"

            case "$runner_bin" in
                umu-run)
                    WINEPREFIX="$pfx_dir" GAMEID="$appid" \
                    "${wrappers[@]}" umu-run "$gdir/$gbin" "${game_args[@]}" || exit_code=$?
                    ;;
                *proton*)
                    STEAM_COMPAT_CLIENT_INSTALL_PATH="${STEAM_CLIENT_INSTALL_PATH:-$(get_steam_root 2>/dev/null || echo "$HOME/.local/share/Steam")}" \
                    STEAM_COMPAT_DATA_PATH="$gdir" \
                    STEAM_COMPAT_APP_ID="$appid" \
                    WINEPREFIX="$pfx_dir" \
                    "${wrappers[@]}" "$runner_bin" waitforexitandrun "$gdir/$gbin" "${game_args[@]}" || exit_code=$?
                    ;;
                *)
                    WINEPREFIX="$pfx_dir" \
                    "${wrappers[@]}" "$runner_bin" "$gdir/$gbin" "${game_args[@]}" || exit_code=$?
                    ;;
            esac
        fi
    else
        echo "[INFO] Menjalankan $title (Native Linux)..."
        "${wrappers[@]}" ./"$gbin" "${game_args[@]}" || exit_code=$?
    fi

    [ "$exit_code" -ne 0 ] && echo "[WARN] Game exited with code $exit_code"

    # Restore CPU governor to pre-launch state
    if [ -n "$prev_governor" ] && [ -w /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor ]; then
        echo "$prev_governor" | tee /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor >/dev/null 2>&1 || true
    fi

    clean_stale_locks
    echo "[INFO] Game ditutup. Sesi bersih."
    return $exit_code
}

# Sync savegame to remote companion host
sync_save_remote() {
    local gdir="$1"
    local title="$2"
    local override_host="${3:-}"
    local sdir="$gdir/saves"
    local rhost="$override_host"
    [ -z "$rhost" ] && rhost=$(get_remote_host)

    if [ ! -d "$sdir" ]; then
        echo "[ERROR] Folder portable saves tidak ditemukan di $gdir"
        return 1
    fi

    if [ -z "$rhost" ]; then
        echo "[WARN] Target remote host belum dikonfigurasi."
        echo "       Tentukan host di ~/.config/gamectl/remote_host atau variabel GAMECTL_REMOTE_HOST."
        return 1
    fi

    echo "[INFO] Memeriksa konektivitas ke $rhost..."
    if ! ssh -q -o ConnectTimeout=1 -o BatchMode=yes "$rhost" exit 2>/dev/null; then
        echo "[WARN] Host remote '$rhost' offline atau tidak terjangkau jaringan lokal."
        return 1
    fi

    echo "[INFO] Menyinkronkan savegame $title ke $rhost..."
    local rel_path="${gdir#$HOME/}"
    ssh "$rhost" "mkdir -p ~/$rel_path"
    rsync -avzP --exclude="*.tmp" "$sdir/" "$rhost:~/$rel_path/saves/"
    echo "[VERIFIED] Sinkronisasi savegame ke $rhost selesai."
}

# Aliases for remote savegame synchronization
sync_to_companion() {
    sync_save_remote "$@"
}

sync_to_tuf() {
    sync_save_remote "$@"
}


# Inject GBE Fork emulator and portable saves into a game folder
inject_game() {
    local target_dir="$1"
    local appid="${2:-}"
    local sync_mode="${3:-all}"

    if [ ! -d "$target_dir" ]; then
        echo "[ERROR] Direktori target tidak ditemukan: $target_dir" >&2
        return 1
    fi

    # Canonical path
    target_dir="$(cd "$target_dir" && pwd)"

    # Resolve AppID if not provided
    if [ -z "$appid" ]; then
        if [ -f "$target_dir/steam_appid.txt" ]; then
            appid=$(tr -dc '0-9' < "$target_dir/steam_appid.txt")
        fi
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

    echo "[INFO] Menyiapkan injeksi GBE Fork di: $target_dir..."

    # 1. Identify Target Executable and Platform
    local gbin=""
    gbin=$(find_game_binary "$target_dir") || true

    local target_platform="linux"
    local arch="x64"
    local is_32bit=false

    # Check existing steam libraries in target folder
    local found_win64 found_win32 found_linux
    found_win64=$(find "$target_dir" -maxdepth 4 -name "steam_api64.dll" 2>/dev/null | head -n 1)
    found_win32=$(find "$target_dir" -maxdepth 4 -name "steam_api.dll" 2>/dev/null | head -n 1)
    found_linux=$(find "$target_dir" -maxdepth 4 -name "libsteam_api.so" 2>/dev/null | head -n 1)

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
        if file -b "$found_linux" | grep -qi "32-bit"; then
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
    local primary_shim_dir="$target_dir"

    # 2a. Windows Shim Injection (if windows steam files exist or target is windows)
    if [ -n "$found_win64" ] || [ -n "$found_win32" ] || [ "$target_platform" = "windows" ]; then
        local win_targets=()
        if [ -n "$found_win64" ]; then
            win_targets+=("$found_win64:x64")
        fi
        if [ -n "$found_win32" ]; then
            win_targets+=("$found_win32:x86")
        fi

        # If neither found but target is windows, determine destination based on detected arch or gbin location
        if [ ${#win_targets[@]} -eq 0 ] && [ "$target_platform" = "windows" ]; then
            local bin_subdir="$target_dir"
            [ -n "$gbin" ] && [ -f "$target_dir/$gbin" ] && bin_subdir="$(dirname "$target_dir/$gbin")"
            if [ "$is_32bit" = true ]; then
                win_targets+=("$bin_subdir/steam_api.dll:x86")
            else
                win_targets+=("$bin_subdir/steam_api64.dll:x64")
            fi
        fi

        for entry in "${win_targets[@]}"; do
            local t_dll="${entry%%:*}"
            local t_arch="${entry##*:}"
            local t_template
            t_template=$(get_gbe_template "windows" "$t_arch") || true

            if [ -z "$t_template" ] || [ ! -f "$t_template" ]; then
                echo "[WARN] Template GBE Fork Windows ($t_arch) tidak ditemukan." >&2
                continue
            fi

            # Backup original Valve DLL if present (<7MB and .orig not existing)
            if [ -f "$t_dll" ]; then
                local sz
                sz=$(stat -c%s "$t_dll" 2>/dev/null || echo 0)
                if [ "$sz" -lt 7000000 ] && [ ! -f "$t_dll.orig" ]; then
                    cp -a "$t_dll" "$t_dll.orig"
                    echo "[INFO] Backup $(basename "$t_dll") asli tersimpan di: $t_dll.orig"
                fi
            fi

            mkdir -p "$(dirname "$t_dll")"
            cp "$t_template" "$t_dll"
            chmod +x "$t_dll" 2>/dev/null || true
            primary_shim_dir="$(dirname "$t_dll")"
            echo "[INFO] GBE Fork Windows DLL ($t_arch) terpasang di: $t_dll"
        done
    fi

    # 2b. Linux Shim Injection (if linux steam files exist or target is linux)
    if [ -n "$found_linux" ] || [ "$target_platform" = "linux" ]; then
        local linux_arch="x64"
        if [ -n "$found_linux" ]; then
            if file -b "$found_linux" | grep -qi "32-bit"; then
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

        local src_so
        src_so=$(get_gbe_template "linux" "$linux_arch") || true
        if [ -n "$src_so" ] && [ -f "$src_so" ]; then
            # Backup original Valve SO if present (<7MB and .orig not existing)
            if [ -f "$target_so" ]; then
                local sz
                sz=$(stat -c%s "$target_so" 2>/dev/null || echo 0)
                if [ "$sz" -lt 7000000 ] && [ ! -f "$target_so.orig" ]; then
                    cp -a "$target_so" "$target_so.orig"
                    echo "[INFO] Backup libsteam_api.so asli tersimpan di: $target_so.orig"
                fi
            fi

            mkdir -p "$(dirname "$target_so")"
            cp "$src_so" "$target_so"
            chmod +x "$target_so"
            primary_shim_dir="$(dirname "$target_so")"
            echo "[INFO] GBE Fork Linux ELF ($linux_arch) terpasang di: $target_so"
        else
            [ "$target_platform" = "linux" ] && echo "[WARN] Template GBE Fork Linux ($linux_arch) tidak ditemukan di: ${src_so:-empty}" >&2
        fi
    fi

    # 3. Setup steam_settings and configs.user.ini
    mkdir -p "$target_dir/steam_settings"
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

    cat <<EOF > "$target_dir/steam_settings/configs.user.ini"
[user::general]
account_name=$user_name
account_steamid=$steamid
language=english

[user::saves]
local_save_path=./saves
EOF

    # Scaffold custom_broadcasts.txt if missing
    if [ ! -f "$target_dir/steam_settings/custom_broadcasts.txt" ]; then
        cat <<EOF > "$target_dir/steam_settings/custom_broadcasts.txt"
# GBE Fork LAN Custom Broadcast IP list
# Tambahkan IP peer atau broadcast subnet (satu IP per baris)
127.0.0.1
255.255.255.255
EOF
    fi

    # If shim is in a subfolder, link steam_settings beside it as per GBE specification
    if [ "$primary_shim_dir" != "$target_dir" ] && [ -d "$primary_shim_dir" ]; then
        ln -sfn "$target_dir/steam_settings" "$primary_shim_dir/steam_settings" 2>/dev/null || true
    fi

    # 4. Setup isolated portable saves folder and markers
    mkdir -p "$target_dir/saves"
    echo -n "saves" > "$target_dir/local_save.txt"
    if [ "$primary_shim_dir" != "$target_dir" ] && [ -d "$primary_shim_dir" ]; then
        echo -n "saves" > "$primary_shim_dir/local_save.txt" 2>/dev/null || true
        ln -sfn "$target_dir/saves" "$primary_shim_dir/saves" 2>/dev/null || true
    fi

    # 5. Write steam_appid.txt if available
    if [ -n "$appid" ] && [ "$appid" != "STANDALONE" ]; then
        echo -n "$appid" > "$target_dir/steam_appid.txt"
        if [ "$primary_shim_dir" != "$target_dir" ] && [ -d "$primary_shim_dir" ]; then
            echo -n "$appid" > "$primary_shim_dir/steam_appid.txt" 2>/dev/null || true
        fi
        echo "[INFO] AppID $appid terdaftar di: $target_dir/steam_appid.txt"
        fetch_dlc "$target_dir" "$appid"
        if [ "$sync_mode" != "--no-sync" ] && [ "$sync_mode" != "no-sync" ] && [ "$sync_mode" != "standalone" ]; then
            sync_steam "$appid" "$(basename "$target_dir")" "$target_dir"
        else
            echo "[INFO] Mode Standalone aktif: Melewati sinkronisasi Steam Client."
        fi
    fi

    echo "[VERIFIED] Game berhasil diinjeksi GBE Fork (Platform: $target_platform, Arsitektur: $arch, Save: ./saves, AppID: ${appid:-None})"
}


# CLI helper for launching games with wrappers and options
cli_launch() {
    local l_dir="${1:-}"
    shift || true
    local l_bin=""
    local l_title=""
    local l_flags=()

    while [ $# -gt 0 ]; do
        case "$1" in
            --hud|--mangohud|--no-hud|--no-mangohud|--gamemode|--no-gamemode|--gamescope|--no-gamescope|--fsr|--no-fsr)
                l_flags+=("$1")
                shift
                ;;
            *)
                if [ -z "$l_bin" ]; then
                    l_bin="$1"
                elif [ -z "$l_title" ]; then
                    l_title="$1"
                else
                    l_flags+=("$1")
                fi
                shift
                ;;
        esac
    done

    [ -z "$l_title" ] && l_title="$(basename "$l_dir")"
    if [ -z "$l_bin" ]; then
        l_bin=$(find_game_binary "$l_dir" 2>/dev/null || echo "")
    fi

    if [ -n "$l_bin" ]; then
        launch_game "$l_dir" "$l_bin" "$l_title" "${l_flags[@]}"
    else
        echo "[ERROR] Biner eksekutabel tidak ditemukan di: $l_dir" >&2
        return 1
    fi
}


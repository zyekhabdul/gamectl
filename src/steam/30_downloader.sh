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

# Ensure DepotDownloader runtime is available
ensure_downloader() {
    local depot_bin=""
    if command -v depotdownloader >/dev/null 2>&1; then
        depot_bin="$(command -v depotdownloader)"
    elif [ -x "$HOME/.local/share/gamectl/bin/DepotDownloader" ]; then
        depot_bin="$HOME/.local/share/gamectl/bin/DepotDownloader"
    elif [ -x "$HOME/.local/bin/depotdownloader" ]; then
        depot_bin="$HOME/.local/bin/depotdownloader"
    else
        local u_arch
        u_arch=$(uname -m 2>/dev/null || echo "x86_64")
        local dl_arch="linux-x64"
        case "$u_arch" in
            aarch64|arm64)
                dl_arch="linux-arm64"
                ;;
            armv7*|armhf)
                dl_arch="linux-arm"
                ;;
            x86_64|amd64)
                dl_arch="linux-x64"
                ;;
            *)
                dl_arch="linux-x64"
                ;;
        esac

        echo "[INFO] Downloading DepotDownloader standalone binary ($dl_arch)..." >&2
        mkdir -p "$HOME/.local/share/gamectl/bin" "$HOME/.local/bin"
        local dl_url="https://github.com/SteamRE/DepotDownloader/releases/download/DepotDownloader_3.4.0/DepotDownloader-${dl_arch}.zip"
        local run_dir="${XDG_RUNTIME_DIR:-/tmp/gamectl-$UID}"
        mkdir -p -m 700 "$run_dir"
        local dl_zip="$run_dir/depotdownloader.zip"
        if curl -sL "$dl_url" -o "$dl_zip" 2>/dev/null; then
            unzip -q -o "$dl_zip" -d "$HOME/.local/share/gamectl/bin/"
            chmod +x "$HOME/.local/share/gamectl/bin/DepotDownloader"
            ln -sf "$HOME/.local/share/gamectl/bin/DepotDownloader" "$HOME/.local/bin/depotdownloader"
            rm -f "$dl_zip"
            depot_bin="$HOME/.local/share/gamectl/bin/DepotDownloader"
            echo "[VERIFIED] DepotDownloader installed at: $depot_bin" >&2
        else
            echo "[ERROR] Failed to download DepotDownloader from GitHub." >&2
            return 1
        fi
    fi
    echo "$depot_bin"
}

# Resolve optimal destination directory based on configured libraries and available disk space
resolve_target_library_dir() {
    local safe_title="${1:-game}"
    local candidate_dirs=()

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

# Headless Game Downloader (Standalone CLI Engine)
download_game() {
    local appid="${1:-}"
    if [ -z "$appid" ]; then
        echo "Usage: gamectl download <appid> [target_dir] [title] [--raw|--inject-only|--all] [--foreground|-f] [--os <linux|windows|all>]" >&2
        return 1
    fi
    shift

    local target_dir=""
    local title=""
    local action="all"     # "all", "inject", "raw"
    local exec_mode="bg"   # "bg" or "fg"
    local target_os=""

    while [ $# -gt 0 ]; do
        case "$1" in
            --raw|--download-only|--no-inject)
                action="raw"
                ;;
            --inject-only|--standalone|--no-sync)
                action="inject"
                ;;
            --all)
                action="all"
                ;;
            --foreground|-f|foreground)
                exec_mode="fg"
                ;;
            --background|-b|background)
                exec_mode="bg"
                ;;
            --os)
                shift
                target_os="${1:-linux}"
                ;;
            --os=*)
                target_os="${1#--os=}"
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

    local depot_bin
    depot_bin=$(ensure_downloader) || return 1

    if [ -z "$title" ]; then
        title=$(curl -s --connect-timeout 4 "https://store.steampowered.com/api/appdetails?appids=${appid}&filters=basic" | jq -r ".\"${appid}\".data.name // empty" 2>/dev/null || true)
        [ -z "$title" ] && title="AppID_${appid}"
    fi

    local safe_title
    safe_title=$(echo "$title" | tr -cd '[:alnum:] _-')
    [ -z "$safe_title" ] && safe_title="$appid"

    if [ -z "$target_os" ]; then
        target_os="$(detect_app_platform_os "$appid")"
    fi

    if [ -z "$target_dir" ]; then
        target_dir="$(resolve_target_library_dir "$safe_title")"
    fi

    mkdir -p "$target_dir"
    target_dir="$(cd "$target_dir" && pwd)"
    local run_dir="${XDG_RUNTIME_DIR:-/tmp/gamectl-$UID}"
    mkdir -p -m 700 "$run_dir"
    local log_file="$run_dir/gamectl_dl_${appid}.log"

    local extra_args=()
    local user_cfg="$HOME/.config/gamectl/steam_user"
    local steam_user="${GAMECTL_STEAM_USER:-}"
    if [ -z "$steam_user" ] && [ -f "$user_cfg" ]; then
        steam_user=$(head -n 1 "$user_cfg" | tr -d '[:space:]')
    fi
    if [ -n "$steam_user" ]; then
        extra_args+=("-username" "$steam_user" "-remember-password")
    fi

    echo "=========================================="
    echo " HEADLESS GAME DOWNLOADER (DepotDownloader)"
    echo "=========================================="
    echo " AppID      : $appid"
    echo " Title      : $title"
    echo " Target Dir : $target_dir"
    echo " Target OS  : $target_os"
    echo " Package    : $action (raw / inject / all)"
    echo " Log Stream : $log_file"
    [ -n "$steam_user" ] && echo " Steam User : $steam_user"
    echo "=========================================="

    if [ "$exec_mode" = "fg" ]; then
        echo "[INFO] Running download in foreground..."
        echo "[INFO] Starting download of AppID $appid ($target_os) to $target_dir at $(date)" > "$log_file"
        "$depot_bin" -app "$appid" -os "$target_os" "${extra_args[@]}" -dir "$target_dir" 2>&1 | tee -a "$log_file"
        local dl_status="${PIPESTATUS[0]}"
        if [ "$dl_status" -eq 0 ]; then
            case "$action" in
                raw)
                    echo "[SUCCESS] Raw asset download completed for $title ($appid)."
                    ;;
                inject)
                    echo "[INFO] Executing standalone GBE Fork injection..."
                    "$SELF_BIN" inject "$target_dir" "$appid" --no-sync
                    echo "[SUCCESS] Download and standalone injection completed for $title ($appid)."
                    ;;
                all|*)
                    echo "[INFO] Executing GBE Fork injection and Steam Client synchronization..."
                    "$SELF_BIN" inject "$target_dir" "$appid"
                    echo "[SUCCESS] All-in-One installation completed for $title ($appid)."
                    ;;
            esac
        else
            echo "[ERROR] Download failed (exit code: $dl_status). See: $log_file" >&2
            return "$dl_status"
        fi
    else
        echo "[INFO] Spawning download process in background..."
        (
            echo "[INFO] Starting download of AppID $appid ($target_os) to $target_dir at $(date)" > "$log_file"
            "$depot_bin" -app "$appid" -os "$target_os" "${extra_args[@]}" -dir "$target_dir" >> "$log_file" 2>&1
            local bg_status=$?
            if [ $bg_status -eq 0 ]; then
                case "$action" in
                    raw)
                        echo "[SUCCESS] Raw asset download completed for $title ($appid) at $(date)." >> "$log_file"
                        ;;
                    inject)
                        echo "[INFO] Executing standalone GBE Fork injection..." >> "$log_file"
                        "$SELF_BIN" inject "$target_dir" "$appid" --no-sync >> "$log_file" 2>&1
                        echo "[SUCCESS] Download and standalone injection completed for $title ($appid) at $(date)." >> "$log_file"
                        ;;
                    all|*)
                        echo "[INFO] Executing auto-injection and Steam Client synchronization..." >> "$log_file"
                        "$SELF_BIN" inject "$target_dir" "$appid" >> "$log_file" 2>&1
                        echo "[SUCCESS] All-in-One complete installation finished for $title ($appid) at $(date)." >> "$log_file"
                        ;;
                esac
            else
                echo "[ERROR] Download failed (exit code: $bg_status) at $(date)." >> "$log_file"
            fi
        ) &
        local pid=$!
        echo "[VERIFIED] Download running in background (PID: $pid)."
        echo "Monitor progress: tail -f $log_file"
    fi
}

# List active and recent downloads
list_downloads() {
    echo "=========================================="
    echo " GAMECTL DOWNLOAD STATUS (DepotDownloader)"
    echo "=========================================="
    local run_dir="${XDG_RUNTIME_DIR:-/tmp/gamectl-$UID}"
    local count=0
    declare -A seen_logs=()
    for log in "$run_dir"/gamectl_dl_*.log /tmp/gamectl_dl_*.log; do
        [ -f "$log" ] || continue
        [[ -v seen_logs["$log"] ]] && continue
        seen_logs["$log"]=1
        count=$((count + 1))
        local appid
        appid=$(basename "$log" | sed -E 's/gamectl_dl_([0-9]+)\.log/\1/')
        local status="[COMPLETED/STOPPED]"
        if pgrep -f "DepotDownloader.*-app[[:space:]]+${appid}([[:space:]]|$)" >/dev/null 2>&1; then
            status="[DOWNLOADING]"
        fi
        echo "$status AppID: $appid | Log: $log"
        tail -n 2 "$log" 2>/dev/null | sed 's/^/  > /'
        echo "------------------------------------------"
    done
    if [ $count -eq 0 ]; then
        echo "[INFO] No active or recent download tasks in $run_dir."
    fi
}

# Interactive Download Monitor TUI
list_downloads_interactive() {
    local run_dir="${XDG_RUNTIME_DIR:-/tmp/gamectl-$UID}"
    mkdir -p -m 700 "$run_dir"
    while true; do
        local valid_logs=()
        declare -A seen_logs=()
        for l in "$run_dir"/gamectl_dl_*.log /tmp/gamectl_dl_*.log; do
            [ -f "$l" ] || continue
            [[ -v seen_logs["$l"] ]] && continue
            seen_logs["$l"]=1
            valid_logs+=("$l")
        done

        if [ ${#valid_logs[@]} -eq 0 ]; then
            clear
            echo "${UI_BOX}╭─ DOWNLOAD MANAGER (DepotDownloader) ────────────────────────╮${UI_RST}"
            echo "│ ${UI_CYAN}No active or recent download tasks found in $run_dir${UI_RST}"
            echo "${UI_BOX}╰─────────────────────────────────────────────────────────────╯${UI_RST}"
            read -r -p "Press [ENTER] to return to Dashboard..."
            return 0
        fi

        local entries=""
        for log in "${valid_logs[@]}"; do
            local appid
            appid=$(basename "$log" | sed -E 's/gamectl_dl_([0-9]+)\.log/\1/')
            local pid
            pid=$(pgrep -f "DepotDownloader.*-app[[:space:]]+${appid}([[:space:]]|$)" 2>/dev/null | head -n 1 || true)
            local status="${UI_ICE}[COMPLETED]${UI_RST}"
            [ -n "$pid" ] && status="${UI_GREEN}[RUNNING PID:$pid]${UI_RST}"
            local last_line
            last_line=$(tail -n 1 "$log" 2>/dev/null | tr -d '\r\n\t' | cut -c1-60)
            [ -z "$last_line" ] && last_line="Waiting for output..."
            entries+="${appid}\t${status}\t${log}\t${last_line}\n"
        done

        local selection fzf_rc=0
        selection=$(printf "%b" "$entries" | fzf \
            --delimiter=$'\t' \
            --with-nth=1,2,4 \
            --border-label="  ╢ gamectl :: Download Manager ╟  " \
            --border-label-pos=2 \
            --header="ACTIVE DOWNLOADS (Enter: Actions & Stream │ Ctrl-K: Stop │ Esc: Back)" \
            --prompt="Downloads > " \
            --preview="echo -e '\033[38;5;60mLog: {3}\033[0m\n──────────────────────────────────────────'; tail -n 30 {3}" \
            --preview-window=right:60%:border-rounded:wrap \
            --bind="ctrl-k:execute(appid={1}; pid=\$(pgrep -f \"DepotDownloader.*-app[[:space:]]+\${appid}([[:space:]]|$)\" 2>/dev/null | head -n 1); if [ -n \"\$pid\" ]; then kill \"\$pid\" 2>/dev/null && echo \"[INFO] AppID \$appid (PID \$pid) terminated.\"; else echo \"[INFO] AppID \$appid not active.\"; fi; bash -c 'read -n 1 -s -r -p \"Press any key to continue...\"')" \
        ) || fzf_rc=$?

        [ "$fzf_rc" -eq 130 ] && break
        [ -z "$selection" ] && continue

        if [ -n "$selection" ]; then
            local sel_appid sel_log sel_status
            sel_appid=$(echo "$selection" | awk -F'\t' '{print $1}')
            sel_log=$(echo "$selection" | awk -F'\t' '{print $3}')
            sel_status=$(echo "$selection" | awk -F'\t' '{print $2}')

            clear
            echo "${UI_BOX}╭─ DOWNLOAD ACTIONS: AppID ${UI_BOLD}$sel_appid${UI_RST} $sel_status ─────────────╮${UI_RST}"
            echo "│ ${UI_CYAN}Log file${UI_RST}: ${UI_DIM}$sel_log${UI_RST}"
            echo "${UI_BOX}╰─────────────────────────────────────────────────────────────╯${UI_RST}"
            echo "  ${UI_PURPLE}1)${UI_RST} Stream live output (tail -f)"
            echo "  ${UI_PURPLE}2)${UI_RST} Terminate this process (Kill task)"
            echo "  ${UI_PURPLE}3)${UI_RST} Remove this log history file"
            echo "  ${UI_DIM}4)${UI_RST} Return to download list"
            echo
            read -r -p "Select option [1-4]: " dl_opt

            case "$dl_opt" in
                1)
                    clear
                    echo "${UI_BOX}╭─ LIVE STREAM: AppID $sel_appid ─────────────────────────────╮${UI_RST}"
                    echo "│ ${UI_CYAN}Press Ctrl-C when done to return${UI_RST}"
                    echo "${UI_BOX}╰─────────────────────────────────────────────────────────────╯${UI_RST}"
                    tail -f "$sel_log" || true
                    read -r -p "Press [ENTER] to return..."
                    ;;
                2)
                    local k_pid
                    k_pid=$(pgrep -f "DepotDownloader.*-app[[:space:]]+${sel_appid}([[:space:]]|$)" 2>/dev/null | head -n 1 || true)
                    if [ -n "$k_pid" ]; then
                        kill "$k_pid" 2>/dev/null && echo "  ${UI_GREEN}[SUCCESS] Download process AppID $sel_appid (PID $k_pid) stopped.${UI_RST}"
                    else
                        echo "  [INFO] AppID $sel_appid is not currently running."
                    fi
                    read -r -p "Press [ENTER] to continue..."
                    ;;
                3)
                    rm -f "$sel_log"
                    echo "  [INFO] Log file $sel_log deleted."
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
    local sls_cfg="$HOME/.config/SLSsteam/config.yaml"
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

    # 3. Create appmanifest_<appid>.acf in Steam steamapps
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


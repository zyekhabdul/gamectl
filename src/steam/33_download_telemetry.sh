# ==============================================================================
# Steam Download Telemetry, ACF State & Depot Progress (Split from 30_downloader.sh)
# ==============================================================================

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
        appid=$(strip_ansi "$target" | tr -dc "0-9")
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

    if [[ "$name$installdir$acf_file" == *[$'\t\r\n']* ]]; then
        echo "[ERROR] ACF fields cannot contain TAB, CR or newline." >&2
        return 1
    fi
    printf "%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n" \
        "$appid" "$name" "$status_str" "$pct" "$bytes_dl" "$bytes_total" "$state_flags" "$installdir" "$acf_file"
}

# List active and recent downloads
list_downloads() {
    echo "=========================================="
    echo " GAMECTL DOWNLOAD STATUS (Unified Engine)"
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

    # Inspect Standalone CDN downloads
    local run_dir
    run_dir="$(get_runtime_dir)"
    shopt -s nullglob
    for st_dir in "$run_dir"/depot_dl_*; do
        [ -d "$st_dir" ] || continue
        local base_st="${st_dir##*/}"
        local st_pid="${base_st##*_}"
        local rest_st="${base_st#depot_dl_}"
        local st_appid="${rest_st%_*}"
        [ -z "$st_appid" ] || [ -z "$st_pid" ] && continue

        # Self-healing: purge orphaned staging dir if downloader process is dead
        if ! [[ "$st_pid" =~ ^[0-9]+$ ]] || ! kill -0 "$st_pid" 2>/dev/null; then
            rm -rf "$st_dir" 2>/dev/null || true
            continue
        fi

        local st_info="$st_dir/status.info"
        local st_title="Native CDN Download"
        local st_log="$st_dir/download.log"
        if [ -f "$st_info" ]; then
            local info_title info_log
            info_title=$(grep -E '^TITLE=' "$st_info" | cut -d= -f2- || true)
            info_log=$(grep -E '^LOG_FILE=' "$st_info" | cut -d= -f2- || true)
            [ -n "$info_title" ] && st_title="$info_title"
            [ -n "$info_log" ] && [ -f "$info_log" ] && st_log="$info_log"
        fi

        local prog_data st_pct st_bytes st_state
        prog_data=$(get_depot_dl_progress "$st_log" "$st_pid")
        IFS=$'\t' read -r st_pct st_bytes st_state <<< "$prog_data"

        count=$((count + 1))
        local dl_label="Engine: Standalone CDN"
        if [ -n "$st_bytes" ] && [ "$st_bytes" != "0 MB / 0 MB" ]; then
            echo "$st_state AppID: $st_appid | $st_title | Progress: $st_pct ($st_bytes) | $dl_label"
        else
            echo "$st_state AppID: $st_appid | $st_title | Progress: $st_pct | $dl_label"
        fi
        echo "------------------------------------------"
    done
    shopt -u nullglob

    if [ $count -eq 0 ]; then
        echo "[INFO] No active download tasks in Steam or Standalone engine."
    fi
}

# Helper: Parse structured download telemetry from depot-dl logs
get_depot_dl_progress() {
    local log_file="$1"
    local pid="${2:-}"

    if [ ! -f "$log_file" ]; then
        printf "0%%\t0 MB / 0 MB\t[STARTING]\n"
        return 0
    fi

    local parsed
    parsed=$(awk '
    /^\[DEPOT_START\]/ {
        for (i=1; i<=NF; i++) {
            if ($i ~ /^\([0-9.]+$/) {
                tot += substr($i, 2);
            }
        }
    }
    /^\[PROGRESS\] Transferred:/ {
        dl = $3;
    }
    /^\[SUCCESS\]/ {
        done = 1;
    }
    /^\[ERROR\]/ {
        err = 1;
    }
    END {
        if (done) {
            printf "100%%\t%.2f MB / %.2f MB\t[COMPLETED]\n", dl ? dl : tot, tot ? tot : dl;
        } else if (err && !dl) {
            printf "0%%\t0 MB / 0 MB\t[FAILED]\n";
        } else if (tot > 0 && dl > 0) {
            pct = int((dl / tot) * 100);
            if (pct > 100) pct = 100;
            printf "%d%%\t%.2f MB / %.2f MB\t[DOWNLOADING]\n", pct, dl, tot;
        } else if (tot > 0) {
            printf "0%%\t0 MB / %.2f MB\t[STARTING]\n", tot;
        } else if (dl > 0) {
            printf "0%%\t%.2f MB transferred\t[DOWNLOADING]\n", dl;
        } else {
            printf "0%%\t0 MB / 0 MB\t[STARTING]\n";
        }
    }' "$log_file")

    local pct bytes_info state_label
    IFS=$'\t' read -r pct bytes_info state_label <<< "$parsed"

    # Check process state for SIGSTOP pause
    if [ -n "$pid" ] && [ -d "/proc/$pid" ]; then
        local proc_state
        proc_state=$(awk '/^State:/ {print $2}' "/proc/$pid/status" 2>/dev/null || true)
        if [[ "$proc_state" =~ ^[Tt] ]]; then
            state_label="[PAUSED]"
        fi
    fi

    printf "%s\t%s\t%s\n" "$pct" "$bytes_info" "$state_label"
}

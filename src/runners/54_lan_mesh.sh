# ==============================================================================
# P2P LAN Mesh Sync & Manifest 404 Sovereign Fallback (SSH / rsync)
# ==============================================================================

_lan_peers_file() {
    printf '%s\n' "${XDG_CONFIG_HOME:-$HOME/.config}/gamectl/peers"
}

_lan_validate_peer() {
    local host="${1:-}"
    [ -n "$host" ] || return 1
    [[ "$host" == -* ]] && return 1
    [[ "$host" == rclone:* ]] && return 1
    if [[ "$host" =~ [[:space:]\;\|\&\$\`\\] ]]; then
        return 1
    fi
    return 0
}

# Print configured LAN companion peers (one SSH host per line, deduplicated)
get_lan_peers() {
    local -a raw_peers=()
    local item
    if [ -n "${GAMECTL_LAN_PEERS:-}" ]; then
        local normalized="${GAMECTL_LAN_PEERS//,/:}"
        normalized="${normalized//$'\n'/:}"
        local -a env_arr=()
        IFS=':' read -r -a env_arr <<< "$normalized"
        raw_peers+=("${env_arr[@]}")
    fi

    local pfile
    pfile="$(_lan_peers_file)"
    if [ -f "$pfile" ]; then
        while IFS= read -r item || [ -n "$item" ]; do
            item="${item%%#*}"
            item=$(printf '%s' "$item" | tr -d '\r' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
            [ -n "$item" ] && raw_peers+=("$item")
        done < "$pfile"
    fi

    local rhost=""
    declare -F get_remote_host >/dev/null 2>&1 && rhost=$(get_remote_host 2>/dev/null || true)
    if [ -n "$rhost" ] && [[ "$rhost" != rclone:* ]]; then
        rhost="${rhost%%:*}"
        raw_peers+=("$rhost")
    fi

    declare -A seen=()
    for item in "${raw_peers[@]}"; do
        _lan_validate_peer "$item" || continue
        [[ -v seen["$item"] ]] && continue
        seen["$item"]=1
        printf '%s\n' "$item"
    done
}

# Manage companion LAN peers (~/.config/gamectl/peers)
peers_cli() {
    local action="${1:-list}"
    local target="${2:-}"
    local pfile
    pfile="$(_lan_peers_file)"

    case "$action" in
        list)
            local peers_out
            peers_out=$(get_lan_peers)
            if [ -z "$peers_out" ]; then
                echo "[INFO] No LAN peers configured. Add one with: gamectl peers add <user@host>"
                return 0
            fi
            printf '%s\n' "$peers_out"
            ;;
        add)
            if ! _lan_validate_peer "$target"; then
                echo "[ERROR] Invalid SSH peer host: '${target:-<empty>}'" >&2
                return 1
            fi
            mkdir -p "$(dirname "$pfile")" || return 1
            if [ -f "$pfile" ] && grep -Fxq "$target" "$pfile" 2>/dev/null; then
                echo "[INFO] LAN peer already registered: $target"
                return 0
            fi
            printf '%s\n' "$target" >> "$pfile"
            echo "[VERIFIED] Added LAN peer: $target ($pfile)"
            ;;
        remove|rm|del)
            [ -n "$target" ] || { echo "Usage: gamectl peers remove <host>" >&2; return 1; }
            if [ ! -f "$pfile" ]; then
                echo "[INFO] No peers file found at $pfile"
                return 0
            fi
            local tmp_p
            tmp_p=$(mktemp "${pfile}.tmp.XXXXXX") || return 1
            grep -Fxv "$target" "$pfile" > "$tmp_p" 2>/dev/null || true
            mv -f "$tmp_p" "$pfile"
            echo "[VERIFIED] Removed LAN peer: $target"
            ;;
        --help|-h|help)
            echo "Usage: gamectl peers [list|add <user@host>|remove <host>]"
            ;;
        *)
            echo "[ERROR] Unknown peers action '$action'. Usage: gamectl peers [list|add <user@host>|remove <host>]" >&2
            return 1
            ;;
    esac
}

_lan_ssh_exec() {
    local peer="$1"
    local remote_cmd="$2"
    local timeout="${GAMECTL_LAN_TIMEOUT:-${GAMECTL_SSH_TIMEOUT:-2}}"
    [[ "$timeout" =~ ^[1-9][0-9]*$ ]] || timeout=2
    ssh -o LogLevel=ERROR -o ConnectTimeout="$timeout" -o BatchMode=yes "$peer" "$remote_cmd"
}

# Pull cached manifest zip or stplug-in lua + depotcache manifests from a LAN peer
lan_pull_manifest() {
    local appid="${1:-}"
    local explicit_peer="${2:-}"
    if [ -z "$appid" ] || [[ ! "$appid" =~ ^[0-9]+$ ]]; then
        echo "[ERROR] lan_pull_manifest requires a numeric AppID." >&2
        return 1
    fi

    local -a peers=()
    if [ -n "$explicit_peer" ]; then
        _lan_validate_peer "$explicit_peer" || { echo "[ERROR] Invalid peer: $explicit_peer" >&2; return 1; }
        peers=("$explicit_peer")
    else
        local p
        while IFS= read -r p; do
            [ -n "$p" ] && peers+=("$p")
        done < <(get_lan_peers)
    fi
    [ "${#peers[@]}" -gt 0 ] || return 1

    local timeout="${GAMECTL_LAN_TIMEOUT:-${GAMECTL_SSH_TIMEOUT:-2}}"
    [[ "$timeout" =~ ^[1-9][0-9]*$ ]] || timeout=2
    local rsync_ssh="ssh -o LogLevel=ERROR -o ConnectTimeout=${timeout} -o BatchMode=yes"

    local run_dir stage_dir
    run_dir="$(get_runtime_dir 2>/dev/null || echo "${TMPDIR:-/tmp}")"
    stage_dir=$(mktemp -d "${run_dir}/lan_mf_${appid}_XXXXXX") || return 1

    local peer remote_res kind r_files
    for peer in "${peers[@]}"; do
        echo "[INFO] Probing LAN peer '$peer' for AppID $appid manifest..." >&2
        remote_res=$(_lan_ssh_exec "$peer" "bash -s -- '$appid'" 2>/dev/null <<'REMOTE_MF'
appid="$1"
for z in "$HOME/.cache/gamectl/${appid}.zip" "$HOME/.cache/gamectl/manifest_${appid}.zip" "${XDG_RUNTIME_DIR:-/tmp}/gamectl-${UID:-$(id -u)}"/*"${appid}"*.zip; do
    if [ -f "$z" ]; then
        printf 'ZIP\t%s\n' "$z"
        exit 0
    fi
done
lua_f=""
for l in "$HOME/.local/share/Steam/config/stplug-in/${appid}.lua" "$HOME/.config/SLSsteam/manifests/${appid}.lua" "$HOME/.cache/gamectl/${appid}.lua"; do
    if [ -f "$l" ]; then
        lua_f="$l"
        break
    fi
done
[ -n "$lua_f" ] || exit 1
files="$lua_f"
dids=$(grep -Eo 'addappid\([[:space:]]*[0-9]+' "$lua_f" 2>/dev/null | tr -dc '0-9\n' || true)
for d in $dids; do
    for mf in "$HOME/.local/share/Steam/depotcache/${d}_"*.manifest "$HOME/.steam/root/depotcache/${d}_"*.manifest; do
        [ -f "$mf" ] && files="$files|$mf"
    done
done
printf 'RAW\t%s\n' "$files"
REMOTE_MF
) || continue

        [ -n "$remote_res" ] || continue
        IFS=$'\t' read -r kind r_files <<< "$remote_res"
        local out_zip="$run_dir/lan_manifest_${appid}.zip"

        if [ "$kind" = "ZIP" ] && [ -n "$r_files" ]; then
            if rsync -s -e "$rsync_ssh" -az "${peer}:${r_files}" "$out_zip" >/dev/null 2>&1; then
                if ! declare -F validate_manifest_zip >/dev/null 2>&1 || validate_manifest_zip "$out_zip" "$appid" true >/dev/null 2>&1; then
                    rm -rf "$stage_dir" 2>/dev/null || true
                    echo "[VERIFIED] Pulled manifest archive for AppID $appid from LAN peer '$peer'." >&2
                    printf '%s\n' "$out_zip"
                    return 0
                fi
                rm -f "$out_zip" 2>/dev/null || true
            fi
        elif [ "$kind" = "RAW" ] && [ -n "$r_files" ]; then
            local -a src_list=()
            IFS='|' read -r -a src_list <<< "$r_files"
            local pulled=0 rf
            for rf in "${src_list[@]}"; do
                [ -n "$rf" ] || continue
                rsync -s -e "$rsync_ssh" -az "${peer}:${rf}" "$stage_dir/" >/dev/null 2>&1 && pulled=$((pulled + 1))
            done
            if [ "$pulled" -gt 0 ] && command -v zip >/dev/null 2>&1; then
                (cd "$stage_dir" && zip -q -j "$out_zip" ./*) 2>/dev/null || true
                if [ -f "$out_zip" ] && { ! declare -F validate_manifest_zip >/dev/null 2>&1 || validate_manifest_zip "$out_zip" "$appid" true >/dev/null 2>&1; }; then
                    rm -rf "$stage_dir" 2>/dev/null || true
                    echo "[VERIFIED] Assembled manifest archive for AppID $appid from LAN peer '$peer'." >&2
                    printf '%s\n' "$out_zip"
                    return 0
                fi
                rm -f "$out_zip" 2>/dev/null || true
            fi
        fi
    done

    rm -rf "$stage_dir" 2>/dev/null || true
    return 1
}

# Pull installed game directory (or manifest only) from companion LAN mesh peer
lan_pull() {
    local query="" explicit_peer="" target_dir="" manifest_only=false with_pfx=false is_dry_run=false
    while [ $# -gt 0 ]; do
        case "$1" in
            --manifest-only|-m) manifest_only=true; shift ;;
            --with-pfx)         with_pfx=true; shift ;;
            --dry-run|-n)       is_dry_run=true; shift ;;
            --target|-d)
                [ -n "${2:-}" ] || { echo "[ERROR] --target requires a directory path." >&2; return 1; }
                target_dir="$2"; shift 2 ;;
            --target=*)
                target_dir="${1#*=}"; shift ;;
            --peer|-p)
                [ -n "${2:-}" ] || { echo "[ERROR] --peer requires a host." >&2; return 1; }
                explicit_peer="$2"; shift 2 ;;
            --peer=*)
                explicit_peer="${1#*=}"; shift ;;
            --help|-h)
                echo "Usage: gamectl lan-pull <appid|title> [peer] [--manifest-only] [--target <dir>] [--with-pfx] [--dry-run]"
                return 0 ;;
            -*)
                echo "[ERROR] Unknown option: $1" >&2
                return 1 ;;
            *)
                if [ -z "$query" ]; then query="$1"
                elif [ -z "$explicit_peer" ]; then explicit_peer="$1"
                else echo "[ERROR] Unexpected argument: $1" >&2; return 1; fi
                shift ;;
        esac
    done

    if [ -z "$query" ]; then
        echo "Usage: gamectl lan-pull <appid|title> [peer] [--manifest-only] [--target <dir>] [--with-pfx] [--dry-run]" >&2
        return 1
    fi

    if [ "$manifest_only" = true ]; then
        lan_pull_manifest "$query" "$explicit_peer"
        return $?
    fi

    local -a peers=()
    if [ -n "$explicit_peer" ]; then
        _lan_validate_peer "$explicit_peer" || { echo "[ERROR] Invalid peer host: $explicit_peer" >&2; return 1; }
        peers=("$explicit_peer")
    else
        local p
        while IFS= read -r p; do
            [ -n "$p" ] && peers+=("$p")
        done < <(get_lan_peers)
    fi

    if [ "${#peers[@]}" -eq 0 ]; then
        echo "[ERROR] No LAN peers configured. Run: gamectl peers add <user@host>" >&2
        return 1
    fi

    local timeout="${GAMECTL_LAN_TIMEOUT:-${GAMECTL_SSH_TIMEOUT:-2}}"
    [[ "$timeout" =~ ^[1-9][0-9]*$ ]] || timeout=2
    local rsync_ssh="ssh -o LogLevel=ERROR -o ConnectTimeout=${timeout} -o BatchMode=yes"

    local peer match_line r_appid r_title r_dir
    for peer in "${peers[@]}"; do
        echo "[INFO] Querying LAN peer '$peer' for '$query'..."
        match_line=$(_lan_ssh_exec "$peer" "bash -s -- '$query'" 2>/dev/null <<'REMOTE_FIND'
q="$1"
q_low=$(printf '%s' "$q" | tr '[:upper:]' '[:lower:]')
gctl=$(command -v gamectl 2>/dev/null || echo "$HOME/.local/bin/gamectl")
if [ -x "$gctl" ]; then
    while IFS=$'\t' read -r col1 col2 _col3 col4 _rest; do
        c1=$(printf '%s' "$col1" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
        c2=$(printf '%s' "$col2" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
        [ -n "$col4" ] || continue
        if [ "$c1" = "$q" ] || printf '%s' "$c2" | tr '[:upper:]' '[:lower:]' | grep -Fq "$q_low"; then
            printf '%s\t%s\t%s\n' "$c1" "$c2" "$col4"
            exit 0
        fi
    done < <("$gctl" --list 2>/dev/null || true)
fi
for base in "$HOME/Games" "$HOME/GOG Games" "$HOME/.local/share/Steam/steamapps/common"; do
    [ -d "$base" ] || continue
    for d in "$base"/*; do
        [ -d "$d" ] || continue
        bname="${d##*/}"
        if [[ "$q" =~ ^[0-9]+$ ]] && [ -f "$d/steam_appid.txt" ]; then
            aid=$(tr -dc '0-9' < "$d/steam_appid.txt" 2>/dev/null || true)
            if [ "$aid" = "$q" ]; then
                printf '%s\t%s\t%s\n' "$aid" "$bname" "$d"
                exit 0
            fi
        fi
        if printf '%s' "$bname" | tr '[:upper:]' '[:lower:]' | grep -Fq "$q_low"; then
            printf 'STANDALONE\t%s\t%s\n' "$bname" "$d"
            exit 0
        fi
    done
done
exit 1
REMOTE_FIND
) || continue

        [ -n "$match_line" ] || continue
        IFS=$'\t' read -r r_appid r_title r_dir <<< "$match_line"
        [ -n "$r_dir" ] && [[ "$r_dir" != *".."* ]] && [ "$r_dir" != "/" ] || continue
        [[ "$r_dir" == *$'\n'* || "$r_dir" == *$'\r'* ]] && continue
        declare -F validate_tui_fields >/dev/null 2>&1 && { validate_tui_fields "$r_appid" "$r_title" "$r_dir" || continue; }

        local dest_dir="$target_dir"
        if [ -z "$dest_dir" ]; then
            local safe_title="${r_title:-$(basename "$r_dir")}"
            safe_title=$(printf '%s' "$safe_title" | tr '/\\:*?"<>|' '_' | sed -E 's/^[.[:space:]]+//; s/[[:space:]]+$//')
            if declare -F resolve_target_library_dir >/dev/null 2>&1; then
                dest_dir="$(resolve_target_library_dir "${safe_title:-game}")"
            else
                dest_dir="${GAMECTL_LIBRARY_DIR:-$HOME/Games}/${safe_title:-game}"
            fi
        fi

        if [ "$is_dry_run" = false ] && [ -d "$dest_dir" ] && declare -F is_game_active_for_dir >/dev/null 2>&1; then
            local active_pid=""
            if active_pid=$(is_game_active_for_dir "$dest_dir" 2>/dev/null); then
                echo "[ERROR] Cannot pull into $dest_dir while game process is active (PID: $active_pid)." >&2
                return 1
            fi
        fi

        if [ "$is_dry_run" = false ] && [ -d "$dest_dir/saves" ] && declare -F backup_save >/dev/null 2>&1; then
            backup_save "$dest_dir" true || return $?
        fi

        local -a rsync_opts=("-avzP" "--exclude=.save_snapshots/")
        [ "$with_pfx" = false ] && rsync_opts+=("--exclude=pfx/")
        [ "$is_dry_run" = true ] && rsync_opts+=("-n")

        [ "$is_dry_run" = false ] && { mkdir -p "$dest_dir" || return 1; }
        echo "[INFO] Pulling '$r_title' ($r_appid) from ${peer}:${r_dir}/ -> ${dest_dir}/"
        if ! rsync -s -e "$rsync_ssh" "${rsync_opts[@]}" "${peer}:${r_dir}/" "${dest_dir}/"; then
            echo "[ERROR] LAN mesh transfer from ${peer}:${r_dir} failed." >&2
            return 1
        fi

        if [ "$is_dry_run" = true ]; then
            echo "[INFO] [DRY-RUN] LAN mesh pull simulated from ${peer}:${r_dir} -> ${dest_dir}."
            return 0
        fi

        declare -F ensure_linux_binaries_executable >/dev/null 2>&1 && ensure_linux_binaries_executable "$dest_dir"
        if [[ "$r_appid" =~ ^[0-9]+$ ]] && declare -F inject_game >/dev/null 2>&1; then
            inject_game "$dest_dir" "$r_appid" --no-sync >/dev/null 2>&1 || true
        fi
        declare -F invalidate_scan_cache >/dev/null 2>&1 && invalidate_scan_cache || true
        echo "[VERIFIED] LAN mesh pull complete: '$r_title' ($r_appid) from $peer -> $dest_dir"
        declare -F log_msg >/dev/null 2>&1 && log_msg "INFO" "LAN" "Pulled '$r_title' ($r_appid) from $peer to $dest_dir" || true
        return 0
    done

    echo "[ERROR] '$query' not found on any reachable LAN peer (${peers[*]})." >&2
    return 1
}

# Fallback helper called by download_game when external manifest providers fail (404)
# Prints manifest zip path on stdout if manifest was retrieved (rc=0); returns 2 if full game was pulled via rsync; returns 1 otherwise.
lan_fallback_for_download() {
    local appid="$1"
    local target_dir="${2:-}"
    local title="${3:-}"
    declare -F get_lan_peers >/dev/null 2>&1 || return 1
    [ -n "$(get_lan_peers 2>/dev/null || true)" ] || return 1

    echo "[WARN] External manifest providers returned no archive for AppID $appid. Trying LAN mesh fallback..." >&2
    local mzip=""
    mzip=$(lan_pull_manifest "$appid" 2>/dev/null || true)
    if [ -n "$mzip" ] && [ -f "$mzip" ]; then
        printf '%s\n' "$mzip"
        return 0
    fi

    local lan_dest="$target_dir"
    if [ -z "$lan_dest" ] && declare -F resolve_standalone_library_dir >/dev/null 2>&1; then
        lan_dest="$(resolve_standalone_library_dir "${title:-AppID_${appid}}")"
    fi
    if lan_pull "$appid" --target "$lan_dest"; then
        return 2
    fi
    return 1
}

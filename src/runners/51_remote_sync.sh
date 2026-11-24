# Probe SSH remote $HOME with honest error classification on stderr
probe_ssh_remote_home() {
    local ssh_host="$1"
    local ssh_timeout="${GAMECTL_SSH_TIMEOUT:-5}"
    [[ "$ssh_timeout" =~ ^[1-9][0-9]*$ ]] || ssh_timeout=5

    local run_dir ssh_err_file
    run_dir="$(get_runtime_dir)"
    ssh_err_file=$(mktemp "$run_dir/ssh_probe_${$}.XXXXXX") || return 1

    local remote_home="" rc=0
    remote_home=$(ssh -o LogLevel=ERROR -o ConnectTimeout="$ssh_timeout" -o BatchMode=yes "$ssh_host" 'printf %s "$HOME"' 2>"$ssh_err_file") || rc=$?

    local ssh_err=""
    if [ -s "$ssh_err_file" ]; then
        ssh_err=$(tr -d '\r' < "$ssh_err_file" | grep -v '^[[:space:]]*$' | head -n 4 || true)
    fi
    rm -f "$ssh_err_file" 2>/dev/null || true

    if [ "$rc" -eq 0 ] && [ -n "$remote_home" ] && [[ "$remote_home" != *$'\n'* && "$remote_home" != *$'\r'* ]]; then
        printf '%s\n' "$remote_home"
        return 0
    fi

    if printf '%s\n' "$ssh_err" | grep -qiE 'Permission denied|publickey|Authentication failed|passphrase'; then
        echo "[ERROR] SSH authentication failed for '$ssh_host':" >&2
        printf '%s\n' "$ssh_err" >&2
        echo "Hint: Load your SSH key into ssh-agent first (e.g. ssh-add ~/.ssh/<key>)." >&2
    elif printf '%s\n' "$ssh_err" | grep -qiE 'Host key verification failed|REMOTE HOST IDENTIFICATION'; then
        echo "[ERROR] SSH host key verification failed for '$ssh_host':" >&2
        printf '%s\n' "$ssh_err" >&2
        echo "Hint: Verify host fingerprint once interactively via: ssh $ssh_host" >&2
    elif printf '%s\n' "$ssh_err" | grep -qiE 'Could not resolve hostname|Name or service not known'; then
        echo "[ERROR] SSH hostname '$ssh_host' could not be resolved:" >&2
        printf '%s\n' "$ssh_err" >&2
    else
        echo "[WARN] Remote host '$ssh_host' offline or unreachable (timeout ${ssh_timeout}s)." >&2
        if [ -n "$ssh_err" ]; then
            echo "SSH detail: $ssh_err" >&2
        fi
    fi
    return 1
}

# Resolve target SSH base directory (default mirror or custom prefix isolated per game folder)
resolve_ssh_remote_base() {
    local remote_home="${1%/}"
    local rel_path="$2"
    local custom_base="$3"
    local game_leaf="$4"

    if [ -z "$custom_base" ]; then
        printf '%s/%s\n' "$remote_home" "$rel_path"
        return 0
    fi

    local resolved=""
    if [ "$custom_base" = "~" ]; then
        resolved="$remote_home"
    elif [[ "$custom_base" == "~/"* ]]; then
        local sub="${custom_base#\~/}"
        while [[ "$sub" == */ ]]; do sub="${sub%/}"; done
        if [ -n "$sub" ]; then
            resolved="${remote_home}/${sub}"
        else
            resolved="$remote_home"
        fi
    elif [[ "$custom_base" == /* ]]; then
        resolved="$custom_base"
        while [[ "$resolved" == */ && "$resolved" != "/" ]]; do resolved="${resolved%/}"; done
    else
        local rel_sub="$custom_base"
        while [[ "$rel_sub" == */ ]]; do rel_sub="${rel_sub%/}"; done
        if [ -n "$rel_sub" ]; then
            resolved="${remote_home}/${rel_sub}"
        else
            resolved="$remote_home"
        fi
    fi

    if [ "$resolved" = "/" ]; then
        printf '/%s\n' "$game_leaf"
    else
        printf '%s/%s\n' "$resolved" "$game_leaf"
    fi
}

# Resolve target rclone saves path (isolated per game folder)
resolve_rclone_remote_saves() {
    local endpoint="$1"
    local custom_base="$2"
    local game_leaf="$3"

    if [ -z "$custom_base" ]; then
        printf '%sgamectl-saves/%s/saves\n' "$endpoint" "$game_leaf"
    else
        printf '%s%s/%s/saves\n' "$endpoint" "$custom_base" "$game_leaf"
    fi
}

# Sync savegame to remote host or rclone cloud remote (Push)
sync_save_remote() {
    local is_dry_run=false
    local is_force=false
    local -a pos=()
    local arg

    for arg in "$@"; do
        case "$arg" in
            --dry-run|-n) is_dry_run=true ;;
            --force|-f) is_force=true ;;
            *) pos+=("$arg") ;;
        esac
    done

    local gdir="${pos[0]:-}"
    local title="${pos[1]:-Game}"
    local override_host="${pos[2]:-}"

    local sdir="$gdir/saves"
    local rhost="$override_host"
    [ -z "$rhost" ] && rhost=$(get_remote_host)

    if [ -z "$gdir" ] || [ ! -d "$sdir" ]; then
        echo "[ERROR] Portable saves directory not found in ${gdir:-<empty>}" >&2
        return 1
    fi

    if [ "$is_dry_run" = false ] && [ "$is_force" = false ]; then
        local active_pid=""
        if active_pid=$(is_game_active_for_dir "$gdir" 2>/dev/null); then
            echo "[ERROR] Cannot sync saves while game process is active (PID: $active_pid). Close the game first or pass --force." >&2
            return 1
        fi
    fi

    parse_remote_sync_target "$rhost" || return 1

    local canon_gdir game_leaf
    canon_gdir="$(cd "$gdir" 2>/dev/null && pwd || echo "$gdir")"
    game_leaf="$(basename "$canon_gdir")"
    if [ -z "$game_leaf" ] || [ "$game_leaf" = "." ] || [ "$game_leaf" = ".." ] || [ "$game_leaf" = "/" ]; then
        echo "[ERROR] Invalid game directory name for remote sync: $canon_gdir" >&2
        return 1
    fi

    local rel_path
    if [[ "$canon_gdir" == "$HOME/"* ]]; then
        rel_path="${canon_gdir#$HOME/}"
    else
        # For games stored on secondary drives (/mnt, /media, /data, etc.)
        rel_path="Games/$(basename "$canon_gdir")"
    fi
    rel_path="${rel_path#/}"

    if [ -z "$rel_path" ] || [[ "$rel_path" == *$'\n'* || "$rel_path" == *$'\r'* ]] || \
       [[ "$rel_path" == ".." || "$rel_path" == "../"* || "$rel_path" == *"/.." || "$rel_path" == *"/../"* ]]; then
        echo "[ERROR] Invalid relative remote sync path: $rel_path" >&2
        return 1
    fi

    local ssh_timeout="${GAMECTL_SSH_TIMEOUT:-5}"
    [[ "$ssh_timeout" =~ ^[1-9][0-9]*$ ]] || ssh_timeout=5

    if [ "$REMOTE_TARGET_BACKEND" = "rclone" ]; then
        local rclone_saves run_dir rc_out rc=0
        rclone_saves=$(resolve_rclone_remote_saves "$REMOTE_TARGET_ENDPOINT" "$REMOTE_TARGET_BASE" "$game_leaf")
        run_dir="$(get_runtime_dir)"
        rc_out=$(mktemp "$run_dir/rclone_push_${$}.XXXXXX") || return 1

        local -a rclone_opts=(
            "--exclude" "*.tmp"
            "--contimeout" "${ssh_timeout}s"
            "--timeout" "30s"
            "--retries" "2"
            "--low-level-retries" "3"
            "--stats-one-line"
        )
        [ "$is_dry_run" = true ] && rclone_opts+=("--dry-run")

        echo "[INFO] Synchronizing savegame $title to $rclone_saves..."
        rclone copy "${rclone_opts[@]}" -- "$sdir" "$rclone_saves" >"$rc_out" 2>&1 || rc=$?
        if [ "$rc" -ne 0 ]; then
            echo "[ERROR] Savegame synchronization via rclone ($rclone_saves) failed (exit $rc)." >&2
            [ -s "$rc_out" ] && tail -n 8 "$rc_out" >&2
            rm -f "$rc_out" 2>/dev/null || true
            return 1
        fi
        [ -s "$rc_out" ] && cat "$rc_out"
        rm -f "$rc_out" 2>/dev/null || true

        if [ "$is_dry_run" = true ]; then
            echo "[INFO] [DRY-RUN] Savegame synchronization via rclone simulated successfully."
        else
            echo "[VERIFIED] Savegame synchronization to $rclone_saves completed."
        fi
        return 0
    fi

    local ssh_host="$REMOTE_TARGET_ENDPOINT"
    echo "[INFO] Checking connectivity to $ssh_host..."
    local remote_home
    remote_home=$(probe_ssh_remote_home "$ssh_host") || return 1

    local remote_base remote_saves q_base
    remote_base=$(resolve_ssh_remote_base "$remote_home" "$rel_path" "$REMOTE_TARGET_BASE" "$game_leaf")
    remote_saves="${remote_base}/saves"
    q_base="'${remote_base//\'/\'\\\'\'}'"

    echo "[INFO] Synchronizing savegame $title to ${ssh_host}:${remote_saves}..."
    local -a ssh_opts=(-o LogLevel=ERROR -o ConnectTimeout="$ssh_timeout" -o BatchMode=yes)
    local rsync_ssh="ssh -o LogLevel=ERROR -o ConnectTimeout=${ssh_timeout} -o BatchMode=yes"
    local -a rsync_opts=("-avzP" "--exclude=*.tmp")
    [ "$is_dry_run" = true ] && rsync_opts+=("-n")

    if [ "$is_dry_run" = false ]; then
        if ! ssh "${ssh_opts[@]}" "$ssh_host" "mkdir -p -- $q_base"; then
            echo "[ERROR] Failed to prepare remote save directory on $ssh_host ($remote_base)." >&2
            return 1
        fi
    fi

    if ! rsync -s -e "$rsync_ssh" "${rsync_opts[@]}" "$sdir/" "${ssh_host}:${remote_saves}/"; then
        echo "[ERROR] Savegame synchronization to ${ssh_host}:${remote_saves} failed." >&2
        return 1
    fi

    if [ "$is_dry_run" = true ]; then
        echo "[INFO] [DRY-RUN] Savegame synchronization simulated successfully."
    else
        echo "[VERIFIED] Savegame synchronization to ${ssh_host}:${remote_saves} completed."
    fi
    return 0
}

# Pull savegame from remote companion host or rclone cloud remote to local workstation (Pull)
pull_save_remote() {
    local is_dry_run=false
    local -a pos=()
    local arg

    for arg in "$@"; do
        case "$arg" in
            --dry-run|-n) is_dry_run=true ;;
            *) pos+=("$arg") ;;
        esac
    done

    local gdir="${pos[0]:-}"
    local title="${pos[1]:-Game}"
    local override_host="${pos[2]:-}"

    local sdir="$gdir/saves"
    local rhost="$override_host"
    [ -z "$rhost" ] && rhost=$(get_remote_host)

    if [ -z "$gdir" ] || [ ! -d "$gdir" ]; then
        echo "[ERROR] Target game directory not found: ${gdir:-<empty>}" >&2
        return 1
    fi

    if [ "$is_dry_run" = false ]; then
        local active_pid=""
        if active_pid=$(is_game_active_for_dir "$gdir" 2>/dev/null); then
            echo "[ERROR] Cannot pull saves while game process is active (PID: $active_pid). Close the game first." >&2
            return 1
        fi
    fi

    parse_remote_sync_target "$rhost" || return 1

    local canon_gdir game_leaf
    canon_gdir="$(cd "$gdir" 2>/dev/null && pwd || echo "$gdir")"
    game_leaf="$(basename "$canon_gdir")"
    if [ -z "$game_leaf" ] || [ "$game_leaf" = "." ] || [ "$game_leaf" = ".." ] || [ "$game_leaf" = "/" ]; then
        echo "[ERROR] Invalid game directory name for remote pull: $canon_gdir" >&2
        return 1
    fi

    local rel_path
    if [[ "$canon_gdir" == "$HOME/"* ]]; then
        rel_path="${canon_gdir#$HOME/}"
    else
        rel_path="Games/$(basename "$canon_gdir")"
    fi
    rel_path="${rel_path#/}"

    if [ -z "$rel_path" ] || [[ "$rel_path" == *$'\n'* || "$rel_path" == *$'\r'* ]] || \
       [[ "$rel_path" == ".." || "$rel_path" == "../"* || "$rel_path" == *"/.." || "$rel_path" == *"/../"* ]]; then
        echo "[ERROR] Invalid relative remote sync path: $rel_path" >&2
        return 1
    fi

    local ssh_timeout="${GAMECTL_SSH_TIMEOUT:-5}"
    [[ "$ssh_timeout" =~ ^[1-9][0-9]*$ ]] || ssh_timeout=5

    if [ "$REMOTE_TARGET_BACKEND" = "rclone" ]; then
        local rclone_saves run_dir rc_out rc=0
        rclone_saves=$(resolve_rclone_remote_saves "$REMOTE_TARGET_ENDPOINT" "$REMOTE_TARGET_BASE" "$game_leaf")
        run_dir="$(get_runtime_dir)"
        rc_out=$(mktemp "$run_dir/rclone_pull_${$}.XXXXXX") || return 1

        if ! rclone lsf --max-depth 1 --contimeout "${ssh_timeout}s" --timeout 30s --retries 2 -- "$rclone_saves" >"$rc_out" 2>&1; then
            echo "[ERROR] Remote saves directory not found or inaccessible on $rclone_saves:" >&2
            [ -s "$rc_out" ] && tail -n 6 "$rc_out" >&2
            rm -f "$rc_out" 2>/dev/null || true
            return 1
        fi

        if [ "$is_dry_run" = false ] && { [ -d "$sdir" ] || [ -L "$sdir" ]; }; then
            if ! backup_save "$gdir" true; then
                echo "[ERROR] Pre-pull local save backup failed. Aborting pull to prevent unrecoverable save overwrite." >&2
                log_msg "ERROR" "SAVE" "Pre-pull local save backup failed for '$title'"
                rm -f "$rc_out" 2>/dev/null || true
                return 1
            fi
        fi

        if [ "$is_dry_run" = false ]; then
            if ! mkdir -p "$sdir"; then
                rm -f "$rc_out" 2>/dev/null || true
                return 1
            fi
        fi

        local -a rclone_opts=(
            "--exclude" "*.tmp"
            "--contimeout" "${ssh_timeout}s"
            "--timeout" "30s"
            "--retries" "2"
            "--low-level-retries" "3"
            "--stats-one-line"
        )
        [ "$is_dry_run" = true ] && rclone_opts+=("--dry-run")

        echo "[INFO] Pulling savegame for '$title' from $rclone_saves -> $sdir/..."
        : > "$rc_out"
        rclone copy "${rclone_opts[@]}" -- "$rclone_saves" "$sdir" >"$rc_out" 2>&1 || rc=$?
        if [ "$rc" -ne 0 ]; then
            echo "[ERROR] Savegame pull via rclone ($rclone_saves) failed (exit $rc)." >&2
            [ -s "$rc_out" ] && tail -n 8 "$rc_out" >&2
            rm -f "$rc_out" 2>/dev/null || true
            return 1
        fi
        [ -s "$rc_out" ] && cat "$rc_out"
        rm -f "$rc_out" 2>/dev/null || true

        if [ "$is_dry_run" = true ]; then
            echo "[INFO] [DRY-RUN] Remote savegame pull via rclone simulated successfully (no local files modified)."
        else
            echo "[VERIFIED] Savegame pull from $rclone_saves completed."
            log_msg "INFO" "SAVE" "Pulled savegame for '$title' from $rclone_saves"
        fi
        return 0
    fi

    local ssh_host="$REMOTE_TARGET_ENDPOINT"
    echo "[INFO] Checking connectivity to $ssh_host..."
    local remote_home
    remote_home=$(probe_ssh_remote_home "$ssh_host") || return 1

    local remote_base remote_saves q_saves
    remote_base=$(resolve_ssh_remote_base "$remote_home" "$rel_path" "$REMOTE_TARGET_BASE" "$game_leaf")
    remote_saves="${remote_base}/saves"
    q_saves="'${remote_saves//\'/\'\\\'\'}'"

    local -a ssh_opts=(-o LogLevel=ERROR -o ConnectTimeout="$ssh_timeout" -o BatchMode=yes)
    # Verify remote saves directory exists
    if ! ssh "${ssh_opts[@]}" "$ssh_host" "test -d $q_saves"; then
        echo "[ERROR] Remote saves directory not found on $ssh_host: $remote_saves" >&2
        return 1
    fi

    # Protect local savegame before pulling remote overwrites
    if [ "$is_dry_run" = false ] && { [ -d "$sdir" ] || [ -L "$sdir" ]; }; then
        if ! backup_save "$gdir" true; then
            echo "[ERROR] Pre-pull local save backup failed. Aborting pull to prevent unrecoverable save overwrite." >&2
            log_msg "ERROR" "SAVE" "Pre-pull local save backup failed for '$title'"
            return 1
        fi
    fi

    if [ "$is_dry_run" = false ]; then
        mkdir -p "$sdir" || return 1
    fi

    local rsync_ssh="ssh -o LogLevel=ERROR -o ConnectTimeout=${ssh_timeout} -o BatchMode=yes"
    local -a rsync_opts=("-avzP" "--exclude=*.tmp")
    [ "$is_dry_run" = true ] && rsync_opts+=("-n")

    echo "[INFO] Pulling savegame for '$title' from ${ssh_host}:${remote_saves}/ -> $sdir/..."
    if ! rsync -s -e "$rsync_ssh" "${rsync_opts[@]}" "${ssh_host}:${remote_saves}/" "$sdir/"; then
        echo "[ERROR] Savegame pull from ${ssh_host}:${remote_saves} failed." >&2
        return 1
    fi

    if [ "$is_dry_run" = true ]; then
        echo "[INFO] [DRY-RUN] Remote savegame pull simulated successfully (no local files modified)."
    else
        echo "[VERIFIED] Savegame pull from ${ssh_host}:${remote_saves} completed."
        log_msg "INFO" "SAVE" "Pulled savegame for '$title' from ${ssh_host}:${remote_saves}"
    fi
    return 0
}

# Aliases for remote savegame synchronization
sync_to_companion() {
    sync_save_remote "$@"
}

sync_to_tuf() {
    sync_save_remote "$@"
}

pull_from_companion() {
    pull_save_remote "$@"
}

pull_from_tuf() {
    pull_save_remote "$@"
}

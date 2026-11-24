# Auto-backup savegame (Rolling 3 snapshots)
backup_save() (
    local game_dir="$1"
    local is_quiet="${2:-false}"

    if [ -z "$game_dir" ] || [ ! -d "$game_dir" ]; then
        [ "$is_quiet" = true ] || echo "[ERROR] Target game directory not found: ${game_dir:-<empty>}" >&2
        return 1
    fi

    local save_dir="$game_dir/saves"

    # If saves path does not exist (neither a directory nor a symlink)
    if [ ! -e "$save_dir" ] && [ ! -L "$save_dir" ]; then
        if [ -e "$game_dir/.save_snapshots/.lock" ] ||
           [ -e "$game_dir/.save_snapshots/.pre_restore_stash" ] ||
           [ -L "$game_dir/.save_snapshots/.pre_restore_stash" ]; then
            echo "[ERROR] Active saves are missing with pending save recovery in $game_dir/.save_snapshots" >&2
            return 1
        fi
        if [ "$is_quiet" = true ]; then
            return 0
        fi
        echo "[WARN] Portable saves directory ($save_dir) not found." >&2
        log_msg "WARN" "SAVE" "Portable saves directory ($save_dir) not found"
        echo "       Game has not been injected with GBE Fork or lacks an isolated save directory." >&2
        echo "       Press <CTRL-I> first to enable portable saves." >&2
        return 1
    fi

    # Symlink validation: ensure target exists and is a directory
    if [ -L "$save_dir" ]; then
        local target_path
        target_path=$(readlink -f "$save_dir" 2>/dev/null || true)
        if [ -z "$target_path" ] || [ ! -d "$target_path" ]; then
            [ "$is_quiet" = true ] || echo "[ERROR] Portable saves symlink points to invalid directory: $save_dir -> ${target_path:-broken}" >&2
            log_msg "ERROR" "SAVE" "Portable saves symlink is broken for $(basename "$game_dir")"
            return 1
        fi
    elif [ ! -d "$save_dir" ]; then
        [ "$is_quiet" = true ] || echo "[ERROR] Portable saves path is not a directory: $save_dir" >&2
        log_msg "ERROR" "SAVE" "Portable saves path is not a directory for $(basename "$game_dir")"
        return 1
    fi

    local snap_dir="$game_dir/.save_snapshots"
    mkdir -p "$snap_dir" 2>/dev/null || {
        [ "$is_quiet" = true ] || echo "[ERROR] Failed to create snapshots directory: $snap_dir" >&2
        return 1
    }

    # shortcut: SIGKILL retains lock/staging for manual recovery; add a durable journal before automatic takeover.
    # Per-game lock using atomic directory creation
    local lock_dir="$snap_dir/.lock"
    local lock_pid=$BASHPID
    local lock_retries=15
    while ! mkdir "$lock_dir" 2>/dev/null; do
        lock_retries=$((lock_retries - 1))
        if [ "$lock_retries" -le 0 ]; then
            echo "[ERROR] Save lock unavailable: $lock_dir. Review owner/recovery data before removing a stale lock." >&2
            log_msg "ERROR" "SAVE" "Lock contention on backup for $(basename "$game_dir")"
            return 1
        fi
        sleep 0.1
    done
    local stage_dir="" committed=false rollback_ok=true
    local -a move_sources=() move_targets=()
    _cleanup_backup() {
        local rc=$? i
        trap - EXIT
        if [ "$committed" = false ]; then
            for ((i=${#move_sources[@]}-1; i>=0; i--)); do
                if [ ! -e "${move_sources[i]}" ] && [ ! -L "${move_sources[i]}" ] &&
                   { [ -e "${move_targets[i]}" ] || [ -L "${move_targets[i]}" ]; }; then
                    mv -T -- "${move_targets[i]}" "${move_sources[i]}" || rollback_ok=false
                fi
            done
        fi
        if [ "$rollback_ok" = true ]; then
            [ -z "$stage_dir" ] || rm -rf -- "$stage_dir" || rc=1
        else
            echo "[ERROR] Snapshot rollback incomplete; lock and recovery files retained in $stage_dir" >&2
            rc=1
        fi
        if [ "$rollback_ok" = true ]; then
            rm -rf -- "$lock_dir" || rc=1
        fi
        exit "$rc"
    }
    trap _cleanup_backup EXIT
    trap 'exit 130' INT
    trap 'exit 143' TERM
    echo "$lock_pid" > "$lock_dir/pid" || return 1

    stage_dir=$(mktemp -d "$snap_dir/.stage_backup.XXXXXX") || return 1
    mkdir "$stage_dir/new" || return 1

    # Copy files dereferencing symlinks so snapshot is an independent copy
    local cp_rc=0
    cp -aL "$save_dir/." "$stage_dir/new/" 2>/dev/null || cp_rc=$?

    if [ "$cp_rc" -ne 0 ]; then
        [ "$is_quiet" = true ] || echo "[ERROR] Failed to copy savegame files to snapshot staging." >&2
        log_msg "ERROR" "SAVE" "Failed to copy savegame files for $(basename "$game_dir")"
        return 1
    fi

    # Retain slot3 until every rename succeeds; reverse completed moves on failure.
    local -a sources=("$snap_dir/slot3" "$snap_dir/slot2" "$snap_dir/slot1" "$stage_dir/new")
    local -a targets=("$stage_dir/slot3" "$snap_dir/slot3" "$snap_dir/slot2" "$snap_dir/slot1")
    local i
    for i in "${!sources[@]}"; do
        [ -e "${sources[i]}" ] || [ -L "${sources[i]}" ] || continue
        move_sources+=("${sources[i]}")
        move_targets+=("${targets[i]}")
        if ! mv -T -- "${sources[i]}" "${targets[i]}"; then
            echo "[ERROR] Snapshot rotation failed: ${sources[i]} -> ${targets[i]}" >&2
            return 1
        fi
    done
    committed=true

    [ "$is_quiet" = true ] || echo "[INFO] Save snapshot created successfully in slot1 ($snap_dir/slot1)"
    log_msg "INFO" "SAVE" "Save snapshot created in slot1 for $(basename "$game_dir")"
    return 0
)

# Check if any active game PID in runtime active_games matches game_dir
is_game_active_for_dir() {
    local game_dir="$1"
    [ -n "$game_dir" ] || return 1
    local active_dir
    active_dir="$(get_runtime_dir)/active_games"
    [ -d "$active_dir" ] || return 1

    local canon_target
    canon_target=$(realpath -m -- "$game_dir" 2>/dev/null || (cd "$game_dir" 2>/dev/null && pwd -P) || printf '%s' "$game_dir")
    canon_target="${canon_target%/}"
    [ -n "$canon_target" ] || canon_target="/"

    local inf a_pid a_dir canon_a_dir
    for inf in "$active_dir"/*.info; do
        [ -f "$inf" ] || continue
        a_pid=$(grep -E '^PID=' "$inf" 2>/dev/null | head -n 1 | cut -d'=' -f2- | tr -dc '0-9')
        [ -n "$a_pid" ] || continue
        kill -0 "$a_pid" 2>/dev/null || continue
        a_dir=$(grep -E '^DIR=' "$inf" 2>/dev/null | head -n 1 | cut -d'=' -f2-)
        [ -n "$a_dir" ] || continue
        canon_a_dir=$(realpath -m -- "$a_dir" 2>/dev/null || (cd "$a_dir" 2>/dev/null && pwd -P) || printf '%s' "$a_dir")
        canon_a_dir="${canon_a_dir%/}"
        [ -n "$canon_a_dir" ] || canon_a_dir="/"
        if [ "$canon_a_dir" = "$canon_target" ]; then
            printf '%s\n' "$a_pid"
            return 0
        fi
    done
    return 1
}

# Restore savegame snapshot from recovery slot (slot1, slot2, or slot3)
restore_save() (
    local game_dir="$1"
    local slot="${2:-1}"
    local is_quiet="${3:-false}"

    if [ -z "$game_dir" ] || [ ! -d "$game_dir" ]; then
        [ "$is_quiet" = true ] || echo "[ERROR] Target game directory not found: ${game_dir:-<empty>}" >&2
        return 1
    fi

    local active_pid=""
    if active_pid=$(is_game_active_for_dir "$game_dir" 2>/dev/null); then
        [ "$is_quiet" = true ] || echo "[ERROR] Cannot restore saves while game process is active (PID: $active_pid). Close the game first." >&2
        log_msg "ERROR" "SAVE" "Restore blocked while active game PID $active_pid running for $(basename "$game_dir")"
        return 1
    fi

    local snap_dir="$game_dir/.save_snapshots"
    local save_dir="$game_dir/saves"
    local stash_dir="$snap_dir/.pre_restore_stash"

    if [ ! -d "$snap_dir" ]; then
        [ "$is_quiet" = true ] || echo "[ERROR] No savegame snapshots directory found in: $game_dir" >&2
        return 1
    fi

    # Normalize slot notation: "1", "slot1", "2", "slot2", etc.
    slot="${slot#slot}"
    case "$slot" in
        1|2|3) ;;
        *)
            [ "$is_quiet" = true ] || echo "[ERROR] Invalid recovery slot: use 1, 2, or 3." >&2
            return 1
            ;;
    esac
    local target_slot="$snap_dir/slot${slot}"

    if [ ! -d "$target_slot" ]; then
        if [ "$is_quiet" != true ]; then
            echo "[ERROR] Recovery snapshot slot $slot not found in: $snap_dir" >&2
            echo "        Available slots:" >&2
            for s in "$snap_dir"/slot*; do
                [ -d "$s" ] && echo "        - $(basename "$s")" >&2
            done
        fi
        return 1
    fi

    # Per-game lock
    local lock_dir="$snap_dir/.lock"
    local lock_pid=$BASHPID
    local lock_retries=15
    while ! mkdir "$lock_dir" 2>/dev/null; do
        lock_retries=$((lock_retries - 1))
        if [ "$lock_retries" -le 0 ]; then
            echo "[ERROR] Save lock unavailable: $lock_dir. Review owner/recovery data before removing a stale lock." >&2
            log_msg "ERROR" "SAVE" "Lock contention on restore for $(basename "$game_dir")"
            return 1
        fi
        sleep 0.1
    done
    local restore_stage="" committed=false rollback_ok=true
    local -a move_sources=() move_targets=()
    _cleanup_restore() {
        local rc=$? i
        trap - EXIT
        if [ "$committed" = false ]; then
            for ((i=${#move_sources[@]}-1; i>=0; i--)); do
                if [ ! -e "${move_sources[i]}" ] && [ ! -L "${move_sources[i]}" ] &&
                   { [ -e "${move_targets[i]}" ] || [ -L "${move_targets[i]}" ]; }; then
                    mv -T -- "${move_targets[i]}" "${move_sources[i]}" || rollback_ok=false
                fi
            done
        fi
        if [ "$rollback_ok" = true ]; then
            [ -z "$restore_stage" ] || rm -rf -- "$restore_stage" || rc=1
        else
            echo "[ERROR] Restore rollback incomplete; lock and recovery files retained in $restore_stage and $stash_dir" >&2
            rc=1
        fi
        if [ "$rollback_ok" = true ]; then
            rm -rf -- "$lock_dir" || rc=1
        fi
        exit "$rc"
    }
    trap _cleanup_restore EXIT
    trap 'exit 130' INT
    trap 'exit 143' TERM
    echo "$lock_pid" > "$lock_dir/pid" || return 1

    if [ ! -e "$save_dir" ] && [ ! -L "$save_dir" ] && [ -d "$stash_dir" ]; then
        mv -T -- "$stash_dir" "$save_dir" || return 1
        log_msg "WARN" "SAVE" "Recovered missing active saves from .pre_restore_stash for $(basename "$game_dir")"
    fi

    restore_stage=$(mktemp -d "$game_dir/.save_restore_stage.XXXXXX") || return 1
    mkdir "$restore_stage/new" || return 1

    local cp_rc=0
    cp -aL "$target_slot/." "$restore_stage/new/" 2>/dev/null || cp_rc=$?

    if [ "$cp_rc" -ne 0 ]; then
        [ "$is_quiet" = true ] || echo "[ERROR] Failed to stage snapshot files for restore." >&2
        log_msg "ERROR" "SAVE" "Restore staging failed for $(basename "$game_dir")"
        return 1
    fi

    # Preserve the previous recovery stash until the new active save is committed.
    local -a sources=() targets=()
    if [ -e "$save_dir" ] || [ -L "$save_dir" ]; then
        if [ -e "$stash_dir" ] || [ -L "$stash_dir" ]; then
            sources+=("$stash_dir")
            targets+=("$restore_stage/previous_stash")
        fi
        sources+=("$save_dir")
        targets+=("$stash_dir")
    fi
    sources+=("$restore_stage/new")
    targets+=("$save_dir")
    local i
    for i in "${!sources[@]}"; do
        move_sources+=("${sources[i]}")
        move_targets+=("${targets[i]}")
        if ! mv -T -- "${sources[i]}" "${targets[i]}"; then
            echo "[ERROR] Restore rename failed: ${sources[i]} -> ${targets[i]}" >&2
            return 1
        fi
    done
    committed=true

    [ "$is_quiet" = true ] || echo "[VERIFIED] Savegame restored successfully from slot${slot} ($target_slot -> $save_dir)"
    log_msg "INFO" "SAVE" "Savegame restored from slot${slot} for $(basename "$game_dir")"
    return 0
)

# Internal helper: check whether a prefix folder name is OS/driver/runtime noise
_is_prefix_save_noise() {
    local name_lc="${1,,}"
    case "$name_lc" in
        microsoft|temp|packages|crashdumps|d3dscache|nvidia|amd|intel|wine|steam|\
        "goldberg steamemu saves"|"gse saves"|mesa_shader_cache|vulkan|windows|\
        "internet explorer"|mozilla|google|chromium|cache|shaders|dxvk_state_cache|nv_cache)
            return 0
            ;;
    esac
    return 1
}

# Internal helper: verify deepest existing ancestor of a target path stays within a root
_check_confined_ancestor() {
    local probe="$1"
    local root="$2"
    while [ "$probe" != "/" ] && [ "$probe" != "." ] && [ ! -e "$probe" ] && [ ! -L "$probe" ]; do
        probe=$(dirname "$probe")
    done
    local probe_real
    probe_real=$(realpath -e -- "$probe" 2>/dev/null || true)
    [ -n "$probe_real" ] || return 1
    if [ "$probe_real" = "$root" ] || [[ "$probe_real" == "$root"/* ]]; then
        return 0
    fi
    return 1
}

# Discover savegame directories inside a Wine/Proton prefix (strictly read-only)
discover_prefix_saves() {
    local game_dir="${1:-}"
    if [ -z "$game_dir" ] || [ ! -d "$game_dir" ]; then
        echo "[ERROR] Target game directory not found: ${game_dir:-<empty>}" >&2
        return 1
    fi

    local pfx_path="$game_dir/pfx"
    local users_path="$pfx_path/drive_c/users"
    if [ ! -e "$users_path" ] && [ ! -L "$users_path" ]; then
        return 0
    fi

    local pfx_root users_root
    pfx_root=$(realpath -e -- "$pfx_path" 2>/dev/null || true)
    users_root=$(realpath -e -- "$users_path" 2>/dev/null || true)
    if [ -z "$pfx_root" ] || [ -z "$users_root" ] || [[ "$users_root" != "$pfx_root"/* ]]; then
        echo "[ERROR] Wine prefix users directory escapes prefix root: $users_path" >&2
        return 1
    fi
    [ -d "$users_root" ] || return 0

    local -a save_roots=(
        "AppData/Local"
        "AppData/LocalLow"
        "AppData/Roaming"
        "Documents/My Games"
        "My Documents/My Games"
        "Saved Games"
    )
    local -A seen_reals=()
    local -a discovered=()

    local user_dir user_real rel_root root_path root_real cand cand_name cand_real
    local sym sym_real escaped has_file rel_out
    for user_dir in "$users_root"/*; do
        [ -e "$user_dir" ] || [ -L "$user_dir" ] || continue
        user_real=$(realpath -e -- "$user_dir" 2>/dev/null || true)
        if [ -z "$user_real" ] || [[ "$user_real" != "$users_root"/* ]] || [ ! -d "$user_real" ]; then
            continue
        fi

        for rel_root in "${save_roots[@]}"; do
            root_path="$user_real/$rel_root"
            [ -e "$root_path" ] || [ -L "$root_path" ] || continue
            root_real=$(realpath -e -- "$root_path" 2>/dev/null || true)
            if [ -z "$root_real" ] || [[ "$root_real" != "$users_root"/* ]]; then
                echo "[WARN] Rejected escaping prefix save root: $root_path" >&2
                continue
            fi
            [ -d "$root_real" ] || continue

            for cand in "$root_real"/*; do
                [ -e "$cand" ] || [ -L "$cand" ] || continue
                cand_name="${cand##*/}"
                if [[ "$cand_name" == *$'\n'* ]] || [[ "$cand_name" == *$'\r'* ]]; then
                    echo "[WARN] Rejected prefix save directory with control character" >&2
                    continue
                fi
                if _is_prefix_save_noise "$cand_name"; then
                    continue
                fi

                cand_real=$(realpath -e -- "$cand" 2>/dev/null || true)
                if [ -z "$cand_real" ] || [[ "$cand_real" != "$users_root"/* ]]; then
                    echo "[WARN] Rejected escaping prefix save candidate: $cand" >&2
                    continue
                fi
                [ -d "$cand_real" ] || continue

                escaped=0
                while IFS= read -r -d '' sym; do
                    sym_real=$(realpath -e -- "$sym" 2>/dev/null || true)
                    if [ -z "$sym_real" ] || [[ "$sym_real" != "$users_root"/* ]]; then
                        echo "[WARN] Rejected prefix save with escaping symlink: $sym" >&2
                        escaped=1
                        break
                    fi
                done < <(find "$cand_real" -type l -print0 2>/dev/null)
                [ "$escaped" -eq 1 ] && continue

                has_file=$(find "$cand_real" -type f -print -quit 2>/dev/null || true)
                [ -n "$has_file" ] || continue

                if [ -n "${seen_reals[$cand_real]:-}" ]; then
                    continue
                fi
                seen_reals["$cand_real"]=1

                rel_out="${cand_real#"$users_root"/}"
                discovered+=("$rel_out")
            done
        done
    done

    if [ ${#discovered[@]} -gt 0 ]; then
        printf '%s\n' "${discovered[@]}" | LC_ALL=C sort -u
    fi
    return 0
}

# Collect discovered Wine prefix saves non-destructively into <game_dir>/saves/_prefix_saves/
collect_prefix_saves() {
    local game_dir="${1:-}"
    local is_quiet="${2:-false}"

    if [ -z "$game_dir" ] || [ ! -d "$game_dir" ]; then
        [ "$is_quiet" = true ] || echo "[ERROR] Target game directory not found: ${game_dir:-<empty>}" >&2
        return 1
    fi

    local active_pid=""
    if active_pid=$(is_game_active_for_dir "$game_dir" 2>/dev/null); then
        [ "$is_quiet" = true ] || echo "[ERROR] Cannot collect prefix saves while game process is active (PID: $active_pid)." >&2
        log_msg "ERROR" "SAVE" "Prefix save collect blocked while active PID $active_pid running for $(basename "$game_dir")"
        return 1
    fi

    local -a rels=()
    local line
    while IFS= read -r line; do
        [ -n "$line" ] && rels+=("$line")
    done < <(discover_prefix_saves "$game_dir")

    if [ ${#rels[@]} -eq 0 ]; then
        [ "$is_quiet" = true ] || echo "[INFO] No Wine prefix save directories found in: $game_dir"
        return 0
    fi

    local save_dir="$game_dir/saves"
    if [ -L "$save_dir" ]; then
        local target_path
        target_path=$(readlink -f "$save_dir" 2>/dev/null || true)
        if [ -z "$target_path" ] || [ ! -d "$target_path" ]; then
            [ "$is_quiet" = true ] || echo "[ERROR] Portable saves symlink points to invalid directory: $save_dir" >&2
            return 1
        fi
    elif [ -e "$save_dir" ] && [ ! -d "$save_dir" ]; then
        [ "$is_quiet" = true ] || echo "[ERROR] Portable saves path is not a directory: $save_dir" >&2
        return 1
    fi

    local stage_root="$save_dir/_prefix_saves"
    mkdir -p -m 700 "$stage_root" || return 1

    local users_root
    users_root=$(realpath -e -- "$game_dir/pfx/drive_c/users" 2>/dev/null || true)
    [ -n "$users_root" ] || return 1

    local rel src src_real tmp_dir dst dst_parent count=0
    for rel in "${rels[@]}"; do
        case "$rel" in
            /*|..|../*|*/..|*/../*)
                echo "[WARN] Skipping unsafe relative save path: $rel" >&2
                continue
                ;;
        esac
        src="$users_root/$rel"
        src_real=$(realpath -e -- "$src" 2>/dev/null || true)
        if [ -z "$src_real" ] || [[ "$src_real" != "$users_root"/* ]] || [ ! -d "$src_real" ]; then
            echo "[WARN] Skipping invalid prefix save source: $rel" >&2
            continue
        fi

        dst="$stage_root/$rel"
        dst_parent=$(dirname "$dst")
        mkdir -p "$dst_parent" || return 1
        tmp_dir=$(mktemp -d "$stage_root/.stage_collect.XXXXXX") || return 1
        mkdir "$tmp_dir/payload" || { rm -rf -- "$tmp_dir"; return 1; }

        if ! cp -a -- "$src_real/." "$tmp_dir/payload/" 2>/dev/null; then
            rm -rf -- "$tmp_dir"
            [ "$is_quiet" = true ] || echo "[ERROR] Failed to stage prefix saves from $src_real" >&2
            return 1
        fi

        if [ -e "$dst" ] || [ -L "$dst" ]; then
            if ! mv -T -- "$dst" "$tmp_dir/old"; then
                rm -rf -- "$tmp_dir"
                return 1
            fi
        fi
        if ! mv -T -- "$tmp_dir/payload" "$dst"; then
            [ -e "$tmp_dir/old" ] && mv -T -- "$tmp_dir/old" "$dst" 2>/dev/null || true
            rm -rf -- "$tmp_dir"
            return 1
        fi
        rm -rf -- "$tmp_dir"
        count=$((count + 1))
    done

    [ "$is_quiet" = true ] || echo "[VERIFIED] Collected $count Wine prefix save directory(ies) into $stage_root"
    log_msg "INFO" "SAVE" "Collected $count Wine prefix save directory(ies) for $(basename "$game_dir")"
    return 0
}

# Opt-in restore of staged Wine prefix saves from <game_dir>/saves/_prefix_saves/ -> pfx/drive_c/users/
restore_prefix_saves() {
    local game_dir="${1:-}"
    local is_quiet="${2:-false}"

    if [ -z "$game_dir" ] || [ ! -d "$game_dir" ]; then
        [ "$is_quiet" = true ] || echo "[ERROR] Target game directory not found: ${game_dir:-<empty>}" >&2
        return 1
    fi

    local active_pid=""
    if active_pid=$(is_game_active_for_dir "$game_dir" 2>/dev/null); then
        [ "$is_quiet" = true ] || echo "[ERROR] Cannot restore prefix saves while game process is active (PID: $active_pid)." >&2
        return 1
    fi

    local stage_root="$game_dir/saves/_prefix_saves"
    if [ ! -d "$stage_root" ]; then
        [ "$is_quiet" = true ] || echo "[INFO] No staged Wine prefix saves found in: $stage_root"
        return 0
    fi

    local pfx_root users_root
    pfx_root=$(realpath -e -- "$game_dir/pfx" 2>/dev/null || true)
    users_root=$(realpath -e -- "$game_dir/pfx/drive_c/users" 2>/dev/null || true)
    if [ -z "$pfx_root" ] || [ -z "$users_root" ] || [[ "$users_root" != "$pfx_root"/* ]]; then
        [ "$is_quiet" = true ] || echo "[ERROR] Target Wine prefix users directory missing or invalid." >&2
        return 1
    fi

    local bad_sym
    bad_sym=$(find "$stage_root" -type l -print -quit 2>/dev/null || true)
    if [ -n "$bad_sym" ]; then
        echo "[ERROR] Staged prefix saves contain disallowed symlink: $bad_sym" >&2
        return 1
    fi

    local file rel dst_file dst_parent dst_parent_real count=0
    while IFS= read -r -d '' file; do
        rel="${file#"$stage_root"/}"
        case "$rel" in
            /*|..|../*|*/..|*/../*)
                echo "[ERROR] Unsafe staged prefix save path: $rel" >&2
                return 1
                ;;
        esac
        dst_file="$users_root/$rel"
        dst_parent=$(dirname "$dst_file")
        if ! _check_confined_ancestor "$dst_parent" "$users_root"; then
            echo "[ERROR] Prefix restore destination escapes users root: $dst_parent" >&2
            return 1
        fi
        mkdir -p -- "$dst_parent" || return 1
        dst_parent_real=$(realpath -e -- "$dst_parent" 2>/dev/null || true)
        if [ -z "$dst_parent_real" ] || { [ "$dst_parent_real" != "$users_root" ] && [[ "$dst_parent_real" != "$users_root"/* ]]; }; then
            echo "[ERROR] Prefix restore destination resolved outside users root: $dst_parent" >&2
            return 1
        fi
        if [ -L "$dst_file" ]; then
            echo "[ERROR] Refusing to overwrite symlink in Wine prefix: $dst_file" >&2
            return 1
        fi
        cp -a -- "$file" "$dst_file" || return 1
        count=$((count + 1))
    done < <(find "$stage_root" -type f -print0 2>/dev/null)

    [ "$is_quiet" = true ] || echo "[VERIFIED] Restored $count Wine prefix save file(s) from $stage_root"
    log_msg "INFO" "SAVE" "Restored $count Wine prefix save file(s) for $(basename "$game_dir")"
    return 0
}


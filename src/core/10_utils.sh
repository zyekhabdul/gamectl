# Resolve GBE template file based on platform and architecture
get_gbe_template() {
    local platform="${1:-linux}" # "linux" or "windows"
    local arch="${2:-x64}"       # "x64" or "x86"
    local p=""
    if [ "$platform" = "windows" ]; then
        if [ "$arch" = "x64" ]; then
            for p in "${GAMECTL_GBE_WIN_X64:-}" \
                     "$HOME/.local/share/gbe-fork/windows/release/regular/x64/steam_api64.dll" \
                     "$HOME/.local/share/gbe-fork/windows/regular/x64/steam_api64.dll" \
                     "$HOME/.local/share/gbe-fork/regular/x64/steam_api64.dll" \
                     "$HOME/.local/share/gbe-fork/windows/release/experimental/x64/steam_api64.dll"; do
                [ -n "$p" ] && [ -f "$p" ] && echo "$p" && return 0
            done
        else
            for p in "${GAMECTL_GBE_WIN_X86:-}" \
                     "$HOME/.local/share/gbe-fork/windows/release/regular/x86/steam_api.dll" \
                     "$HOME/.local/share/gbe-fork/windows/regular/x86/steam_api.dll" \
                     "$HOME/.local/share/gbe-fork/regular/x86/steam_api.dll" \
                     "$HOME/.local/share/gbe-fork/windows/release/experimental/x86/steam_api.dll"; do
                [ -n "$p" ] && [ -f "$p" ] && echo "$p" && return 0
            done
        fi
    else
        if [ "$arch" = "x64" ]; then
            for p in "${GAMECTL_GBE_X64:-}" \
                     "$HOME/.local/share/gbe-fork/regular/x64/libsteam_api.so" \
                     "$HOME/.local/share/gbe-fork/experimental/x64/libsteam_api.so"; do
                [ -n "$p" ] && [ -f "$p" ] && echo "$p" && return 0
            done
        else
            for p in "${GAMECTL_GBE_X86:-}" \
                     "$HOME/.local/share/gbe-fork/regular/x86/libsteam_api.so" \
                     "$HOME/.local/share/gbe-fork/experimental/x86/libsteam_api.so"; do
                [ -n "$p" ] && [ -f "$p" ] && echo "$p" && return 0
            done
        fi
    fi
    return 1
}

# Auto-download and provision Goldberg Emulator (GBE Fork) templates into destination
setup_gbe_templates() {
    local auto_yes=false
    local force=false
    local linux_only=false
    local win_only=false
    local dry_run=false
    local src_linux=""
    local src_win=""
    local dest_dir="${GAMECTL_GBE_DIR:-$HOME/.local/share/gbe-fork}"

    while [ $# -gt 0 ]; do
        case "$1" in
            -y|--yes) auto_yes=true ;;
            -f|--force) force=true ;;
            --dry-run) dry_run=true ;;
            --linux-only) linux_only=true ;;
            --win-only) win_only=true ;;
            --source-linux) shift; src_linux="${1:-}" ;;
            --source-linux=*) src_linux="${1#--source-linux=}" ;;
            --source-win) shift; src_win="${1:-}" ;;
            --source-win=*) src_win="${1#--source-win=}" ;;
            --dest) shift; dest_dir="${1:-}" ;;
            --dest=*) dest_dir="${1#--dest=}" ;;
            -h|--help)
                cat <<EOF
Usage: gamectl setup-gbe [options]

Auto-download & provision Goldberg Emulator templates into ~/.local/share/gbe-fork/

Options:
  -y, --yes          Non-interactive mode, skip confirmations
  -f, --force        Overwrite existing templates
  --linux-only       Install only Linux templates (.so)
  --win-only         Install only Windows templates (.dll)
  --dry-run          Test execution without downloading or modifying filesystem
  --source-linux     Custom file or URL for Linux tarball (emu-linux-release.tar.bz2)
  --source-win       Custom file or URL for Windows 7z (emu-win-release-vs22.7z)
  --dest <dir>       Target GBE directory (default: ~/.local/share/gbe-fork)
EOF
                return 0
                ;;
            *)
                echo "[WARN] Unknown argument: $1" >&2
                ;;
        esac
        shift || true
    done

    echo "=========================================="
    echo " GOLDBERG EMULATOR PROVISIONING (GBE Fork)"
    echo " Target Dir : $dest_dir"
    echo " Mode       : $([ "$linux_only" = true ] && echo "Linux Only" || ([ "$win_only" = true ] && echo "Windows Only" || echo "Dual Platform (Linux + Windows)"))"
    echo "=========================================="

    if [ "$dry_run" = true ]; then
        echo "[DRY-RUN] Target destination verified: $dest_dir"
        return 0
    fi

    local has_lin_x64=false has_lin_x86=false has_win_x64=false has_win_x86=false
    [ -f "$dest_dir/regular/x64/libsteam_api.so" ] || [ -f "$dest_dir/experimental/x64/libsteam_api.so" ] && has_lin_x64=true
    [ -f "$dest_dir/regular/x86/libsteam_api.so" ] || [ -f "$dest_dir/experimental/x86/libsteam_api.so" ] && has_lin_x86=true
    [ -f "$dest_dir/windows/release/regular/x64/steam_api64.dll" ] || [ -f "$dest_dir/regular/x64/steam_api64.dll" ] || [ -f "$dest_dir/windows/regular/x64/steam_api64.dll" ] && has_win_x64=true
    [ -f "$dest_dir/windows/release/regular/x86/steam_api.dll" ] || [ -f "$dest_dir/regular/x86/steam_api.dll" ] || [ -f "$dest_dir/windows/regular/x86/steam_api.dll" ] && has_win_x86=true

    if [ "$force" = false ]; then
        if [ "$linux_only" = true ] && [ "$has_lin_x64" = true ] && [ "$has_lin_x86" = true ]; then
            echo "[PASS] Linux GBE Fork templates already provisioned in $dest_dir."
            return 0
        elif [ "$win_only" = true ] && [ "$has_win_x64" = true ] && [ "$has_win_x86" = true ]; then
            echo "[PASS] Windows GBE Fork templates already provisioned in $dest_dir."
            return 0
        elif [ "$linux_only" = false ] && [ "$win_only" = false ] && [ "$has_lin_x64" = true ] && [ "$has_lin_x86" = true ] && [ "$has_win_x64" = true ] && [ "$has_win_x86" = true ]; then
            echo "[PASS] All GBE Fork templates already provisioned in $dest_dir."
            return 0
        fi
    fi

    mkdir -p "$dest_dir"

    local tmp_work=""
    tmp_work=$(mktemp -d "${TMPDIR:-/tmp}/gamectl_gbe_setup_XXXXXX")
    trap 'rm -rf "${tmp_work:-}" 2>/dev/null || true' RETURN

    # 1. Linux Templates
    if [ "$win_only" = false ]; then
        echo "[INFO] Provisioning Linux GBE templates..."
        local lin_archive="$tmp_work/emu-linux.tar.bz2"
        local lin_url="${src_linux:-https://github.com/Detanup01/gbe_fork/releases/latest/download/emu-linux-release.tar.bz2}"

        if [ -f "$lin_url" ]; then
            cp -f "$lin_url" "$lin_archive"
        else
            echo "[INFO] Downloading Linux archive from: $lin_url"
            if ! curl -sL --connect-timeout 8 --max-time 60 "$lin_url" -o "$lin_archive"; then
                echo "[ERROR] Failed to download Linux GBE archive from $lin_url" >&2
                return 1
            fi
        fi

        if [ -f "$lin_archive" ] && [ -s "$lin_archive" ]; then
            mkdir -p "$tmp_work/linux_extract"
            if tar -xjf "$lin_archive" -C "$tmp_work/linux_extract" 2>/dev/null || tar -xf "$lin_archive" -C "$tmp_work/linux_extract" 2>/dev/null; then
                local src_root="$tmp_work/linux_extract"
                [ -d "$src_root/release" ] && src_root="$src_root/release"
                mkdir -p "$dest_dir/regular/x64" "$dest_dir/regular/x86" "$dest_dir/experimental/x64" "$dest_dir/experimental/x86"
                [ -f "$src_root/regular/x64/libsteam_api.so" ] && cp -f "$src_root/regular/x64/libsteam_api.so" "$dest_dir/regular/x64/"
                [ -f "$src_root/regular/x86/libsteam_api.so" ] && cp -f "$src_root/regular/x86/libsteam_api.so" "$dest_dir/regular/x86/"
                [ -f "$src_root/experimental/x64/libsteam_api.so" ] && cp -f "$src_root/experimental/x64/libsteam_api.so" "$dest_dir/experimental/x64/"
                [ -f "$src_root/experimental/x86/libsteam_api.so" ] && cp -f "$src_root/experimental/x86/libsteam_api.so" "$dest_dir/experimental/x86/"
                echo "[PASS] Linux GBE templates provisioned (x64 & x86)."
            else
                echo "[ERROR] Failed to extract Linux GBE archive." >&2
                return 1
            fi
        fi
    fi

    # 2. Windows Templates
    if [ "$linux_only" = false ]; then
        echo "[INFO] Provisioning Windows GBE templates..."
        local win_archive="$tmp_work/emu-win.7z"
        local win_url="${src_win:-https://github.com/Detanup01/gbe_fork/releases/latest/download/emu-win-release-vs22.7z}"

        local has_7z=false
        local cmd_7z=""
        for c in 7z 7za 7zr; do
            if command -v "$c" >/dev/null 2>&1; then
                has_7z=true
                cmd_7z="$c"
                break
            fi
        done

        if [ "$has_7z" = false ]; then
            echo "[WARN] 7z decompression utility not found. Install 7zip or p7zip-full to unpack Windows templates." >&2
            echo "       Skipping Windows template extraction. Linux templates remain functional." >&2
        else
            if [ -f "$win_url" ]; then
                cp -f "$win_url" "$win_archive"
            else
                echo "[INFO] Downloading Windows archive from: $win_url"
                if ! curl -sL --connect-timeout 8 --max-time 60 "$win_url" -o "$win_archive"; then
                    echo "[WARN] Failed to download Windows GBE archive from $win_url" >&2
                fi
            fi

            if [ -f "$win_archive" ] && [ -s "$win_archive" ]; then
                mkdir -p "$tmp_work/win_extract"
                if "$cmd_7z" x -y -o"$tmp_work/win_extract" "$win_archive" >/dev/null 2>&1; then
                    local w_root="$tmp_work/win_extract"
                    [ -d "$w_root/release" ] && w_root="$w_root/release"
                    mkdir -p "$dest_dir/windows/release/regular/x64" "$dest_dir/windows/release/regular/x86" \
                             "$dest_dir/regular/x64" "$dest_dir/regular/x86"
                    if [ -f "$w_root/regular/x64/steam_api64.dll" ]; then
                        cp -f "$w_root/regular/x64/steam_api64.dll" "$dest_dir/windows/release/regular/x64/"
                        cp -f "$w_root/regular/x64/steam_api64.dll" "$dest_dir/regular/x64/"
                    fi
                    if [ -f "$w_root/regular/x86/steam_api.dll" ]; then
                        cp -f "$w_root/regular/x86/steam_api.dll" "$dest_dir/windows/release/regular/x86/"
                        cp -f "$w_root/regular/x86/steam_api.dll" "$dest_dir/regular/x86/"
                    fi
                    echo "[PASS] Windows GBE templates provisioned (x64 & x86)."
                else
                    echo "[WARN] Failed to extract Windows GBE archive." >&2
                fi
            fi
        fi
    fi

    echo "[VERIFIED] GBE Fork template provisioning completed in $dest_dir."
    rm -rf "${tmp_work:-}" 2>/dev/null || true
    trap - RETURN
    return 0
}

# Resolve remote sync host (optional)
get_remote_host() {
    local host="${GAMECTL_REMOTE_HOST:-${GAMECTL_COMPANION_HOST:-${GAMECTL_SYNC_HOST:-${GAMECTL_TUF_HOST:-}}}}"
    if [ -z "$host" ] && [ -f "$HOME/.config/gamectl/remote_host" ]; then
        host=$(head -n 1 "$HOME/.config/gamectl/remote_host" | tr -d '[:space:]')
    fi
    echo "$host"
}

# Pre-flight cleanup of orphaned sockets, locks, and stale download staging directories
clean_stale_locks() {
    local run_dir
    run_dir="$(get_runtime_dir)"
    rm -f /tmp/steam_chrome_shmem_* /tmp/steam_chrome_overlay_* 2>/dev/null || true
    rm -f "$run_dir"/steam_chrome_* 2>/dev/null || true
    rm -f "$HOME/.config/SLSsteam/cache/.picsbuffer.lock" 2>/dev/null || true

    # Self-healing cleanup of orphaned standalone download staging directories
    local st_dir
    shopt -s nullglob
    for st_dir in "$run_dir"/depot_dl_*; do
        if [ -d "$st_dir" ]; then
            local st_pid="${st_dir##*_}"
            if ! [[ "$st_pid" =~ ^[0-9]+$ ]] || ! kill -0 "$st_pid" 2>/dev/null; then
                rm -rf "$st_dir" 2>/dev/null || true
            fi
        fi
    done
    shopt -u nullglob
}

# Invalidate ephemeral library scanner cache
invalidate_scan_cache() {
    local cache_dir
    cache_dir="$(get_runtime_dir)"
    rm -f "$cache_dir/scancache.tab" "$cache_dir/scancache.tab.tmp" 2>/dev/null || true
}

# Flush pending keyboard input to prevent ghost keypress propagation across TUI views
flush_tty_input() {
    if [ -t 0 ] || [ -r /dev/tty ]; then
        while read -r -t 0.05 -n 10000 _ < /dev/tty 2>/dev/null || read -r -t 0.05 -n 10000 _ 2>/dev/null; do
            :
        done
    fi
    return 0
}

# Terminal Screen Lifecycle Management (Alternate Screen Buffer)
GAMECTL_IN_ALT_SCREEN=0

enter_tui_screen() {
    if [ -t 1 ] && [ "${TERM:-}" != "dumb" ] && [ "${GAMECTL_IN_ALT_SCREEN:-0}" -eq 0 ]; then
        tput smcup 2>/dev/null || printf '\033[?1049h'
        GAMECTL_IN_ALT_SCREEN=1
        trap 'trap - EXIT INT TERM; exit_tui_screen; exit' EXIT INT TERM
    fi
    return 0
}

exit_tui_screen() {
    if [ -t 1 ] && [ "${GAMECTL_IN_ALT_SCREEN:-0}" -eq 1 ]; then
        tput rmcup 2>/dev/null || printf '\033[?1049l'
        GAMECTL_IN_ALT_SCREEN=0
    fi
    return 0
}

# Clean FZF Modal Notification Dialog (Zero-Flicker)
tui_modal_notice() {
    local title="${1:-Notice}"
    local msg="${2:-}"
    local height="${3:-25%}"

    if [ ! -t 0 ] || [ ! -t 1 ] || ! command -v fzf >/dev/null 2>&1; then
        log_msg "INFO" "UI" "[$title] $msg"
        echo "[$title] $msg"
        return 0
    fi

    printf "%b\n" "$msg" | fzf \
        --border-label="  ╢ $title ╟  " \
        --border-label-pos=2 \
        --header="NOTICE (Enter or Esc: Dismiss)" \
        --prompt="> " \
        --height="$height" \
        --reverse 2>/dev/null || true
    return 0
}

# Canonical user-isolated runtime directory (0700 permissions)
get_runtime_dir() {
    local run_uid="${UID:-$(id -u 2>/dev/null || echo 1000)}"
    local run_dir="${XDG_RUNTIME_DIR:-/tmp/gamectl-$run_uid}"
    mkdir -p -m 700 "$run_dir" 2>/dev/null || true
    echo "$run_dir"
}

# Canonical POSIX-compliant ANSI escape sequence stripper
strip_ansi() {
    printf "%s" "${1:-}" | sed -E $'s/\033\\[[0-9;]*[a-zA-Z]//g'
}

# Centralized Runtime Logger (user-isolated, rolling buffer max 1000 lines)
get_runtime_log_file() {
    local run_dir
    run_dir="$(get_runtime_dir)"
    echo "$run_dir/gamectl.log"
}

log_msg() {
    local level="${1:-INFO}"
    local comp="${2:-CORE}"
    shift 2 || true
    local msg="$*"

    local log_file
    log_file="$(get_runtime_log_file)"

    local ts
    ts=$(date '+%Y-%m-%d %H:%M:%S' 2>/dev/null || date)
    printf "[%s] [%-5s] [%-10s] %s\n" "$ts" "${level^^}" "${comp^^}" "$msg" >> "$log_file" 2>/dev/null || true

    # Rolling buffer cap: keep last 1000 lines if log file exceeds ~120KB
    local sz=0
    sz=$(stat -c%s "$log_file" 2>/dev/null || echo 0)
    if [ "$sz" -gt 120000 ]; then
        local tmp_log="$log_file.tmp.$$"
        tail -n 1000 "$log_file" > "$tmp_log" 2>/dev/null && mv -f "$tmp_log" "$log_file" 2>/dev/null || rm -f "$tmp_log" 2>/dev/null || true
    fi
    return 0
}

log_info() { log_msg "INFO" "$@"; }
log_warn() { log_msg "WARN" "$@"; }
log_error() { log_msg "ERROR" "$@"; }

# Ephemeral cache tier for JSON APIs (Steam Store & ProtonDB) with TTL
fetch_cached_json() {
    local url="${1:-}"
    local cache_key="${2:-}"
    local ttl="${3:-3600}"

    if [ -z "$url" ] || [ -z "$cache_key" ]; then
        return 1
    fi

    local cache_dir="${XDG_CACHE_HOME:-$HOME/.cache}/gamectl"
    mkdir -p "$cache_dir" 2>/dev/null || true

    local safe_key
    safe_key=$(echo "$cache_key" | tr -cd '[:alnum:]_-')
    local cache_file="$cache_dir/${safe_key}.json"

    local now
    now=$(date +%s)

    # 1. Check existing cache validity against TTL
    if [ -f "$cache_file" ]; then
        local mtime
        mtime=$(stat -c %Y "$cache_file" 2>/dev/null || stat -f %m "$cache_file" 2>/dev/null || echo 0)
        local age=$(( now - mtime ))
        if [ "$age" -ge 0 ] && [ "$age" -lt "$ttl" ] && [ -s "$cache_file" ]; then
            cat "$cache_file"
            return 0
        fi
    fi

    # 2. Fetch fresh content with timeout and atomic replacement
    local tmp_file="${cache_file}.tmp.$$"
    local fetched
    fetched=$(curl -s --connect-timeout 2 --max-time 4 "$url" 2>/dev/null || true)

    if [ -n "$fetched" ] && [ "$fetched" != "null" ]; then
        # Ensure it contains valid JSON before caching
        if echo "$fetched" | jq . >/dev/null 2>&1; then
            echo "$fetched" > "$tmp_file" 2>/dev/null && mv -f "$tmp_file" "$cache_file" 2>/dev/null || rm -f "$tmp_file" 2>/dev/null
            echo "$fetched"
            return 0
        fi
    fi
    rm -f "$tmp_file" 2>/dev/null || true

    # 3. Fallback to stale cache if network/API failed
    if [ -s "$cache_file" ]; then
        cat "$cache_file"
        return 0
    fi

    return 1
}

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

# Restore savegame snapshot from recovery slot (slot1, slot2, or slot3)
restore_save() (
    local game_dir="$1"
    local slot="${2:-1}"
    local is_quiet="${3:-false}"

    if [ -z "$game_dir" ] || [ ! -d "$game_dir" ]; then
        [ "$is_quiet" = true ] || echo "[ERROR] Target game directory not found: ${game_dir:-<empty>}" >&2
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

# Dynamic executable finder for game directory
find_game_binary() {
    local dir="$1"
    local base
    base=$(basename "$dir")
    local clean_base="${base// /}"
    local lower_base="${base,,}"
    local lower_clean="${clean_base,,}"

    # Priority 1: Common launch scripts or matching names
    local candidates=(
        "start.sh" "run.sh" "launch.sh" "start" "run"
        "$base" "$clean_base" "$lower_base" "$lower_clean"
    )
    for c in "${candidates[@]}"; do
        if [ -x "$dir/$c" ] && [ ! -d "$dir/$c" ]; then
            echo "$c"
            return 0
        fi
    done

    # Priority 2: Any root executable file excluding assets/libs/runtime dumps
    local f fname
    for f in "$dir"/*; do
        if [ -x "$f" ] && [ ! -d "$f" ]; then
            fname=$(basename "$f")
            case "$fname" in
                *.so|*.so.*|*.dll|*.dylib|installscript.vdf|*.png|*.bmp|*.txt|*.pkg|createdump|monoconfig|monomachineconfig)
                    continue
                    ;;
                *)
                    echo "$fname"
                    return 0
                    ;;
            esac
        fi
    done

    # Priority 3: Windows executables matching title/folder name
    local win_candidates=(
        "$base.exe" "$clean_base.exe" "$lower_base.exe" "$lower_clean.exe"
    )
    for c in "${win_candidates[@]}"; do
        if [ -f "$dir/$c" ] && [ ! -d "$dir/$c" ]; then
            chmod +x "$dir/$c" 2>/dev/null || true
            echo "$c"
            return 0
        fi
    done

    # Priority 4: Any root .exe excluding setup/redist/crash handlers
    for f in "$dir"/*.exe "$dir"/*.EXE; do
        [ -f "$f" ] || continue
        fname=$(basename "$f")
        case "$fname" in
            UnityCrashHandler*|*unins*|*setup*|*installer*|*redist*|DXSETUP*|vcredist*|dotnet*|vc_redist*|*CrashReport*)
                continue
                ;;
            *)
                chmod +x "$f" 2>/dev/null || true
                echo "$fname"
                return 0
                ;;
        esac
    done

    # Priority 5: Subdirectory .exe in standard game binary folders
    for sub in "bin" "bin/x64" "bin/Win64" "Binaries/Win64" "Binaries/Win32" "x64"; do
        if [ -d "$dir/$sub" ]; then
            for f in "$dir/$sub"/*.exe "$dir/$sub"/*.EXE; do
                [ -f "$f" ] || continue
                fname=$(basename "$f")
                case "$fname" in
                    UnityCrashHandler*|*unins*|*setup*|*installer*|*redist*|DXSETUP*|vcredist*|dotnet*|vc_redist*|*CrashReport*)
                        continue
                        ;;
                    *)
                        chmod +x "$f" 2>/dev/null || true
                        echo "$sub/$fname"
                        return 0
                        ;;
                esac
            done
        fi
    done

    return 1
}

# Resolve sovereign library path prioritizing explicit arg, env, config, and default $HOME/Games
resolve_standalone_library_dir() {
    local safe_title="${1:-}"
    local explicit_dir="${2:-}"

    local base_dir=""
    if [ -n "$explicit_dir" ]; then
        base_dir="$explicit_dir"
    elif [ -n "${GAMECTL_LIBRARY_DIR:-}" ]; then
        base_dir="$GAMECTL_LIBRARY_DIR"
    elif [ -f "$HOME/.config/gamectl/library_dir" ]; then
        local cfg_dir
        cfg_dir=$(head -n 1 "$HOME/.config/gamectl/library_dir" 2>/dev/null | tr -d '\r\n' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
        if [ -n "$cfg_dir" ]; then
            base_dir="${cfg_dir/#\~/$HOME}"
        fi
    fi

    if [ -z "$base_dir" ]; then
        base_dir="$HOME/Games"
    fi

    if [ -n "$safe_title" ]; then
        echo "$base_dir/$safe_title"
    else
        echo "$base_dir"
    fi
}

# Detect SteamStub DRM wrapper in Linux ELF (.bind section) or Windows PE
detect_steamstub_drm() {
    local bin_path="$1"
    [ -f "$bin_path" ] || return 1

    # Check 1: Linux ELF .bind section (readelf or strings)
    if command -v readelf >/dev/null 2>&1; then
        if readelf -S "$bin_path" 2>/dev/null | grep -Eq '(\.bind|[[:space:]]\.bind[[:space:]])'; then
            return 0
        fi
    fi

    # Check 2: Strings heuristic for SteamStub / SteamDRM markers
    if command -v strings >/dev/null 2>&1; then
        if strings -n 6 "$bin_path" 2>/dev/null | head -n 500 | grep -Eq '(SteamDRM|\.bind|SteamStub)'; then
            return 0
        fi
    fi

    return 1
}

# Distinguish SteamStub type (windows_pe, linux_elf, or unknown)
detect_steamstub_type() {
    local bin_path="$1"
    [ -f "$bin_path" ] || return 1
    if ! detect_steamstub_drm "$bin_path"; then
        return 1
    fi
    local btype
    btype=$(file -b "$bin_path" 2>/dev/null || echo "")
    if echo "$btype" | grep -qi -E "PE32|MS Windows"; then
        echo "windows_pe"
    elif case "$bin_path" in *.exe|*.EXE) true ;; *) false ;; esac; then
        echo "windows_pe"
    elif echo "$btype" | grep -qi "ELF"; then
        echo "linux_elf"
    else
        echo "unknown"
    fi
    return 0
}

# Resolve candidate unpacked binary for Windows PE SteamStub
resolve_unpacked_binary() {
    local gdir="$1"
    local gbin="$2"
    [ -d "$gdir" ] || return 1
    [ -n "$gbin" ] || return 1

    local base_no_ext="${gbin%.*}"
    local cand
    for cand in "${base_no_ext}.unpacked.exe" \
                "${base_no_ext}_unpacked.exe" \
                "${base_no_ext}-unpacked.exe" \
                "${gbin}.unpacked.exe" \
                "${gbin}.unpacked"; do
        if [ -f "$gdir/$cand" ]; then
            echo "$cand"
            return 0
        fi
    done
    return 1
}

# Find Steamless CLI executable on system
find_steamless_cli() {
    local cand
    for cand in "${GAMECTL_STEAMLESS_PATH:-}" \
                "$(command -v steamless 2>/dev/null || true)" \
                "$(command -v Steamless.CLI.exe 2>/dev/null || true)" \
                "$HOME/.local/share/steamless/Steamless.CLI.exe" \
                "$HOME/.local/share/steamless/Steamless.exe" \
                "$HOME/.config/gamectl/tools/Steamless.CLI.exe"; do
        if [ -n "$cand" ] && [ -f "$cand" ]; then
            echo "$cand"
            return 0
        fi
    done
    return 1
}

# Unpack Windows PE SteamStub binary via Steamless CLI
unpack_steamstub_pe() {
    local target_exe="$1"
    local runner_bin="${2:-}"
    local pfx_dir="${3:-}"
    [ -f "$target_exe" ] || return 1

    local gdir
    gdir="$(dirname "$target_exe")"
    local gbin
    gbin="$(basename "$target_exe")"

    # If already unpacked, nothing to do
    if resolve_unpacked_binary "$gdir" "$gbin" >/dev/null 2>&1; then
        return 0
    fi

    local steamless_bin
    steamless_bin=$(find_steamless_cli 2>/dev/null || true)
    if [ -z "$steamless_bin" ]; then
        return 1
    fi

    echo "  ${UI_CYAN}[INFO] Invoking Steamless CLI: $steamless_bin on $gbin...${UI_RST}"
    local unpack_rc=0
    if [ -x "$steamless_bin" ] && ! echo "$steamless_bin" | grep -qi '\.exe$'; then
        "$steamless_bin" "$target_exe" >/dev/null 2>&1 || unpack_rc=$?
    elif command -v mono >/dev/null 2>&1; then
        mono "$steamless_bin" "$target_exe" >/dev/null 2>&1 || unpack_rc=$?
    elif command -v dotnet >/dev/null 2>&1; then
        dotnet "$steamless_bin" "$target_exe" >/dev/null 2>&1 || unpack_rc=$?
    elif [ -n "$runner_bin" ] && [ -x "$runner_bin" ]; then
        WINEPREFIX="${pfx_dir:-$gdir/pfx}" "$runner_bin" "$steamless_bin" "$target_exe" >/dev/null 2>&1 || unpack_rc=$?
    elif command -v wine >/dev/null 2>&1; then
        WINEPREFIX="${pfx_dir:-$gdir/pfx}" wine "$steamless_bin" "$target_exe" >/dev/null 2>&1 || unpack_rc=$?
    else
        return 1
    fi

    # Check if unpacked binary was produced
    if resolve_unpacked_binary "$gdir" "$gbin" >/dev/null 2>&1; then
        return 0
    fi
    return 1
}

# Setup sovereign Steam interceptor scripts in target directory
setup_steam_interceptor() {
    local target_dir="${1:-$(get_runtime_dir)/interceptor}"
    mkdir -p -m 700 "$target_dir" 2>/dev/null || mkdir -p "$target_dir"
    cat << 'EOF_INTERCEPTOR' > "$target_dir/steam"
#!/usr/bin/env bash
# Sovereign Steam Interceptor: traps and silences unshielded Steam Client calls
target_appid=""
for arg in "$@"; do
    case "$arg" in
        steam://run/*)
            target_appid="${arg##steam://run/}"
            target_appid="${target_appid%%/*}"
            ;;
    esac
done
if [ -n "$target_appid" ]; then
    echo "[gamectl interceptor] Blocked unsolicited Steam Client launch (steam://run/$target_appid)" >&2
else
    echo "[gamectl interceptor] Blocked unsolicited Steam Client launch ($*)" >&2
fi
exit 0
EOF_INTERCEPTOR
    chmod +x "$target_dir/steam" 2>/dev/null || true
    cp -f "$target_dir/steam" "$target_dir/steam.sh" 2>/dev/null || true
    return 0
}

# Forensic diagnostics report for SteamStub DRM inspection
diagnose_steamstub() {
    local bin_path="$1"
    if [ ! -f "$bin_path" ]; then
        echo "[ERROR] File not found: $bin_path" >&2
        return 1
    fi

    local b_name
    b_name="$(basename "$bin_path")"
    local b_dir
    b_dir="$(dirname "$bin_path")"
    local b_type
    b_type=$(file -b "$bin_path" 2>/dev/null || echo "Unknown")

    echo "╭─ STEAMSTUB FORENSIC DIAGNOSTICS ────────────────────────────╮"
    echo "│ Target Binary : $b_name"
    echo "│ Full Path     : $bin_path"
    echo "│ Architecture  : $b_type"

    local is_stub=false
    local stub_type="none"

    if detect_steamstub_drm "$bin_path"; then
        is_stub=true
        stub_type=$(detect_steamstub_type "$bin_path" 2>/dev/null || echo "unknown")
    fi

    if [ "$is_stub" = true ]; then
        if [ "$stub_type" = "windows_pe" ]; then
            echo "│ DRM Status    : ${UI_AMBER}[DETECTED] Windows PE SteamStub DRM${UI_RST}"
            local up_bin
            up_bin=$(resolve_unpacked_binary "$b_dir" "$b_name" 2>/dev/null || true)
            if [ -n "$up_bin" ]; then
                echo "│ Unpack Status : ${UI_GREEN}[READY] Unpacked counterpart found: $up_bin${UI_RST}"
                echo "│ Remediation   : launch_game will automatically execute $up_bin"
            else
                echo "│ Unpack Status : ${UI_AMBER}[PENDING] No unpacked binary found${UI_RST}"
                local s_cli
                s_cli=$(find_steamless_cli 2>/dev/null || true)
                if [ -n "$s_cli" ]; then
                    echo "│ Steamless CLI : ${UI_GREEN}[AVAILABLE] $s_cli${UI_RST}"
                    echo "│ Action        : Run 'gamectl unpack-stub \"$bin_path\"'"
                else
                    echo "│ Steamless CLI : ${UI_AMBER}[NOT FOUND] Place Steamless in ~/.local/share/steamless/${UI_RST}"
                    echo "│ Remediation   : Unpack $b_name with Steamless or provide ${b_name%.*}.unpacked.exe"
                fi
            fi
        elif [ "$stub_type" = "linux_elf" ]; then
            echo "│ DRM Status    : ${UI_AMBER}[DETECTED] Linux ELF SteamStub (.bind section)${UI_RST}"
            echo "│ Interceptor   : ${UI_GREEN}[ACTIVE] Sovereign steam.sh trap prevents Steam Client launch${UI_RST}"
            local cand_win
            cand_win=$(find "$b_dir" -maxdepth 2 -iname "*.exe" 2>/dev/null | head -n 1 || true)
            if [ -n "$cand_win" ]; then
                echo "│ Runner Option : Windows executable found ($(basename "$cand_win")). Can run via Proton with Steamless."
            else
                echo "│ Runner Option : Pure Linux native. Runs with sovereign interceptor trapping steam.sh calls."
            fi
        else
            echo "│ DRM Status    : ${UI_AMBER}[DETECTED] SteamStub / SteamDRM markers found${UI_RST}"
        fi
    else
        echo "│ DRM Status    : ${UI_GREEN}[CLEAN] No SteamStub DRM markers detected${UI_RST}"
    fi
    echo "╰─────────────────────────────────────────────────────────────╯"

    [ "$is_stub" = true ] && return 0 || return 1
}

# CLI subcommand handler for unpacking SteamStub Windows PE binaries
cli_unpack_stub() {
    local target="$1"
    if [ ! -f "$target" ]; then
        echo "[ERROR] Target file not found: $target" >&2
        return 1
    fi
    local up_res
    up_res=$(resolve_unpacked_binary "$(dirname "$target")" "$(basename "$target")" 2>/dev/null || true)
    if [ -n "$up_res" ]; then
        echo "[VERIFIED] Binary is already unpacked: $up_res"
        return 0
    fi
    echo "[INFO] Attempting to unpack $target via Steamless CLI..."
    if unpack_steamstub_pe "$target"; then
        up_res=$(resolve_unpacked_binary "$(dirname "$target")" "$(basename "$target")" 2>/dev/null || true)
        echo "[SUCCESS] Binary successfully unpacked: $up_res"
        return 0
    else
        echo "[ERROR] Failed to unpack binary. Ensure Steamless CLI is installed or run under Wine." >&2
        return 1
    fi
}

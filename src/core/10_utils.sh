# Resolve remote sync host (optional)
get_remote_host() {
    local host="${GAMECTL_REMOTE_HOST:-${GAMECTL_COMPANION_HOST:-${GAMECTL_SYNC_HOST:-${GAMECTL_TUF_HOST:-}}}}"
    if [ -z "$host" ] && [ -f "$HOME/.config/gamectl/remote_host" ]; then
        host=$(head -n 1 "$HOME/.config/gamectl/remote_host" | tr -d '[:space:]')
    fi
    echo "$host"
}

# Parse remote sync target into REMOTE_TARGET_BACKEND (ssh|rclone), REMOTE_TARGET_ENDPOINT, REMOTE_TARGET_BASE
parse_remote_sync_target() {
    local raw="${1:-}"
    REMOTE_TARGET_BACKEND=""
    REMOTE_TARGET_ENDPOINT=""
    REMOTE_TARGET_BASE=""

    if [ -z "$raw" ]; then
        echo "[WARN] Target remote host not configured." >&2
        echo "       Define target in ~/.config/gamectl/remote_host or GAMECTL_REMOTE_HOST variable." >&2
        return 1
    fi
    if [[ "$raw" == *$'\n'* || "$raw" == *$'\r'* ]] || [[ "$raw" == -* ]]; then
        echo "[ERROR] Invalid remote sync target '$raw': cannot start with '-' or contain newlines." >&2
        return 1
    fi

    if [[ "$raw" == rclone:* ]]; then
        local rest="${raw#rclone:}"
        local r_name="${rest%%:*}"
        local r_base="${rest#*:}"
        if [[ "$rest" != *:* ]] || [ -z "$r_name" ]; then
            echo "[ERROR] Invalid rclone target '$raw'. Expected format: rclone:<remote>:[path]." >&2
            return 1
        fi
        if ! command -v rclone >/dev/null 2>&1; then
            echo "[ERROR] Remote target '$raw' requires rclone, which is not installed in PATH." >&2
            return 1
        fi
        local rclone_remotes
        rclone_remotes=$(rclone listremotes 2>/dev/null || true)
        if ! grep -Fqx "${r_name}:" <<< "$rclone_remotes"; then
            echo "[ERROR] rclone remote '${r_name}:' not found (check 'rclone listremotes')." >&2
            return 1
        fi
        while [[ "$r_base" == /* ]]; do r_base="${r_base#/}"; done
        while [[ "$r_base" == */ ]]; do r_base="${r_base%/}"; done
        REMOTE_TARGET_BACKEND="rclone"
        REMOTE_TARGET_ENDPOINT="${r_name}:"
        REMOTE_TARGET_BASE="$r_base"
    elif [[ "$raw" == \[* ]]; then
        if [[ "$raw" =~ ^(\[[^]]+\])(:(.*))?$ ]]; then
            REMOTE_TARGET_BACKEND="ssh"
            REMOTE_TARGET_ENDPOINT="${BASH_REMATCH[1]}"
            REMOTE_TARGET_BASE="${BASH_REMATCH[3]:-}"
        else
            echo "[ERROR] Invalid IPv6 remote sync target: $raw" >&2
            return 1
        fi
    elif [[ "$raw" == *:* ]]; then
        local lhs="${raw%%:*}"
        local rhs="${raw#*:}"
        if [ -z "$lhs" ]; then
            echo "[ERROR] Invalid remote sync target '$raw': missing host or remote name." >&2
            return 1
        fi
        local rclone_remotes=""
        if command -v rclone >/dev/null 2>&1; then
            rclone_remotes=$(rclone listremotes 2>/dev/null || true)
        fi
        if [[ "$lhs" == *@* ]] || [[ "$lhs" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
            if [ -z "$rhs" ]; then
                echo "[ERROR] SSH target '$raw' has empty path after ':'. Omit ':' or specify a path (e.g. ${lhs}:~/gamectl-saves)." >&2
                return 1
            fi
            REMOTE_TARGET_BACKEND="ssh"
            REMOTE_TARGET_ENDPOINT="$lhs"
            REMOTE_TARGET_BASE="$rhs"
        elif [ -n "$rclone_remotes" ] && grep -Fqx "${lhs}:" <<< "$rclone_remotes"; then
            while [[ "$rhs" == /* ]]; do rhs="${rhs#/}"; done
            while [[ "$rhs" == */ ]]; do rhs="${rhs%/}"; done
            REMOTE_TARGET_BACKEND="rclone"
            REMOTE_TARGET_ENDPOINT="${lhs}:"
            REMOTE_TARGET_BASE="$rhs"
        elif [ -z "$rhs" ]; then
            if ! command -v rclone >/dev/null 2>&1; then
                echo "[ERROR] Remote target '$raw' requires rclone, which is not installed in PATH." >&2
            else
                echo "[ERROR] Remote '${lhs}:' not found in 'rclone listremotes'. For SSH, omit ':' or append a path (e.g. ${lhs}:~/gamectl-saves)." >&2
            fi
            return 1
        else
            REMOTE_TARGET_BACKEND="ssh"
            REMOTE_TARGET_ENDPOINT="$lhs"
            REMOTE_TARGET_BASE="$rhs"
        fi
    else
        REMOTE_TARGET_BACKEND="ssh"
        REMOTE_TARGET_ENDPOINT="$raw"
        REMOTE_TARGET_BASE=""
    fi

    if [ -n "$REMOTE_TARGET_BASE" ]; then
        if [[ "$REMOTE_TARGET_BASE" == ".." || "$REMOTE_TARGET_BASE" == "../"* || "$REMOTE_TARGET_BASE" == *"/.." || "$REMOTE_TARGET_BASE" == *"/../"* ]]; then
            echo "[ERROR] Invalid remote path traversal in '$REMOTE_TARGET_BASE'." >&2
            return 1
        fi
        if [ "$REMOTE_TARGET_BACKEND" = "rclone" ] && [[ "$REMOTE_TARGET_BASE" == "~" || "$REMOTE_TARGET_BASE" == "~/"* ]]; then
            echo "[ERROR] rclone remote path cannot start with '~' ('$REMOTE_TARGET_BASE'). Use e.g. ${REMOTE_TARGET_ENDPOINT}gamectl-saves." >&2
            return 1
        fi
    fi

    return 0
}

# Pre-flight cleanup of orphaned sockets, locks, and stale download staging directories
clean_stale_locks() {
    local run_dir
    run_dir="$(get_runtime_dir)"
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

# Canonical desktop session runtime directory (Wayland/PipeWire/Pulse/D-Bus sockets)
get_desktop_runtime_dir() {
    local run_uid="${UID:-$(id -u 2>/dev/null || echo 1000)}"
    echo "${XDG_RUNTIME_DIR:-/run/user/$run_uid}"
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

# Canonical DRM & Emulator Resolution SSoT
# Resolves: GBE_FORK | VALVE_DLL | VALVE_SO | STANDALONE
resolve_game_drm_status() {
    local gdir="$1"
    local api_file="${2:-}"
    local bin_file="${3:-}"

    [ -n "$gdir" ] && [ -d "$gdir" ] || { echo "STANDALONE"; return 0; }

    if [ -z "$api_file" ] || [ ! -f "$api_file" ]; then
        local is_win=false
        case "$bin_file" in
            *.exe|*.EXE|*.bat|*.BAT) is_win=true ;;
        esac

        if [ "$is_win" = true ]; then
            if [ -f "$gdir/steam_api64.dll" ]; then
                api_file="$gdir/steam_api64.dll"
            elif [ -f "$gdir/steam_api.dll" ]; then
                api_file="$gdir/steam_api.dll"
            elif [ -f "$gdir/libsteam_api.so" ]; then
                api_file="$gdir/libsteam_api.so"
            elif [ -f "$gdir/lib64/libsteam_api.so" ]; then
                api_file="$gdir/lib64/libsteam_api.so"
            else
                api_file=$(find "$gdir" -maxdepth 3 \( -name "steam_api64.dll" -o -name "steam_api.dll" -o -name "libsteam_api.so" \) 2>/dev/null | head -n 1)
            fi
        else
            if [ -f "$gdir/libsteam_api.so" ]; then
                api_file="$gdir/libsteam_api.so"
            elif [ -f "$gdir/lib64/libsteam_api.so" ]; then
                api_file="$gdir/lib64/libsteam_api.so"
            elif [ -f "$gdir/steam_api64.dll" ]; then
                api_file="$gdir/steam_api64.dll"
            elif [ -f "$gdir/steam_api.dll" ]; then
                api_file="$gdir/steam_api.dll"
            else
                api_file=$(find "$gdir" -maxdepth 3 \( -name "libsteam_api.so" -o -name "steam_api64.dll" -o -name "steam_api.dll" \) 2>/dev/null | head -n 1)
            fi
        fi
    fi

    local is_gbe=false
    if [ -n "$api_file" ] && [ -f "$api_file" ]; then
        if is_gbe_library "$api_file" 2>/dev/null; then
            is_gbe=true
        fi
    fi

    if [ "$is_gbe" = false ]; then
        if { [ -n "$api_file" ] && [ -f "${api_file}.orig" ]; } || \
           [ -f "$gdir/libsteam_api.so.orig" ] || [ -f "$gdir/lib64/libsteam_api.so.orig" ] || \
           [ -f "$gdir/steam_api64.dll.orig" ] || [ -f "$gdir/steam_api.dll.orig" ] || \
           [ -d "$gdir/steam_settings" ] || [ -f "$gdir/local_save.txt" ] || [ -f "$gdir/.gamectl_gbe" ]; then
            is_gbe=true
        fi
    fi

    if [ "$is_gbe" = false ] && [ -n "$api_file" ] && [ -f "$api_file" ]; then
        if LC_ALL=C grep -q -a -E 'steam_settings/configs\.user\.ini|coldclient|goldberg|gbe_fork' "$api_file" 2>/dev/null; then
            is_gbe=true
        else
            local sz
            sz=$(stat -c%s "$api_file" 2>/dev/null || echo 0)
            [ "$sz" -gt 7000000 ] && is_gbe=true
        fi
    fi

    if [ "$is_gbe" = true ]; then
        echo "GBE_FORK"
    elif [ -n "$api_file" ] && [ -f "$api_file" ]; then
        case "$api_file" in
            *.dll) echo "VALVE_DLL" ;;
            *)     echo "VALVE_SO" ;;
        esac
    else
        echo "STANDALONE"
    fi
    return 0
}

# Canonical SSoT AppID resolver across standalone & Steam game directories
resolve_game_appid() {
    local gdir="${1:-}"
    local default_val="${2:-}"
    if [ -z "$gdir" ] || [ ! -d "$gdir" ]; then
        [ -n "$default_val" ] && echo "$default_val"
        return 0
    fi

    local cand line digits
    for cand in "$gdir/steam_appid.txt" "$gdir/steam_settings/steam_appid.txt" "$gdir/.gamectl_appid"; do
        [ -f "$cand" ] || continue
        while IFS= read -r line || [ -n "$line" ]; do
            digits="${line//[!0-9]/}"
            if [ -n "$digits" ]; then
                echo "$digits"
                return 0
            fi
        done < "$cand" 2>/dev/null
    done

    [ -n "$default_val" ] && echo "$default_val"
    return 0
}

# Canonical collision-free runtime log path resolver per game directory + executable
get_game_log_file() {
    local gdir="${1:-}"
    local gbin="${2:-game}"
    local run_dir safe_gbin
    run_dir="$(get_runtime_dir)"
    safe_gbin=$(basename "${gbin:-game}" 2>/dev/null | tr -cd '[:alnum:]_-')
    [ -z "$safe_gbin" ] && safe_gbin="game"

    if [ -n "$gdir" ]; then
        local base_slug path_id
        base_slug=$(basename "$gdir" 2>/dev/null | tr -cd '[:alnum:]_-')
        path_id=$(printf '%s' "$gdir" | cksum | awk '{print $1}')
        echo "$run_dir/game_${base_slug:+${base_slug}_}${path_id}_${safe_gbin}.log"
    else
        echo "$run_dir/game_${safe_gbin}.log"
    fi
}

# Atomically set or append a key=value entry without sed delimiter/escape injection
atomic_set_kv_file() {
    local file="${1:-}"
    local key="${2:-}"
    local val="${3:-}"
    local sep="${4:-=}"
    [ -n "$file" ] && [ -n "$key" ] || return 1
    if [[ "$key" == *[$'\n\r']* ]] || [[ "$val" == *[$'\n\r']* ]]; then
        echo "[ERROR] Key/value mutation rejected: newline/CR not permitted." >&2
        return 1
    fi
    mkdir -p "$(dirname "$file")" || return 1

    local tmp
    tmp=$(mktemp "${file}.gamectl.XXXXXX") || return 1
    local src_file="/dev/null"
    [ -f "$file" ] && src_file="$file"

    if ! GAMECTL_KV_KEY="$key" GAMECTL_KV_VAL="$val" GAMECTL_KV_SEP="$sep" awk '
        BEGIN {
            k = ENVIRON["GAMECTL_KV_KEY"]
            v = ENVIRON["GAMECTL_KV_VAL"]
            s = ENVIRON["GAMECTL_KV_SEP"]
            found = 0
        }
        {
            pos = index($0, "=")
            if (pos > 0) {
                lhs = substr($0, 1, pos - 1)
                gsub(/^[ \t]+|[ \t]+$/, "", lhs)
                if (lhs == k) {
                    if (!found) {
                        print k s v
                        found = 1
                    }
                    next
                }
            }
            print $0
        }
        END {
            if (!found) {
                print k s v
            }
        }
    ' "$src_file" > "$tmp"; then
        rm -f "$tmp"
        return 1
    fi

    if [ -f "$file" ]; then
        chmod --reference="$file" "$tmp" 2>/dev/null || true
    else
        chmod 600 "$tmp" 2>/dev/null || true
    fi

    if ! mv -f "$tmp" "$file"; then
        rm -f "$tmp"
        return 1
    fi
}

# Atomically prepend a line to a file (safe on 0-byte or nonexistent files)
atomic_prepend_line() {
    local file="${1:-}"
    local line="${2:-}"
    [ -n "$file" ] || return 1
    if [[ "$line" == *[$'\n\r']* ]]; then
        echo "[ERROR] Line prepend rejected: newline/CR not permitted." >&2
        return 1
    fi
    mkdir -p "$(dirname "$file")" || return 1

    local tmp
    tmp=$(mktemp "${file}.gamectl.XXXXXX") || return 1
    if ! printf '%s\n' "$line" > "$tmp"; then
        rm -f "$tmp"
        return 1
    fi
    if [ -f "$file" ]; then
        if ! cat "$file" >> "$tmp"; then
            rm -f "$tmp"
            return 1
        fi
        chmod --reference="$file" "$tmp" 2>/dev/null || true
    else
        chmod 600 "$tmp" 2>/dev/null || true
    fi
    if ! mv -f "$tmp" "$file"; then
        rm -f "$tmp"
        return 1
    fi
}

# Audit ZIP archive integrity, path traversal, and symlink entries before extraction
audit_zip_safety() {
    local zip_file="${1:-}"
    if [ -z "$zip_file" ] || [ ! -f "$zip_file" ] || [ ! -s "$zip_file" ]; then
        echo "[ERROR] Archive not found or empty: ${zip_file:-<empty>}" >&2
        return 1
    fi
    if ! unzip -tq "$zip_file" >/dev/null 2>&1; then
        echo "[ERROR] Archive failed ZIP integrity check: $zip_file" >&2
        return 1
    fi
    local entries
    entries=$(unzip -Z1 "$zip_file" 2>/dev/null) || return 1
    if [ -z "$entries" ]; then
        echo "[ERROR] Archive contains no entries: $zip_file" >&2
        return 1
    fi
    if printf '%s\n' "$entries" | grep -Eq '(^/|^[A-Za-z]:|(^|[/\\])\.\.([/\\]|$)|\\)'; then
        echo "[ERROR] Security violation: unsafe path traversal detected in archive payload." >&2
        return 1
    fi
    local zip_details
    zip_details=$(unzip -Z "$zip_file" 2>/dev/null) || return 1
    if grep -Eq '^l[-rwxstST]{6,9}[[:space:]]' <<< "$zip_details"; then
        echo "[ERROR] Security violation: symlink entry detected in archive payload." >&2
        return 1
    fi
    return 0
}

# Read a configuration key from ~/.config/gamectl/config
get_config_value() {
    local key="$1"
    local default_val="${2:-}"
    local cfg_file="$HOME/.config/gamectl/config"
    [ -f "$cfg_file" ] || { echo "$default_val"; return 0; }
    local val
    val=$(grep -E "^[[:space:]]*${key}[[:space:]]*=" "$cfg_file" 2>/dev/null | tail -n 1 | sed -E "s/^[[:space:]]*${key}[[:space:]]*=[[:space:]]*//" | tr -d '\r')
    if [ -z "$val" ] && [ "$key" = "hubcap_key" ]; then
        val=$(grep -E "^[[:space:]]*hubcap_api_key[[:space:]]*=" "$cfg_file" 2>/dev/null | tail -n 1 | sed -E "s/^[[:space:]]*hubcap_api_key[[:space:]]*=[[:space:]]*//" | tr -d '\r')
    elif [ -z "$val" ] && [ "$key" = "hubcap_api_key" ]; then
        val=$(grep -E "^[[:space:]]*hubcap_key[[:space:]]*=" "$cfg_file" 2>/dev/null | tail -n 1 | sed -E "s/^[[:space:]]*hubcap_key[[:space:]]*=[[:space:]]*//" | tr -d '\r')
    fi
    if [ -n "$val" ]; then
        echo "$val"
    else
        echo "$default_val"
    fi
}

# Write or update a configuration key in ~/.config/gamectl/config
set_config_value() {
    local key="$1"
    local val="$2"
    [ "$key" = "hubcap_key" ] && key="hubcap_api_key"
    local cfg_dir="$HOME/.config/gamectl"
    local cfg_file="$cfg_dir/config"
    mkdir -p "$cfg_dir"
    atomic_set_kv_file "$cfg_file" "$key" "$val" "="
}

# Resolve Hubcap Manifest API key across environment, config file, and legacy stash
get_hubcap_api_key() {
    if [ -n "${HUBCAP_API_KEY:-}" ]; then
        echo "$HUBCAP_API_KEY"
        return 0
    elif [ -n "${HUBCAP_KEY:-}" ]; then
        echo "$HUBCAP_KEY"
        return 0
    fi

    local key
    key=$(get_config_value "hubcap_api_key")
    if [ -z "$key" ]; then
        key=$(get_config_value "hubcap_key")
    fi

    if [ -z "$key" ] && [ -f "$HOME/.config/gamectl/hubcap_api_key" ]; then
        key=$(head -n 1 "$HOME/.config/gamectl/hubcap_api_key" 2>/dev/null | tr -d '[:space:]')
    fi

    echo "$key"
}
# Standalone-source compatibility: load split core submodules when sourced directly outside bin/gamectl
if [ -z "${GAMECTL_BUNDLED:-}" ] && [ -n "${BASH_SOURCE[0]:-}" ]; then
    _core_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd)"
    for _core_sub in 12_tui_primitives.sh 14_saves.sh 16_steamstub.sh 18_process_runtime.sh 19_gbe_templates.sh; do
        if [ -f "$_core_dir/$_core_sub" ]; then
            # shellcheck source=/dev/null
            source "$_core_dir/$_core_sub"
        fi
    done
    unset _core_dir _core_sub
fi

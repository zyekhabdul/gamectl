# Binary Resolution, Shebang Detection & Active Process SSoT Helpers

# Check if a regular file begins with a POSIX shebang (#!)
_is_shebang_script() {
    local f="${1:-}" magic=""
    [ -s "$f" ] && [ ! -d "$f" ] || return 1
    IFS= read -r -n 2 magic < "$f" 2>/dev/null || true
    [ "$magic" = "#!" ]
}

# Print ELF class ("64", "32", or "0") if non-empty regular file starts with ELF magic
_read_elf_class() {
    local f="${1:-}" hdr=""
    [ -s "$f" ] && [ ! -d "$f" ] || return 1
    hdr=$(od -An -tx1 -N5 "$f" 2>/dev/null | tr -d ' \n' || true)
    case "$hdr" in
        7f454c4602) echo "64"; return 0 ;;
        7f454c4601) echo "32"; return 0 ;;
        7f454c46*)  echo "0";  return 0 ;;
    esac
    return 1
}

# Check if filename is an ignorable non-launcher artifact
_is_ignored_binary_name() {
    case "${1:-}" in
        *.so|*.so.*|*.dll|*.dylib|*.exe|*.EXE|*.lock|*.log|installscript.vdf|*.png|*.bmp|*.txt|*.pkg|\
        createdump|monoconfig|monomachineconfig|*.vdf|*.json|*.cfg|*.ini|*.xml|*.md|*.README|*.config|*.orig|crashpad_handler|chrome-sandbox)
            return 0 ;;
    esac
    return 1
}

# Select best native Linux executable from directory prioritizing host architecture
_pick_native_linux_binary() {
    local dir="$1"
    local host_arch
    host_arch="$(uname -m 2>/dev/null || echo x86_64)"
    local is_64bit=false
    case "$host_arch" in
        x86_64|amd64|aarch64) is_64bit=true ;;
    esac

    local f fname elf_cls is_script preferred_bin="" fallback_bin=""
    for f in "$dir"/*; do
        [ -x "$f" ] && [ -s "$f" ] && [ ! -d "$f" ] || continue
        fname="${f##*/}"
        validate_tui_fields "$fname" || continue
        _is_ignored_binary_name "$fname" && continue

        elf_cls=""
        is_script=false
        if _is_shebang_script "$f"; then
            is_script=true
        elif ! elf_cls=$(_read_elf_class "$f"); then
            continue
        fi

        if [ "$is_64bit" = true ]; then
            if [ "$is_script" = true ] || [ "$elf_cls" = "64" ] || \
               [[ "$fname" == *.x86_64 || "$fname" == *.x64 || "$fname" == *_64 || "$fname" == *64 ]]; then
                preferred_bin="$fname"
                break
            fi
            [ -z "$fallback_bin" ] && fallback_bin="$fname"
        else
            if [ "$is_script" = true ] || [ "$elf_cls" = "32" ] || \
               [[ "$fname" == *.x86 || "$fname" == *32 ]]; then
                preferred_bin="$fname"
                break
            fi
            [ -z "$fallback_bin" ] && fallback_bin="$fname"
        fi
    done

    if [ -n "$preferred_bin" ]; then
        echo "$preferred_bin"
        return 0
    fi
    if [ -n "$fallback_bin" ]; then
        echo "$fallback_bin"
        return 0
    fi
    return 1
}

# Dynamic executable finder for game directory
find_game_binary() {
    local dir="$1"
    local base
    base=$(basename "$dir")
    local clean_base="${base// /}"
    local lower_base="${base,,}"
    local lower_clean="${clean_base,,}"

    # Priority 1: Common launch scripts or matching names (auto-+x shebang scripts)
    local candidates=(
        "start.sh" "run.sh" "launch.sh" "start" "run"
        "$base" "$clean_base" "$lower_base" "$lower_clean"
    )
    local c
    for c in "${candidates[@]}"; do
        if [ -f "$dir/$c" ] && [ ! -d "$dir/$c" ]; then
            validate_tui_fields "$c" || continue
            if [ ! -x "$dir/$c" ] && _is_shebang_script "$dir/$c"; then
                chmod +x "$dir/$c" 2>/dev/null || true
            fi
            if [ -x "$dir/$c" ]; then
                echo "$c"
                return 0
            fi
        fi
    done

    # Priority 2: Native Linux executables matching host architecture
    local native_bin
    if native_bin=$(_pick_native_linux_binary "$dir"); then
        echo "$native_bin"
        return 0
    fi

    # Priority 3: Windows executables matching title/folder name
    local win_candidates=(
        "$base.exe" "$clean_base.exe" "$lower_base.exe" "$lower_clean.exe"
    )
    for c in "${win_candidates[@]}"; do
        if [ -f "$dir/$c" ] && [ ! -d "$dir/$c" ]; then
            validate_tui_fields "$c" || continue
            chmod +x "$dir/$c" 2>/dev/null || true
            echo "$c"
            return 0
        fi
    done

    # Priority 4: Any root .exe excluding setup/redist/crash handlers
    local f fname
    for f in "$dir"/*.exe "$dir"/*.EXE; do
        [ -f "$f" ] || continue
        fname="${f##*/}"
        validate_tui_fields "$fname" || continue
        case "$fname" in
            UnityCrashHandler*|*unins*|*setup*|*installer*|*redist*|DXSETUP*|dotnet*|*CrashReport*)
                continue
                ;;
            *)
                chmod +x "$f" 2>/dev/null || true
                echo "$fname"
                return 0
                ;;
        esac
    done

    # Priority 5a: Subdirectory native Linux executables (ELF / shebang)
    local sub sub_bin
    for sub in "bin" "bin/x64" "bin/x86_64" "bin/linux64" "bin/linux" "x86_64" "x64" "linux64" "linux" "game"; do
        [ -d "$dir/$sub" ] || continue
        for c in "$base" "$clean_base" "$lower_base" "$lower_clean"; do
            if [ -f "$dir/$sub/$c" ] && [ ! -d "$dir/$sub/$c" ] && validate_tui_fields "$c"; then
                [ ! -x "$dir/$sub/$c" ] && _is_shebang_script "$dir/$sub/$c" && chmod +x "$dir/$sub/$c" 2>/dev/null || true
                if [ -x "$dir/$sub/$c" ]; then
                    echo "$sub/$c"; return 0
                fi
            fi
        done
        if sub_bin=$(_pick_native_linux_binary "$dir/$sub"); then
            echo "$sub/$sub_bin"; return 0
        fi
    done

    # Priority 5: Subdirectory .exe in standard game binary folders
    for sub in "bin" "bin/x64" "bin/Win64" "Binaries/Win64" "Binaries/Win32" "x64"; do
        if [ -d "$dir/$sub" ]; then
            for f in "$dir/$sub"/*.exe "$dir/$sub"/*.EXE; do
                [ -f "$f" ] || continue
                fname="${f##*/}"
                validate_tui_fields "$fname" || continue
                case "$fname" in
                    UnityCrashHandler*|*unins*|*setup*|*installer*|*redist*|DXSETUP*|dotnet*|*CrashReport*)
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

    # Priority 6: Unrecognized +x files when no native ELF/shebang or Windows PE exists
    for f in "$dir"/*; do
        [ -x "$f" ] && [ ! -d "$f" ] || continue
        fname="${f##*/}"
        validate_tui_fields "$fname" || continue
        _is_ignored_binary_name "$fname" && continue
        echo "$fname"
        return 0
    done

    return 1
}

# Extract an actionable 1-line diagnostic hint from a game's recent launch log
inspect_game_log_hint() {
    local log_file="${1:-}"
    [ -n "$log_file" ] && [ -f "$log_file" ] || return 0

    local tail_log
    tail_log=$(tail -n 60 "$log_file" 2>/dev/null || true)
    [ -n "$tail_log" ] || return 0

    if echo "$tail_log" | grep -qiE '0x887a0002|DXGI_ERROR|Vulkan support is incomplete|dxvk.*(failed|error|unable)|vkCreateInstance'; then
        echo "Graphics API error detected -> switch Renderer to WineD3D (<CTRL-O> or --wined3d)"
    elif echo "$tail_log" | grep -qiE 'err:module:import_dll|cannot open shared object file|error while loading shared libraries|libGL\.so\.1|System\.DllNotFoundException|DllNotFoundException|Unable to load shared library'; then
        echo "Missing runtime DLL/library -> run 'gamectl setup-runtime', Community Fixes (<CTRL-X>), or install 32-bit multilib"
    elif echo "$tail_log" | grep -qiE 'cannot enable executable stack|execstack'; then
        echo "Legacy executable-stack library blocked by glibc 2.41+ -> retry with GLIBC_TUNABLES=glibc.rtld.execstack=2"
    elif echo "$tail_log" | grep -qiE 'Exec format error|cannot execute binary file|Permission denied'; then
        echo "Executable architecture or permission mismatch -> verify 64-bit binary / chmod +x"
    elif echo "$tail_log" | grep -qiE 'SteamStub|Application load error|steamclient.*fail'; then
        echo "SteamStub/DRM signature detected -> run unpack-stub or Inject GBE (<CTRL-I>)"
    elif echo "$tail_log" | grep -qiE 'Segmentation fault|SIGSEGV|SIGABRT|SIGBUS|SIGILL|Aborted|core dumped|Illegal instruction|Bus error'; then
        echo "Process crashed with fatal signal (segfault/abort) -> inspect log or try Steam Runtime / WineD3D"
    fi
    return 0
}

# Return 0 only if PID is alive and not an unreaped zombie/dead task (Z/X/x)
is_pid_running() {
    local pid="${1:-}"
    [[ "$pid" =~ ^[0-9]+$ ]] || return 1
    kill -0 "$pid" 2>/dev/null || return 1
    if [ -r "/proc/$pid/stat" ]; then
        local stat_line="" state=""
        IFS= read -r stat_line < "/proc/$pid/stat" 2>/dev/null || return 1
        stat_line="${stat_line##*) }"
        state="${stat_line%% *}"
        case "$state" in
            Z|X|x) return 1 ;;
        esac
    fi
    return 0
}

# Emit active running game rows (FS=\x1f: PID, TITLE, DIR, BIN, LOG, INFO_FILE, SCOPE_UNIT) and prune stale info files
list_active_games() {
    local run_dir
    run_dir="$(get_runtime_dir)"
    local active_dir="$run_dir/active_games"
    [ -d "$active_dir" ] || return 0

    local inf p_pid p_title p_dir p_bin p_log p_scope
    local sep=$'\x1f'
    local had_nullglob=0
    shopt -q nullglob && had_nullglob=1
    shopt -s nullglob
    for inf in "$active_dir"/*.info; do
        [ -f "$inf" ] || continue
        p_pid="" p_title="" p_dir="" p_bin="" p_log="" p_scope=""
        local k v
        while IFS='=' read -r k v; do
            case "$k" in
                PID) p_pid="$v" ;;
                TITLE) p_title="$v" ;;
                DIR) p_dir="$v" ;;
                BIN) p_bin="$v" ;;
                LOG) p_log="$v" ;;
                SCOPE_UNIT) p_scope="$v" ;;
            esac
        done < "$inf"
        if [ -n "$p_pid" ] && is_pid_running "$p_pid"; then
            printf '%s%s%s%s%s%s%s%s%s%s%s%s%s\n' \
                "$p_pid" "$sep" "$p_title" "$sep" "$p_dir" "$sep" "$p_bin" "$sep" "$p_log" "$sep" "$inf" "$sep" "$p_scope"
        else
            rm -f "$inf" 2>/dev/null || true
        fi
    done
    [ "$had_nullglob" -eq 0 ] && shopt -u nullglob
    return 0
}

# Find active game row matching target directory (exact or realpath canonical)
find_active_game_for_dir() {
    local gdir="${1:-}"
    [ -n "$gdir" ] || return 1
    local canon_gdir
    canon_gdir=$(realpath -e "$gdir" 2>/dev/null || echo "$gdir")

    local sep=$'\x1f'
    local r_pid r_title r_dir r_bin r_log r_inf r_scope r_canon
    while IFS="$sep" read -r r_pid r_title r_dir r_bin r_log r_inf r_scope; do
        [ -n "$r_pid" ] || continue
        if [ "$r_dir" = "$gdir" ]; then
            printf '%s%s%s%s%s%s%s%s%s%s%s%s%s\n' \
                "$r_pid" "$sep" "$r_title" "$sep" "$r_dir" "$sep" "$r_bin" "$sep" "$r_log" "$sep" "$r_inf" "$sep" "$r_scope"
            return 0
        fi
        r_canon=$(realpath -e "$r_dir" 2>/dev/null || echo "$r_dir")
        if [ "$r_canon" = "$canon_gdir" ]; then
            printf '%s%s%s%s%s%s%s%s%s%s%s%s%s\n' \
                "$r_pid" "$sep" "$r_title" "$sep" "$r_dir" "$sep" "$r_bin" "$sep" "$r_log" "$sep" "$r_inf" "$sep" "$r_scope"
            return 0
        fi
    done < <(list_active_games)
    return 1
}

# Return active game summary as "COUNT\x1fTITLE1, TITLE2"
get_active_games_summary() {
    local count=0 titles="" sep=$'\x1f'
    local r_pid r_title _rest
    while IFS="$sep" read -r r_pid r_title _rest; do
        [ -n "$r_pid" ] || continue
        count=$((count + 1))
        if [ -z "$titles" ]; then
            titles="$r_title"
        else
            titles="$titles, $r_title"
        fi
    done < <(list_active_games)
    printf '%d%s%s\n' "$count" "$sep" "$titles"
}

# Canonical XDG directory for gamectl's standalone Native Linux Steam Runtime (Scout)
get_standalone_runtime_dir() {
    if [ -n "${GAMECTL_RUNTIME_DIR:-}" ]; then
        echo "$GAMECTL_RUNTIME_DIR"
    else
        echo "${XDG_DATA_HOME:-$HOME/.local/share}/gamectl/runtime/steam-runtime"
    fi
}

# Resolve Valve Steam Runtime run.sh wrapper for Native Linux games (opt-out via native_runtime=host)
find_steam_runtime_run() {
    local gdir="${1:-}" rt_mode="" w_cfg k v
    local -a w_cfgs=("$HOME/.config/gamectl/wrappers")
    [ -n "$gdir" ] && w_cfgs+=("$gdir/.wrappers")
    for w_cfg in "${w_cfgs[@]}"; do
        [ -f "$w_cfg" ] || continue
        while IFS='=' read -r k v || [ -n "$k" ]; do
            k="${k//[[:space:]]/}"
            [ "$k" = "native_runtime" ] || continue
            v="${v//$'\r'/}"
            v="${v#"${v%%[![:space:]]*}"}"
            v="${v%"${v##*[![:space:]]}"}"
            v="${v#\"}"
            v="${v%\"}"
            v="${v#\'}"
            v="${v%\'}"
            rt_mode="$v"
        done < "$w_cfg"
    done
    [ -n "${GAMECTL_NATIVE_RUNTIME:-}" ] && rt_mode="$GAMECTL_NATIVE_RUNTIME"
    case "${rt_mode,,}" in
        host|0|off|none|direct|disabled) return 1 ;;
    esac

    if [ -n "${GAMECTL_STEAM_RUNTIME_RUN:-}" ] && [ -x "$GAMECTL_STEAM_RUNTIME_RUN" ]; then
        echo "$GAMECTL_STEAM_RUNTIME_RUN"
        return 0
    fi

    local standalone_dir=""
    standalone_dir="$(get_standalone_runtime_dir)"
    if [ -n "$standalone_dir" ] && [ -x "$standalone_dir/run.sh" ]; then
        echo "$standalone_dir/run.sh"
        return 0
    fi

    local s_root="" cand=""
    local -a candidates=()
    if declare -F get_steam_root >/dev/null 2>&1; then
        s_root="$(get_steam_root 2>/dev/null || true)"
        [ -n "$s_root" ] && candidates+=("$s_root/ubuntu12_32/steam-runtime/run.sh")
    fi
    candidates+=(
        "$HOME/.local/share/Steam/ubuntu12_32/steam-runtime/run.sh"
        "$HOME/.steam/root/ubuntu12_32/steam-runtime/run.sh"
        "$HOME/.steam/steam/ubuntu12_32/steam-runtime/run.sh"
        "$HOME/.var/app/com.valvesoftware.Steam/.local/share/Steam/ubuntu12_32/steam-runtime/run.sh"
        "$HOME/snap/steam/common/.local/share/Steam/ubuntu12_32/steam-runtime/run.sh"
    )
    for cand in "${candidates[@]}"; do
        [ -n "$cand" ] && [ -x "$cand" ] && { echo "$cand"; return 0; }
    done
    return 1
}

# Resolve effective LD_LIBRARY_PATH for Native Linux ELF execution (host + Steam Runtime fallback)
resolve_native_linux_ld_path() {
    local gdir="${1:-}" rel_ld="${2:-.:lib64:lib}"
    local base_ld="${rel_ld}${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
    local sr_run="" sr_ld=""
    sr_run=$(find_steam_runtime_run "$gdir" 2>/dev/null || true)
    if [ -n "$sr_run" ]; then
        sr_ld=$(LD_LIBRARY_PATH="$base_ld" "$sr_run" --print-steam-runtime-library-paths 2>/dev/null || true)
        if [ -n "$sr_ld" ]; then
            printf '%s\n' "$sr_ld"
            return 0
        fi
    fi
    printf '%s\n' "$base_ld"
}

# Audit a Native Linux ELF executable via ldd and emit "ARCH\x1flib1, lib2" for missing shared libraries
list_missing_elf_libs() {
    local gdir="${1:-}"
    local gbin="${2:-}"
    [ -n "$gdir" ] && [ -n "$gbin" ] && [ -d "$gdir" ] && [ -f "$gdir/$gbin" ] || return 1
    command -v ldd >/dev/null 2>&1 || return 1

    local elf_cls=""
    elf_cls=$(_read_elf_class "$gdir/$gbin") || return 1

    local arch_label="ELF" rel_ld=".:lib64:lib"
    case "$elf_cls" in
        32) arch_label="32-bit"; rel_ld=".:lib" ;;
        64) arch_label="64-bit"; rel_ld=".:lib64:lib" ;;
    esac

    # Use cd + relative LD_LIBRARY_PATH so directory names with ':' never split lookup entries
    local ldd_out="" missing_joined="" eff_ld=""
    eff_ld=$(resolve_native_linux_ld_path "$gdir" "$rel_ld")
    ldd_out=$(cd "$gdir" && LC_ALL=C LD_LIBRARY_PATH="$eff_ld" ldd -- "./$gbin" 2>/dev/null || true)
    [ -n "$ldd_out" ] || return 1

    missing_joined=$(awk '/=> not found/ {
        sub(/^[ \t]+/, "", $1)
        if ($1 != "" && !seen[$1]++) {
            out = (out == "" ? $1 : out ", " $1)
        }
    }
    END { print out }' <<< "$ldd_out")

    [ -n "$missing_joined" ] || return 1
    printf '%s\x1f%s\n' "$arch_label" "$missing_joined"
    return 0
}

# Probe newly launched game across startup window to catch early crashes cleanly
verify_launched_game_startup() {
    local gdir="${1:-}"
    local gbin="${2:-}"
    local title="${3:-}"
    local probe_ticks="${GAMECTL_LAUNCH_PROBE_TICKS:-10}"
    [[ "$probe_ticks" =~ ^[0-9]+$ ]] && [ "$probe_ticks" -ge 1 ] || probe_ticks=10

    GAMECTL_VERIFY_PID=""
    GAMECTL_VERIFY_LOG=""
    GAMECTL_VERIFY_INFO=""
    GAMECTL_VERIFY_SUMMARY=""

    local row=""
    row=$(find_active_game_for_dir "$gdir" 2>/dev/null || true)
    if [ -z "$row" ]; then
        sleep 0.1
        row=$(find_active_game_for_dir "$gdir" 2>/dev/null || true)
    fi

    local sep=$'\x1f'
    local v_pid="" v_title="" v_dir="" v_bin="" v_log="" v_inf="" v_scope=""
    if [ -n "$row" ]; then
        IFS="$sep" read -r v_pid v_title v_dir v_bin v_log v_inf v_scope <<< "$row"
    fi

    local alive=false
    if [ -n "$v_pid" ]; then
        alive=true
        local tick=0
        while [ "$tick" -lt "$probe_ticks" ]; do
            if ! is_pid_running "$v_pid"; then
                alive=false
                break
            fi
            tick=$((tick + 1))
            [ "$tick" -lt "$probe_ticks" ] && sleep 0.1
        done
    fi

    if [ "$alive" = true ]; then
        GAMECTL_VERIFY_PID="$v_pid"
        GAMECTL_VERIFY_LOG="$v_log"
        GAMECTL_VERIFY_INFO="$v_inf"
        export GAMECTL_VERIFY_PID GAMECTL_VERIFY_LOG GAMECTL_VERIFY_INFO
        return 0
    fi

    [ -n "$v_inf" ] && rm -f "$v_inf" 2>/dev/null || true
    [ -z "$v_log" ] && v_log="$(get_game_log_file "$gdir" "$gbin")"
    GAMECTL_VERIFY_LOG="$v_log"
    export GAMECTL_VERIFY_LOG

    local v_hint="" v_tail="" missing_info="" m_arch="" m_libs=""
    v_hint=$(inspect_game_log_hint "$v_log" 2>/dev/null || true)
    missing_info=$(list_missing_elf_libs "$gdir" "$gbin" 2>/dev/null || true)
    if [ -n "$missing_info" ]; then
        IFS="$sep" read -r m_arch m_libs <<< "$missing_info"
        [ -z "$v_hint" ] && v_hint="Missing $m_arch shared libraries -> run 'gamectl setup-runtime' or install required multilib packages"
    fi
    if [ -s "$v_log" ]; then
        v_tail=$(tail -n 12 "$v_log" 2>/dev/null || true)
    else
        v_tail="(No diagnostic output recorded in log file.)"
    fi

    GAMECTL_VERIFY_SUMMARY="Game '$title' exited immediately after launch."
    [ -n "$v_hint" ] && GAMECTL_VERIFY_SUMMARY+=$'\n\n'"[HINT] $v_hint"
    [ -n "$m_libs" ] && GAMECTL_VERIFY_SUMMARY+=$'\n\n'"Missing Shared Libraries ($m_arch):"$'\n'"$m_libs"
    GAMECTL_VERIFY_SUMMARY+=$'\n\n'"Recent Log Output:"$'\n'"$v_tail"$'\n\n'"Full log:"$'\n'"$v_log"
    export GAMECTL_VERIFY_SUMMARY
    return 1
}

# Record most recent game exit metadata atomically for event-driven consumers
record_game_exit_event() {
    local pid="${1:-}" title="${2:-}" gdir="${3:-}" log_file="${4:-}"
    local hint="" run_dir exit_file tmp_file
    [ -n "$log_file" ] && hint=$(inspect_game_log_hint "$log_file" 2>/dev/null || true)
    title="${title//$'\n'/ }"; title="${title//$'\r'/}"
    hint="${hint//$'\n'/ }"; hint="${hint//$'\r'/}"
    run_dir="$(get_runtime_dir)"
    exit_file="$run_dir/last_game_exit.info"
    tmp_file=$(mktemp "${exit_file}.tmp.XXXXXX" 2>/dev/null) || return 0
    {
        printf 'PID=%s\nTITLE=%s\nDIR=%s\nLOG=%s\nHINT=%s\nTS=%s\n' \
            "$pid" "$title" "$gdir" "$log_file" "$hint" "$(date +%s)"
    } > "$tmp_file" 2>/dev/null && mv -f "$tmp_file" "$exit_file" 2>/dev/null || rm -f "$tmp_file" 2>/dev/null || true
    return 0
}

# Emit recent exit event within max_age_secs as \x1f-delimited row: PID, TITLE, DIR, LOG, HINT, TS
get_last_game_exit_event() {
    local max_age="${1:-15}"
    [[ "$max_age" =~ ^[0-9]+$ ]] || max_age=15
    local exit_file
    exit_file="$(get_runtime_dir)/last_game_exit.info"
    [ -f "$exit_file" ] || return 1

    local e_pid="" e_title="" e_dir="" e_log="" e_hint="" e_ts="" k v
    while IFS='=' read -r k v; do
        case "$k" in
            PID) e_pid="$v" ;;
            TITLE) e_title="$v" ;;
            DIR) e_dir="$v" ;;
            LOG) e_log="$v" ;;
            HINT) e_hint="$v" ;;
            TS) e_ts="$v" ;;
        esac
    done < "$exit_file"
    [[ "$e_ts" =~ ^[0-9]+$ ]] || return 1
    local now; now=$(date +%s)
    [ $((now - e_ts)) -le "$max_age" ] || return 1

    local sep=$'\x1f'
    printf '%s%s%s%s%s%s%s%s%s%s%s\n' \
        "$e_pid" "$sep" "$e_title" "$sep" "$e_dir" "$sep" "$e_log" "$sep" "$e_hint" "$sep" "$e_ts"
    return 0
}

# Return 0 if local fzf and curl binaries support Unix-socket --listen live event triggers
tui_supports_live_events() {
    local fzf_bin="" curl_bin=""
    fzf_bin=$(command -v fzf 2>/dev/null || true)
    curl_bin=$(command -v curl 2>/dev/null || true)
    [ -n "$fzf_bin" ] && [ -n "$curl_bin" ] || return 1
    _is_shebang_script "$fzf_bin" && return 1
    _is_shebang_script "$curl_bin" && return 1
    "$fzf_bin" --help </dev/null 2>/dev/null | grep -Fq -- '--listen=SOCKET_PATH' || return 1
    "$curl_bin" --help all </dev/null 2>/dev/null | grep -Fq -- '--unix-socket' || return 1
    return 0
}

# Push trigger(f12) event to all active TUI listener sockets and prune dead ones
notify_tui_listeners() {
    local ldir
    ldir="$(get_runtime_dir)/tui_listeners"
    [ -d "$ldir" ] || return 0
    command -v curl >/dev/null 2>&1 || return 0

    local had_nullglob=0 sock
    shopt -q nullglob && had_nullglob=1
    shopt -s nullglob
    for sock in "$ldir"/*.sock; do
        if [ -S "$sock" ]; then
            curl -sS --max-time 1 --unix-socket "$sock" -X POST http://localhost/ -d 'trigger(f12)' >/dev/null 2>&1 || rm -f "$sock" 2>/dev/null || true
        else
            rm -f "$sock" 2>/dev/null || true
        fi
    done
    [ "$had_nullglob" -eq 0 ] && shopt -u nullglob
    return 0
}

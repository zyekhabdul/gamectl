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
        createdump|monoconfig|monomachineconfig|*.vdf|*.json|*.cfg|*.ini|*.xml|*.md|*.README|*.config|*.orig)
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

    # Priority 5: Subdirectory .exe in standard game binary folders
    local sub
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
        echo "Missing runtime DLL/library -> run Community Fixes (<CTRL-X>) or install 32-bit multilib"
    elif echo "$tail_log" | grep -qiE 'Exec format error|cannot execute binary file|Permission denied'; then
        echo "Executable architecture or permission mismatch -> verify 64-bit binary / chmod +x"
    elif echo "$tail_log" | grep -qiE 'SteamStub|Application load error|steamclient.*fail'; then
        echo "SteamStub/DRM signature detected -> run unpack-stub or Inject GBE (<CTRL-I>)"
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
        if [ -n "$p_pid" ] && kill -0 "$p_pid" 2>/dev/null; then
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
    local ldd_out="" missing_joined=""
    ldd_out=$(cd "$gdir" && LC_ALL=C LD_LIBRARY_PATH="${rel_ld}${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}" ldd -- "./$gbin" 2>/dev/null || true)
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
            if ! kill -0 "$v_pid" 2>/dev/null; then
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
        [ -z "$v_hint" ] && v_hint="Missing $m_arch shared libraries -> install required multilib/system packages"
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

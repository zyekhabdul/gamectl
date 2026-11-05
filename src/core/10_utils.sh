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

# Resolve remote sync host (optional)
get_remote_host() {
    local host="${GAMECTL_REMOTE_HOST:-${GAMECTL_COMPANION_HOST:-${GAMECTL_SYNC_HOST:-${GAMECTL_TUF_HOST:-}}}}"
    if [ -z "$host" ] && [ -f "$HOME/.config/gamectl/remote_host" ]; then
        host=$(head -n 1 "$HOME/.config/gamectl/remote_host" | tr -d '[:space:]')
    fi
    echo "$host"
}

# Pre-flight cleanup of orphaned sockets and locks
clean_stale_locks() {
    local run_dir="${XDG_RUNTIME_DIR:-/tmp/gamectl-$UID}"
    rm -f /tmp/SteaMidra-* /tmp/steam_chrome_shmem_* /tmp/steam_chrome_overlay_* 2>/dev/null || true
    rm -f "$run_dir"/SteaMidra-* "$run_dir"/steam_chrome_* 2>/dev/null || true
    rm -f "$HOME/.config/SLSsteam/cache/.picsbuffer.lock" 2>/dev/null || true
}

# Auto-backup savegame (Rolling 3 snapshots)
backup_save() {
    local game_dir="$1"
    local is_quiet="${2:-false}"
    local save_dir="$game_dir/saves"
    if [ -d "$save_dir" ]; then
        local snap_dir="$game_dir/.save_snapshots"
        mkdir -p "$snap_dir"
        [ -d "$snap_dir/slot2" ] && rm -rf "$snap_dir/slot3" && mv "$snap_dir/slot2" "$snap_dir/slot3"
        [ -d "$snap_dir/slot1" ] && mv "$snap_dir/slot1" "$snap_dir/slot2"
        cp -a "$save_dir" "$snap_dir/slot1"
        echo "[INFO] Save snapshot created successfully in slot1 ($snap_dir/slot1)"
    else
        if [ "$is_quiet" = true ]; then
            return 0
        fi
        echo "[WARN] Portable saves directory ($save_dir) not found." >&2
        echo "       Game has not been injected with GBE Fork or lacks an isolated save directory." >&2
        echo "       Press <CTRL-I> first to enable portable saves." >&2
        return 1
    fi
}

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

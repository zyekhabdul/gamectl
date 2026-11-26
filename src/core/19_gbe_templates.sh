# ==============================================================================
# Goldberg Emulator (GBE Fork) Template Resolver & Provisioner (Split from 10_utils.sh)
# ==============================================================================

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

# Check the installed bytes, not the presence of an original-library backup.
is_gbe_library() {
    local library="$1" platform=linux arch=x64 template
    case "${library##*/}" in
        steam_api64.dll) platform=windows ;;
        steam_api.dll) platform=windows; arch=x86 ;;
        libsteam_api.so)
            if file -Lb "$library" 2>/dev/null | grep -qi '32-bit'; then arch=x86; fi
            ;;
        *) return 1 ;;
    esac
    template=$(get_gbe_template "$platform" "$arch") || return 1
    cmp -s -- "$template" "$library"
}

# Stage replacements beside their destination so failed copies preserve the live library.
install_gbe_library() {
    local template="$1" destination="$2" staged
    mkdir -p "$(dirname "$destination")" || return 1
    if [ -e "$destination.orig" ] || [ -L "$destination.orig" ]; then
        [ -f "$destination.orig" ] || return 1
    elif [ -f "$destination" ]; then
        staged=$(mktemp "$destination.orig.gamectl.XXXXXX") || return 1
        if ! cp -a -- "$destination" "$staged" || ! mv -nT -- "$staged" "$destination.orig"; then
            rm -f -- "$staged"
            return 1
        fi
        rm -f -- "$staged"
    fi
    staged=$(mktemp "$destination.gamectl.XXXXXX") || return 1
    if ! cp "$template" "$staged" || ! chmod +x "$staged" || \
       ! cmp -s -- "$template" "$staged" || ! mv -fT -- "$staged" "$destination"; then
        rm -f -- "$staged"
        echo "[ERROR] Failed to install GBE library: $destination" >&2
        return 1
    fi
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
                if [ -d "$src_root/tools/generate_interfaces" ]; then
                    mkdir -p "$dest_dir/tools/generate_interfaces"
                    cp -f "$src_root/tools/generate_interfaces/"* "$dest_dir/tools/generate_interfaces/" 2>/dev/null || true
                    chmod +x "$dest_dir/tools/generate_interfaces"/generate_interfaces_* 2>/dev/null || true
                fi
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

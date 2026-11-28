# ==============================================================================
# GOG Offline Installer Extractor (Zero Login: innoextract + MojoSetup)
# ==============================================================================

_gog_derive_title_from_filename() {
    local fname="${1##*/}"
    fname="${fname%.exe}"
    fname="${fname%.EXE}"
    fname="${fname%.sh}"
    fname="${fname%.SH}"
    fname="${fname#setup_}"
    fname="${fname#Setup_}"
    fname=$(printf '%s' "$fname" | sed -E 's/[_-](v?[0-9]+(\.[0-9]+)+.*|\([0-9]+\))$//' | tr '_' ' ' | sed -E 's/[[:space:]]+/ /g; s/^[[:space:]]+//; s/[[:space:]]+$//')
    [ -n "$fname" ] || fname="GOG_Game"
    printf '%s\n' "$fname"
}

_gog_audit_extracted_symlinks() {
    local stage_dir="$1"
    local canon_stage link_target
    canon_stage=$(realpath -m "$stage_dir" 2>/dev/null || echo "$stage_dir")
    while IFS= read -r sym; do
        [ -n "$sym" ] || continue
        link_target=$(readlink "$sym" 2>/dev/null || true)
        if [[ "$link_target" == /* ]]; then
            echo "[ERROR] Unsafe absolute symlink in GOG installer payload: $sym -> $link_target" >&2
            return 1
        fi
        local resolved_link
        resolved_link=$(realpath -m "$(dirname "$sym")/$link_target" 2>/dev/null || echo "")
        if [ -z "$resolved_link" ] || [[ "$resolved_link" != "$canon_stage/"* && "$resolved_link" != "$canon_stage" ]]; then
            echo "[ERROR] Unsafe path traversal symlink in GOG installer payload: $sym -> $link_target" >&2
            return 1
        fi
    done < <(find "$stage_dir" -type l 2>/dev/null || true)
    return 0
}

_gog_extract_exe() {
    local installer_abs="$1"
    local stage_dir="$2"
    if ! command -v innoextract >/dev/null 2>&1; then
        echo "[ERROR] 'innoextract' is required for Windows GOG installers (.exe)." >&2
        echo "[INFO] Install via package manager (e.g. sudo pacman -S innoextract / sudo apt install innoextract)." >&2
        return 1
    fi
    echo "[INFO] Extracting GOG Windows installer with innoextract..."
    innoextract -e -d "$stage_dir" "$installer_abs" || return 1
    _gog_audit_extracted_symlinks "$stage_dir" || return 1
    return 0
}

_gog_extract_sh() {
    local installer_abs="$1"
    local stage_dir="$2"
    local rc=0
    echo "[INFO] Extracting GOG Linux MojoSetup installer (.sh)..."
    if command -v unzip >/dev/null 2>&1; then
        unzip -q -o "$installer_abs" -d "$stage_dir" 2>/dev/null || rc=$?
        # MojoSetup .sh wrappers prepend a shell header, causing Info-ZIP unzip to return 1 (warning).
        if [ "$rc" -ne 0 ] && [ "$rc" -ne 1 ]; then
            echo "[ERROR] Failed to extract GOG .sh installer with unzip (exit $rc)." >&2
            return 1
        fi
    elif command -v 7z >/dev/null 2>&1; then
        7z x -y "-o$stage_dir" "$installer_abs" >/dev/null || return 1
    else
        echo "[ERROR] 'unzip' or '7z' is required to extract GOG .sh installers." >&2
        return 1
    fi

    local entry_count
    entry_count=$(find "$stage_dir" -mindepth 1 -maxdepth 2 2>/dev/null | head -n 1 | wc -l)
    if [ "$entry_count" -eq 0 ]; then
        echo "[ERROR] Extracted GOG .sh archive yielded no files." >&2
        return 1
    fi
    _gog_audit_extracted_symlinks "$stage_dir" || return 1
    return 0
}

_gog_resolve_stage_root() {
    local stage_dir="$1"
    if [ -d "$stage_dir/data/noarch" ]; then
        printf '%s\n' "$stage_dir/data/noarch"
    elif [ -d "$stage_dir/app" ]; then
        local mf
        for mf in "$stage_dir"/goggame-*.info; do
            [ -f "$mf" ] && cp -f "$mf" "$stage_dir/app/" 2>/dev/null || true
        done
        printf '%s\n' "$stage_dir/app"
    else
        printf '%s\n' "$stage_dir"
    fi
}

_gog_read_extracted_metadata() {
    local content_root="$1"
    local fallback_title="$2"
    local gog_id="" gog_title="" gog_info="" gf

    for gf in "$content_root"/goggame-*.info "$content_root"/game/goggame-*.info; do
        [ -f "$gf" ] && gog_info="$gf" && break
    done

    if [ -n "$gog_info" ] && command -v jq >/dev/null 2>&1; then
        local tsv=""
        tsv=$(jq -r '[((.gameId // .rootGameId // "") | tostring), ((.name // "") | tostring)] | if any(test("[\\t\\r\\n]")) then "" else @tsv end' "$gog_info" 2>/dev/null || true)
        if [ -n "$tsv" ]; then
            IFS=$'\t' read -r gog_id gog_title <<< "$tsv"
        fi
        if [ -z "$gog_id" ]; then
            local bname="${gog_info##*/}"
            bname="${bname#goggame-}"
            gog_id="${bname%.info}"
        fi
    fi

    if [ -z "$gog_title" ] && [ -f "$content_root/gameinfo" ]; then
        gog_title=$(head -n 1 "$content_root/gameinfo" 2>/dev/null | tr -d '\r\n' || true)
    fi

    [ -n "$gog_title" ] || gog_title="$fallback_title"
    if [ -z "$gog_id" ]; then
        local slug
        slug=$(printf '%s' "$gog_title" | tr '[:upper:]' '[:lower:]' | tr -cs '[:alnum:]' '_' | sed 's/^_//; s/_$//')
        gog_id="LOCAL_${slug:-gog}"
    fi

    printf '%s\t%s\n' "$gog_id" "$gog_title"
}

_gog_init_windows_prefix() {
    local target_dir="$1"
    local gog_id="$2"
    local runner_bin=""
    declare -F find_runner >/dev/null 2>&1 && runner_bin=$(find_runner "$target_dir" 2>/dev/null || true)
    [ -z "$runner_bin" ] && command -v wine >/dev/null 2>&1 && runner_bin="wine"

    if [ -z "$runner_bin" ]; then
        echo "[WARN] No Wine/Proton runner detected on host; skipping initial prefix creation for $target_dir." >&2
        return 0
    fi

    local pfx_dir="$target_dir/pfx"
    mkdir -p "$pfx_dir" || return 1
    if declare -F prepare_windows_runner_env >/dev/null 2>&1; then
        prepare_windows_runner_env "$runner_bin" "$target_dir" "$gog_id" "auto" "0"
    else
        GAMECTL_WIN_PFX_DIR="$pfx_dir"
        GAMECTL_WIN_RUNNER_KIND="wine"
    fi

    echo "[INFO] Initializing isolated Wine prefix ($pfx_dir) via $(basename "$runner_bin")..."
    (
        export WINEPREFIX="$GAMECTL_WIN_PFX_DIR"
        [ -n "${GAMECTL_WIN_UMU_GAMEID:-}" ] && export GAMEID="$GAMECTL_WIN_UMU_GAMEID"
        [ "${GAMECTL_WIN_RUNNER_KIND:-}" = "proton" ] && export STEAM_COMPAT_CLIENT_INSTALL_PATH="${GAMECTL_WIN_STEAM_ROOT:-$HOME/.local/share/Steam}" STEAM_COMPAT_DATA_PATH="$target_dir"
        local wb_bin
        wb_bin="$(dirname "$runner_bin")/wineboot"
        [ -x "$wb_bin" ] || wb_bin="wineboot"
        case "${GAMECTL_WIN_RUNNER_KIND:-wine}" in
            proton) "$runner_bin" run wineboot -u >/dev/null 2>&1 ;;
            umu)    "$runner_bin" wineboot -u >/dev/null 2>&1 ;;
            *)      WINEARCH=win64 WINEDEBUG=-all "$wb_bin" -u >/dev/null 2>&1 || WINEPREFIX="$pfx_dir" "$runner_bin" wineboot -u >/dev/null 2>&1 ;;
        esac
    ) || echo "[WARN] Wine prefix pre-initialization returned non-zero; prefix will complete on first launch." >&2
    return 0
}

# Offline GOG Installer Extractor: gamectl install-gog <setup.exe|installer.sh> [target_dir] [--title <name>] [--no-prefix] [--dry-run]
install_gog_offline() {
    local installer="" target_dir="" custom_title="" no_prefix=false is_dry_run=false
    while [ $# -gt 0 ]; do
        case "$1" in
            --title)
                [ -n "${2:-}" ] || { echo "[ERROR] --title requires a value." >&2; return 1; }
                custom_title="$2"; shift 2 ;;
            --title=*)
                custom_title="${1#*=}"; shift ;;
            --no-prefix)
                no_prefix=true; shift ;;
            --dry-run|-n)
                is_dry_run=true; shift ;;
            --help|-h)
                echo "Usage: gamectl install-gog <setup.exe|installer.sh> [target_dir] [--title <name>] [--no-prefix] [--dry-run]"
                return 0 ;;
            -*)
                echo "[ERROR] Unknown option: $1" >&2
                return 1 ;;
            *)
                if [ -z "$installer" ]; then installer="$1"
                elif [ -z "$target_dir" ]; then target_dir="$1"
                else echo "[ERROR] Unexpected argument: $1" >&2; return 1; fi
                shift ;;
        esac
    done

    if [ -z "$installer" ] || [ ! -f "$installer" ]; then
        echo "[ERROR] GOG installer file not found: ${installer:-<empty>}" >&2
        echo "Usage: gamectl install-gog <setup.exe|installer.sh> [target_dir] [--title <name>] [--no-prefix]" >&2
        return 1
    fi

    local installer_abs
    installer_abs=$(realpath -e "$installer" 2>/dev/null || echo "$installer")
    local ext="${installer_abs##*.}"
    ext="${ext,,}"
    if [ "$ext" != "exe" ] && [ "$ext" != "sh" ]; then
        local ftype=""
        ftype=$(file -b "$installer_abs" 2>/dev/null || true)
        if echo "$ftype" | grep -qiE 'PE32|MS Windows'; then ext="exe"
        elif echo "$ftype" | grep -qiE 'shell script|Zip archive'; then ext="sh"
        else
            echo "[ERROR] Unsupported GOG installer format '$installer' (expected .exe or .sh)." >&2
            return 1
        fi
    fi

    local fallback_title="${custom_title:-$(_gog_derive_title_from_filename "$installer_abs")}"
    declare -F validate_tui_fields >/dev/null 2>&1 && { validate_tui_fields "$fallback_title" || return 1; }

    if [ "$is_dry_run" = true ]; then
        local dry_dir="${target_dir:-${GAMECTL_LIBRARY_DIR:-$HOME/GOG Games}/$fallback_title}"
        echo "[INFO] [DRY-RUN] GOG offline installer: $installer_abs (type: .$ext)"
        echo "[INFO] [DRY-RUN] Target directory: $dry_dir"
        return 0
    fi

    local run_dir stage_dir
    run_dir="$(get_runtime_dir 2>/dev/null || echo "${TMPDIR:-/tmp}")"
    stage_dir=$(mktemp -d "${run_dir}/gog_extract_XXXXXX") || return 1
    trap 'rm -rf "${stage_dir:-}" 2>/dev/null || true; trap - RETURN' RETURN

    if [ "$ext" = "exe" ]; then
        _gog_extract_exe "$installer_abs" "$stage_dir" || return 1
    else
        _gog_extract_sh "$installer_abs" "$stage_dir" || return 1
    fi

    local content_root meta_tsv gog_id gog_title
    content_root=$(_gog_resolve_stage_root "$stage_dir")
    meta_tsv=$(_gog_read_extracted_metadata "$content_root" "$fallback_title")
    IFS=$'\t' read -r gog_id gog_title <<< "$meta_tsv"
    [ -n "$custom_title" ] && gog_title="$custom_title"
    declare -F validate_tui_fields >/dev/null 2>&1 && { validate_tui_fields "$gog_id" "$gog_title" || return 1; }

    if [ -z "$target_dir" ]; then
        local safe_folder
        safe_folder=$(printf '%s' "$gog_title" | tr '/\\:*?"<>|' '_' | sed -E 's/^[.[:space:]]+//; s/[[:space:]]+$//')
        [ -n "$safe_folder" ] || safe_folder="GOG_Game"
        target_dir="${GAMECTL_LIBRARY_DIR:-$HOME/GOG Games}/$safe_folder"
    fi

    if [ "$target_dir" = "/" ] || [[ "$target_dir" == *".."* ]]; then
        echo "[ERROR] Invalid target directory: $target_dir" >&2
        return 1
    fi

    if [ -d "$target_dir" ] && declare -F is_game_active_for_dir >/dev/null 2>&1; then
        local active_pid=""
        if active_pid=$(is_game_active_for_dir "$target_dir" 2>/dev/null); then
            echo "[ERROR] Cannot overwrite running game in $target_dir (PID: $active_pid)." >&2
            return 1
        fi
    fi

    mkdir -p "$target_dir" "$target_dir/saves" || return 1
    echo "[INFO] Installing '$gog_title' into $target_dir..."
    cp -a "$content_root"/. "$target_dir/" || return 1

    # Ensure scanner metadata is present even for stripped GOG installers
    local has_gog_info=0
    local _gf
    for _gf in "$target_dir"/goggame-*.info; do
        [ -f "$_gf" ] && has_gog_info=1 && break
    done
    if [ "$has_gog_info" -eq 0 ]; then
        printf '%s\n' "$gog_id" > "$target_dir/.gog_id"
    fi
    printf '%s\n' "$gog_title" > "$target_dir/.gamectl_title"

    declare -F ensure_linux_binaries_executable >/dev/null 2>&1 && ensure_linux_binaries_executable "$target_dir"
    [ -f "$target_dir/start.sh" ] && chmod +x "$target_dir/start.sh" 2>/dev/null || true

    local detected_bin=""
    declare -F find_game_binary >/dev/null 2>&1 && detected_bin=$(find_game_binary "$target_dir" 2>/dev/null || true)
    if [ "$no_prefix" = false ] && [[ "${detected_bin,,}" == *.exe ]]; then
        _gog_init_windows_prefix "$target_dir" "$gog_id"
    fi

    declare -F invalidate_scan_cache >/dev/null 2>&1 && invalidate_scan_cache || true
    echo "[VERIFIED] GOG offline install complete: '$gog_title' ($gog_id) -> $target_dir${detected_bin:+ [bin: $detected_bin]}"
    declare -F log_msg >/dev/null 2>&1 && log_msg "INFO" "GOG" "Installed offline GOG package '$gog_title' ($gog_id) to $target_dir" || true
    return 0
}

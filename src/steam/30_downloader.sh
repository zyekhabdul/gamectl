# Standalone-source bootstrap: load canonical SSoT helpers when sourced outside bin/gamectl
if ! declare -F get_runtime_dir >/dev/null 2>&1 || ! declare -F audit_zip_safety >/dev/null 2>&1 || ! declare -F atomic_prepend_line >/dev/null 2>&1; then
    _dl_core_utils="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." 2>/dev/null && pwd)/core/10_utils.sh"
    if [ -f "$_dl_core_utils" ]; then
        # shellcheck source=../core/10_utils.sh
        source "$_dl_core_utils"
    fi
    unset _dl_core_utils
fi

if ! declare -F get_runtime_dir >/dev/null 2>&1; then
    get_runtime_dir() {
        local run_uid="${UID:-$(id -u 2>/dev/null || echo 1000)}"
        local run_dir="${XDG_RUNTIME_DIR:-/tmp/gamectl-$UID}"
        [ -z "${UID:-}" ] && run_dir="${XDG_RUNTIME_DIR:-/tmp/gamectl-$run_uid}"
        mkdir -p -m 700 "$run_dir" 2>/dev/null || true
        echo "$run_dir"
    }
fi

# Resolve path to standalone Steam CDN depot downloader binary (gamectl-depot-dl)
resolve_depot_dl_bin() {
    if [ -n "${GAMECTL_DEPOT_DL_BIN:-}" ] && [ -x "$GAMECTL_DEPOT_DL_BIN" ]; then
        echo "$GAMECTL_DEPOT_DL_BIN"
        return 0
    fi
    local candidate
    local script_dir
    script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd 2>/dev/null || echo "")"
    for candidate in \
        "$script_dir/gamectl-depot-dl" \
        "$script_dir/../../bin/gamectl-depot-dl" \
        "$script_dir/../bin/gamectl-depot-dl" \
        "$script_dir/bin/gamectl-depot-dl" \
        "$HOME/.local/bin/gamectl-depot-dl" \
        "/usr/local/bin/gamectl-depot-dl" \
        "/usr/bin/gamectl-depot-dl"; do
        if [ -x "$candidate" ]; then
            echo "$candidate"
            return 0
        fi
    done
    if command -v gamectl-depot-dl >/dev/null 2>&1; then
        command -v gamectl-depot-dl
        return 0
    fi
    return 1
}

# Ensure Steam CDN depot downloader runtime is available
ensure_downloader() {
    if resolve_depot_dl_bin >/dev/null 2>&1; then
        return 0
    fi
    echo "[WARN] Standalone depot downloader binary (gamectl-depot-dl) not found." >&2
    return 1
}

# Resolve optimal destination directory based on configured libraries and available disk space
resolve_target_library_dir() {
    local safe_title="${1:-game}"
    local candidate_dirs=()

    # 0. Primary sovereign library override
    if [ -n "${GAMECTL_LIBRARY_DIR:-}" ]; then
        candidate_dirs+=("$GAMECTL_LIBRARY_DIR")
    elif [ -f "$HOME/.config/gamectl/library_dir" ]; then
        local p_lib
        p_lib=$(head -n 1 "$HOME/.config/gamectl/library_dir" 2>/dev/null | tr -d '\r\n' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
        [ -n "$p_lib" ] && candidate_dirs+=("${p_lib/#\~/$HOME}")
    fi

    # 1. Custom libraries from config
    local cfg_libs="$HOME/.config/gamectl/libraries"
    if [ -f "$cfg_libs" ]; then
        while IFS= read -r line || [ -n "$line" ]; do
            line="${line#"${line%%[![:space:]]*}"}" # trim leading
            line="${line%"${line##*[![:space:]]}"}" # trim trailing
            [ -z "$line" ] && continue
            [[ "$line" =~ ^# ]] && continue
            candidate_dirs+=("${line/#\~/$HOME}")
        done < "$cfg_libs"
    fi

    # 2. Extra libraries from environment
    if [ -n "${GAMECTL_LIBRARY_DIRS:-}" ]; then
        local extra_dirs=()
        IFS=":" read -r -a extra_dirs <<< "$GAMECTL_LIBRARY_DIRS"
        candidate_dirs+=("${extra_dirs[@]}")
    fi

    # 3. Default fallback directory
    candidate_dirs+=("$HOME/Games")

    local best_dir="$HOME/Games"
    local max_free=0
    declare -A seen_candidates=()

    for d in "${candidate_dirs[@]}"; do
        [ -n "$d" ] || continue
        [[ -v seen_candidates["$d"] ]] && continue
        seen_candidates["$d"]=1

        # If dir doesn't exist yet, probe parent dir
        local probe_target="$d"
        while [ ! -d "$probe_target" ] && [ "$probe_target" != "/" ] && [ "$probe_target" != "." ]; do
            probe_target="$(dirname "$probe_target")"
        done

        if [ -d "$probe_target" ]; then
            local free_space
            free_space=$(df -PB 1M "$probe_target" 2>/dev/null | awk 'NR==2 {print $4}' || echo "0")
            if [[ "$free_space" =~ ^[0-9]+$ ]] && [ "$free_space" -gt "$max_free" ]; then
                max_free="$free_space"
                best_dir="$d"
            fi
        fi
    done

    echo "$best_dir/$safe_title"
}

# Detect primary OS platform for AppID via Steam API (returns "windows" or "linux")
detect_app_platform_os() {
    local appid="${1:-}"
    [ -z "$appid" ] && echo "linux" && return 0

    local det_json
    det_json=$(fetch_cached_json "https://store.steampowered.com/api/appdetails?appids=${appid}&filters=platforms" "steam_platforms_${appid}" 3600 2>/dev/null || true)
    local is_linux is_win
    is_linux=$(echo "$det_json" | jq -r ".\"${appid}\".data.platforms.linux // false" 2>/dev/null || echo "false")
    is_win=$(echo "$det_json" | jq -r ".\"${appid}\".data.platforms.windows // false" 2>/dev/null || echo "false")
    if [ "$is_linux" != "true" ] && [ "$is_win" = "true" ]; then
        echo "windows"
    else
        echo "linux"
    fi
}

# Parse depot ID to oslist mapping from manifest JSON in staging directory
parse_depot_os_map() {
    local stage_dir="$1"
    [ -d "$stage_dir" ] || return 0

    shopt -s nullglob globstar
    local json_files=("$stage_dir"/**/*.json "$stage_dir"/*.json)
    shopt -u nullglob globstar

    for jf in "${json_files[@]}"; do
        [ -f "$jf" ] || continue
        jq -r '.depot | to_entries[] | select(.value | type == "object") | select(.value.config.oslist != null) | "\(.key)=\(.value.config.oslist)"' "$jf" 2>/dev/null || true
    done
}

# Ensure Linux ELF binaries in target directory have executable permission (+x)
ensure_linux_binaries_executable() {
    local target_dir="$1"
    [ -d "$target_dir" ] || return 0

    local elf_count=0
    while IFS= read -r f_cand; do
        [ -f "$f_cand" ] || continue
        local sig
        sig=$(od -An -tx1 -N4 "$f_cand" 2>/dev/null | tr -d " \n" || true)
        if [ "$sig" = "7f454c46" ]; then
            if [ ! -x "$f_cand" ]; then
                chmod +x "$f_cand" 2>/dev/null || true
                elf_count=$((elf_count + 1))
            fi
        fi
    done < <(find "$target_dir" -maxdepth 4 -type f ! -path '*/.*' ! -name '*.pak' ! -name '*.vpk' ! -name '*.dat' ! -name '*.assets' ! -name '*.bundle' ! -name '*.txt' ! -name '*.json' ! -name '*.png' ! -name '*.jpg' ! -name '*.ogg' ! -name '*.wav' ! -name '*.mp3' 2>/dev/null || true)

    if [ "$elf_count" -gt 0 ]; then
        echo "[INFO] Granted executable permission (chmod +x) to $elf_count Linux ELF binary(s)." >&2
    fi
    return 0
}

# Steam Native Game Downloader & Provisioner (Standalone CDN Engine)
download_game() {
    local appid="${1:-}"
    # Strip ANSI escape sequences & non-digits
    appid=$(strip_ansi "$appid" | tr -dc "0-9")
    if [ -z "$appid" ]; then
        echo "Usage: gamectl download <appid> [target_dir] [title] [--source <auto|manifesthub|ryuu|sushi|luatools>] [--os <linux|windows|macos|all>] [--allow-dlc] [--raw|--inject-only|--all|--standalone|--sls]" >&2
        return 1
    fi
    shift

    local target_dir=""
    local title=""
    local target_os=""
    local action="all"          # "all", "inject", "raw"
    local source="auto"         # "auto", "ryuu", "sushi", "luatools"
    local engine="standalone"   # Default to Pure Standalone CDN engine (Zero Steam Client)
    local is_strict_standalone=true
    local allow_dlc=false

    while [ $# -gt 0 ]; do
        case "$1" in
            --allow-dlc)
                allow_dlc=true
                ;;
            --engine)
                shift
                case "${1:-}" in
                    depot)
                        echo "[WARN] DepotDownloader is deprecated and removed. Routing to native Steam CDN engine." >&2
                        ;;
                    steam|sls)
                        engine="sls"
                        is_strict_standalone=false
                        ;;
                    standalone|direct)
                        engine="standalone"
                        is_strict_standalone=true
                        ;;
                esac
                ;;
            --engine=*)
                local eng_val="${1#--engine=}"
                case "$eng_val" in
                    depot)
                        echo "[WARN] DepotDownloader is deprecated and removed. Routing to native Steam CDN engine." >&2
                        ;;
                    steam|sls)
                        engine="sls"
                        is_strict_standalone=false
                        ;;
                    standalone|direct)
                        engine="standalone"
                        is_strict_standalone=true
                        ;;
                esac
                ;;
            --sls|--steam)
                engine="sls"
                is_strict_standalone=false
                ;;
            --direct|--no-steam|--standalone|--headless)
                engine="standalone"
                is_strict_standalone=true
                ;;
            --source)
                shift
                source="${1:-auto}"
                ;;
            --source=*)
                source="${1#--source=}"
                ;;
            --raw|--download-only|--no-inject)
                action="raw"
                ;;
            --inject-only|--no-sync)
                action="inject"
                ;;
            --all)
                action="all"
                ;;
            --foreground|-f|foreground|--background|-b|background)
                # Preserved for CLI flag backwards-compatibility
                ;;
            --os)
                shift
                target_os="${1:-}"
                ;;
            --os=*)
                target_os="${1#--os=}"
                ;;
            *)
                if [ -z "$target_dir" ]; then
                    target_dir="$1"
                elif [ -z "$title" ]; then
                    title="$1"
                fi
                ;;
        esac
        shift
    done

    if [ -n "$target_os" ]; then
        target_os="${target_os,,}"
        case "$target_os" in
            linux|windows|macos|osx|all)
                [ "$target_os" = "osx" ] && target_os="macos"
                ;;
            *)
                echo "[ERROR] Invalid target OS '$target_os'. Valid options: linux, windows, macos, all." >&2
                return 1
                ;;
        esac
    fi

    # Auto-resolve engine preference
    if [ "$engine" = "auto" ]; then
        if [ "$action" = "inject" ]; then
            engine="sls"
        elif resolve_depot_dl_bin >/dev/null 2>&1; then
            engine="standalone"
        else
            engine="sls"
        fi
    fi

    # Verify standalone binary availability with graceful fallback
    if [ "$engine" = "standalone" ]; then
        local dl_bin
        dl_bin="$(resolve_depot_dl_bin 2>/dev/null || true)"
        if [ -z "$dl_bin" ] || [ ! -x "$dl_bin" ]; then
            if [ "$is_strict_standalone" = true ]; then
                echo "[ERROR] Standalone downloader binary (gamectl-depot-dl) not found." >&2
                echo "[ERROR] Compile it via 'make build-depot-dl' or run 'gamectl setup-gbe'." >&2
                log_msg "ERROR" "DOWNLOAD" "Standalone downloader binary not found in strict standalone mode"
                return 1
            fi
            echo "[WARN] Standalone downloader binary (gamectl-depot-dl) not found. Falling back to SLSsteam engine." >&2
            engine="sls"
        fi

        # Fail-fast offline credential preflight for explicit gated sources before metadata HTTP lookups
        local dl_cache_zip="${XDG_CACHE_HOME:-$HOME/.cache}/gamectl/manifests/${appid}.zip"
        local dl_stash_zip="$HOME/.local/share/gamectl/manifests/${appid}.zip"
        if [ ! -f "$dl_cache_zip" ] && [ ! -f "$dl_stash_zip" ]; then
            if [ "${source,,}" = "luatools" ] && ! get_valid_luatools_token >/dev/null 2>&1; then
                echo "[ERROR] LuaTools session unavailable. Authenticate with 'gamectl login-luatools <code | session.json>' and retry." >&2
                return 1
            elif [ "${source,,}" = "hubcap" ] && [ -z "$(get_hubcap_api_key 2>/dev/null || true)" ]; then
                echo "[ERROR] Hubcap API key is not configured. Run 'gamectl config set hubcap_key <smm_key>' and retry." >&2
                return 1
            fi
        fi
    fi

    # Engine-level DLC guard (consistent across CLI and TUI)
    if [ "$allow_dlc" != true ] && declare -F resolve_steam_app_type >/dev/null 2>&1; then
        local app_type_info="" app_type="" parent_appid="" parent_name=""
        app_type_info=$(resolve_steam_app_type "$appid" 2>/dev/null || true)
        IFS=$'\t' read -r app_type parent_appid parent_name <<< "$app_type_info"
        if [ "$app_type" = "DLC" ] && [[ "$parent_appid" =~ ^[0-9]+$ ]]; then
            local dlc_label="${title:+ ($title)}"
            local parent_label="${parent_name:+${parent_name} }($parent_appid)"
            echo "[ERROR] AppID ${appid}${dlc_label} is a DLC for Base Game ${parent_label}." >&2
            echo "[ERROR] Base game downloads already include associated DLC depots. Run: gamectl download $parent_appid" >&2
            echo "[ERROR] To download this DLC AppID explicitly anyway, re-run with --allow-dlc." >&2
            log_msg "WARN" "DOWNLOAD" "Blocked direct DLC download for AppID $appid (base game: $parent_appid)"
            return 1
        fi
    fi

    if [ -z "$title" ]; then
        title=$(fetch_cached_json "https://store.steampowered.com/api/appdetails?appids=${appid}&filters=basic" "steam_basic_${appid}" 3600 2>/dev/null | jq -r ".\"${appid}\".data.name // empty" 2>/dev/null || true)
        [ -z "$title" ] && title="AppID_${appid}"
    fi

    log_msg "INFO" "DOWNLOAD" "Starting download for $title (AppID: $appid, Action: $action, Source: $source)"

    # Route 1: Standalone Native Steam CDN Engine (Zero Steam Client required)
    if [ "$engine" = "standalone" ]; then
        local manifest_zip
        echo "[INFO] Manifest archive not provided. Attempting automatic harvest (source: $source)..." >&2
        manifest_zip=$(fetch_manifest "$appid" "" "$source" true) || return 1
        if [ -z "$manifest_zip" ] || [ ! -f "$manifest_zip" ]; then
            echo "[ERROR] Manifest archive for AppID $appid could not be acquired across providers." >&2
            return 1
        fi

        if ! validate_manifest_zip "$manifest_zip" "$appid" true; then
            echo "[ERROR] Manifest zip validation failed: $manifest_zip" >&2
            return 1
        fi

        local run_dir
        run_dir="$(get_runtime_dir)"
        local stage_dir="$run_dir/depot_dl_${appid}_${BASHPID:-$$}"
        mkdir -p -m 700 "$stage_dir"
        trap 'rm -rf "$stage_dir" 2>/dev/null || true' RETURN

        if ! unzip -q "$manifest_zip" -d "$stage_dir" 2>/dev/null; then
            echo "[ERROR] Failed to unpack manifest archive: $manifest_zip" >&2
            return 1
        fi

        # Integrate any physical DLC manifest archives
        harvest_dlc_manifests "$appid" "$stage_dir" "$source" 2>/dev/null || true

        declare -A depot_keys=()
        shopt -s nullglob globstar
        local cand_luas=("$stage_dir"/**/*.lua "$stage_dir"/*.lua)
        shopt -u nullglob globstar
        local re_key='addappid\([[:space:]]*([0-9]+)[[:space:]]*,[[:space:]]*[0-9]+[[:space:]]*,[[:space:]]*['\''"]([0-9a-fA-F]{64})['\''"]'
        declare -A seen_lua=()
        for clua in "${cand_luas[@]}"; do
            [ -f "$clua" ] || continue
            [[ -v seen_lua["$clua"] ]] && continue
            seen_lua["$clua"]=1
            while IFS= read -r line || [ -n "$line" ]; do
                if [[ "$line" =~ $re_key ]]; then
                    depot_keys["${BASH_REMATCH[1]}"]="${BASH_REMATCH[2]}"
                fi
            done < "$clua"
        done

        # Parse depot OS mappings from manifest JSON
        declare -A depot_os_map=()
        while IFS='=' read -r did osval || [ -n "$did" ]; do
            [ -n "$did" ] && [ -n "$osval" ] && depot_os_map["$did"]="${osval,,}"
        done < <(parse_depot_os_map "$stage_dir")

        # Determine effective target OS if not explicitly supplied
        local effective_os="$target_os"
        if [ -z "$effective_os" ]; then
            if [ "${#depot_os_map[@]}" -eq 0 ]; then
                effective_os="all"
            else
                local has_linux=0
                local has_windows=0
                for d_os in "${depot_os_map[@]}"; do
                    [[ "$d_os" =~ linux ]] && has_linux=1
                    [[ "$d_os" =~ windows ]] && has_windows=1
                done

                local host_os
                host_os="$(uname -s)"
                if [ "$host_os" = "Linux" ]; then
                    if [ "$has_linux" -eq 1 ]; then
                        effective_os="linux"
                        echo "[INFO] Native Linux depot detected. Auto-selecting target OS: linux" >&2
                    elif [ "$has_windows" -eq 1 ]; then
                        effective_os="windows"
                        echo "[INFO] No native Linux depot found. Targeting Windows depot for Proton/Wine runner." >&2
                    else
                        effective_os="all"
                    fi
                else
                    effective_os="all"
                fi
            fi
        fi

        local depot_args=()
        shopt -s nullglob globstar
        local mf_files=("$stage_dir"/**/*.manifest "$stage_dir"/*.manifest)
        declare -A seen_mf=()
        local skipped_os_count=0
        for mf in "${mf_files[@]}"; do
            [ -f "$mf" ] || continue
            local mf_name="$(basename "$mf")"
            [[ -v seen_mf["$mf_name"] ]] && continue
            seen_mf["$mf_name"]=1

            if manifest_has_payload_magic "$mf"; then
                if [[ "$mf_name" =~ ^([0-9]+)_([0-9]+)\.manifest$ ]]; then
                    local did="${BASH_REMATCH[1]}"
                    local key="${depot_keys["$did"]:-}"

                    # OS filter check
                    if [ "$effective_os" != "all" ] && [ -n "${depot_os_map["$did"]:-}" ]; then
                        local d_os="${depot_os_map["$did"]}"
                        local match=0
                        if [ "$effective_os" = "macos" ]; then
                            [[ "$d_os" =~ (macos|osx) ]] && match=1
                        else
                            [[ "$d_os" =~ $effective_os ]] && match=1
                        fi

                        if [ "$match" -eq 0 ]; then
                            echo "[INFO] Skipping depot $did (oslist: $d_os != target: $effective_os)" >&2
                            skipped_os_count=$((skipped_os_count + 1))
                            continue
                        fi
                    fi

                    if [ -n "$key" ]; then
                        depot_args+=(--depot "$mf:$key")
                    else
                        echo "[WARN] No AES decryption key found for depot $did ($mf_name). Skipping." >&2
                    fi
                fi
            fi
        done
        shopt -u nullglob globstar

        if [ "${#depot_args[@]}" -eq 0 ]; then
            if [ "$skipped_os_count" -gt 0 ] && [ "$effective_os" != "all" ]; then
                echo "[ERROR] All candidate depots were filtered out by target OS '$effective_os' ($skipped_os_count skipped)." >&2
                echo "[ERROR] Target AppID $appid may not have depots for '$effective_os'. Try '--os windows' or '--os all'." >&2
                log_msg "ERROR" "DOWNLOAD" "Depot OS filter ($effective_os) rejected all depots for AppID $appid"
                return 1
            fi
            if [ "$is_strict_standalone" = true ]; then
                echo "[ERROR] Strict standalone mode: No encrypted manifests with valid AES keys found for AppID $appid." >&2
                echo "[ERROR] Cannot fallback to Steam Client/SLSsteam in standalone mode (ADR-022)." >&2
                log_msg "ERROR" "DOWNLOAD" "No valid AES depot keys found for AppID $appid in strict standalone mode"
                return 1
            fi
            echo "[WARN] No encrypted manifests with valid AES keys found. Falling back to SLSsteam engine." >&2
            engine="sls"
        else
            if [ -z "$target_dir" ]; then
                target_dir="$(resolve_standalone_library_dir "$title")"
            fi
            mkdir -p "$target_dir"

            echo "=========================================="
            echo " STEAM STANDALONE CDN ENGINE (gamectl-depot-dl)"
            echo "=========================================="
            echo " AppID      : $appid"
            echo " Title      : $title"
            echo " Target Dir : $target_dir"
            echo " Target OS  : $effective_os"
            echo " Depots     : $(( ${#depot_args[@]} / 2 ))"
            echo " Engine     : Native Rust Standalone (Zero Steam Client)"
            echo "=========================================="

            local cur_pid="${BASHPID:-$$}"
            cat <<EOF > "$stage_dir/status.info"
APPID=$appid
TITLE=$title
TARGET_DIR=$target_dir
TARGET_OS=$effective_os
PID=$cur_pid
START_TIME=$(date +%s)
LOG_FILE=$stage_dir/download.log
ENGINE=standalone
STATUS=DOWNLOADING
EOF

            local dl_bin dl_log="$stage_dir/download.log" dl_rc=0
            dl_bin="$(resolve_depot_dl_bin)"
            "$dl_bin" --app "$appid" --dir "$target_dir" "${depot_args[@]}" 2>&1 | tee "$dl_log" || dl_rc=${PIPESTATUS[0]}
            if [ "$dl_rc" -ne 0 ]; then
                echo "STATUS=FAILED" >> "$stage_dir/status.info"
                echo "[ERROR] Standalone CDN download failed (exit code $dl_rc)." >&2
                return 1
            fi

            # Post-download Linux ELF permission hook (Chunk 27.02)
            if [ "$effective_os" = "linux" ] || [ "$effective_os" = "all" ]; then
                ensure_linux_binaries_executable "$target_dir"
            fi

            # Preserve staged lua manifests in target_dir for offline DLC discovery
            shopt -s nullglob globstar
            for l in "$stage_dir"/**/*.lua "$stage_dir"/*.lua; do
                [ -f "$l" ] && cp -f "$l" "$target_dir/" 2>/dev/null || true
            done
            shopt -u nullglob globstar

            if [ "$action" != "raw" ]; then
                fetch_dlc "$target_dir" "$appid" 2>/dev/null || true
                if ! inject_game "$target_dir" "$appid" --no-sync; then
                    echo "STATUS=FAILED" >> "$stage_dir/status.info"
                    echo "[ERROR] Download completed, but standalone GBE provisioning failed." >&2
                    return 1
                fi
            fi

            echo "STATUS=COMPLETED" >> "$stage_dir/status.info"
            invalidate_scan_cache
            echo "[SUCCESS] Standalone download & provisioning complete for $title ($appid) in $target_dir."
            log_msg "INFO" "DOWNLOAD" "Standalone download & provisioning complete for $title ($appid) in $target_dir"
            return 0
        fi
    fi

    # Route 2: Steam Client URI Install (Legacy Content Engine)
    echo "=========================================="
    echo " STEAM NATIVE CONTENT ENGINE"
    echo "=========================================="
    echo " AppID      : $appid"
    echo " Title      : $title"
    echo " Engine     : SLSsteam (Valve High-Speed CDN)"
    echo " Source     : $source"
    echo " Mode       : $action"
    echo "=========================================="

    if deploy_sls_manifest "$appid" "" "$title" "$source"; then
        invalidate_scan_cache
        echo "[SUCCESS] SLSsteam manifests and stplug-in keys provisioned for $title ($appid)."
        log_msg "INFO" "DOWNLOAD" "SLSsteam manifests and stplug-in keys provisioned for $title ($appid)"
        if [ "$action" != "inject" ]; then
            trigger_steam_install "$appid"
        fi
        return 0
    else
        echo "[ERROR] Manifest archive and keys for AppID $appid could not be acquired across providers." >&2
        log_msg "ERROR" "DOWNLOAD" "Manifest archive and keys for AppID $appid could not be acquired across providers"
        return 1
    fi
}
# Locate appmanifest_<appid>.acf across primary and secondary libraries
find_app_acf() {
    local appid="$1"
    [ -z "$appid" ] && return 1

    local primary_apps
    primary_apps="$(get_steam_primary_apps 2>/dev/null || echo "$HOME/.local/share/Steam/steamapps")"
    if [ -f "$primary_apps/appmanifest_${appid}.acf" ]; then
        echo "$primary_apps/appmanifest_${appid}.acf"
        return 0
    fi

    local lib
    while IFS= read -r lib; do
        [ -d "$lib" ] || continue
        if [ -f "$lib/appmanifest_${appid}.acf" ]; then
            echo "$lib/appmanifest_${appid}.acf"
            return 0
        fi
        if [ -f "$lib/steamapps/appmanifest_${appid}.acf" ]; then
            echo "$lib/steamapps/appmanifest_${appid}.acf"
            return 0
        fi
    done < <(get_steam_libraries 2>/dev/null || true)

    return 1
}

# Format byte integer into readable B, KB, MB, GB representation
format_bytes() {
    local b="${1:-0}"
    if [ "$b" -ge 1073741824 ] 2>/dev/null; then
        local gb=$(( b / 1073741824 ))
        local rem=$(( (b % 1073741824) / 104857600 ))
        echo "${gb}.${rem} GB"
    elif [ "$b" -ge 1048576 ] 2>/dev/null; then
        local mb=$(( b / 1048576 ))
        echo "${mb} MB"
    elif [ "$b" -ge 1024 ] 2>/dev/null; then
        local kb=$(( b / 1024 ))
        echo "${kb} KB"
    else
        echo "${b} B"
    fi
}

# Parse Steam appmanifest ACF file for download progress, state, and byte metrics
parse_acf_download_state() {
    local target="$1"
    local acf_file=""
    local appid=""

    if [ -f "$target" ]; then
        acf_file="$target"
    else
        appid=$(strip_ansi "$target" | tr -dc "0-9")
        [ -z "$appid" ] && return 1
        acf_file=$(find_app_acf "$appid" 2>/dev/null || true)
    fi

    if [ -z "$acf_file" ] || [ ! -f "$acf_file" ]; then
        return 1
    fi

    local name="" state_flags="0" bytes_dl="0" bytes_total="0" installdir=""
    local re_appid='^[[:space:]]*"appid"[[:space:]]+"([0-9]+)"'
    local re_name='^[[:space:]]*"name"[[:space:]]+"([^"]+)"'
    local re_flags='^[[:space:]]*"StateFlags"[[:space:]]+"([0-9]+)"'
    local re_bytes_dl='^[[:space:]]*"BytesDownloaded"[[:space:]]+"([0-9]+)"'
    local re_bytes_total='^[[:space:]]*"BytesToDownload"[[:space:]]+"([0-9]+)"'
    local re_installdir='^[[:space:]]*"installdir"[[:space:]]+"([^"]+)"'

    while IFS= read -r line || [ -n "$line" ]; do
        if [[ "$line" =~ $re_appid ]] && [ -z "$appid" ]; then
            appid="${BASH_REMATCH[1]}"
        elif [[ "$line" =~ $re_name ]] && [ -z "$name" ]; then
            name="${BASH_REMATCH[1]}"
        elif [[ "$line" =~ $re_flags ]]; then
            state_flags="${BASH_REMATCH[1]}"
        elif [[ "$line" =~ $re_bytes_dl ]]; then
            bytes_dl="${BASH_REMATCH[1]}"
        elif [[ "$line" =~ $re_bytes_total ]]; then
            bytes_total="${BASH_REMATCH[1]}"
        elif [[ "$line" =~ $re_installdir ]] && [ -z "$installdir" ]; then
            installdir="${BASH_REMATCH[1]}"
        fi
    done < "$acf_file"

    [ -z "$appid" ] && return 1

    local status_str="[UNKNOWN]"
    if [ "$state_flags" -eq 4 ]; then
        status_str="[INSTALLED]"
    elif [ "$state_flags" -eq 512 ] || [ "$state_flags" -eq 514 ] || (( (state_flags & 512) != 0 )); then
        status_str="[PAUSED]"
    elif [ "$state_flags" -eq 1024 ] || [ "$state_flags" -eq 1026 ] || (( (state_flags & 1024) != 0 )); then
        status_str="[DOWNLOADING]"
    elif [ "$state_flags" -eq 2 ] || (( (state_flags & 2) != 0 )); then
        status_str="[UPDATE REQUIRED]"
    fi

    local pct="0%"
    if [ "$bytes_total" -gt 0 ] 2>/dev/null; then
        local calc_pct=$(( (bytes_dl * 100) / bytes_total ))
        [ "$calc_pct" -gt 100 ] && calc_pct=100
        pct="${calc_pct}%"
    elif [ "$state_flags" -eq 4 ]; then
        pct="100%"
    fi

    if [[ "$name$installdir$acf_file" == *[$'\t\r\n']* ]]; then
        echo "[ERROR] ACF fields cannot contain TAB, CR or newline." >&2
        return 1
    fi
    printf "%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n" \
        "$appid" "$name" "$status_str" "$pct" "$bytes_dl" "$bytes_total" "$state_flags" "$installdir" "$acf_file"
}

# List active and recent downloads
list_downloads() {
    echo "=========================================="
    echo " GAMECTL DOWNLOAD STATUS (Unified Engine)"
    echo "=========================================="
    local count=0

    # Inspect Steam Native ACF downloads
    local steam_apps
    steam_apps="$(get_steam_primary_apps 2>/dev/null || echo "$HOME/.local/share/Steam/steamapps")"
    shopt -s nullglob
    local acf_files=("$steam_apps"/appmanifest_*.acf)
    shopt -u nullglob

    for acf in "${acf_files[@]}"; do
        local state_data
        state_data=$(parse_acf_download_state "$acf" 2>/dev/null || true)
        [ -z "$state_data" ] && continue

        local a_id a_title a_status a_pct a_dl a_total a_flags a_dir a_path
        IFS=$'\t' read -r a_id a_title a_status a_pct a_dl a_total a_flags a_dir a_path <<< "$state_data"

        # Only display active downloads or paused/updating apps in download status
        if [ "$a_status" = "[DOWNLOADING]" ] || [ "$a_status" = "[PAUSED]" ] || [ "$a_status" = "[UPDATE REQUIRED]" ]; then
            count=$((count + 1))
            local dl_fmt tot_fmt
            dl_fmt=$(format_bytes "$a_dl")
            tot_fmt=$(format_bytes "$a_total")
            echo "$a_status AppID: $a_id | $a_title | Progress: $a_pct ($dl_fmt / $tot_fmt) [Steam Engine]"
            echo "------------------------------------------"
        fi
    done

    # Inspect Standalone CDN downloads
    local run_dir
    run_dir="$(get_runtime_dir)"
    shopt -s nullglob
    for st_dir in "$run_dir"/depot_dl_*; do
        [ -d "$st_dir" ] || continue
        local base_st="${st_dir##*/}"
        local st_pid="${base_st##*_}"
        local rest_st="${base_st#depot_dl_}"
        local st_appid="${rest_st%_*}"
        [ -z "$st_appid" ] || [ -z "$st_pid" ] && continue

        # Self-healing: purge orphaned staging dir if downloader process is dead
        if ! [[ "$st_pid" =~ ^[0-9]+$ ]] || ! kill -0 "$st_pid" 2>/dev/null; then
            rm -rf "$st_dir" 2>/dev/null || true
            continue
        fi

        local st_info="$st_dir/status.info"
        local st_title="Native CDN Download"
        local st_log="$st_dir/download.log"
        if [ -f "$st_info" ]; then
            local info_title info_log
            info_title=$(grep -E '^TITLE=' "$st_info" | cut -d= -f2- || true)
            info_log=$(grep -E '^LOG_FILE=' "$st_info" | cut -d= -f2- || true)
            [ -n "$info_title" ] && st_title="$info_title"
            [ -n "$info_log" ] && [ -f "$info_log" ] && st_log="$info_log"
        fi

        local prog_data st_pct st_bytes st_state
        prog_data=$(get_depot_dl_progress "$st_log" "$st_pid")
        IFS=$'\t' read -r st_pct st_bytes st_state <<< "$prog_data"

        count=$((count + 1))
        local dl_label="Engine: Standalone CDN"
        if [ -n "$st_bytes" ] && [ "$st_bytes" != "0 MB / 0 MB" ]; then
            echo "$st_state AppID: $st_appid | $st_title | Progress: $st_pct ($st_bytes) | $dl_label"
        else
            echo "$st_state AppID: $st_appid | $st_title | Progress: $st_pct | $dl_label"
        fi
        echo "------------------------------------------"
    done
    shopt -u nullglob

    if [ $count -eq 0 ]; then
        echo "[INFO] No active download tasks in Steam or Standalone engine."
    fi
}

# Helper: Parse structured download telemetry from depot-dl logs
get_depot_dl_progress() {
    local log_file="$1"
    local pid="${2:-}"

    if [ ! -f "$log_file" ]; then
        printf "0%%\t0 MB / 0 MB\t[STARTING]\n"
        return 0
    fi

    local parsed
    parsed=$(awk '
    /^\[DEPOT_START\]/ {
        for (i=1; i<=NF; i++) {
            if ($i ~ /^\([0-9.]+$/) {
                tot += substr($i, 2);
            }
        }
    }
    /^\[PROGRESS\] Transferred:/ {
        dl = $3;
    }
    /^\[SUCCESS\]/ {
        done = 1;
    }
    /^\[ERROR\]/ {
        err = 1;
    }
    END {
        if (done) {
            printf "100%%\t%.2f MB / %.2f MB\t[COMPLETED]\n", dl ? dl : tot, tot ? tot : dl;
        } else if (err && !dl) {
            printf "0%%\t0 MB / 0 MB\t[FAILED]\n";
        } else if (tot > 0 && dl > 0) {
            pct = int((dl / tot) * 100);
            if (pct > 100) pct = 100;
            printf "%d%%\t%.2f MB / %.2f MB\t[DOWNLOADING]\n", pct, dl, tot;
        } else if (tot > 0) {
            printf "0%%\t0 MB / %.2f MB\t[STARTING]\n", tot;
        } else if (dl > 0) {
            printf "0%%\t%.2f MB transferred\t[DOWNLOADING]\n", dl;
        } else {
            printf "0%%\t0 MB / 0 MB\t[STARTING]\n";
        }
    }' "$log_file")

    local pct bytes_info state_label
    IFS=$'\t' read -r pct bytes_info state_label <<< "$parsed"

    # Check process state for SIGSTOP pause
    if [ -n "$pid" ] && [ -d "/proc/$pid" ]; then
        local proc_state
        proc_state=$(awk '/^State:/ {print $2}' "/proc/$pid/status" 2>/dev/null || true)
        if [[ "$proc_state" =~ ^[Tt] ]]; then
            state_label="[PAUSED]"
        fi
    fi

    printf "%s\t%s\t%s\n" "$pct" "$bytes_info" "$state_label"
}

# Dedicated Download Telemetry & ACF Preview Handler
preview_download() {
    local appid="${1:-}"
    local engine="${2:-}"
    local ref_path="${3:-}"

    appid=$(strip_ansi "$appid" | tr -d '[:space:]')
    engine=$(strip_ansi "$engine" | tr -d '[:space:]')
    ref_path=$(strip_ansi "$ref_path" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')

    if [ -z "$appid" ] || [ "$appid" = "0" ] || [ -z "$ref_path" ]; then
        printf "%s╭─ DOWNLOAD TELEMETRY MONITOR ────────────────────────╮%s\n" "${UI_BOX}" "${UI_RST}"
        printf "│ %sNo Active Download Selected%s\n" "${UI_DIM}" "${UI_RST}"
        printf "%s╰─────────────────────────────────────────────────────╯%s\n" "${UI_BOX}" "${UI_RST}"
        printf "  %sNo active download telemetry or reference available in queue.%s\n" "${UI_DIM}" "${UI_RST}"
        return 0
    fi

    if [ -d "$ref_path" ]; then
        # Standalone Staging Directory
        local title="Unknown Title" target_dir="Not configured" pid="Unknown" start_time="" log_file="$ref_path/download.log" status="DOWNLOADING"
        if [ -f "$ref_path/status.info" ]; then
            local k v
            while IFS='=' read -r k v || [ -n "$k" ]; do
                case "$k" in
                    TITLE) title="$v" ;;
                    TARGET_DIR) target_dir="$v" ;;
                    PID) pid="$v" ;;
                    START_TIME) start_time="$v" ;;
                    LOG_FILE) [ -n "$v" ] && log_file="$v" ;;
                    STATUS) status="$v" ;;
                esac
            done < "$ref_path/status.info"
        fi

        local pid_status="${UI_RED}[TERMINATED]${UI_RST}"
        if [[ "$pid" =~ ^[0-9]+$ ]] && kill -0 "$pid" 2>/dev/null; then
            local p_stat
            p_stat=$(awk '/^State:/ {print $2}' "/proc/$pid/status" 2>/dev/null || true)
            if [[ "$p_stat" =~ ^[Tt] ]]; then
                pid_status="${UI_PURPLE}[PAUSED (SIGSTOP)]${UI_RST}"
            else
                pid_status="${UI_GREEN}[RUNNING (PID $pid)]${UI_RST}"
            fi
        fi

        local elapsed_str="N/A"
        if [ -n "$start_time" ] && [[ "$start_time" =~ ^[0-9]+$ ]]; then
            local now_ts elapsed
            now_ts=$(date +%s)
            elapsed=$(( now_ts - start_time ))
            if [ "$elapsed" -ge 0 ]; then
                local mins=$(( elapsed / 60 ))
                local secs=$(( elapsed % 60 ))
                elapsed_str="${mins}m ${secs}s"
            fi
        fi

        local prog_data st_pct st_bytes st_state
        prog_data=$(get_depot_dl_progress "$log_file" "$pid")
        IFS=$'\t' read -r st_pct st_bytes st_state <<< "$prog_data"

        printf "%s╭─ STANDALONE CDN DOWNLOAD TELEMETRY ────────────────╮%s\n" "${UI_BOX}" "${UI_RST}"
        printf "│ %s%s%s %s(AppID: %s)%s\n" "${UI_BOLD}" "$title" "${UI_RST}" "${UI_DIM}" "$appid" "${UI_RST}"
        printf "%s╰─────────────────────────────────────────────────────╯%s\n" "${UI_BOX}" "${UI_RST}"
        printf "  %sEngine%s        : %s\n" "${UI_CYAN}" "${UI_RST}" "Native Rust gamectl-depot-dl (Valve CDN)"
        printf "  %sProcess State%s : %s\n" "${UI_CYAN}" "${UI_RST}" "$pid_status"
        printf "  %sProgress%s      : %s%s%s (%s)\n" "${UI_CYAN}" "${UI_RST}" "${UI_BOLD}" "$st_pct" "${UI_RST}" "$st_bytes"
        printf "  %sElapsed Time%s  : %s\n" "${UI_CYAN}" "${UI_RST}" "$elapsed_str"
        printf "  %sTarget Dir%s    : %s\n" "${UI_CYAN}" "${UI_RST}" "$target_dir"
        printf "  %sStaging Dir%s   : %s\n" "${UI_CYAN}" "${UI_RST}" "$ref_path"
        printf "\n"
        printf "%s╭─ RECENT DOWNLOAD LOG (tail -n 12) ──────────────────╮%s\n" "${UI_BOX}" "${UI_RST}"
        if [ -f "$log_file" ]; then
            tail -n 12 "$log_file"
        else
            printf "%s(No log file generated yet)%s\n" "${UI_DIM}" "${UI_RST}"
        fi
        return 0
    fi

    if [ -f "$ref_path" ]; then
        # Steam ACF Manifest
        local state_data
        state_data=$(parse_acf_download_state "$ref_path" 2>/dev/null || true)
        if [ -n "$state_data" ]; then
            local a_id a_name a_status a_pct a_dl a_tot a_flags a_dir a_path
            IFS=$'\t' read -r a_id a_name a_status a_pct a_dl a_tot a_flags a_dir a_path <<< "$state_data"
            local dl_fmt tot_fmt
            dl_fmt=$(format_bytes "$a_dl")
            tot_fmt=$(format_bytes "$a_tot")
            local install_path="$(dirname "$ref_path")/common/$a_dir"

            printf "%s╭─ STEAM CLIENT DOWNLOAD TELEMETRY ───────────────────╮%s\n" "${UI_BOX}" "${UI_RST}"
            printf "│ %s%s%s %s(AppID: %s)%s\n" "${UI_BOLD}" "$a_name" "${UI_RST}" "${UI_DIM}" "$a_id" "${UI_RST}"
            printf "%s╰─────────────────────────────────────────────────────╯%s\n" "${UI_BOX}" "${UI_RST}"
            printf "  %sEngine%s        : %s\n" "${UI_CYAN}" "${UI_RST}" "Steam Client (ACF Manifest Engine)"
            printf "  %sStatus%s        : %s\n" "${UI_CYAN}" "${UI_RST}" "$a_status"
            printf "  %sProgress%s      : %s%s%s (%s / %s)\n" "${UI_CYAN}" "${UI_RST}" "${UI_BOLD}" "$a_pct" "${UI_RST}" "$dl_fmt" "$tot_fmt"
            printf "  %sStateFlags%s    : %s\n" "${UI_CYAN}" "${UI_RST}" "$a_flags"
            printf "  %sInstall Dir%s   : %s\n" "${UI_CYAN}" "${UI_RST}" "$install_path"
            printf "  %sManifest File%s : %s\n" "${UI_CYAN}" "${UI_RST}" "$ref_path"
            printf "\n"
            printf "%s╭─ MANIFEST CONFIGURATION (VDF) ──────────────────────╮%s\n" "${UI_BOX}" "${UI_RST}"
            grep -E '"(appid|name|StateFlags|BytesDownloaded|BytesToDownload|installdir|buildid|LastOwner)"' "$ref_path" 2>/dev/null || true
            return 0
        fi
    fi

    printf "%s╭─ DOWNLOAD TELEMETRY MONITOR ────────────────────────╮%s\n" "${UI_BOX}" "${UI_RST}"
    printf "│ %sReference: %s%s\n" "${UI_DIM}" "$ref_path" "${UI_RST}"
    printf "%s╰─────────────────────────────────────────────────────╯%s\n" "${UI_BOX}" "${UI_RST}"
    printf "  No active download telemetry or reference available for this target.\n"
}

# Interactive Download Monitor TUI
list_downloads_interactive() {
    if [ ! -t 0 ] || [ ! -t 1 ]; then
        echo "[ERROR] Interactive download monitor requires a terminal (TTY)." >&2
        return 1
    fi
    if ! command -v fzf >/dev/null 2>&1; then
        echo "[ERROR] fzf is required for interactive mode but was not found in PATH." >&2
        return 127
    fi

    local run_dir
    run_dir="$(get_runtime_dir)"
    while true; do
        local entries=""
        local total_items=0

        # Scan Steam ACF entries
        local steam_apps
        steam_apps="$(get_steam_primary_apps 2>/dev/null || echo "$HOME/.local/share/Steam/steamapps")"
        shopt -s nullglob
        local acf_files=("$steam_apps"/appmanifest_*.acf)
        shopt -u nullglob

        for acf in "${acf_files[@]}"; do
            local state_data
            state_data=$(parse_acf_download_state "$acf" 2>/dev/null || true)
            [ -z "$state_data" ] && continue

            local a_id a_title a_status a_pct a_dl a_total a_flags a_dir a_path
            IFS=$'\t' read -r a_id a_title a_status a_pct a_dl a_total a_flags a_dir a_path <<< "$state_data"

            if [ "$a_status" = "[DOWNLOADING]" ] || [ "$a_status" = "[PAUSED]" ] || [ "$a_status" = "[UPDATE REQUIRED]" ] || [ "$a_status" = "[INSTALLED]" ]; then
                local ui_status="${UI_ICE}${a_status}${UI_RST}"
                [ "$a_status" = "[DOWNLOADING]" ] && ui_status="${UI_GREEN}[DOWNLOADING ${a_pct}]${UI_RST}"
                [ "$a_status" = "[PAUSED]" ] && ui_status="${UI_PURPLE}[PAUSED ${a_pct}]${UI_RST}"
                [ "$a_status" = "[INSTALLED]" ] && ui_status="${UI_CYAN}[INSTALLED]${UI_RST}"

                local dl_fmt tot_fmt
                dl_fmt=$(format_bytes "$a_dl")
                tot_fmt=$(format_bytes "$a_total")
                local detail="${a_title} (${dl_fmt}/${tot_fmt})"
                validate_tui_fields "$a_id" "$detail" "$a_path" || continue
                entries+="${a_id}"$'\t'"Steam"$'\t'"${ui_status}"$'\t'"${a_pct}"$'\t'"${detail}"$'\t'"${a_path}"$'\n'
                total_items=$((total_items + 1))
            fi
        done

        shopt -s nullglob
        for st_dir in "$run_dir"/depot_dl_*; do
            [ -d "$st_dir" ] || continue
            local base_st="${st_dir##*/}"
            local st_pid="${base_st##*_}"
            local rest_st="${base_st#depot_dl_}"
            local st_appid="${rest_st%_*}"
            [ -z "$st_appid" ] || [ -z "$st_pid" ] && continue

            # Self-healing: purge orphaned staging dir if downloader process is dead
            if ! [[ "$st_pid" =~ ^[0-9]+$ ]] || ! kill -0 "$st_pid" 2>/dev/null; then
                rm -rf "$st_dir" 2>/dev/null || true
                continue
            fi

            local st_info="$st_dir/status.info"
            local st_title="Native CDN Download"
            local st_log="$st_dir/download.log"
            if [ -f "$st_info" ]; then
                local info_title info_log
                info_title=$(grep -E '^TITLE=' "$st_info" | cut -d= -f2- || true)
                info_log=$(grep -E '^LOG_FILE=' "$st_info" | cut -d= -f2- || true)
                [ -n "$info_title" ] && st_title="$info_title"
                [ -n "$info_log" ] && [ -f "$info_log" ] && st_log="$info_log"
            fi

            local prog_data st_pct st_bytes st_state
            prog_data=$(get_depot_dl_progress "$st_log" "$st_pid")
            IFS=$'\t' read -r st_pct st_bytes st_state <<< "$prog_data"

            local st_ui="${UI_GREEN}[DOWNLOADING ${st_pct}]${UI_RST}"
            if [ "$st_state" = "[PAUSED]" ]; then
                st_ui="${UI_PURPLE}[PAUSED ${st_pct}]${UI_RST}"
            elif [ "$st_state" = "[COMPLETED]" ]; then
                st_ui="${UI_CYAN}[COMPLETED]${UI_RST}"
            elif [ "$st_state" = "[FAILED]" ]; then
                st_ui="${UI_RED}[FAILED]${UI_RST}"
            elif [ "$st_state" = "[STARTING]" ]; then
                st_ui="${UI_ICE}[STARTING]${UI_RST}"
            fi

            local st_detail="${st_title} (${st_bytes}, PID: ${st_pid})"
            validate_tui_fields "$st_appid" "$st_detail" "$st_dir" || continue
            entries+="${st_appid}"$'\t'"Standalone"$'\t'"${st_ui}"$'\t'"${st_pct}"$'\t'"${st_detail}"$'\t'"${st_dir}"$'\n'
            total_items=$((total_items + 1))
        done
        shopt -u nullglob

        if [ "$total_items" -eq 0 ]; then
            entries+="0"$'\t'"Info"$'\t'"${UI_DIM}[NO ACTIVE DOWNLOADS]${UI_RST}"$'\t'"0%"$'\t'"No active downloads found in Steam or Standalone engine. Press Esc to return."$'\t\n'
        fi

        flush_tty_input
        local fzf_out fzf_rc=0
        export GAMECTL_PREVIEW_BIN="$SELF_BIN"
        fzf_out=$(printf "%s" "$entries" | fzf \
            --delimiter=$'\t' \
            --with-nth=1,2,3,5 \
            --expect=ctrl-k \
            --border-label="  ╢ gamectl :: Download Manager ╟  " \
            --border-label-pos=2 \
            --header="Enter: Actions │ Ctrl-K: Pause │ Esc: Back" \
            --prompt="Downloads > " \
            --preview='"$GAMECTL_PREVIEW_BIN" --preview-download {1} {2} {6}' \
            --preview-window=right:60%:border-rounded:wrap \
        ) || fzf_rc=$?

        [ "$fzf_rc" -eq 130 ] && break
        if [ "$fzf_rc" -ne 0 ] && [ "$fzf_rc" -ne 1 ]; then
            echo "[ERROR] Download monitor failed (fzf exit code $fzf_rc)." >&2
            return "$fzf_rc"
        fi
        [ -z "$fzf_out" ] && continue

        local trigger_key selection
        trigger_key=$(echo "$fzf_out" | head -n 1)
        selection=$(echo "$fzf_out" | sed -n '2p')

        [ -z "$selection" ] && continue

        local sel_appid sel_engine sel_status sel_pct sel_title sel_ref
        sel_appid=$(echo "$selection" | awk -F'\t' '{print $1}')
        sel_engine=$(echo "$selection" | awk -F'\t' '{print $2}')
        sel_status=$(echo "$selection" | awk -F'\t' '{print $3}')
        sel_pct=$(echo "$selection" | awk -F'\t' '{print $4}')
        sel_title=$(echo "$selection" | awk -F'\t' '{print $5}')
        sel_ref=$(echo "$selection" | awk -F'\t' '{print $6}')

        [ "$sel_appid" = "0" ] && break

        if [ "$trigger_key" = "ctrl-k" ]; then
            if [ "$sel_engine" = "Standalone" ]; then
                local t_pid="${sel_ref##*_}"
                if [[ "$t_pid" =~ ^[0-9]+$ ]] && kill -0 "$t_pid" 2>/dev/null; then
                    kill -STOP "$t_pid" 2>/dev/null || true
                    log_msg "INFO" "DOWNLOAD" "Paused standalone download PID $t_pid (AppID: $sel_appid) via SIGSTOP"
                    tui_modal_notice "Standalone Download Paused" "Dispatched SIGSTOP to process PID: $t_pid (AppID: $sel_appid).\nUse Action Menu to resume or terminate." || return $?
                else
                    tui_modal_notice "Pause Standalone" "Downloader process (PID: $t_pid) is no longer active." || return $?
                fi
            elif command -v steam >/dev/null 2>&1; then
                steam "steam://pause/$sel_appid" >/dev/null 2>&1 &
                log_msg "INFO" "DOWNLOAD" "Paused download for AppID $sel_appid"
                tui_modal_notice "Download Paused" "Dispatched pause signal to Steam Client for AppID: $sel_appid" || return $?
            else
                tui_modal_notice "Pause Unsupported" "Steam client CLI is not available in PATH." || return $?
            fi
            continue
        fi

        local action_entries
        if [ "$sel_engine" = "Standalone" ]; then
            local t_pid="${sel_ref##*_}"
            action_entries=$(cat <<EOF
1	Pause Standalone Download (SIGSTOP)	Suspend process PID $t_pid
2	Resume Standalone Download (SIGCONT)	Continue process PID $t_pid
3	Terminate Standalone Download (SIGTERM)	Kill process PID $t_pid
4	Inject Standalone GBE Fork LAN Runtime	Deploy Goldberg emulator
5	Return to Download List	Back
EOF
)
        else
            action_entries=$(cat <<EOF
1	Pause Steam Client Download	steam://pause/$sel_appid
2	Resume Steam Client Download	steam://resume/$sel_appid
3	Inject Standalone GBE Fork LAN Runtime	Deploy Goldberg emulator
4	Return to Download List	Back
EOF
)
        fi
        flush_tty_input
        local act_sel act_rc=0
        act_sel=$(echo "$action_entries" | fzf \
            --delimiter=$'\t' \
            --with-nth=2,3 \
            --border-label="  ╢ Actions: AppID $sel_appid ($sel_engine) ╟  " \
            --border-label-pos=2 \
            --header="DOWNLOAD ACTIONS (Enter: Execute │ Esc: Return)" \
            --prompt="Action > " \
            --reverse 2>/dev/null) || act_rc=$?

        check_fzf_status "$act_rc" || return $?
        [ "$act_rc" -eq 130 ] && continue
        [ -z "$act_sel" ] && continue

        local dl_opt
        dl_opt=$(echo "$act_sel" | cut -f1 | tr -d '[:space:]')

        case "$dl_opt" in
            1)
                if [ "$sel_engine" = "Standalone" ]; then
                    local t_pid="${sel_ref##*_}"
                    if [[ "$t_pid" =~ ^[0-9]+$ ]] && kill -0 "$t_pid" 2>/dev/null; then
                        kill -STOP "$t_pid" 2>/dev/null || true
                        log_msg "INFO" "DOWNLOAD" "Paused standalone download PID $t_pid (AppID: $sel_appid) via SIGSTOP"
                        tui_modal_notice "Download Paused" "Sent SIGSTOP to standalone downloader PID $t_pid." || return $?
                    fi
                elif command -v steam >/dev/null 2>&1; then
                    steam "steam://pause/$sel_appid" >/dev/null 2>&1 &
                    log_msg "INFO" "DOWNLOAD" "Paused download for AppID $sel_appid"
                fi
                ;;
            2)
                if [ "$sel_engine" = "Standalone" ]; then
                    local t_pid="${sel_ref##*_}"
                    if [[ "$t_pid" =~ ^[0-9]+$ ]] && kill -0 "$t_pid" 2>/dev/null; then
                        kill -CONT "$t_pid" 2>/dev/null || true
                        log_msg "INFO" "DOWNLOAD" "Resumed standalone download PID $t_pid (AppID: $sel_appid) via SIGCONT"
                        tui_modal_notice "Download Resumed" "Sent SIGCONT to standalone downloader PID $t_pid." || return $?
                    fi
                elif command -v steam >/dev/null 2>&1; then
                    steam "steam://resume/$sel_appid" >/dev/null 2>&1 &
                    log_msg "INFO" "DOWNLOAD" "Resumed download for AppID $sel_appid"
                fi
                ;;
            3)
                if [ "$sel_engine" = "Standalone" ]; then
                    local t_pid="${sel_ref##*_}"
                    if [[ "$t_pid" =~ ^[0-9]+$ ]] && kill -0 "$t_pid" 2>/dev/null; then
                        kill -TERM "$t_pid" 2>/dev/null || true
                        rm -rf "$sel_ref" 2>/dev/null || true
                        log_msg "WARN" "DOWNLOAD" "Terminated standalone download PID $t_pid (AppID: $sel_appid) via SIGTERM"
                        tui_modal_notice "Download Terminated" "Sent SIGTERM to standalone downloader PID $t_pid and purged staging." || return $?
                    fi
                else
                    local g_dir=""
                    if [ -f "$sel_ref" ]; then
                        local i_dir
                        i_dir=$(grep -m1 '"installdir"' "$sel_ref" 2>/dev/null | awk -F'"' '{print $4}')
                        if [ -n "$i_dir" ]; then
                            g_dir="$(dirname "$sel_ref")/common/$i_dir"
                        fi
                    fi
                    if [ -n "$g_dir" ] && [ -d "$g_dir" ]; then
                        log_msg "INFO" "DOWNLOAD" "Injecting GBE Fork LAN runtime into: $g_dir"
                        "$SELF_BIN" inject "$g_dir" "$sel_appid"
                        tui_modal_notice "GBE Runtime Injected" "Goldberg emulator LAN runtime successfully injected into:\n$g_dir" || return $?
                    else
                        tui_modal_notice "Target Not Found" "Steam common game directory not found:\n$g_dir" || return $?
                    fi
                fi
                ;;
            4)
                if [ "$sel_engine" = "Standalone" ]; then
                    local g_dir=""
                    if [ -f "$sel_ref/status.info" ]; then
                        g_dir=$(grep -E '^TARGET_DIR=' "$sel_ref/status.info" | cut -d= -f2-)
                    fi
                    if [ -z "$g_dir" ] || [ ! -d "$g_dir" ]; then
                        local st_title=""
                        [ -f "$sel_ref/status.info" ] && st_title=$(grep -E '^TITLE=' "$sel_ref/status.info" | cut -d= -f2-)
                        if [ -n "$st_title" ]; then
                            g_dir="$(resolve_standalone_library_dir "$st_title")"
                        fi
                    fi
                    if [ -n "$g_dir" ] && [ -d "$g_dir" ]; then
                        log_msg "INFO" "DOWNLOAD" "Injecting GBE Fork LAN runtime into target dir: $g_dir"
                        "$SELF_BIN" inject "$g_dir" "$sel_appid"
                        tui_modal_notice "GBE Runtime Injected" "Goldberg emulator LAN runtime successfully injected into:\n$g_dir" || return $?
                    else
                        tui_modal_notice "Target Not Found" "Target installation directory not found or not yet created:\n$g_dir" || return $?
                    fi
                else
                    continue
                fi
                ;;
            *)
                continue
                ;;
        esac
    done
}
# Standalone-source compatibility: load split steam submodules when sourced directly outside bin/gamectl
if [ -z "${GAMECTL_BUNDLED:-}" ] && [ -n "${BASH_SOURCE[0]:-}" ]; then
    _steam_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd)"
    for _steam_sub in 31_manifests.sh 32_steam_bridge.sh; do
        if [ -f "$_steam_dir/$_steam_sub" ]; then
            # shellcheck source=/dev/null
            source "$_steam_dir/$_steam_sub"
        fi
    done
    unset _steam_dir _steam_sub
fi

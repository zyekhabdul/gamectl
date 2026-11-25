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
        if [ "$sig" = "7f454c46" ] || [[ "$sig" == 2321* ]]; then
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
        if declare -F preflight_manifest_source >/dev/null 2>&1; then
            preflight_manifest_source "$appid" "$source" true || return 1
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

# Standalone-source compatibility: load split steam submodules when sourced directly outside bin/gamectl
if [ -z "${GAMECTL_BUNDLED:-}" ] && [ -n "${BASH_SOURCE[0]:-}" ]; then
    _steam_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd)"
    for _steam_sub in 31_manifests.sh 32_steam_bridge.sh 33_download_telemetry.sh 34_download_monitor.sh; do
        if [ -f "$_steam_dir/$_steam_sub" ]; then
            # shellcheck source=/dev/null
            source "$_steam_dir/$_steam_sub"
        fi
    done
    unset _steam_dir _steam_sub
fi

# Detect P2P multiplayer compatibility hooks, mod loaders, and custom DLL overrides for a game directory
detect_dll_overrides() {
    local gdir="${1:-}"
    [ -n "$gdir" ] && [ -d "$gdir" ] || return 0

    local has_onlinefix=0
    local has_bepinex=0
    local has_ue4ss=0
    local has_reframework=0
    local has_reshade=0
    local custom_overrides=""

    # 1. Check custom declarative .dll_overrides file
    if [ -f "$gdir/.dll_overrides" ]; then
        custom_overrides=$(grep -v -E '^[[:space:]]*(#|$)' "$gdir/.dll_overrides" 2>/dev/null | tr '\n' ';' || true)
    fi

    # 2. Scan root and subdirectories (up to depth 3) excluding runtime/save folders
    local found_signatures
    found_signatures=$(find "$gdir" -maxdepth 3 \( \
        -name "pfx" -o -name ".git" -o -name ".save_snapshots" -o -name "saves" \
    \) -prune -o \( \
        -iname "OnlineFix64.dll" -o -iname "OnlineFix.dll" -o -iname "dnet.dll" -o \
        -iname "SteamOverlay64.dll" -o -iname "winmm.dll" -o -iname "version.dll" -o \
        -iname "BepInEx" -o -iname "doorstop_config.ini" -o -iname "winhttp.dll" -o \
        -iname "ue4ss" -o -iname "UE4SS.dll" -o -iname "dwmapi.dll" -o \
        -iname "dinput8.dll" -o \
        -iname "ReShade.ini" -o -iname "dxgi.dll" \
    \) -print 2>/dev/null || true)

    if [ -n "$found_signatures" ]; then
        while IFS= read -r item; do
            [ -z "$item" ] && continue
            local base
            base=$(basename "$item")
            case "${base,,}" in
                onlinefix64.dll|onlinefix.dll|dnet.dll|steamoverlay64.dll|winmm.dll|version.dll)
                    has_onlinefix=1 ;;
                bepinex|doorstop_config.ini|winhttp.dll)
                    has_bepinex=1 ;;
                ue4ss|ue4ss.dll|dwmapi.dll)
                    has_ue4ss=1 ;;
                dinput8.dll)
                    has_reframework=1 ;;
                reshade.ini|dxgi.dll)
                    has_reshade=1 ;;
            esac
        done <<< "$found_signatures"
    fi

    # Return empty string if no mod/OnlineFix signatures or custom overrides found
    if [ "$has_onlinefix" -eq 0 ] && [ "$has_bepinex" -eq 0 ] && \
       [ "$has_ue4ss" -eq 0 ] && [ "$has_reframework" -eq 0 ] && \
       [ "$has_reshade" -eq 0 ] && [ -z "$custom_overrides" ]; then
        return 0
    fi

    local detected_tokens=""
    if [ "$has_onlinefix" -eq 1 ]; then
        detected_tokens="${detected_tokens:+${detected_tokens};}onlinefix=n;onlinefix64=n;steamoverlay64=n;dnet=n;winmm=n,b;version=n,b;steam_api64=n;steam_api=n"
    fi
    if [ "$has_bepinex" -eq 1 ]; then
        detected_tokens="${detected_tokens:+${detected_tokens};}winhttp=n,b"
    fi
    if [ "$has_ue4ss" -eq 1 ]; then
        detected_tokens="${detected_tokens:+${detected_tokens};}dwmapi=n,b"
    fi
    if [ "$has_reframework" -eq 1 ]; then
        detected_tokens="${detected_tokens:+${detected_tokens};}dinput8=n,b"
    fi
    if [ "$has_reshade" -eq 1 ]; then
        detected_tokens="${detected_tokens:+${detected_tokens};}dxgi=n,b"
    fi
    if [ -n "$custom_overrides" ]; then
        detected_tokens="${detected_tokens:+${detected_tokens};}${custom_overrides}"
    fi

    local user_env_overrides="${2:-${WINEDLLOVERRIDES:-}}"
    declare -A seen=()
    declare -A values=()
    local ordered_keys=()

    # 1. Process user environment overrides first to preserve user precedence
    if [ -n "$user_env_overrides" ]; then
        local u_arr=()
        IFS=';' read -r -a u_arr <<< "$user_env_overrides"
        for item in "${u_arr[@]}"; do
            [ -z "$item" ] && continue
            local k="${item%%=*}"
            local v="${item#*=}"
            [ "$item" = "$k" ] && v="n"
            k=$(echo "$k" | tr -d '[:space:]' | tr '[:upper:]' '[:lower:]')
            v=$(echo "$v" | tr -d '[:space:]')
            [ -z "$k" ] && continue
            if [ -z "${seen["$k"]:-}" ]; then
                seen["$k"]=1
                ordered_keys+=("$k")
                values["$k"]="$v"
            fi
        done
    fi

    # 2. Process detected mod tokens (add only if not overridden by user)
    local d_arr=()
    IFS=';' read -r -a d_arr <<< "$detected_tokens"
    for item in "${d_arr[@]}"; do
        [ -z "$item" ] && continue
        local k="${item%%=*}"
        local v="${item#*=}"
        [ "$item" = "$k" ] && v="n"
        k=$(echo "$k" | tr -d '[:space:]' | tr '[:upper:]' '[:lower:]')
        v=$(echo "$v" | tr -d '[:space:]')
        [ -z "$k" ] && continue
        if [ -z "${seen["$k"]:-}" ]; then
            seen["$k"]=1
            ordered_keys+=("$k")
            values["$k"]="$v"
        fi
    done

    # 3. Format normalized semicolon-separated output
    local result=""
    for k in "${ordered_keys[@]}"; do
        local entry="${k}=${values["$k"]}"
        result="${result:+${result};}${entry}"
    done
    echo "$result"
}

# Canonical ordered list of standalone XDG and Steam runner parent directories
list_runner_dirs() {
    local s_dyn_root
    s_dyn_root="$(get_steam_root 2>/dev/null || true)"
    local xdg_runners="${XDG_DATA_HOME:-$HOME/.local/share}/gamectl/runners"
    local -a raw_dirs=()
    [ -n "${GAMECTL_RUNNER_DIR:-}" ] && raw_dirs+=("$GAMECTL_RUNNER_DIR")
    raw_dirs+=("$xdg_runners")
    [ -n "$s_dyn_root" ] && raw_dirs+=("$s_dyn_root/compatibilitytools.d")
    raw_dirs+=(
        "$HOME/.local/share/Steam/compatibilitytools.d"
        "$HOME/.steam/root/compatibilitytools.d"
        "$HOME/.var/app/com.valvesoftware.Steam/.local/share/Steam/compatibilitytools.d"
    )
    local d
    declare -A seen=()
    for d in "${raw_dirs[@]}"; do
        [ -n "$d" ] || continue
        if [ -z "${seen["$d"]:-}" ]; then
            seen["$d"]=1
            printf '%s\n' "$d"
        fi
    done
}

# Discover runner for Windows games (priority: umu-run -> GE-Proton / Proton Steam -> wine)
find_runner() {
    local target_dir="${1:-}"

    # Priority 0: Per-game runner override or environment override
    if [ -n "$target_dir" ] && [ -f "$target_dir/.runner" ]; then
        local g_runner
        g_runner=$(head -n 1 "$target_dir/.runner" | tr -d '[:space:]')
        if [ -n "$g_runner" ] && { [ -x "$g_runner" ] || command -v "$g_runner" >/dev/null 2>&1; }; then
            echo "$g_runner"
            return 0
        fi
    fi
    if [ -n "${GAMECTL_RUNNER:-}" ]; then
        if [ -x "$GAMECTL_RUNNER" ] || command -v "$GAMECTL_RUNNER" >/dev/null 2>&1; then
            echo "$GAMECTL_RUNNER"
            return 0
        fi
    fi
    if [ -f "$HOME/.config/gamectl/runner" ]; then
        local user_runner
        user_runner=$(head -n 1 "$HOME/.config/gamectl/runner" | tr -d '[:space:]')
        if [ -n "$user_runner" ] && { [ -x "$user_runner" ] || command -v "$user_runner" >/dev/null 2>&1; }; then
            echo "$user_runner"
            return 0
        fi
    fi

    # Priority 1: umu-run
    if command -v umu-run >/dev/null 2>&1; then
        echo "umu-run"
        return 0
    fi

    # Priority 2: Standalone XDG runners & Steam compatibilitytools.d
    local -a compat_dirs=()
    local cdir
    while IFS= read -r cdir; do
        [ -n "$cdir" ] && compat_dirs+=("$cdir")
    done < <(list_runner_dirs)
    for cdir in "${compat_dirs[@]}"; do
        [ -d "$cdir" ] || continue
        local p
        while read -r p; do
            [ -z "$p" ] && continue
            if [ -x "$p/proton" ]; then
                echo "$p/proton"
                return 0
            fi
        done < <(find "$cdir" -mindepth 1 -maxdepth 1 -type d -iname "*proton*" 2>/dev/null | sort -Vr)
    done

    # Check Proton in Steam common libraries
    local steam_lib
    while read -r steam_lib; do
        [ -d "$steam_lib/common" ] || continue
        local p
        while read -r p; do
            [ -z "$p" ] && continue
            if [ -x "$p/proton" ]; then
                echo "$p/proton"
                return 0
            fi
        done < <(find "$steam_lib/common" -mindepth 1 -maxdepth 1 -type d -name "Proton*" 2>/dev/null | sort -Vr)
    done < <(get_steam_libraries 2>/dev/null || true)

    # Priority 3: System Wine
    if command -v wine64 >/dev/null 2>&1; then
        echo "wine64"
        return 0
    elif command -v wine >/dev/null 2>&1; then
        echo "wine"
        return 0
    fi

    # Priority 4: Internal wine binary inside GE-Proton files/bin
    for cdir in "${compat_dirs[@]}"; do
        [ -d "$cdir" ] || continue
        local w
        w=$(find "$cdir" -type f \( -name "wine64" -o -name "wine" \) 2>/dev/null | head -n 1)
        if [ -n "$w" ] && [ -x "$w" ]; then
            echo "$w"
            return 0
        fi
    done

    return 1
}

# Resolve wineserver binary matching active runner or system/Proton installation
get_wineserver_bin() {
    local runner="${1:-}"

    # 1. If runner points directly to a Proton executable or runner string contains proton
    if [ -n "$runner" ]; then
        if [[ "$runner" =~ proton ]] || [ -f "$runner" ]; then
            local p_base
            p_base="$(dirname "$runner")"
            for sub in "files/bin/wineserver" "dist/bin/wineserver" "bin/wineserver"; do
                if [ -x "$p_base/$sub" ]; then
                    echo "$p_base/$sub"
                    return 0
                fi
            done
        fi
    fi

    # 2. Check system PATH for wineserver
    if command -v wineserver >/dev/null 2>&1; then
        command -v wineserver
        return 0
    fi

    # 3. Fallback: Search standalone XDG & Steam compatibility tools for highest GE-Proton wineserver
    local -a compat_dirs=()
    local cdir
    while IFS= read -r cdir; do
        [ -n "$cdir" ] && compat_dirs+=("$cdir")
    done < <(list_runner_dirs)
    for cdir in "${compat_dirs[@]}"; do
        [ -n "$cdir" ] && [ -d "$cdir" ] || continue
        local p
        while read -r p; do
            [ -z "$p" ] && continue
            for sub in "files/bin/wineserver" "dist/bin/wineserver" "bin/wineserver"; do
                if [ -x "$p/$sub" ]; then
                    echo "$p/$sub"
                    return 0
                fi
            done
        done < <(find "$cdir" -mindepth 1 -maxdepth 1 -type d -iname "*proton*" 2>/dev/null | sort -Vr)
    done

    # 4. Check system wine64 / wine adjacent wineserver
    for w in "$(command -v wine64 2>/dev/null || true)" "$(command -v wine 2>/dev/null || true)"; do
        [ -n "$w" ] || continue
        local w_dir
        w_dir="$(dirname "$w")"
        if [ -x "$w_dir/wineserver" ]; then
            echo "$w_dir/wineserver"
            return 0
        fi
    done

    return 1
}

# Resolve active runner compatibility tools directory (standalone XDG fallback when Steam is absent)
get_compat_dir() {
    if [ -n "${GAMECTL_RUNNER_DIR:-}" ]; then
        echo "$GAMECTL_RUNNER_DIR"
        return 0
    fi
    local s_dyn_root
    s_dyn_root="$(get_steam_root 2>/dev/null || true)"
    if [ -n "$s_dyn_root" ] && [ -d "$s_dyn_root" ]; then
        echo "$s_dyn_root/compatibilitytools.d"
    elif [ -d "$HOME/.steam/root" ]; then
        echo "$HOME/.steam/root/compatibilitytools.d"
    else
        echo "${XDG_DATA_HOME:-$HOME/.local/share}/gamectl/runners"
    fi
}

# List local and latest upstream GE-Proton releases
proton_list() {
    local -a compat_dirs=()
    local cdir
    while IFS= read -r cdir; do
        [ -n "$cdir" ] && compat_dirs+=("$cdir")
    done < <(list_runner_dirs)

    declare -A local_installs=()
    for cdir in "${compat_dirs[@]}"; do
        [ -n "$cdir" ] && [ -d "$cdir" ] || continue
        for d in "$cdir"/*; do
            [ -d "$d" ] || continue
            local t_name
            t_name=$(basename "$d")
            [ -z "${local_installs["$t_name"]:-}" ] && local_installs["$t_name"]="$d"
        done
    done

    echo "${UI_BOX}╭─ GE-PROTON RELEASE MANAGER (HEADLESS) ───────────────────────╮${UI_RST}"
    echo "│ ${UI_CYAN}Target Path${UI_RST}: $(get_compat_dir)"
    echo "│ ${UI_CYAN}Installed  ${UI_RST}: ${#local_installs[@]} version(s) detected locally"
    echo "${UI_BOX}╰─────────────────────────────────────────────────────────────╯${UI_RST}"

    # 1. Show local versions
    echo
    echo "  ${UI_PURPLE}[LOCAL VERSIONS]${UI_RST}"
    if [ ${#local_installs[@]} -gt 0 ]; then
        for v in "${!local_installs[@]}"; do
            local v_path="${local_installs["$v"]}"
            local v_sz
            v_sz=$(du -sh "$v_path" 2>/dev/null | awk '{print $1}')
            echo "    • ${UI_BOLD}$(printf '%-22s' "$v")${UI_RST} : ${UI_GREEN}[INSTALLED]${UI_RST} ${UI_DIM}(Size: $v_sz | $v_path)${UI_RST}"
        done
    else
        echo "    ${UI_DIM}(No GE-Proton versions installed in gamectl/runners/ or compatibilitytools.d/)${UI_RST}"
    fi

    # 2. Query GitHub Releases upstream
    echo
    echo "  ${UI_PURPLE}[UPSTREAM RELEASES (GitHub: GloriousEggroll/proton-ge-custom)]${UI_RST}"
    local arch_pat="x86_64\\.tar\\.gz$"
    case "$(uname -m 2>/dev/null || echo "x86_64")" in
        aarch64|arm64) arch_pat="aarch64\\.tar\\.gz$" ;;
        *) arch_pat="x86_64\\.tar\\.gz$" ;;
    esac

    local raw_json=""
    raw_json=$(curl -s --connect-timeout 5 --max-time 10 "https://api.github.com/repos/GloriousEggroll/proton-ge-custom/releases?per_page=5" 2>/dev/null || echo "")

    local parsed_releases=""
    if [ -n "$raw_json" ] && echo "$raw_json" | jq -e 'if type=="array" then true else false end' >/dev/null 2>&1; then
        parsed_releases=$(echo "$raw_json" | jq -r --arg pat "$arch_pat" '
            .[] | {
                tag: .tag_name,
                asset: ([.assets[] | select(.name | test($pat))] | first)
            } | select(.asset != null) | [
                .tag,
                .asset.name,
                ((.asset.size // 0) / 1048576 | floor | tostring + " MB"),
                .asset.browser_download_url
            ] | @tsv
        ' 2>/dev/null || true)
    fi

    if [ -n "$parsed_releases" ]; then
        local idx=0
        while IFS=$'\t' read -r r_tag r_asset r_size r_url; do
            [ -z "$r_tag" ] && continue
            idx=$((idx + 1))
            local status_badge="${UI_CYAN}[AVAILABLE]${UI_RST}"
            [ -n "${local_installs["$r_tag"]:-}" ] && status_badge="${UI_GREEN}[INSTALLED]${UI_RST}"
            [ "$idx" -eq 1 ] && status_badge="${status_badge} ${UI_AMBER}(Latest)${UI_RST}"
            echo "    • ${UI_BOLD}$(printf '%-22s' "$r_tag")${UI_RST} : $status_badge ${UI_DIM}(Download Size: $r_size)${UI_RST}"
        done <<< "$parsed_releases"
        echo
        echo "  ${UI_DIM}Install command: gamectl proton-install [tag|latest]${UI_RST}"
    else
        echo "    ${UI_AMBER}[WARN]${UI_RST} ${UI_DIM}Unable to fetch upstream release list (Offline or GitHub API rate-limited).${UI_RST}"
        echo "    ${UI_DIM}You can still install directly via: gamectl proton-install <tag_name>${UI_RST}"
    fi
    echo
}

# Headless GE-Proton installer
proton_install() {
    local target_tag="${1:-latest}"
    local auto_yes=false
    shift || true
    while [ $# -gt 0 ]; do
        case "$1" in
            -y|--yes) auto_yes=true; shift ;;
            *) shift ;;
        esac
    done

    local compat_dir
    compat_dir="$(get_compat_dir)"
    mkdir -p "$compat_dir"

    local arch_suffix="x86_64"
    case "$(uname -m 2>/dev/null || echo "x86_64")" in
        aarch64|arm64) arch_suffix="aarch64" ;;
        *) arch_suffix="x86_64" ;;
    esac

    echo "[INFO] Preparing GE-Proton installation ($target_tag) for architecture $arch_suffix..."

    local resolved_tag=""
    local download_url=""
    local sha512_url=""
    local release_json=""

    if [ "$target_tag" = "latest" ]; then
        release_json=$(curl -s --connect-timeout 5 --max-time 10 "https://api.github.com/repos/GloriousEggroll/proton-ge-custom/releases/latest" 2>/dev/null || echo "")
        if [ -n "$release_json" ] && echo "$release_json" | jq -e '.tag_name' >/dev/null 2>&1; then
            resolved_tag=$(echo "$release_json" | jq -r '.tag_name')
            local pat="${arch_suffix}\\.tar\\.gz$"
            download_url=$(echo "$release_json" | jq -r --arg pat "$pat" '
                [.assets[] | select(.name | test($pat))] | first | .browser_download_url
            ' 2>/dev/null || echo "")
        fi
        if [ -z "$resolved_tag" ] || [ -z "$download_url" ] || [ "$download_url" = "null" ]; then
            echo "[ERROR] Failed to obtain latest release URL from GitHub API." >&2
            echo "        Specify target tag explicitly: gamectl proton-install <tag_name>" >&2
            return 1
        fi
    else
        resolved_tag="$target_tag"
        release_json=$(curl -s --connect-timeout 5 --max-time 10 "https://api.github.com/repos/GloriousEggroll/proton-ge-custom/releases/tags/${resolved_tag}" 2>/dev/null || echo "")
        if [ -n "$release_json" ] && echo "$release_json" | jq -e '.tag_name' >/dev/null 2>&1; then
            local pat="${arch_suffix}\\.tar\\.gz$"
            download_url=$(echo "$release_json" | jq -r --arg pat "$pat" '
                [.assets[] | select(.name | test($pat))] | first | .browser_download_url
            ' 2>/dev/null || echo "")
        fi
        if [ -z "$download_url" ] || [ "$download_url" = "null" ]; then
            # Direct asset fallback pattern
            download_url="https://github.com/GloriousEggroll/proton-ge-custom/releases/download/${resolved_tag}/${resolved_tag}-${arch_suffix}.tar.gz"
        fi
    fi

    local tarball_name
    tarball_name=$(basename "${download_url%%\?*}")
    [ -z "$tarball_name" ] && tarball_name="${resolved_tag}-${arch_suffix}.tar.gz"

    if [ -n "$release_json" ] && echo "$release_json" | jq -e '.assets' >/dev/null 2>&1; then
        local exact_sum1="${tarball_name%.tar.gz}.sha512sum"
        local exact_sum2="${tarball_name}.sha512sum"
        local arch_sum_pat="${arch_suffix}.*\\.sha512sum$"
        sha512_url=$(echo "$release_json" | jq -r --arg e1 "$exact_sum1" --arg e2 "$exact_sum2" --arg ap "$arch_sum_pat" '
            ([.assets[] | select(.name == $e1 or .name == $e2)] | first | .browser_download_url) //
            ([.assets[] | select(.name | test($ap))] | first | .browser_download_url) //
            (
                [.assets[] | select(.name | test("\\.sha512sum$"))] as $all |
                if ($all | length) == 1 then ($all[0].browser_download_url) else "" end
            ) // ""
        ' 2>/dev/null || echo "")
    fi

    echo "[INFO] Target version : $resolved_tag"
    echo "[INFO] Download URL   : $download_url"
    echo "[INFO] Target Dir     : $compat_dir/"

    if [ -d "$compat_dir/$resolved_tag" ] && [ "$auto_yes" = false ]; then
        if [ -t 0 ]; then
            echo -n "[WARN] Directory $resolved_tag already exists. Overwrite installation? [y/N]: "
            local confirm=""
            read -t 10 -r confirm || confirm="n"
            if [[ ! "$confirm" =~ ^[yY] ]]; then
                echo "[INFO] Installation canceled."
                return 0
            fi
        fi
    fi

    (
        local stage_dir=""
        stage_dir=$(mktemp -d "$compat_dir/.proton_stage.XXXXXX") || exit 1
        trap 'rm -rf "$stage_dir"' EXIT INT TERM

        local staged_tar="$stage_dir/$tarball_name"
        echo "[INFO] Downloading release tarball to staging directory..."
        if ! curl -# -fL --connect-timeout 15 -o "$staged_tar" "$download_url" || [ ! -s "$staged_tar" ]; then
            echo "[ERROR] Failed to download $resolved_tag from $download_url" >&2
            exit 1
        fi

        if [ -n "$sha512_url" ] && [ "$sha512_url" != "null" ]; then
            echo "[INFO] Verifying SHA-512 checksum..."
            local sum_file="$stage_dir/release.sha512sum"
            if ! curl -sSL --connect-timeout 15 --max-time 30 -o "$sum_file" "$sha512_url" || [ ! -s "$sum_file" ]; then
                echo "[ERROR] Failed to download SHA-512 checksum from $sha512_url" >&2
                exit 1
            fi
            local expected_hash=""
            expected_hash=$(grep -F "$tarball_name" "$sum_file" 2>/dev/null | grep -Eoi '[0-9a-f]{128}' | head -n 1 || true)
            [ -z "$expected_hash" ] && expected_hash=$(grep -Eoi '[0-9a-f]{128}' "$sum_file" 2>/dev/null | head -n 1 || true)
            if [ -z "$expected_hash" ]; then
                echo "[ERROR] SHA-512 checksum asset did not contain a valid 128-hex digest." >&2
                exit 1
            fi
            printf '%s  %s\n' "$expected_hash" "$tarball_name" > "$stage_dir/verify.sha512sum"
            if ! ( cd "$stage_dir" && sha512sum -c "verify.sha512sum" >/dev/null 2>&1 ); then
                echo "[ERROR] SHA-512 checksum verification failed for $tarball_name." >&2
                exit 1
            fi
            echo "[VERIFIED] SHA-512 checksum matched."
        fi

        if ! python3 - "$staged_tar" <<'PY'
import posixpath, re, sys, tarfile

tar_path = sys.argv[1]
unsafe_re = re.compile(r"(^/|^[A-Za-z]:|(^|[/\\])\.\.([/\\]|$)|\\)")
try:
    with tarfile.open(tar_path, "r:gz") as tf:
        members = tf.getmembers()
        if not members:
            print("[ERROR] Downloaded tarball is empty or unreadable.", file=sys.stderr)
            sys.exit(1)
        for m in members:
            if unsafe_re.search(m.name):
                print(f"[ERROR] Security violation: unsafe path traversal in tarball ({m.name}).", file=sys.stderr)
                sys.exit(1)
            if m.isdev() or m.isfifo():
                print(f"[ERROR] Security violation: device/fifo entry in tarball ({m.name}).", file=sys.stderr)
                sys.exit(1)
            if m.issym() or m.islnk():
                lnk = m.linkname
                if not lnk or lnk.startswith(("/", "\\")) or re.match(r"^[A-Za-z]:", lnk):
                    print(f"[ERROR] Security violation: absolute link target in tarball ({m.name} -> {lnk}).", file=sys.stderr)
                    sys.exit(1)
                norm = posixpath.normpath(posixpath.join(posixpath.dirname(m.name), lnk) if m.issym() else lnk)
                if norm == ".." or norm.startswith("../"):
                    print(f"[ERROR] Security violation: escaping link target in tarball ({m.name} -> {lnk}).", file=sys.stderr)
                    sys.exit(1)
except tarfile.TarError as exc:
    print(f"[ERROR] Downloaded tarball is corrupt or unreadable ({exc}).", file=sys.stderr)
    sys.exit(1)
PY
        then
            exit 1
        fi

        mkdir -p "$stage_dir/extract"
        echo "[INFO] Extracting staged tarball..."
        if ! tar -xzf "$staged_tar" -C "$stage_dir/extract"; then
            echo "[ERROR] Failed to extract $tarball_name in staging directory." >&2
            exit 1
        fi

        local extracted_folder="$stage_dir/extract/$resolved_tag"
        if [ ! -d "$extracted_folder" ]; then
            extracted_folder=$(find "$stage_dir/extract" -mindepth 1 -maxdepth 1 -type d -name "*${resolved_tag}*" 2>/dev/null | head -n 1)
        fi
        if [ -z "$extracted_folder" ] || [ ! -d "$extracted_folder" ]; then
            extracted_folder=$(find "$stage_dir/extract" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | head -n 1)
        fi
        if [ -z "$extracted_folder" ] || [ ! -f "$extracted_folder/compatibilitytool.vdf" ]; then
            echo "[ERROR] Extraction completed but compatibilitytool.vdf not found in staged release." >&2
            exit 1
        fi
        [ -f "$extracted_folder/proton" ] && chmod +x "$extracted_folder/proton"

        local final_folder="$compat_dir/$(basename "$extracted_folder")"
        if [ -e "$final_folder" ]; then
            mv "$final_folder" "$stage_dir/old_backup" 2>/dev/null || {
                echo "[ERROR] Failed to replace existing runner directory: $final_folder" >&2
                exit 1
            }
        fi
        if ! mv "$extracted_folder" "$final_folder"; then
            [ -d "$stage_dir/old_backup" ] && mv "$stage_dir/old_backup" "$final_folder" 2>/dev/null || true
            echo "[ERROR] Failed to promote staged runner to: $final_folder" >&2
            exit 1
        fi

        echo "[VERIFIED] GE-Proton $resolved_tag installed successfully in: $final_folder"
        exit 0
    )
}

# Safely remove an installed GE-Proton version
proton_remove() {
    local tag="${1:-}"
    local auto_yes=false
    shift || true
    while [ $# -gt 0 ]; do
        case "$1" in
            -y|--yes) auto_yes=true; shift ;;
            *) shift ;;
        esac
    done

    if [ -z "$tag" ]; then
        echo "Usage: gamectl proton-remove <tag> [-y|--yes]" >&2
        return 1
    fi

    # Path traversal protection
    if [[ "$tag" =~ (\.\.|\/|\\) ]]; then
        echo "[ERROR] Invalid tag (path traversal sequence detected): $tag" >&2
        return 1
    fi

    local -a compat_dirs=()
    local cdir
    while IFS= read -r cdir; do
        [ -n "$cdir" ] && compat_dirs+=("$cdir")
    done < <(list_runner_dirs)

    local target_dir=""
    for cdir in "${compat_dirs[@]}"; do
        [ -n "$cdir" ] && [ -d "$cdir" ] || continue
        if [ -d "$cdir/$tag" ]; then
            target_dir="$cdir/$tag"
            break
        fi
    done

    if [ -z "$target_dir" ] || [ ! -d "$target_dir" ]; then
        echo "[ERROR] GE-Proton version '$tag' not found in runner directories." >&2
        return 1
    fi

    # Canonical path traversal assertion against authorized runner parent directories
    local real_target guard_ok=0 real_parent
    real_target="$(realpath "$target_dir" 2>/dev/null || echo "")"
    if [ -n "$real_target" ]; then
        for cdir in "${compat_dirs[@]}"; do
            [ -n "$cdir" ] && [ -d "$cdir" ] || continue
            real_parent="$(realpath "$cdir" 2>/dev/null || echo "")"
            if [ -n "$real_parent" ] && [[ "$real_target" == "$real_parent/"* ]] && [ "$real_target" != "$real_parent" ]; then
                guard_ok=1
                break
            fi
        done
    fi
    if [ "$guard_ok" -ne 1 ]; then
        echo "[ERROR] Path traversal guard failed for: $target_dir" >&2
        return 1
    fi

    local sz
    sz=$(du -sh "$target_dir" 2>/dev/null | awk '{print $1}')

    if [ "$auto_yes" = false ] && [ -t 0 ]; then
        echo -n "Delete GE-Proton directory '$tag' (Size: $sz)? [y/N]: "
        local confirm=""
        read -t 10 -r confirm || confirm="n"
        echo
        if [[ ! "$confirm" =~ ^[yY] ]]; then
            echo "[INFO] Removal of $tag canceled."
            return 0
        fi
    fi

    rm -rf "$target_dir"
    echo "[VERIFIED] GE-Proton '$tag' removed successfully ($sz disk space freed)."
    return 0
}

# Canonical Windows runner environment contract shared by launch_game & manage_prefix
prepare_windows_runner_env() {
    local runner_bin="${1:-wine}"
    local gdir="${2:-}"
    local raw_appid="${3:-0}"
    local renderer_mode="${4:-auto}"
    local prime_active="${5:-0}"

    local clean_appid="${raw_appid//[!0-9]/}"
    [ -z "$clean_appid" ] && clean_appid="0"

    GAMECTL_WIN_PFX_DIR="$gdir/pfx"
    GAMECTL_WIN_APPID="$clean_appid"
    if [ "$clean_appid" != "0" ]; then
        GAMECTL_WIN_UMU_GAMEID="umu-${clean_appid}"
    else
        GAMECTL_WIN_UMU_GAMEID="umu-default"
    fi
    GAMECTL_WIN_STEAM_ROOT="${STEAM_CLIENT_INSTALL_PATH:-$(get_steam_root 2>/dev/null || echo "$HOME/.local/share/Steam")}"

    case "$runner_bin" in
        umu-run|*/umu-run) GAMECTL_WIN_RUNNER_KIND="umu" ;;
        *proton*)          GAMECTL_WIN_RUNNER_KIND="proton" ;;
        *)                 GAMECTL_WIN_RUNNER_KIND="wine" ;;
    esac

    local eff_renderer="${GAMECTL_ACTIVE_RENDERER:-}"
    if [ -z "$eff_renderer" ]; then
        if [ -n "${PROTON_USE_WINED3D:-}" ]; then
            [ "$PROTON_USE_WINED3D" = "1" ] && eff_renderer="wined3d" || eff_renderer="dxvk"
        elif type resolve_graphics_renderer >/dev/null 2>&1; then
            eff_renderer="$(resolve_graphics_renderer "$renderer_mode" "$prime_active")"
        else
            eff_renderer="dxvk"
        fi
    fi
    GAMECTL_WIN_RENDERER="$eff_renderer"
    if [ "$eff_renderer" = "wined3d" ]; then
        GAMECTL_WIN_PROTON_WINED3D="1"
    else
        GAMECTL_WIN_PROTON_WINED3D="0"
    fi

    if [ "$clean_appid" = "0" ] && [ -z "${PROTONFIXES_DISABLE+x}" ]; then
        GAMECTL_WIN_DISABLE_PROTONFIXES="1"
    else
        GAMECTL_WIN_DISABLE_PROTONFIXES=""
    fi
}

# Wine Prefix Swiss Army Knife & Wineserver Lifecycle Guard (Chunk 4)
manage_prefix() {
    local game_dir="${1:-}"
    local action="${2:-}"
    shift 2 2>/dev/null || shift $# 2>/dev/null || true

    if [ -z "$game_dir" ] || [ ! -d "$game_dir" ]; then
        echo "[ERROR] Game directory not found or invalid: $game_dir" >&2
        echo "Usage: gamectl pfx <game_dir> [winecfg|regedit|cmd|shell|kill|clean|winetricks] [args...]" >&2
        return 1
    fi

    # Canonicalize game_dir path
    game_dir="$(cd "$game_dir" 2>/dev/null && pwd || echo "$game_dir")"
    local pfx_dir="$game_dir/pfx"
    local runner_bin
    runner_bin="$(find_runner "$game_dir" 2>/dev/null || true)"
    [ -z "$runner_bin" ] && runner_bin="wine"

    # AppID resolution (SSoT)
    local appid
    appid="$(resolve_game_appid "$game_dir" "0")"

    # Wineserver resolution
    local ws_bin
    ws_bin="$(get_wineserver_bin "$runner_bin" 2>/dev/null || echo "")"

    # Interactive menu if action is empty and stdin is terminal
    if [ -z "$action" ]; then
        require_tui "Wine prefix manager" || return $?
        if [ -t 0 ]; then
            if command -v fzf >/dev/null 2>&1; then
                flush_tty_input
                local game_name
                game_name="$(basename "$game_dir")"
                local pfx_status="[NOT FOUND]"
                local pfx_color="\033[38;5;203m"
                local pfx_size="0 B"
                if [ -d "$pfx_dir" ]; then
                    pfx_status="[ACTIVE]"
                    pfx_color="\033[38;5;120m"
                    pfx_size="$(du -sh "$pfx_dir" 2>/dev/null | awk '{print $1}' || echo "N/A")"
                fi

                local pfx_palette
                pfx_palette=$(cat <<EOF
winecfg	Wine Configuration	Configure Audio, Graphics, Windows Version & DLL Overrides
regedit	Registry Editor	Windows Registry Editor (regedit.exe)
cmd	Command Prompt	Windows Command Prompt (cmd.exe)
shell	Host Bash Subshell	Spawn bash subshell with active WINEPREFIX & PATH
winetricks	Winetricks Manager	Launch winetricks GUI / Package Manager helper
kill	Kill Wineserver	Terminate locked / hung Wineserver process
clean	Wipe Wine Prefix	Create save snapshot backup & wipe entire pfx directory
EOF
)

                export GAMECTL_PFX_NAME="$game_name"
                export GAMECTL_PFX_DIR="$game_dir"
                export GAMECTL_PFX_PATH="$pfx_dir"
                export GAMECTL_PFX_RUNNER="$runner_bin"
                export GAMECTL_PFX_STATUS="${pfx_color}${pfx_status}"
                export GAMECTL_PFX_SIZE="$pfx_size"

                local preview_cmd
                preview_cmd='printf "\033[38;5;60m╭─ WINE PREFIX OVERVIEW ──────────────────────────────╮\033[0m\n  Game Title  : \033[1m%s\033[0m\n  Directory   : %s\n  Prefix Path : %s\n  Active Wine : \033[38;5;111m%s\033[0m\n  Status      : %b\033[0m (Size: %s)\n\033[38;5;60m╰─────────────────────────────────────────────────────╯\033[0m\n\033[38;5;60m╭─ ACTION DETAIL ─────────────────────────────────────╮\033[0m\n  Tool   : \033[1m%s\033[0m - %s\n  Desc   : %s\n\033[38;5;60m╰─────────────────────────────────────────────────────╯\033[0m\n" "$GAMECTL_PFX_NAME" "$GAMECTL_PFX_DIR" "$GAMECTL_PFX_PATH" "$GAMECTL_PFX_RUNNER" "$GAMECTL_PFX_STATUS" "$GAMECTL_PFX_SIZE" {1} {2} {3}'

                local pfx_sel fzf_rc=0
                pfx_sel=$(echo "$pfx_palette" | fzf \
                    --delimiter=$'\t' \
                    --with-nth=1,2 \
                    --border-label="  ╢ gamectl :: Wine Prefix Manager :: $game_name ╟  " \
                    --border-label-pos=2 \
                    --header="Enter: Execute │ Esc: Return" \
                    --prompt="Prefix > " \
                    --preview="$preview_cmd" \
                    --preview-window=down:50%:border-rounded:wrap \
                    --reverse 2>/dev/null) || fzf_rc=$?

                if [ "$fzf_rc" -eq 130 ]; then
                    return 0
                fi
                if [ "$fzf_rc" -ne 0 ] && [ "$fzf_rc" -ne 1 ]; then
                    echo "[ERROR] Wine prefix manager failed (fzf exit code $fzf_rc)." >&2
                    return "$fzf_rc"
                fi
                [ -z "$pfx_sel" ] && return 0

                action=$(echo "$pfx_sel" | awk -F'\t' '{print $1}')
            else
                echo "[ERROR] fzf is required for Wine prefix manager." >&2
                return 127
            fi
        else
            echo "Usage: gamectl pfx <game_dir> [winecfg|regedit|cmd|shell|kill|clean|winetricks] [args...]" >&2
            return 1
        fi
    fi

    case "$action" in
        kill)
            echo "[INFO] Sending force termination signal (wineserver -k) to prefix: $pfx_dir"
            if [ -d "$pfx_dir" ]; then
                if [ -n "$ws_bin" ]; then
                    WINEPREFIX="$pfx_dir" "$ws_bin" -k 2>/dev/null || true
                elif command -v wineserver >/dev/null 2>&1; then
                    WINEPREFIX="$pfx_dir" wineserver -k 2>/dev/null || true
                fi
            fi
            echo "[VERIFIED] Wineserver for prefix $pfx_dir has been stopped."
            return 0
            ;;
        clean)
            echo "[INFO] Starting Wine prefix cleanup: $pfx_dir"
            if [ ! -d "$pfx_dir" ]; then
                echo "[INFO] Prefix directory $pfx_dir does not exist, nothing to clean."
                return 0
            fi

            local is_dry_run=false auto_yes=false
            for arg in "$@"; do
                if [ "$arg" = "--dry-run" ] || [ "$arg" = "-n" ]; then
                    is_dry_run=true
                elif [ "$arg" = "-y" ] || [ "$arg" = "--yes" ]; then
                    auto_yes=true
                fi
            done

            if [ "$is_dry_run" = true ]; then
                local pfx_sz="0"
                pfx_sz=$(du -sh "$pfx_dir" 2>/dev/null | cut -f1 || echo "unknown")
                echo "[INFO] [DRY-RUN] Target Wine prefix directory: $pfx_dir (Size: $pfx_sz)"
                echo "[INFO] [DRY-RUN] Would create pre-wipe savegame backup snapshot via backup_save."
                echo "[INFO] [DRY-RUN] Would terminate wineserver process."
                echo "[INFO] [DRY-RUN] Would remove prefix directory: $pfx_dir"
                echo "[INFO] [DRY-RUN] Wine prefix cleanup simulated successfully (no files deleted)."
                return 0
            fi

            # 1. Create save snapshot backup
            if [ -d "$game_dir/saves" ] || [ -L "$game_dir/saves" ]; then
                if ! backup_save "$game_dir" true; then
                    echo "[ERROR] Pre-wipe save snapshot backup failed. Aborting prefix wipe to protect saves." >&2
                    log_msg "ERROR" "PFX" "Pre-wipe save snapshot backup failed for $(basename "$game_dir")"
                    return 1
                fi
            fi

            # 2. Kill running wineserver
            if [ -n "$ws_bin" ]; then
                WINEPREFIX="$pfx_dir" "$ws_bin" -k 2>/dev/null || true
            elif command -v wineserver >/dev/null 2>&1; then
                WINEPREFIX="$pfx_dir" wineserver -k 2>/dev/null || true
            fi
            sleep 0.2

            # 3. Confirmation check
            if [ "$auto_yes" = false ] && [ -t 0 ]; then
                echo -n "[WARN] Wipe entire Wine prefix ($pfx_dir)? Registry and Wine configuration will be reset. [y/N]: "
                local confirm=""
                read -t 10 -r confirm || confirm="n"
                echo
                if [[ ! "$confirm" =~ ^[yY] ]]; then
                    echo "[INFO] Prefix cleanup canceled."
                    return 0
                fi
            fi

            # 4. Remove pfx folder safely
            rm -rf "$pfx_dir"
            echo "[VERIFIED] Wine prefix wiped successfully ($pfx_dir removed)."
            return 0
            ;;
        shell)
            prepare_windows_runner_env "$runner_bin" "$game_dir" "$appid" "auto" "0"
            echo "[INFO] Spawning interactive bash subshell inside prefix environment: $pfx_dir"
            echo "[INFO] Active environment: WINEPREFIX=$pfx_dir, RUNNER=$runner_bin"
            echo "[INFO] Type 'exit' to return to gamectl."
            (
                export WINEPREFIX="$GAMECTL_WIN_PFX_DIR" \
                    GAMECTL_RUNNER="$runner_bin" \
                    GAMEID="$GAMECTL_WIN_UMU_GAMEID" \
                    STEAM_COMPAT_APP_ID="$GAMECTL_WIN_APPID" \
                    SteamAppId="$GAMECTL_WIN_APPID" \
                    SteamGameId="$GAMECTL_WIN_APPID"
                if [ "$GAMECTL_WIN_RUNNER_KIND" = "proton" ] || [ "$GAMECTL_WIN_RUNNER_KIND" = "umu" ]; then
                    export PROTON_USE_WINED3D="$GAMECTL_WIN_PROTON_WINED3D"
                    [ "$GAMECTL_WIN_DISABLE_PROTONFIXES" = "1" ] && export PROTONFIXES_DISABLE=1
                fi
                if [ "$GAMECTL_WIN_RUNNER_KIND" = "proton" ]; then
                    export STEAM_COMPAT_CLIENT_INSTALL_PATH="$GAMECTL_WIN_STEAM_ROOT" \
                        STEAM_COMPAT_DATA_PATH="$game_dir"
                    local p_bin_dir
                    p_bin_dir="$(dirname "$runner_bin")/files/bin"
                    [ -d "$p_bin_dir" ] && export PATH="$p_bin_dir:$PATH"
                fi
                cd "$game_dir" || true
                exec bash -i
            )
            return 0
            ;;
        winecfg|regedit|cmd)
            mkdir -p "$pfx_dir"
            prepare_windows_runner_env "$runner_bin" "$game_dir" "$appid" "auto" "0"
            echo "[INFO] Executing $action inside prefix: $pfx_dir (Runner: $runner_bin)..."
            local target_exec="$action"
            [ "$action" = "cmd" ] && target_exec="cmd.exe"

            (
                export WINEPREFIX="$GAMECTL_WIN_PFX_DIR" \
                    GAMEID="$GAMECTL_WIN_UMU_GAMEID" \
                    STEAM_COMPAT_APP_ID="$GAMECTL_WIN_APPID" \
                    SteamAppId="$GAMECTL_WIN_APPID" \
                    SteamGameId="$GAMECTL_WIN_APPID"
                if [ "$GAMECTL_WIN_RUNNER_KIND" = "proton" ] || [ "$GAMECTL_WIN_RUNNER_KIND" = "umu" ]; then
                    export PROTON_USE_WINED3D="$GAMECTL_WIN_PROTON_WINED3D"
                    [ "$GAMECTL_WIN_DISABLE_PROTONFIXES" = "1" ] && export PROTONFIXES_DISABLE=1
                fi
                case "$GAMECTL_WIN_RUNNER_KIND" in
                    umu)
                        "$runner_bin" "$target_exec" "$@"
                        ;;
                    proton)
                        export STEAM_COMPAT_CLIENT_INSTALL_PATH="$GAMECTL_WIN_STEAM_ROOT" \
                            STEAM_COMPAT_DATA_PATH="$game_dir"
                        "$runner_bin" run "$target_exec" "$@"
                        ;;
                    *)
                        "$runner_bin" "$target_exec" "$@"
                        ;;
                esac
            )
            ;;
        winetricks)
            if ! command -v winetricks >/dev/null 2>&1; then
                echo "[ERROR] 'winetricks' binary not found on host system." >&2
                echo "[INFO] Install winetricks via your distribution package manager (e.g. pacman -S winetricks / apt install winetricks)." >&2
                return 1
            fi
            mkdir -p "$pfx_dir"
            echo "[INFO] Launching winetricks inside prefix: $pfx_dir"
            WINEPREFIX="$pfx_dir" winetricks "$@"
            ;;
        *)
            echo "[ERROR] Unknown prefix action: '$action'" >&2
            echo "Supported actions: winecfg, regedit, cmd, shell, kill, clean, winetricks" >&2
            return 1
            ;;
    esac
}

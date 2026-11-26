# ==============================================================================
# GE-Proton & Wine Runner Discovery, Installer & Lifecycle Manager
# ==============================================================================

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
        while IFS=$'\t' read -r r_tag _ r_size _; do
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

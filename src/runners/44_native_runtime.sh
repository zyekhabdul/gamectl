# ==============================================================================
# Standalone Native Linux Steam Runtime (Scout) Provisioner
# ==============================================================================

# Auto-download and provision standalone Steam Runtime (Scout) without Steam Client
setup_native_runtime() {
    local auto_yes=false force=false dry_run=false
    local custom_src="" custom_sha=""
    local dest_dir
    dest_dir="$(get_standalone_runtime_dir)"
    local default_url="https://repo.steampowered.com/steamrt1/images/latest-public-beta/steam-runtime.tar.xz"
    local default_sha_url="https://repo.steampowered.com/steamrt1/images/latest-public-beta/SHA256SUMS"

    while [ $# -gt 0 ]; do
        case "$1" in
            -y|--yes) auto_yes=true ;;
            -f|--force) force=true ;;
            --dry-run) dry_run=true ;;
            --source) shift; custom_src="${1:-}" ;;
            --source=*) custom_src="${1#--source=}" ;;
            --sha256) shift; custom_sha="${1:-}" ;;
            --sha256=*) custom_sha="${1#--sha256=}" ;;
            --dest) shift; dest_dir="${1:-}" ;;
            --dest=*) dest_dir="${1#--dest=}" ;;
            -h|--help)
                cat <<EOF
Usage: gamectl setup-runtime [options]

Provision standalone Valve Steam Runtime (Scout) into ~/.local/share/gamectl/runtime/

Options:
  -y, --yes             Non-interactive mode
  -f, --force           Overwrite existing standalone runtime installation
  --dry-run             Validate target and source without modifying filesystem
  --source <file|url>   Custom tarball path or URL for steam-runtime.tar.xz
  --sha256 <hex|file|url> Expected SHA-256 digest, checksum file, or SHA256SUMS URL
  --dest <dir>          Target runtime directory (default: ~/.local/share/gamectl/runtime/steam-runtime)
EOF
                return 0
                ;;
            *) echo "[WARN] Unknown argument: $1" >&2 ;;
        esac
        shift || true
    done
    : "$auto_yes"

    local src_target="${custom_src:-$default_url}"
    if [ "$dry_run" = true ]; then
        echo "[DRY-RUN] Target destination verified: $dest_dir (Source: $src_target)"
        return 0
    fi
    if [ "$force" = false ] && [ -x "$dest_dir/run.sh" ]; then
        echo "[PASS] Standalone Native Linux runtime already provisioned in $dest_dir."
        return 0
    fi

    (
        local parent_dir stage_dir tar_name staged_tar
        parent_dir="$(dirname "$dest_dir")"
        mkdir -p "$parent_dir" || exit 1
        stage_dir=$(mktemp -d "$parent_dir/.runtime_stage.XXXXXX") || exit 1
        trap 'rm -rf "$stage_dir"' EXIT INT TERM

        tar_name=$(basename "${src_target%%\?*}")
        [ -z "$tar_name" ] && tar_name="steam-runtime.tar.xz"
        staged_tar="$stage_dir/$tar_name"

        if [ -f "$src_target" ]; then
            cp -f "$src_target" "$staged_tar" || { echo "[ERROR] Failed to copy runtime archive: $src_target" >&2; exit 1; }
        else
            echo "[INFO] Downloading Steam Runtime (Scout) from: $src_target"
            if ! curl -# -fL --connect-timeout 15 -o "$staged_tar" "$src_target" || [ ! -s "$staged_tar" ]; then
                echo "[ERROR] Failed to download Steam Runtime archive from $src_target" >&2
                exit 1
            fi
        fi

        if [ ! -f "$src_target" ] || [ -n "$custom_sha" ]; then
            local sha_src="${custom_sha:-$default_sha_url}" expected_hash="" sum_file="$stage_dir/SHA256SUMS"
            if [[ "$sha_src" =~ ^[0-9A-Fa-f]{64}$ ]]; then
                expected_hash="${sha_src,,}"
            else
                if [ -f "$sha_src" ]; then
                    cp -f "$sha_src" "$sum_file" || exit 1
                elif ! curl -sSL --connect-timeout 15 --max-time 30 -o "$sum_file" "$sha_src" || [ ! -s "$sum_file" ]; then
                    echo "[ERROR] Failed to retrieve SHA-256 checksums from $sha_src" >&2
                    exit 1
                fi
                expected_hash=$(grep -F "$tar_name" "$sum_file" 2>/dev/null | grep -Eoi '[0-9a-f]{64}' | head -n 1 || true)
                [ -z "$expected_hash" ] && expected_hash=$(grep -Eoi '[0-9a-f]{64}' "$sum_file" 2>/dev/null | head -n 1 || true)
            fi
            if [ -z "$expected_hash" ]; then
                echo "[ERROR] Valid SHA-256 digest not found for $tar_name." >&2
                exit 1
            fi
            if ! ( cd "$stage_dir" && printf '%s  %s\n' "$expected_hash" "$tar_name" | sha256sum -c - >/dev/null 2>&1 ); then
                echo "[ERROR] SHA-256 verification failed for $tar_name." >&2
                exit 1
            fi
            echo "[VERIFIED] SHA-256 checksum matched."
        fi

        if ! python3 - "$staged_tar" <<'PY'
import posixpath, re, sys, tarfile
unsafe = re.compile(r"(^/|^[A-Za-z]:|(^|[/\\])\.\.([/\\]|$)|\\)")
try:
    with tarfile.open(sys.argv[1], "r:*") as tf:
        members = tf.getmembers()
        if not members:
            print("[ERROR] Runtime archive is empty.", file=sys.stderr); sys.exit(1)
        for m in members:
            if unsafe.search(m.name) or m.isdev() or m.isfifo():
                print(f"[ERROR] Security violation in archive entry: {m.name}", file=sys.stderr); sys.exit(1)
            if m.issym() or m.islnk():
                lnk = m.linkname
                if not lnk or lnk.startswith(("/", "\\")) or re.match(r"^[A-Za-z]:", lnk):
                    print(f"[ERROR] Security violation: unsafe link {m.name} -> {lnk}", file=sys.stderr); sys.exit(1)
                norm = posixpath.normpath(posixpath.join(posixpath.dirname(m.name), lnk) if m.issym() else lnk)
                if norm == ".." or norm.startswith("../"):
                    print(f"[ERROR] Security violation: escaping link {m.name} -> {lnk}", file=sys.stderr); sys.exit(1)
except tarfile.TarError as exc:
    print(f"[ERROR] Corrupt runtime archive ({exc}).", file=sys.stderr); sys.exit(1)
PY
        then
            exit 1
        fi

        mkdir -p "$stage_dir/extract"
        echo "[INFO] Extracting Steam Runtime to staging..."
        if ! tar -xf "$staged_tar" -C "$stage_dir/extract"; then
            echo "[ERROR] Failed to extract runtime archive." >&2; exit 1
        fi

        local extracted_dir="" run_found=""
        if [ -f "$stage_dir/extract/run.sh" ]; then
            extracted_dir="$stage_dir/extract"
        else
            run_found=$(find "$stage_dir/extract" -maxdepth 2 -name "run.sh" -print -quit 2>/dev/null || true)
            [ -n "$run_found" ] && extracted_dir="$(dirname "$run_found")"
        fi
        if [ -z "$extracted_dir" ] || [ ! -f "$extracted_dir/run.sh" ]; then
            echo "[ERROR] Extracted runtime does not contain run.sh." >&2; exit 1
        fi
        chmod +x "$extracted_dir/run.sh"
        [ -f "$extracted_dir/setup.sh" ] && chmod +x "$extracted_dir/setup.sh"

        if [ -e "$dest_dir" ] || [ -L "$dest_dir" ]; then
            mv "$dest_dir" "$stage_dir/old_backup" || { echo "[ERROR] Failed to stage existing runtime backup." >&2; exit 1; }
        fi
        if ! mv "$extracted_dir" "$dest_dir"; then
            [ -e "$stage_dir/old_backup" ] && mv "$stage_dir/old_backup" "$dest_dir" 2>/dev/null || true
            echo "[ERROR] Failed to install runtime into $dest_dir" >&2; exit 1
        fi

        # Run setup.sh after final placement so pinned_libs_* absolute symlinks target $dest_dir
        if [ -x "$dest_dir/setup.sh" ]; then
            if ! ( cd "$dest_dir" && ./setup.sh >/dev/null ); then
                rm -rf "$dest_dir" 2>/dev/null || true
                [ -e "$stage_dir/old_backup" ] && mv "$stage_dir/old_backup" "$dest_dir" 2>/dev/null || true
                echo "[ERROR] Runtime setup.sh initialization failed." >&2; exit 1
            fi
        fi
        [ -x "$dest_dir/run.sh" ] || { echo "[ERROR] Installed runtime missing executable run.sh." >&2; exit 1; }
        echo "[VERIFIED] Standalone Native Linux runtime installed in: $dest_dir"
    )
}

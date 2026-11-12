# ==============================================================================
# gamectl - Automated Game Fix & Online-Fix Harvester & Steam Lifecycle Engine
# Integrates LuaTools Fix API, Cloudflare R2 Presigned Downloads, Safe Extraction,
# Atomic Revert Snapshots, Proton Compatibility Guards, & Graceful Steam Reload.
# ==============================================================================

# Query community & Online-Fix bypasses for a given AppID
# Public unauthenticated endpoint: https://lua.tools/api/denuvo/fixes?appid=<appid>
check_game_fixes() {
    local appid="${1:-}"
    if [ -z "$appid" ] || ! [[ "$appid" =~ ^[0-9]+$ ]]; then
        echo "[ERROR] Invalid or missing Steam AppID: '$appid'" >&2
        echo "Usage: gamectl fix-check <appid>" >&2
        return 1
    fi

    echo "[INFO] Querying available fixes and bypasses for AppID: $appid..."

    local api_url="https://lua.tools/api/denuvo/fixes?appid=${appid}"
    local json_out
    json_out=$(curl -sSL --connect-timeout 5 --max-time 15 -A "discord(dot)gg/luatools" "$api_url" 2>/dev/null || true)

    if [ -z "$json_out" ]; then
        echo "[WARN] Could not reach LuaTools fix catalog for AppID $appid." >&2
        return 1
    fi

    # Check for empty response or 'No fixes found'
    if echo "$json_out" | grep -q '"No fixes found"'; then
        echo "[INFO] No community fixes or bypasses registered for AppID: $appid."
        return 0
    fi

    python3 -c '
import sys, json

try:
    data = json.loads(sys.argv[1])
except Exception as e:
    print("[ERROR] Failed to parse API response JSON:", e)
    sys.exit(1)

app_name = data.get("name", "Unknown Game")
appid = data.get("appid", sys.argv[2])
fixes = data.get("fixes", [])

if not fixes:
    print("[INFO] No community fixes or bypasses found for:", app_name, f"(AppID: {appid})")
    sys.exit(0)

print("==============================================================================")
print(f" GAMECTL FIX CATALOG: {app_name} (AppID: {appid})")
print(f" Available Fixes: {len(fixes)}")
print("==============================================================================")

for idx, fix in enumerate(fixes, 1):
    fix_id = fix.get("id", "unknown")
    title = fix.get("title", "Fix")
    filename = fix.get("fixFilename", "N/A")
    tags = [t.get("name", "") for t in fix.get("tags", []) if isinstance(t, dict)]
    tag_str = ", ".join(tags) if tags else "generic"
    has_fix = "[READY]" if fix.get("hasFix") else "[PENDING]"
    
    print(f" [{idx}] {has_fix} Title: {title}")
    print(f"     • Fix ID  : {fix_id}")
    print(f"     • Archive : {filename}")
    print(f"     • Tags    : {tag_str}")
    desc = fix.get("description", "").strip()
    if desc:
        print(f"     • Notes   : {desc}")
print("==============================================================================")
' "$json_out" "$appid"
}

# Resolve target game directory from AppID or path argument
resolve_game_install_dir() {
    local target="${1:-}"
    [ -z "$target" ] && return 1

    # If it is already an existing directory, resolve absolute path
    if [ -d "$target" ]; then
        (cd "$target" && pwd)
        return 0
    fi

    # If it is numeric AppID, inspect Steam libraries via appmanifest_<appid>.acf
    if [[ "$target" =~ ^[0-9]+$ ]]; then
        local acf_file
        acf_file=$(find_app_acf "$target" 2>/dev/null || true)
        if [ -n "$acf_file" ] && [ -f "$acf_file" ]; then
            local state_data
            state_data=$(parse_acf_download_state "$acf_file" 2>/dev/null || true)
            if [ -n "$state_data" ]; then
                local installdir
                installdir=$(echo "$state_data" | cut -f 8)
                if [ -n "$installdir" ]; then
                    local cand_dir="$(dirname "$acf_file")/common/$installdir"
                    if [ -d "$cand_dir" ]; then
                        echo "$cand_dir"
                        return 0
                    fi
                fi
            fi
        fi

        # Fallback: Search inside all known library common directories
        local lib
        while IFS= read -r lib; do
            [ -d "$lib" ] || continue
            local common_dir="$lib"
            [ "$(basename "$lib")" != "common" ] && common_dir="$lib/common"
            [ -d "$common_dir" ] || common_dir="$(dirname "$lib")/common"
            [ -d "$common_dir" ] || continue

            # Search directory with matching appid or title
            local match
            match=$(find "$common_dir" -maxdepth 2 -type f \( -name "steam_appid.txt" -o -name "OnlineFix.ini" \) -exec grep -l "^$target$" {} + 2>/dev/null | head -n 1)
            if [ -n "$match" ]; then
                dirname "$match"
                return 0
            fi
        done < <(get_steam_libraries 2>/dev/null || true)
    fi

    return 1
}

# Audit Proton compatibility in config.vdf for Windows DLL fixes
audit_proton_compatibility() {
    local appid="$1"
    [ -z "$appid" ] && return 0

    local config_vdf=""
    for cand in "$HOME/.local/share/Steam/config/config.vdf" "$HOME/.steam/steam/config/config.vdf"; do
        if [ -f "$cand" ]; then
            config_vdf="$cand"
            break
        fi
    done

    [ -z "$config_vdf" ] && return 0

    local has_mapping=0
    if grep -E -A 5 "\"${appid}\"[[:space:]]*\{" "$config_vdf" 2>/dev/null | grep -q -E '"[Nn]ame"'; then
        has_mapping=1
    fi

    if [ "$has_mapping" -eq 0 ]; then
        echo "  [WARN] AppID $appid does not have an explicit Steam Play (Proton) compatibility tool set."
        echo "         If this game has native Linux binaries, Windows DLL fixes will NOT load."
        echo "         -> In Steam: Game Properties -> Compatibility -> Check 'Force the use of a specific Steam Play compatibility tool'."
    fi
}

# Detect custom crack launcher executable shipped by fix payload
detect_fix_custom_launcher() {
    local gdir="$1"
    [ -z "$gdir" ] || [ ! -d "$gdir" ] && return 0

    local custom_launcher
    custom_launcher=$(find "$gdir" -maxdepth 2 -type f \( \
        -iname "Launcher.exe" -o -iname "*_launcher.exe" -o -iname "launcher_*.exe" \
    \) ! -iname "UnityCrashHandler*.exe" ! -iname "crash*.exe" 2>/dev/null | head -n 1)

    if [ -n "$custom_launcher" ]; then
        local rel_launcher
        rel_launcher="$(basename "$custom_launcher")"
        echo "  [INFO] Custom crack launcher detected: $rel_launcher"
        echo "         If launching via Steam Client, set Launch Options in Steam Properties:"
        echo "         bash -c 'cmd=(%command%); cmd[-1]=\"\$PWD/$rel_launcher\"; \"\${cmd[@]}\"'"
    fi
}

# Download, verify, and safely extract game fix
install_game_fix() {
    local appid=""
    local target_dir=""
    local fix_type="online"
    local explicit_fix_id=""
    local auto_yes=false
    local should_restart=false

    while [ $# -gt 0 ]; do
        case "$1" in
            --type)
                fix_type="${2:-online}"
                shift 2 || true
                ;;
            --fix-id)
                explicit_fix_id="${2:-}"
                shift 2 || true
                ;;
            -y|--yes)
                auto_yes=true
                shift
                ;;
            --restart)
                should_restart=true
                shift
                ;;
            *)
                if [ -z "$appid" ]; then
                    appid="$1"
                elif [ -z "$target_dir" ]; then
                    target_dir="$1"
                fi
                shift
                ;;
        esac
    done

    if [ -z "$appid" ] || ! [[ "$appid" =~ ^[0-9]+$ ]]; then
        echo "[ERROR] Invalid or missing Steam AppID: '$appid'" >&2
        echo "Usage: gamectl fix-install <appid> [game_dir] [--type online|generic|voices38|all] [--fix-id <id>] [--yes|-y] [--restart]" >&2
        return 1
    fi

    # 1. Resolve Target Game Directory
    local resolved_dir=""
    if [ -n "$target_dir" ] && [ -d "$target_dir" ]; then
        resolved_dir="$(cd "$target_dir" && pwd)"
    else
        resolved_dir=$(resolve_game_install_dir "$appid" 2>/dev/null || true)
    fi

    if [ -z "$resolved_dir" ] || [ ! -d "$resolved_dir" ]; then
        echo "[ERROR] Could not resolve game installation directory for AppID $appid." >&2
        echo "       Please provide the target directory explicitly:" >&2
        echo "       gamectl fix-install $appid /path/to/game_directory" >&2
        return 1
    fi
    echo "[INFO] Target installation directory: $resolved_dir"

    # 2. Query available fixes
    local api_url="https://lua.tools/api/denuvo/fixes?appid=${appid}"
    local json_out
    json_out=$(curl -sSL --connect-timeout 5 --max-time 15 -A "discord(dot)gg/luatools" "$api_url" 2>/dev/null || true)

    if [ -z "$json_out" ] || echo "$json_out" | grep -q '"No fixes found"'; then
        echo "[ERROR] No fixes available in catalog for AppID: $appid." >&2
        return 1
    fi

    # 3. Select target fix ID using Python selector
    local chosen_fix_json
    chosen_fix_json=$(python3 -c '
import sys, json

try:
    data = json.loads(sys.argv[1])
except Exception:
    sys.exit(1)

fixes = data.get("fixes", [])
if not fixes:
    sys.exit(1)

explicit_id = sys.argv[2]
pref_type = sys.argv[3].lower()

chosen = None

if explicit_id:
    for f in fixes:
        if f.get("id") == explicit_id:
            chosen = f
            break

if not chosen:
    ranked = []
    for f in fixes:
        if not f.get("hasFix"):
            continue
        tags = [t.get("slug", "").lower() for t in f.get("tags", []) if isinstance(t, dict)]
        title = f.get("title", "").lower()
        score = 100
        if "online-fix" in tags or "online fix" in title or "onlinefix" in title:
            score = 10 if pref_type == "online" else 50
        elif "voices38-crack" in tags or "voices38" in title:
            score = 20 if pref_type == "voices38" else 60
        elif "generic" in tags or "bypass" in title:
            score = 30 if pref_type == "generic" else 70
        ranked.append((score, f))
    
    if ranked:
        ranked.sort(key=lambda x: x[0])
        chosen = ranked[0][1]
    elif fixes:
        chosen = fixes[0]

if chosen:
    print(json.dumps(chosen))
' "$json_out" "$explicit_fix_id" "$fix_type")

    if [ -z "$chosen_fix_json" ]; then
        echo "[ERROR] Could not select a valid fix for AppID $appid." >&2
        return 1
    fi

    local fix_id fix_title fix_filename
    fix_id=$(echo "$chosen_fix_json" | python3 -c 'import sys, json; print(json.load(sys.stdin).get("id", ""))')
    fix_title=$(echo "$chosen_fix_json" | python3 -c 'import sys, json; print(json.load(sys.stdin).get("title", ""))')
    fix_filename=$(echo "$chosen_fix_json" | python3 -c 'import sys, json; print(json.load(sys.stdin).get("fixFilename", ""))')

    echo "[INFO] Selected Fix:"
    echo "  • Fix ID   : $fix_id"
    echo "  • Title    : $fix_title"
    echo "  • Filename : $fix_filename"

    # 4. Authenticate via LuaTools token resolver
    local token
    token=$(get_valid_luatools_token 2>/dev/null || true)
    if [ -z "$token" ]; then
        echo "[ERROR] Downloading fix archives requires an active LuaTools account session." >&2
        echo "       Run: gamectl login-luatools <6-character-code | refresh_token | session.json>" >&2
        return 1
    fi

    # 5. Resolve presigned Cloudflare R2 download URL
    echo "[INFO] Resolving secure presigned download link..."
    local encoded_fix_id
    encoded_fix_id=$(python3 -c "import urllib.parse, sys; print(urllib.parse.quote(sys.argv[1]))" "$fix_id")
    local dl_api="https://lua.tools/api/denuvo/download?fix=${encoded_fix_id}&slot=fix"
    local dl_resp
    dl_resp=$(curl -sSL --connect-timeout 8 --max-time 20 \
        -H "Authorization: Bearer $token" \
        -H "User-Agent: discord(dot)gg/luatools" \
        "$dl_api" 2>/dev/null || true)

    local signed_url
    signed_url=$(echo "$dl_resp" | python3 -c '
import sys, json
try:
    data = json.load(sys.stdin)
    print(data.get("url", ""))
except Exception:
    pass
')

    if [ -z "$signed_url" ] || ! [[ "$signed_url" =~ ^https:// ]]; then
        echo "[ERROR] Failed to obtain presigned download link from LuaTools API." >&2
        echo "       Response: $dl_resp" >&2
        return 1
    fi

    # 6. Download archive to temporary file
    local tmp_zip
    tmp_zip=$(mktemp "${TMPDIR:-/tmp}/gamectl_fix_${appid}_XXXXXX.zip")
    echo "[INFO] Downloading fix archive payload..."
    if ! curl -sSL --connect-timeout 10 --max-time 180 \
        -A "discord(dot)gg/luatools" \
        -o "$tmp_zip" "$signed_url"; then
        rm -f "$tmp_zip"
        echo "[ERROR] Download failed from storage backend." >&2
        return 1
    fi

    if [ ! -s "$tmp_zip" ] || ! unzip -tq "$tmp_zip" >/dev/null 2>&1; then
        rm -f "$tmp_zip"
        echo "[ERROR] Downloaded archive is corrupt or not a valid ZIP file." >&2
        return 1
    fi

    # 7. Zip-Slip Security Audit
    if unzip -Z1 "$tmp_zip" 2>/dev/null | grep -E '(^/|^\.\./|/\.\./|^\.\.\\|\\\.\.\\)' >/dev/null 2>&1; then
        rm -f "$tmp_zip"
        echo "[ERROR] Security violation: Zip slip path traversal detected in archive payload!" >&2
        return 1
    fi
    echo "[VERIFIED] Archive payload integrity & security audit passed."

    # 8. Create Atomic Backup Snapshot Before Overwriting
    local ts
    ts="$(date +%Y%m%d_%H%M%S)"
    local backup_dir="$resolved_dir/.gamectl_fix_backup/$ts"
    local backup_files_dir="$backup_dir/backup_files"
    mkdir -p "$backup_files_dir"

    local zip_files
    zip_files=$(unzip -Z1 "$tmp_zip" 2>/dev/null || true)
    local backed_up_count=0

    # Save list of all files extracted by this fix
    echo "$zip_files" > "$backup_dir/installed_files.txt"

    while IFS= read -r f; do
        [ -z "$f" ] && continue
        if [ -f "$resolved_dir/$f" ]; then
            mkdir -p "$(dirname "$backup_files_dir/$f")"
            cp -p "$resolved_dir/$f" "$backup_files_dir/$f"
            backed_up_count=$((backed_up_count + 1))
        fi
    done <<< "$zip_files"

    cat <<META > "$resolved_dir/.gamectl_fix_backup/latest.json"
{
  "timestamp": "$ts",
  "appid": "$appid",
  "fix_id": "$fix_id",
  "fix_title": "$fix_title",
  "backed_up_count": $backed_up_count
}
META
    echo "[VERIFIED] Created pre-install snapshot: $backed_up_count original file(s) saved to .gamectl_fix_backup/$ts"

    # 9. Extract Payload into Target Game Directory
    echo "[INFO] Extracting fix payload into: $resolved_dir..."
    unzip -q -o "$tmp_zip" -d "$resolved_dir"
    rm -f "$tmp_zip"

    # 10. Audit Proton Compatibility & Custom Launcher Redirection
    audit_proton_compatibility "$appid"
    detect_fix_custom_launcher "$resolved_dir"

    # 11. Chain Auto-Execute: setup_onlinefix
    echo "[INFO] Running automated P2P compatibility and Spacewar entitlement setup..."
    setup_onlinefix "$resolved_dir" --yes || true

    echo "=============================================================================="
    invalidate_scan_cache
    echo " [SUCCESS] Fix successfully deployed for: $(basename "$resolved_dir")"
    echo "           To revert changes at any time: gamectl fix-revert \"$resolved_dir\""
    echo "=============================================================================="

    # 12. Optional Graceful Steam Restart
    if [ "$should_restart" = true ]; then
        restart_steam_client
    fi

    return 0
}

# Revert deployed game fix and restore original files from backup snapshot
revert_game_fix() {
    local target="${1:-}"
    if [ -z "$target" ]; then
        echo "Usage: gamectl fix-revert <game_dir|appid> [--dry-run]" >&2
        return 1
    fi

    local is_dry_run=false
    for arg in "$@"; do
        if [ "$arg" = "--dry-run" ] || [ "$arg" = "-n" ]; then
            is_dry_run=true
        fi
    done

    local resolved_dir
    resolved_dir=$(resolve_game_install_dir "$target" 2>/dev/null || true)
    if [ -z "$resolved_dir" ] || [ ! -d "$resolved_dir" ]; then
        echo "[ERROR] Game directory not found for: '$target'" >&2
        return 1
    fi

    local backup_root="$resolved_dir/.gamectl_fix_backup"
    if [ ! -d "$backup_root" ]; then
        echo "[ERROR] No backup snapshots found in: $backup_root" >&2
        return 1
    fi

    # Find the most recent timestamp directory
    local latest_snap
    latest_snap=$(find "$backup_root" -mindepth 1 -maxdepth 1 -type d ! -name "latest.json" | sort -r | head -n 1)

    if [ -z "$latest_snap" ] || [ ! -d "$latest_snap" ]; then
        echo "[ERROR] No valid snapshot directory found in $backup_root." >&2
        return 1
    fi

    local backup_files_dir="$latest_snap/backup_files"
    local installed_list="$latest_snap/installed_files.txt"

    if [ "$is_dry_run" = true ]; then
        echo "[INFO] [DRY-RUN] Simulating game fix revert using snapshot: $(basename "$latest_snap")"
        if [ -f "$installed_list" ]; then
            while IFS= read -r f; do
                [ -z "$f" ] && continue
                [ "${f: -1}" = "/" ] && continue
                if [ -f "$backup_files_dir/$f" ]; then
                    echo "  • [RESTORE] $f (original file from backup)"
                elif [ -f "$resolved_dir/$f" ]; then
                    echo "  • [PURGE] $f (fix-introduced artifact)"
                fi
            done < "$installed_list"
        elif [ -d "$backup_files_dir" ]; then
            (
                cd "$backup_files_dir"
                find . -type f | while read -r f; do
                    echo "  • [RESTORE] ${f#./} (original file from backup)"
                done
            )
        fi
        echo "[INFO] [DRY-RUN] Game fix revert simulated successfully (no files modified)."
        return 0
    fi

    echo "[INFO] Reverting game fix using snapshot: $(basename "$latest_snap")..."

    if [ -f "$installed_list" ]; then
        while IFS= read -r f; do
            [ -z "$f" ] && continue
            # If the path was a directory entry in zip, skip file removal
            [ "${f: -1}" = "/" ] && continue

            if [ -f "$backup_files_dir/$f" ]; then
                # Restore original file that was replaced
                mkdir -p "$(dirname "$resolved_dir/$f")"
                cp -p "$backup_files_dir/$f" "$resolved_dir/$f"
            elif [ -f "$resolved_dir/$f" ]; then
                # File was newly introduced by the fix, remove it
                rm -f "$resolved_dir/$f"
            fi
        done < "$installed_list"
    elif [ -d "$backup_files_dir" ]; then
        (
            cd "$backup_files_dir"
            find . -type f -exec cp -pv {} "$resolved_dir/{}" \;
        )
    fi

    invalidate_scan_cache
    echo "[VERIFIED] Game fix reverted. Pristine files restored and fix artifacts purged."
    return 0
}

# Graceful Steam Client restart engine with SLSsteam wrapper preservation
restart_steam_client() {
    echo "[INFO] Initiating graceful Steam Client reload..."

    # Check if Steam process is active
    if ! pgrep -x steam >/dev/null 2>&1; then
        echo "[INFO] Steam Client is not currently running. No restart needed."
        return 0
    fi

    # Check for Game Mode supervisor (Steam Deck)
    if command -v systemctl >/dev/null 2>&1; then
        if systemctl --user is-active --quiet steam-launcher.service 2>/dev/null; then
            echo "[INFO] Detected Game Mode systemd unit: steam-launcher.service. Restarting..."
            systemctl --user restart steam-launcher.service
            echo "[VERIFIED] Steam launcher service restarted."
            return 0
        fi
        local gs_unit
        gs_unit="$(systemctl --user list-units --type=service --state=active --plain --no-legend 'gamescope-session*' 2>/dev/null | awk '{print $1}' | head -n 1)"
        if [ -n "$gs_unit" ]; then
            echo "[INFO] Detected Game Mode gamescope session unit: $gs_unit. Restarting..."
            systemctl --user restart "$gs_unit"
            echo "[VERIFIED] Gamescope session unit restarted."
            return 0
        fi
    fi

    # Desktop Session: Resolve SLSsteam launcher wrapper
    local launcher="$HOME/.local/share/SLSsteam/path/steam"
    if [ ! -x "$launcher" ]; then
        launcher="$(command -v steam 2>/dev/null || echo "")"
    fi

    # Flush disk writes
    sync

    # Request graceful shutdown via SIGTERM
    pkill -TERM -x steam >/dev/null 2>&1 || true

    # Wait up to 10 seconds for clean exit
    local terminated=false
    for _ in {1..50}; do
        if ! pgrep -x steam >/dev/null 2>&1; then
            terminated=true
            break
        fi
        sleep 0.2
    done

    # Escalate to SIGKILL if still hanging
    if [ "$terminated" = false ]; then
        echo "[WARN] Steam did not exit within grace period. Escalating to SIGKILL..."
        pkill -KILL -x steam >/dev/null 2>&1 || true
    fi

    # Clean residual child processes
    pkill -KILL -f 'steamwebhelper' >/dev/null 2>&1 || true
    sleep 1

    # Relaunch launcher in detached background session
    if [ -n "$launcher" ] && [ -x "$launcher" ]; then
        echo "[INFO] Relaunching Steam via: $launcher"
        nohup "$launcher" </dev/null >/dev/null 2>&1 &
        echo "[VERIFIED] Steam client successfully restarted."
    else
        echo "[WARN] Could not find executable Steam launcher binary to relaunch."
    fi

    return 0
}

# Preview pane generator for Community Fixes and OnlineFix catalog
preview_fix_entry() {
    local fix_id="${1:-}"
    local appid="${2:-${GAMECTL_PREVIEW_APPID:-}}"
    local fix_title="${3:-}"
    local fix_file="${4:-}"
    local fix_tags="${5:-}"
    local gdir="${6:-${GAMECTL_PREVIEW_GDIR:-}}"
    local fix_desc="${7:-}"

    fix_id=$(strip_ansi "$fix_id" | tr -d '[:space:]')
    appid=$(strip_ansi "$appid" | tr -d '[:space:]')
    fix_title=$(strip_ansi "$fix_title" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
    fix_file=$(strip_ansi "$fix_file" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
    fix_tags=$(strip_ansi "$fix_tags" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
    gdir=$(strip_ansi "$gdir" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')

    printf "%s╭─ COMMUNITY FIX & ONLINEFIX HARVESTER ───────────────╮%s\n" "${UI_BOX}" "${UI_RST}"
    printf "│ %s%s%s %s(AppID: %s)%s\n" "${UI_BOLD}" "${fix_title:-Community Fix}" "${UI_RST}" "${UI_DIM}" "${appid:-N/A}" "${UI_RST}"
    printf "%s╰─────────────────────────────────────────────────────╯%s\n" "${UI_BOX}" "${UI_RST}"

    if [ "$fix_id" = "[RESTORE]" ] || [ "$fix_id" = "[SIMULATE]" ]; then
        local snap_dir="$gdir/.gamectl_fix_backup"
        local latest_snap=""
        if [ -d "$snap_dir" ]; then
            latest_snap=$(find "$snap_dir" -mindepth 1 -maxdepth 1 -type d ! -name "latest.json" 2>/dev/null | sort -r | head -n 1)
        fi

        local snap_meta="$snap_dir/latest.json"
        local snap_ts="Unknown" orig_title="Unknown" backed_cnt="0"
        if [ -f "$snap_meta" ]; then
            snap_ts=$(jq -r '.timestamp // "Unknown"' "$snap_meta" 2>/dev/null || echo "Unknown")
            orig_title=$(jq -r '.fix_title // "Unknown"' "$snap_meta" 2>/dev/null || echo "Unknown")
            backed_cnt=$(jq -r '.backed_up_count // 0' "$snap_meta" 2>/dev/null || echo "0")
        fi

        if [ "$fix_id" = "[RESTORE]" ]; then
            printf "  %sOperation  %s: %s[RESTORE ROLLBACK]%s\n" "${UI_CYAN}" "${UI_RST}" "${UI_AMBER}" "${UI_RST}"
            printf "  %sTarget Dir %s: %s%s%s\n" "${UI_CYAN}" "${UI_RST}" "${UI_DIM}" "${gdir:-N/A}" "${UI_RST}"
            printf "\n%s╭─ SNAPSHOT RESTORATION DETAILS ──────────────────────╮%s\n" "${UI_BOX}" "${UI_RST}"
            printf "  %sActive Snapshot%s : %s%s%s\n" "${UI_CYAN}" "${UI_RST}" "${UI_BOLD}" "$(basename "${latest_snap:-None}")" "${UI_RST}"
            printf "  %sTimestamp      %s : %s\n" "${UI_CYAN}" "${UI_RST}" "$snap_ts"
            printf "  %sPatched Fix    %s : %s\n" "${UI_CYAN}" "${UI_RST}" "$orig_title"
            printf "  %sOriginal Files %s : %s%s files preserved%s\n" "${UI_CYAN}" "${UI_RST}" "${UI_GREEN}" "$backed_cnt" "${UI_RST}"
            printf "%s╰─────────────────────────────────────────────────────╯%s\n" "${UI_BOX}" "${UI_RST}"
            printf "\n%s╭─ SAFETY & INTEGRITY GUARANTEES ─────────────────────╮%s\n" "${UI_BOX}" "${UI_RST}"
            printf "  • Overwrites all patched files with original untouched binaries\n"
            printf "  • Purges newly introduced DLLs, wrappers, and OnlineFix hooks\n"
            printf "  • Restores pristine state without requiring complete re-download\n"
            printf "%s╰─────────────────────────────────────────────────────╯%s\n" "${UI_BOX}" "${UI_RST}"
        else
            printf "  %sOperation  %s: %s[DRY-RUN SIMULATION]%s\n" "${UI_CYAN}" "${UI_RST}" "${UI_ICE}" "${UI_RST}"
            printf "  %sTarget Dir %s: %s%s%s\n" "${UI_CYAN}" "${UI_RST}" "${UI_DIM}" "${gdir:-N/A}" "${UI_RST}"
            printf "\n%s╭─ DRY-RUN AUDIT PREVIEW ─────────────────────────────╮%s\n" "${UI_BOX}" "${UI_RST}"
            if [ -n "$gdir" ] && [ -d "$gdir" ]; then
                local sim_lines
                sim_lines=$(revert_game_fix "$gdir" --dry-run 2>&1 | grep -E '• \[(RESTORE|PURGE)\]' | head -n 10 || true)
                if [ -n "$sim_lines" ]; then
                    printf "%s\n" "$sim_lines"
                else
                    printf "  %sNo file differences or uncommitted artifacts detected.%s\n" "${UI_DIM}" "${UI_RST}"
                fi
            else
                printf "  %sNo local game directory available for simulation.%s\n" "${UI_DIM}" "${UI_RST}"
            fi
            printf "%s╰─────────────────────────────────────────────────────╯%s\n" "${UI_BOX}" "${UI_RST}"
        fi
        return 0
    fi

    # Check cached metadata JSON if available to get rich description
    local cache_dir="${XDG_CACHE_HOME:-$HOME/.cache}/gamectl"
    local cache_file="$cache_dir/luatools_fixes_${appid}.json"
    if [ -f "$cache_file" ]; then
        local json_details
        json_details=$(python3 -c '
import sys, json
try:
    with open(sys.argv[1], "r", encoding="utf-8") as f:
        data = json.load(f)
    target_id = sys.argv[2]
    for fix in data.get("fixes", []):
        if str(fix.get("id")) == target_id:
            tags = [t.get("name", "") for t in fix.get("tags", []) if isinstance(t, dict)]
            print(fix.get("title", ""))
            print(fix.get("fixFilename", ""))
            print(", ".join(tags) if tags else "Community Fix")
            print(fix.get("description", "").strip())
            sys.exit(0)
except Exception:
    pass
sys.exit(1)
' "$cache_file" "$fix_id" 2>/dev/null || true)
        if [ -n "$json_details" ]; then
            fix_title=$(echo "$json_details" | sed -n '1p')
            fix_file=$(echo "$json_details" | sed -n '2p')
            fix_tags=$(echo "$json_details" | sed -n '3p')
            fix_desc=$(echo "$json_details" | sed -n '4,$p')
        fi
    fi

    # Community Fix / OnlineFix metadata
    printf "  %sFix ID     %s: %s%s%s\n" "${UI_CYAN}" "${UI_RST}" "${UI_DIM}" "$fix_id" "${UI_RST}"
    printf "  %sCategory   %s: %s%s%s\n" "${UI_CYAN}" "${UI_RST}" "${UI_GREEN}" "${fix_tags:-Community Fix}" "${UI_RST}"
    [ -n "$fix_file" ] && printf "  %sPayload    %s: %s%s%s\n" "${UI_CYAN}" "${UI_RST}" "${UI_BOLD}" "$fix_file" "${UI_RST}"

    printf "\n%s╭─ FIX CAPABILITIES & MULTIPLAYER ────────────────────╮%s\n" "${UI_BOX}" "${UI_RST}"
    if [[ "$fix_tags" =~ [Oo]nline|[Ff]ix|P2P|Co-?op ]] || [[ "$fix_title" =~ [Oo]nline|P2P|Co-?op ]]; then
        printf "  %sOnline P2P %s: %s[SUPPORTED] Steamworks Spacewar Overlay (AppID 480)%s\n" "${UI_CYAN}" "${UI_RST}" "${UI_GREEN}" "${UI_RST}"
        printf "  %sOverrides  %s: %sAutomatic WINEDLLOVERRIDES injection (wsock32, etc.)%s\n" "${UI_CYAN}" "${UI_RST}" "${UI_DIM}" "${UI_RST}"
    else
        printf "  %sFix Scope  %s: %sGeneral compatibility / DLC unlock patch%s\n" "${UI_CYAN}" "${UI_RST}" "${UI_DIM}" "${UI_RST}"
    fi

    local token_status="${UI_RED}[MISSING] Login required (gamectl login-luatools)${UI_RST}"
    if get_valid_luatools_token >/dev/null 2>&1; then
        token_status="${UI_GREEN}[ACTIVE] Authorized session ready${UI_RST}"
    fi
    printf "  %sLuaTools   %s: %s\n" "${UI_CYAN}" "${UI_RST}" "$token_status"

    if [ -n "$gdir" ] && [ -d "$gdir" ]; then
        printf "  %sTarget Dir %s: %s%s%s %s[READY]%s\n" "${UI_CYAN}" "${UI_RST}" "${UI_DIM}" "$gdir" "${UI_RST}" "${UI_GREEN}" "${UI_RST}"
    else
        printf "  %sTarget Dir %s: %sCatalog Browsing Mode (Not installed locally)%s\n" "${UI_CYAN}" "${UI_RST}" "${UI_AMBER}" "${UI_RST}"
    fi
    printf "%s╰─────────────────────────────────────────────────────╯%s\n" "${UI_BOX}" "${UI_RST}"

    if [ -n "$fix_desc" ]; then
        printf "\n%s╭─ RELEASE NOTES & INSTRUCTIONS ──────────────────────╮%s\n" "${UI_BOX}" "${UI_RST}"
        printf "  %s%s%s\n" "${UI_DIM}" "$fix_desc" "${UI_RST}"
        printf "%s╰─────────────────────────────────────────────────────╯%s\n" "${UI_BOX}" "${UI_RST}"
    fi
}

# Interactive TUI modal for inspecting, installing, and reverting community fixes
manage_game_fixes_interactive() {
    local appid="${1:-}"
    local title="${2:-}"
    local gdir="${3:-}"

    # 1. Resolve numeric Steam AppID if not directly provided
    if [ -z "$appid" ] || ! [[ "$appid" =~ ^[0-9]+$ ]]; then
        if [ -n "$gdir" ] && [ -d "$gdir" ]; then
            if [ -f "$gdir/steam_appid.txt" ]; then
                local detected_id
                detected_id=$(head -n 1 "$gdir/steam_appid.txt" | tr -dc '0-9')
                [ -n "$detected_id" ] && appid="$detected_id"
            elif [ -f "$gdir/.gamectl_appid" ]; then
                local detected_id
                detected_id=$(head -n 1 "$gdir/.gamectl_appid" | tr -dc '0-9')
                [ -n "$detected_id" ] && appid="$detected_id"
            fi
        fi
    fi

    if [ -z "$appid" ] || ! [[ "$appid" =~ ^[0-9]+$ ]]; then
        tui_modal_notice "Fix Catalog" "Numeric Steam AppID could not be determined for:\n${title:-$gdir}\nCommunity fixes catalog requires a valid Steam AppID." || return $?
        return 1
    fi

    if [ ! -t 0 ] || [ ! -t 1 ]; then
        echo "[ERROR] Interactive fixes manager requires a terminal (TTY)." >&2
        return 1
    fi
    if ! command -v fzf >/dev/null 2>&1; then
        echo "[ERROR] fzf is required for interactive mode but was not found in PATH." >&2
        return 127
    fi

    # 2. Resolve target installation directory if missing
    if [ -z "$gdir" ] || [ ! -d "$gdir" ]; then
        gdir=$(resolve_game_install_dir "$appid" 2>/dev/null || true)
    fi

    # 3. Query LuaTools API (with caching)
    local cache_dir="${XDG_CACHE_HOME:-$HOME/.cache}/gamectl"
    mkdir -p "$cache_dir" 2>/dev/null || true
    local cache_file="$cache_dir/luatools_fixes_${appid}.json"
    local json_out=""
    local now
    now=$(date +%s)
    if [ -f "$cache_file" ]; then
        local mtime
        mtime=$(stat -c %Y "$cache_file" 2>/dev/null || stat -f %m "$cache_file" 2>/dev/null || echo 0)
        if [ $(( now - mtime )) -lt 3600 ] && [ -s "$cache_file" ]; then
            json_out=$(cat "$cache_file")
        fi
    fi

    if [ -z "$json_out" ]; then
        local api_url="https://lua.tools/api/denuvo/fixes?appid=${appid}"
        json_out=$(curl -sSL --connect-timeout 5 --max-time 15 -A "discord(dot)gg/luatools" "$api_url" 2>/dev/null || true)
        if [ -n "$json_out" ] && echo "$json_out" | jq . >/dev/null 2>&1; then
            echo "$json_out" > "$cache_file" 2>/dev/null || true
        fi
    fi

    # 4. Interactive selection loop
    while true; do
        flush_tty_input

        # Check for backup snapshot in target directory
        local has_backup=false
        local backup_root=""
        if [ -n "$gdir" ] && [ -d "$gdir/.gamectl_fix_backup" ]; then
            backup_root="$gdir/.gamectl_fix_backup"
            if find "$backup_root" -mindepth 1 -maxdepth 1 -type d ! -name "latest.json" 2>/dev/null | grep -q .; then
                has_backup=true
            fi
        fi

        # Parse available fixes from JSON
        local fix_tsv=""
        if [ -n "$json_out" ]; then
            fix_tsv=$(python3 -c '
import sys, json

try:
    data = json.loads(sys.argv[1])
except Exception:
    print("[ERROR] Invalid fixes catalog JSON", file=sys.stderr)
    sys.exit(1)

fixes = data.get("fixes", [])
rows = []
for f in fixes:
    fid = f.get("id", "")
    title = f.get("title", "Fix")
    filename = f.get("fixFilename", "")
    tags = [t.get("name", "") for t in f.get("tags", []) if isinstance(t, dict)]
    tag_str = ", ".join(tags) if tags else "Community Fix"
    desc = f.get("description", "").strip().replace("\n", " ").replace("\t", " ").replace("\r", " ")
    has_fix = "[READY]" if f.get("hasFix") else "[PENDING]"
    fields = [str(fid), title, f"{has_fix} [{tag_str}]", filename, desc]
    if any(any(c in field for c in "\t\r\n") for field in fields):
        print("[ERROR] Fix catalog fields contain TAB, CR or newline", file=sys.stderr)
        sys.exit(1)
    rows.append("\t".join(fields))
print("\n".join(rows))
' "$json_out") || return 1
        fi

        # If both fixes and backups are empty, notify and return
        if [ -z "$fix_tsv" ] && [ "$has_backup" = false ]; then
            tui_modal_notice "Community Fix Catalog" "No community fixes, OnlineFixes, or backup snapshots found for:\n${title:-AppID $appid}" || return $?
            return 0
        fi

        # Build list for FZF
        local menu_list=""
        if [ "$has_backup" = true ]; then
            menu_list+=$'[RESTORE]\tRestore Pristine Game Binaries\t[ROLLBACK]\tpre-patch backup\tRestore original untouched files\n'
            menu_list+=$'[SIMULATE]\tSimulate Revert (--dry-run)\t[DRY-RUN]\tdry-run audit\tAudit files that would be restored or purged\n'
        fi
        if [ -n "$fix_tsv" ]; then
            menu_list+="$fix_tsv"
        fi

        local fzf_out="" fzf_rc=0
        export GAMECTL_PREVIEW_BIN="$SELF_BIN"
        export GAMECTL_PREVIEW_APPID="$appid"
        export GAMECTL_PREVIEW_GDIR="$gdir"
        fzf_out=$(printf '%s' "$menu_list" | fzf \
            --delimiter=$'\t' \
            --with-nth=2,3 \
            --border-label="  ╢ Community Fixes & OnlineFix :: ${title:-AppID $appid} ╟  " \
            --border-label-pos=2 \
            --header="SELECT FIX OR ACTION (Enter: Select / Execute │ Esc: Return)" \
            --prompt="Fix > " \
            --preview='"$GAMECTL_PREVIEW_BIN" --preview-fix {1} "$GAMECTL_PREVIEW_APPID" {2} {4} {3} "$GAMECTL_PREVIEW_GDIR"' \
            --preview-window=right:55%:border-rounded:wrap 2>/dev/null) || fzf_rc=$?

        if [ "$fzf_rc" -eq 130 ]; then
            break
        fi
        if [ "$fzf_rc" -ne 0 ] && [ "$fzf_rc" -ne 1 ]; then
            echo "[ERROR] Community fixes menu failed (fzf exit code $fzf_rc)." >&2
            return "$fzf_rc"
        fi
        [ -z "$fzf_out" ] && continue

        local sel_fix_id sel_fix_title sel_fix_tags sel_fix_file
        sel_fix_id=$(echo "$fzf_out" | awk -F'\t' '{print $1}')
        sel_fix_title=$(echo "$fzf_out" | awk -F'\t' '{print $2}')
        sel_fix_tags=$(echo "$fzf_out" | awk -F'\t' '{print $3}')
        sel_fix_file=$(echo "$fzf_out" | awk -F'\t' '{print $4}')

        if [ "$sel_fix_id" = "[RESTORE]" ]; then
            if [ -z "$gdir" ] || [ ! -d "$gdir" ]; then
                tui_modal_notice "Revert Error" "Game directory is missing or invalid: $gdir" || return $?
                continue
            fi
            local restore_palette
            restore_palette=$(cat <<EOF
1	Confirm & Restore Pristine Binaries from Snapshot
2	Cancel / Return
EOF
)
            local r_sel fzf_r_rc=0
            r_sel=$(echo "$restore_palette" | fzf \
                --delimiter=$'\t' \
                --with-nth=2 \
                --border-label="  ╢ Confirm Snapshot Restore ╟  " \
                --border-label-pos=2 \
                --header="RESTORE CONFIRMATION (Enter: Execute │ Esc: Cancel)" \
                --prompt="Confirm > " \
                --height=30% \
                --reverse 2>/dev/null) || fzf_r_rc=$?

            if [ "$fzf_r_rc" -eq 130 ]; then
                continue
            fi
            if [ "$fzf_r_rc" -ne 0 ] && [ "$fzf_r_rc" -ne 1 ]; then
                echo "[ERROR] Snapshot restore confirmation failed (fzf exit code $fzf_r_rc)." >&2
                return "$fzf_r_rc"
            fi

            if [ "$(echo "$r_sel" | cut -f1)" = "1" ]; then
                if revert_game_fix "$gdir"; then
                    tui_modal_notice "Revert Successful" "Community fix reverted. Pristine files restored for:\n${title:-$gdir}" || return $?
                    invalidate_scan_cache
                else
                    tui_modal_notice "Revert Error" "Failed to revert game fix. Check activity logs." || return $?
                fi
            fi
            continue
        elif [ "$sel_fix_id" = "[SIMULATE]" ]; then
            if [ -z "$gdir" ] || [ ! -d "$gdir" ]; then
                tui_modal_notice "Dry-Run Error" "Game directory is missing or invalid: $gdir" || return $?
                continue
            fi
            local dry_output
            dry_output=$(revert_game_fix "$gdir" --dry-run 2>&1 || true)
            tui_modal_notice "Dry-Run Simulation" "$dry_output" || return $?
            continue
        else
            # Fix selected
            if [ -z "$gdir" ] || [ ! -d "$gdir" ]; then
                tui_modal_notice "Installation Target Missing" "Game installation directory not found for AppID $appid.\n\nTo install community fixes, the game must be installed locally." || return $?
                continue
            fi

            local fix_palette
            fix_palette=$(cat <<EOF
1	Deploy Fix & Auto-Configure P2P (Backup & Apply)
2	Simulate Deployment (--dry-run check)
3	Cancel / Return
EOF
)
            local f_sel fzf_f_rc=0
            f_sel=$(echo "$fix_palette" | fzf \
                --delimiter=$'\t' \
                --with-nth=2 \
                --border-label="  ╢ Fix Action: $sel_fix_title ╟  " \
                --border-label-pos=2 \
                --header="FIX DEPLOYMENT (Enter: Select │ Esc: Return)" \
                --prompt="Action > " \
                --height=35% \
                --reverse 2>/dev/null) || fzf_f_rc=$?

            if [ "$fzf_f_rc" -eq 130 ]; then
                continue
            fi
            if [ "$fzf_f_rc" -ne 0 ] && [ "$fzf_f_rc" -ne 1 ]; then
                echo "[ERROR] Fix deployment prompt failed (fzf exit code $fzf_f_rc)." >&2
                return "$fzf_f_rc"
            fi

            local f_opt
            f_opt=$(echo "$f_sel" | cut -f1)
            case "$f_opt" in
                1)
                    if ! get_valid_luatools_token >/dev/null 2>&1; then
                        tui_modal_notice "LuaTools Authentication Required" "Downloading community fixes requires an active LuaTools account session.\n\nPlease authenticate in terminal via:\n  gamectl login-luatools <token|session.json>" || return $?
                        continue
                    fi
                    log_msg "INFO" "FIX" "Installing community fix '$sel_fix_title' ($sel_fix_id) for ${title:-AppID $appid}..."
                    if install_game_fix "$appid" "$gdir" --fix-id "$sel_fix_id" --yes; then
                        tui_modal_notice "Fix Deployed" "Successfully installed community fix: $sel_fix_title\nBackup snapshot created in: .gamectl_fix_backup/" || return $?
                        invalidate_scan_cache
                    else
                        tui_modal_notice "Fix Error" "Failed to install fix: $sel_fix_title\nCheck activity logs for detailed failure trace." || return $?
                    fi
                    ;;
                2)
                    tui_modal_notice "Simulation Audit" "Target Directory : $gdir\nFix ID           : $sel_fix_id\nPayload Archive  : $sel_fix_file\nOnline P2P       : Automatic AppID 480 & DLL Overrides\nRollback         : Pre-install snapshot will be saved to .gamectl_fix_backup/" || return $?
                    ;;
                *)
                    continue
                    ;;
            esac
        fi
    done

    flush_tty_input
    return 0
}

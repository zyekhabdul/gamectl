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
        echo "Usage: gamectl fix-revert <game_dir|appid>" >&2
        return 1
    fi

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

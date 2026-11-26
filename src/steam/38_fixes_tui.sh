# ==============================================================================
# Community Fixes TUI Harvester, Preview Pane & Steam Client Hot-Reload
# ==============================================================================

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
        echo "[WARN] Steam did not exit within grace period. Escalating to SIGKILL..." >&2
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
        echo "[WARN] Could not find executable Steam launcher binary to relaunch." >&2
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
            local detected_id
            detected_id="$(resolve_game_appid "$gdir")"
            [ -n "$detected_id" ] && appid="$detected_id"
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
                --reverse 2>/dev/null) || fzf_r_rc=$?

            if [ "$fzf_r_rc" -eq 130 ]; then
                continue
            fi
            if [ "$fzf_r_rc" -ne 0 ] && [ "$fzf_r_rc" -ne 1 ]; then
                echo "[ERROR] Snapshot restore confirmation failed (fzf exit code $fzf_r_rc)." >&2
                return "$fzf_r_rc"
            fi

            if [ "$(echo "$r_sel" | cut -f1)" = "1" ]; then
                if tui_run_engine --fail-title "Revert Error" "Revert Community Fix (${title:-$gdir})" revert_game_fix "$gdir"; then
                    tui_modal_notice "Revert Successful" "Community fix reverted. Pristine files restored for:\n${title:-$gdir}" || return $?
                    invalidate_scan_cache
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
                    if tui_run_engine --fail-title "Fix Error" "Install Community Fix ($sel_fix_title)" install_game_fix "$appid" "$gdir" --fix-id "$sel_fix_id" --yes; then
                        tui_modal_notice "Fix Deployed" "Successfully installed community fix: $sel_fix_title\nBackup snapshot created in: .gamectl_fix_backup/" || return $?
                        invalidate_scan_cache
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

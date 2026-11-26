# Deploy manifest archive into SLSsteam manifests, stplug-in Lua, and config.yaml
deploy_sls_manifest() {
    local appid="$1"
    local manifest_zip="${2:-}"
    local title="${3:-}"
    local source="${4:-auto}"

    # Strip ANSI escape sequences
    appid=$(strip_ansi "$appid" | tr -dc "0-9")
    title=$(strip_ansi "$title")

    if [ -z "$appid" ]; then
        echo "[ERROR] deploy_sls_manifest: Invalid numeric AppID." >&2
        return 1
    fi

    # 1. Acquire manifest archive if not provided
    if [ -z "$manifest_zip" ] || [ ! -f "$manifest_zip" ]; then
        echo "[INFO] Manifest archive not provided. Attempting automatic harvest (source: $source)..." >&2
        manifest_zip=$(fetch_manifest "$appid" "" "$source" 2>/dev/null || true)
        if [ -z "$manifest_zip" ] || [ ! -f "$manifest_zip" ]; then
            echo "[ERROR] Could not acquire manifest archive for AppID $appid." >&2
            return 1
        fi
    fi

    if ! validate_manifest_zip "$manifest_zip" "$appid"; then
        echo "[ERROR] Manifest zip validation failed: $manifest_zip" >&2
        return 1
    fi

    local run_dir
    run_dir="$(get_runtime_dir)"
    local stage_dir="$run_dir/sls_deploy_${appid}_$$"
    mkdir -p -m 700 "$stage_dir"
    trap 'rm -rf "$stage_dir" 2>/dev/null || true' RETURN

    if ! unzip -q "$manifest_zip" -d "$stage_dir" 2>/dev/null; then
        echo "[ERROR] Failed to unpack manifest archive: $manifest_zip" >&2
        return 1
    fi

    local sls_mf_dir
    sls_mf_dir="$(get_sls_manifests_dir 2>/dev/null || echo "$HOME/.config/SLSsteam/manifests")"
    local steam_depot_dir
    steam_depot_dir="$(get_steam_depotcache_dir 2>/dev/null || echo "$HOME/.local/share/Steam/depotcache")"
    local stplug_dir
    stplug_dir="$(get_steam_stplug_in_dir 2>/dev/null || echo "$HOME/.local/share/Steam/config/stplug-in")"

    mkdir -p -m 700 "$sls_mf_dir" "$steam_depot_dir" "$stplug_dir"

    local manifest_count=0
    declare -A pinned_depots=()

    # 2. Process and deploy binary manifests
    shopt -s nullglob globstar
    local mf_files=("$stage_dir"/**/*.manifest "$stage_dir"/*.manifest)
    declare -A seen_mf=()
    for mf in "${mf_files[@]}"; do
        [ -f "$mf" ] || continue
        local mf_name
        mf_name="$(basename "$mf")"
        [[ -v seen_mf["$mf_name"] ]] && continue
        seen_mf["$mf_name"]=1

        if manifest_has_payload_magic "$mf"; then
            cp -f "$mf" "$sls_mf_dir/$mf_name"
            chmod 600 "$sls_mf_dir/$mf_name"

            # Mirror to Steam internal depotcache
            cp -f "$mf" "$steam_depot_dir/$mf_name"
            chmod 600 "$steam_depot_dir/$mf_name"

            # Parse depot and GID from <depot>_<gid>.manifest
            if [[ "$mf_name" =~ ^([0-9]+)_([0-9]+)\.manifest$ ]]; then
                local depot_id="${BASH_REMATCH[1]}"
                local gid="${BASH_REMATCH[2]}"
                echo "$gid" > "$sls_mf_dir/.preferred_${depot_id}"
                chmod 600 "$sls_mf_dir/.preferred_${depot_id}"
                pinned_depots["$depot_id"]="$gid"
            fi
            manifest_count=$((manifest_count + 1))
        fi
    done
    shopt -u nullglob globstar

    # 3. Extract or synthesize stplug-in Lua script
    local target_lua="$stplug_dir/${appid}.lua"
    local staged_lua=""
    if [ -f "$stage_dir/${appid}.lua" ]; then
        staged_lua="$stage_dir/${appid}.lua"
    else
        shopt -s nullglob globstar
        local app_luas=("$stage_dir"/**/"${appid}.lua")
        if [ "${#app_luas[@]}" -gt 0 ]; then
            staged_lua="${app_luas[0]}"
        else
            local candidate_luas=("$stage_dir"/**/*.lua "$stage_dir"/*.lua)
            if [ "${#candidate_luas[@]}" -eq 1 ]; then
                staged_lua="${candidate_luas[0]}"
            fi
        fi
        shopt -u nullglob globstar
    fi

    if [ -n "$staged_lua" ] && [ -f "$staged_lua" ]; then
        cp -f "$staged_lua" "$target_lua"
        if ! grep -Eq "^[[:space:]]*addappid[[:space:]]*\([[:space:]]*${appid}[[:space:]]*\)" "$target_lua"; then
            atomic_prepend_line "$target_lua" "addappid(${appid})" || return 1
        fi
        chmod 600 "$target_lua"
        echo "[VERIFIED] Stplug-in Lua deployed from archive: $target_lua" >&2
    else
        echo "[INFO] Synthesizing stplug-in Lua script for AppID $appid..." >&2
        local synth_lua="addappid($appid)\n"
        for d_id in "${!pinned_depots[@]}"; do
            synth_lua+="addappid($d_id)\n"
        done
        printf "%b" "$synth_lua" > "$target_lua"
        chmod 600 "$target_lua"
        echo "[VERIFIED] Synthesized stplug-in Lua: $target_lua" >&2
    fi

    # 4. Synchronize entitlement in SLSsteam config.yaml (skipping ACF creation)
    sync_steam "$appid" "$title" "--no-acf"

    echo "[VERIFIED] SLSsteam deployment complete for AppID $appid ($manifest_count manifest(s) linked)." >&2
    return 0
}

# Trigger Steam client native installation for AppID via URI protocol
trigger_steam_install() {
    local appid="$1"
    local uri="steam://install/${appid}"

    if [ -n "${GAMECTL_MOCK_STEAM_TRIGGER:-}" ]; then
        echo "[VERIFIED] Triggered Steam installation for AppID $appid (Mocked URI: $uri)."
        return 0
    fi

    if command -v steam >/dev/null 2>&1; then
        if pgrep -x steam >/dev/null 2>&1; then
            echo "[INFO] Steam client is running. Dispatching install command..."
            steam "$uri" >/dev/null 2>&1 &
            echo "[VERIFIED] Dispatched '$uri' to running Steam client."
        else
            echo "[INFO] Steam client is not running. Starting Steam client in background..."
            steam -silent "$uri" >/dev/null 2>&1 &
            echo "[VERIFIED] Launched Steam silently with install intent ($uri)."
        fi
    elif command -v flatpak >/dev/null 2>&1 && flatpak info com.valvesoftware.Steam >/dev/null 2>&1; then
        if pgrep -f com.valvesoftware.Steam >/dev/null 2>&1 || pgrep -x steam >/dev/null 2>&1; then
            echo "[INFO] Steam (Flatpak) is running. Dispatching install command..."
            flatpak run com.valvesoftware.Steam "$uri" >/dev/null 2>&1 &
            echo "[VERIFIED] Dispatched '$uri' to running Steam Flatpak client."
        else
            echo "[INFO] Steam (Flatpak) is not running. Starting Flatpak Steam in background..."
            flatpak run com.valvesoftware.Steam -silent "$uri" >/dev/null 2>&1 &
            echo "[VERIFIED] Launched Steam Flatpak silently with install intent ($uri)."
        fi
    else
        echo "[WARN] Steam executable not found on system PATH." >&2
        echo "[INFO] You can start the download manually by opening: $uri" >&2
    fi
    echo "[INFO] Monitor download progress with: gamectl downloads"
    return 0
}

# Dual-Mode Steam Client & SLSsteam Full DLC Sync
sync_steam() {
    local appid="$1"
    local title="${2:-}"
    local game_dir="${3:-}"

    # Strip ANSI escape sequences
    appid=$(strip_ansi "$appid" | tr -dc '0-9')
    title=$(strip_ansi "$title")

    if [ -z "$appid" ] || [ "$appid" = "STANDALONE" ]; then
        echo "[WARN] Invalid numeric AppID. Skipping Steam synchronization." >&2
        return 0
    fi

    if [ -z "$title" ]; then
        title="AppID_${appid}"
    fi

    local safe_title
    safe_title=$(echo "$title" | tr -cd '[:alnum:] _-')
    [ -z "$safe_title" ] && safe_title="$appid"

    echo "[INFO] Synchronizing Steam Client & SLSsteam for: $title ($appid)..."

    # 1. Fetch DLC mapping via Steam API (disk-cached 3600s)
    local dlc_json
    dlc_json=$(fetch_cached_json "https://store.steampowered.com/api/dlcforapp/?appid=${appid}" "steam_dlc_${appid}" 3600 2>/dev/null || echo "{}")
    [ -z "$dlc_json" ] && dlc_json="{}"

    # 2. Update ~/.config/SLSsteam/config.yaml using ruamel.yaml
    local sls_cfg; sls_cfg="$(get_sls_root 2>/dev/null || echo "$HOME/.config/SLSsteam")/config.yaml"
    if [ -f "$sls_cfg" ]; then
        python3 -c "
import sys, json

cfg_path = sys.argv[1]
appid = int(sys.argv[2])
dlc_raw = sys.argv[3]

has_ruamel = False
try:
    from ruamel.yaml import YAML
    yaml_engine = YAML()
    yaml_engine.preserve_quotes = True
    has_ruamel = True
except Exception:
    try:
        import yaml as pyyaml
    except Exception:
        print('[ERROR] No YAML library found in Python (ruamel.yaml or pyyaml)', file=sys.stderr)
        sys.exit(1)

try:
    with open(cfg_path, 'r') as f:
        if has_ruamel:
            data = yaml_engine.load(f) or {}
        else:
            data = pyyaml.safe_load(f) or {}

    if 'AppIds' not in data or data['AppIds'] is None:
        data['AppIds'] = []
    if appid not in data['AppIds']:
        data['AppIds'].append(appid)

    if 'AdditionalApps' not in data or data['AdditionalApps'] is None:
        data['AdditionalApps'] = []
    if appid not in data['AdditionalApps']:
        data['AdditionalApps'].append(appid)

    dlc_obj = json.loads(dlc_raw)
    dlc_list = dlc_obj.get('dlc', [])
    if dlc_list:
        if 'DlcData' not in data or data['DlcData'] is None:
            data['DlcData'] = {}
        if appid not in data['DlcData'] or data['DlcData'][appid] is None:
            data['DlcData'][appid] = {}
        for item in dlc_list:
            d_id = int(item['id'])
            d_name = item.get('name', f'DLC {d_id}')
            data['DlcData'][appid][d_id] = d_name

    with open(cfg_path, 'w') as f:
        if has_ruamel:
            yaml_engine.dump(data, f)
        else:
            pyyaml.dump(data, f, default_flow_style=False, sort_keys=False)
    engine_name = 'ruamel.yaml' if has_ruamel else 'pyyaml (fallback)'
    print(f'[VERIFIED] SLSsteam config.yaml: AppID {appid} and {len(dlc_list)} DLC(s) registered ({engine_name}).')
except Exception as e:
    print(f'[WARN] SLSsteam config sync notice: {e}', file=sys.stderr)
" "$sls_cfg" "$appid" "$dlc_json" 2>/dev/null || true
    fi

    # 2b. Guarantee stplug-in Lua script has addappid($appid) entitlement
    local stplug_dir
    stplug_dir="$(get_steam_stplug_in_dir 2>/dev/null || echo "$HOME/.local/share/Steam/config/stplug-in")"
    if [ -d "$stplug_dir" ]; then
        local target_lua="$stplug_dir/${appid}.lua"
        if [ -f "$target_lua" ]; then
            if ! grep -Eq "^[[:space:]]*addappid[[:space:]]*\([[:space:]]*${appid}[[:space:]]*\)" "$target_lua"; then
                atomic_prepend_line "$target_lua" "addappid(${appid})" || echo "[WARN] Failed to update entitlement in $target_lua" >&2
            fi
        else
            printf "addappid(%s)\n" "$appid" > "$target_lua"
            chmod 600 "$target_lua"
        fi
    fi

    # 3. Create appmanifest_<appid>.acf in Steam steamapps (unless --no-acf requested)
    if [ "${game_dir:-}" = "--no-acf" ] || [ "${4:-}" = "--no-acf" ]; then
        return 0
    fi

    local steam_apps
    steam_apps="$(get_steam_primary_apps 2>/dev/null || echo "$HOME/.local/share/Steam/steamapps")"
    if [ ! -d "$steam_apps" ]; then
        echo "  ${UI_AMBER}[NOTE] Steam steamapps directory not found at $steam_apps.${UI_RST}"
        echo "  ${UI_DIM}Physical ACF manifest deferred.${UI_RST}"
        log_msg "INFO" "STEAM" "Steam steamapps directory not found at $steam_apps; ACF creation deferred"
        invalidate_scan_cache
        return 2
    fi

    # Guard against concurrent Steam client memory lock on manifests
    check_steam_active "Writing appmanifest_${appid}.acf" || true

    local resolved_dir="$game_dir"
    if [ -z "$resolved_dir" ]; then
        if [ -d "$steam_apps/common/$safe_title" ] && [ -n "$(find "$steam_apps/common/$safe_title" -mindepth 1 -maxdepth 1 2>/dev/null | head -n 1)" ]; then
            resolved_dir="$steam_apps/common/$safe_title"
        elif [ -d "$steam_apps/common/$title" ] && [ -n "$(find "$steam_apps/common/$title" -mindepth 1 -maxdepth 1 2>/dev/null | head -n 1)" ]; then
            resolved_dir="$steam_apps/common/$title"
        fi
    fi

    # Cross-Library physical file discovery across all active game libraries
    if [ -z "$resolved_dir" ]; then
        local sc_id sc_name sc_st sc_dir sc_bin
        local clean_target="${title,,}"
        while IFS=$'\t' read -r sc_id sc_name sc_st sc_dir sc_bin; do
            sc_id="${sc_id//[[:space:]]/}"
            sc_dir="${sc_dir//$'\r'/}"
            if [ -n "$sc_id" ] && [ "$sc_id" = "$appid" ] && [ -d "$sc_dir" ] && [ -n "$(find "$sc_dir" -mindepth 1 -maxdepth 1 2>/dev/null | head -n 1)" ]; then
                resolved_dir="$sc_dir"
                break
            fi
            local cur_clean="${sc_name,,}"
            cur_clean="${cur_clean#"${cur_clean%%[![:space:]]*}"}"
            cur_clean="${cur_clean%"${cur_clean##*[![:space:]]}"}"
            if [ -n "$cur_clean" ] && [ "$cur_clean" = "$clean_target" ] && [ -d "$sc_dir" ] && [ -n "$(find "$sc_dir" -mindepth 1 -maxdepth 1 2>/dev/null | head -n 1)" ]; then
                resolved_dir="$sc_dir"
                break
            fi
        done < <(scan_installed_games 2>/dev/null || true)
    fi

    # Ghost ACF Defense: do not generate empty 1GB dummy ACF if files do not exist physically
    if [ -n "$resolved_dir" ] && [ -d "$resolved_dir" ]; then
        local acf_file="$steam_apps/appmanifest_${appid}.acf"
        local install_name; install_name="$(basename "$resolved_dir")"
        local size_bytes
        size_bytes=$(du -sb "$resolved_dir" 2>/dev/null | awk '{print $1}')
        [ -z "$size_bytes" ] || [ "$size_bytes" -le 0 ] && size_bytes=1000000000
        local steamid
        steamid=$(resolve_active_steamid)

        cat <<ACF > "$acf_file"
"AppState"
{
	"appid"		"$appid"
	"Universe"		"1"
	"name"		"$safe_title"
	"StateFlags"		"4"
	"installdir"		"$install_name"
	"LastUpdated"		"$(date +%s)"
	"SizeOnDisk"		"$size_bytes"
	"buildid"		"1"
	"LastOwner"		"$steamid"
	"UserConfig"
	{
		"language"		"english"
	}
	"MountedConfig"
	{
		"language"		"english"
	}
}
ACF
        mkdir -p "$steam_apps/common"
        local common_target="$steam_apps/common/$install_name"
        if [ "$resolved_dir" != "$common_target" ] && [ ! -e "$common_target" ]; then
            ln -sf "$resolved_dir" "$common_target"
            echo "[INFO] Created common symlink: $common_target -> $resolved_dir"
        fi
        echo "[VERIFIED] appmanifest_${appid}.acf registered (Status: Installed in Steam, Size: $size_bytes bytes)."
        log_msg "INFO" "STEAM" "Registered physical ACF manifest for $title ($appid) in $common_target"
        invalidate_scan_cache
        return 0
    else
        echo "  ${UI_AMBER}[NOTE] No physical game files detected across libraries for AppID $appid.${UI_RST}"
        echo "  ${UI_DIM}Entitlement registered in SLSsteam. Physical ACF manifest deferred (game files not installed).${UI_RST}"
        log_msg "INFO" "STEAM" "SLSsteam entitlement registered for $title ($appid); ACF creation deferred"
        invalidate_scan_cache
        return 2
    fi
    invalidate_scan_cache
}

# Entitle game and adopt assets in official Steam client without downloading
unlock_game() {
    local appid="${1:-}"
    local title="${2:-}"
    local game_dir="${3:-}"

    if [ -z "$appid" ]; then
        echo "Usage: gamectl entitle <appid> [title] [game_dir] (aliases: unlock, adopt-steam)" >&2
        return 1
    fi

    if [ -z "$title" ]; then
        echo "[INFO] Fetching game title for AppID $appid from Steam Store API..."
        title=$(fetch_cached_json "https://store.steampowered.com/api/appdetails?appids=${appid}&filters=basic" "steam_basic_${appid}" 3600 2>/dev/null | jq -r ".\"${appid}\".data.name // empty" 2>/dev/null || true)
        [ -z "$title" ] && title="AppID_${appid}"
    fi

    echo "${UI_BOX}╭─ STEAM ENTITLEMENT & ACF ADOPTION ENGINE ───────────────────╮${UI_RST}"
    echo "│ ${UI_CYAN}Target Game${UI_RST}: ${UI_BOLD}$title${UI_RST} ${UI_DIM}(AppID: $appid)${UI_RST}"
    echo "│ ${UI_DIM}Adopts local files across libraries, Steam Input & Vulkan shaders${UI_RST}"
    echo "${UI_BOX}╰─────────────────────────────────────────────────────────────╯${UI_RST}"

    local sync_rc=0
    sync_steam "$appid" "$title" "$game_dir" || sync_rc=$?
    invalidate_scan_cache

    if [ "$sync_rc" -eq 0 ]; then
        echo "  ${UI_GREEN}[SUCCESS] Game '$title' ($appid) entitled in Steam Client with Full DLC & ACF manifest.${UI_RST}"
        return 0
    elif [ "$sync_rc" -eq 2 ]; then
        echo "  ${UI_AMBER}[DEFERRED] Entitlement registered in SLSsteam. Physical ACF manifest deferred (game files not installed).${UI_RST}"
        return 0
    else
        echo "  ${UI_RED}[WARN] Steam synchronization encountered a notice (Exit: $sync_rc).${UI_RST}"
        return "$sync_rc"
    fi
}

# Preview pane generator for Steam ACF Adoption candidate (physical directory auto-detection)
preview_adopt_candidate() {
    local appid="$1"
    local title="$2"
    [ -z "$appid" ] && return 0

    local found_dir=""
    local found_source=""
    local has_acf=""

    # 1. Check scancache if available
    local cache_file
    cache_file="$(get_runtime_dir)/scancache.tab"
    if [ -f "$cache_file" ]; then
        local sc_id sc_name sc_st sc_dir sc_bin
        while IFS=$'\t' read -r sc_id sc_name sc_st sc_dir sc_bin; do
            sc_id="${sc_id//[[:space:]]/}"
            if [ "$sc_id" = "$appid" ] && [ -d "$sc_dir" ]; then
                found_dir="$sc_dir"
                found_source="Library Cache ($sc_st)"
                break
            fi
        done < "$cache_file"
    fi

    # 2. Check ~/Games directly
    if [ -z "$found_dir" ] && [ -d "$HOME/Games" ]; then
        for cand in "$HOME/Games"/*; do
            [ -d "$cand" ] || continue
            local c_aid
            c_aid="$(resolve_game_appid "$cand")"
            if [ -n "$c_aid" ] && [ "$c_aid" = "$appid" ]; then
                found_dir="$cand"
                found_source="Physical ~/Games (AppID match)"
                break
            fi
            local c_base="${cand##*/}"
            if [ "${c_base,,}" = "${title,,}" ]; then
                found_dir="$cand"
                found_source="Physical ~/Games (Title match)"
                break
            fi
        done
    fi

    # 3. Check Steam Libraries
    if [ -z "$found_dir" ]; then
        while read -r steam_lib; do
            [ -d "$steam_lib" ] || continue
            if [ -d "$steam_lib/common/$title" ]; then
                found_dir="$steam_lib/common/$title"
                found_source="Steam Primary Library"
                break
            fi
        done < <(get_steam_libraries 2>/dev/null || true)
    fi

    # Check ACF status
    local acf_file
    acf_file=$(find_app_acf "$appid" 2>/dev/null || true)
    if [ -n "$acf_file" ] && [ -f "$acf_file" ]; then
        has_acf="${UI_GREEN}[EXISTS] $(basename "$acf_file")${UI_RST}"
    else
        has_acf="${UI_AMBER}[MISSING] Not yet registered${UI_RST}"
    fi

    echo "${UI_BOX}╭─ TARGET STORE GAME & PHYSICAL DISCOVERY AUDIT ──────╮${UI_RST}"
    echo "  ${UI_CYAN}Store AppID ${UI_RST}: ${UI_BOLD}$appid${UI_RST}"
    echo "  ${UI_CYAN}Store Title ${UI_RST}: ${UI_BOLD}$title${UI_RST}"
    echo "  ${UI_CYAN}ACF Manifest${UI_RST}: $has_acf"
    echo
    if [ -n "$found_dir" ]; then
        local dir_size="N/A"
        dir_size=$(du -sh "$found_dir" 2>/dev/null | awk '{print $1}' || echo "N/A")
        echo "  ${UI_CYAN}Physical Dir${UI_RST}: ${UI_GREEN}${UI_BOLD}[FOUND]${UI_RST} $found_dir"
        echo "  ${UI_CYAN}Detection   ${UI_RST}: ${UI_DIM}$found_source • $dir_size on disk${UI_RST}"
        echo "  ${UI_CYAN}Adoption Act${UI_RST}: ${UI_GREEN}Instant Linking Ready (StateFlags=4)${UI_RST}"
    else
        echo "  ${UI_CYAN}Physical Dir${UI_RST}: ${UI_AMBER}[NOT FOUND]${UI_RST} No existing local installation"
        echo "  ${UI_CYAN}Adoption Act${UI_RST}: ${UI_PURPLE}Triggers Auto-Download Bridge${UI_RST} ${UI_DIM}(Standalone CDN / Steam)${UI_RST}"
    fi
    echo "${UI_BOX}╰─────────────────────────────────────────────────────╯${UI_RST}"
}

# Aliases for entitlement engine
entitle_game() { unlock_game "$@"; }
adopt_steam() { unlock_game "$@"; }

# Interactive Steam ACF Adoption & Asset Manager Wizard (Dual Input: Title or AppID)
unlock_interactive() {
    if [ ! -t 0 ] || [ ! -t 1 ]; then
        echo "[ERROR] Interactive ACF adoption requires a terminal (TTY)." >&2
        return 1
    fi
    if ! command -v fzf >/dev/null 2>&1; then
        echo "[ERROR] fzf is required for interactive mode but was not found in PATH." >&2
        return 127
    fi

    local u_input fzf_rc=0
    # Input primitive canonicalized via tui_prompt_input (: | fzf wrapper)
    u_input=$(tui_prompt_input "Steam ACF Adoption & Asset Manager" "Enter game title or numeric AppID (Enter: Adopt │ Esc: Cancel)" "" "Game Title or ID > ") || fzf_rc=$?
    [ "$fzf_rc" -eq 130 ] && return 0
    [ "$fzf_rc" -ne 0 ] && return "$fzf_rc"
    u_input=$(echo "$u_input" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
    [ -z "$u_input" ] && return 0

    local u_appid=""
    local u_title=""

    if [[ "$u_input" =~ ^[0-9]+$ ]]; then
        u_appid="$u_input"
        log_msg "INFO" "ADOPT" "Fetching title from Steam Store API for AppID $u_appid..."
        u_title=$(fetch_cached_json "https://store.steampowered.com/api/appdetails?appids=${u_appid}&filters=basic" "steam_basic_${u_appid}" 3600 2>/dev/null | jq -r ".\"${u_appid}\".data.name // empty" 2>/dev/null || true)
        [ -z "$u_title" ] && u_title="AppID_${u_appid}"
    else
        log_msg "INFO" "ADOPT" "Searching Steam Store API for title: '$u_input'..."
        local encoded_query
        encoded_query=$(python3 -c "import urllib.parse, sys; print(urllib.parse.quote(sys.argv[1]))" "$u_input" 2>/dev/null || echo "$u_input")
        local raw_results
        raw_results=$(curl -s --connect-timeout 5 --max-time 15 "https://store.steampowered.com/api/storesearch/?term=${encoded_query}&l=english&cc=US" 2>/dev/null)
        local search_items
        search_items=$(printf '%s' "$raw_results" | store_search_items) || {
            echo "[ERROR] Invalid Steam search catalog." >&2
            return 1
        }

        if [ -z "$search_items" ]; then
            log_msg "WARN" "ADOPT" "Game title '$u_input' not found on Steam Store API"
            tui_modal_notice "Game Not Found" "Game title '$u_input' was not found on Steam Store.\nPlease verify title or provide numeric AppID." || return $?
            return 1
        fi

        local -a adopt_ids=()
        local aid aname
        while IFS=$'\t' read -r aid aname; do
            aid="${aid//[[:space:]]/}"
            [[ "$aid" =~ ^[0-9]+$ ]] && adopt_ids+=("$aid")
        done <<< "$search_items"

        declare -A adopt_type_map=() adopt_parent_map=()
        if [ "${#adopt_ids[@]}" -gt 0 ] && declare -F classify_steam_app_types >/dev/null 2>&1; then
            local c_out c_id c_type c_parent
            c_out=$(classify_steam_app_types "${adopt_ids[@]}" 2>/dev/null || true)
            while IFS=$'\t' read -r c_id c_type c_parent; do
                [ -n "$c_id" ] || continue
                adopt_type_map["$c_id"]="${c_type:-APP}"
                adopt_parent_map["$c_id"]="${c_parent:-}"
            done <<< "$c_out"
        fi

        local adopt_items=""
        while IFS=$'\t' read -r aid aname; do
            [ -n "$aid" ] || continue
            local raw_type="${adopt_type_map[$aid]:-APP}"
            local parent_id="${adopt_parent_map[$aid]:-}"
            local type_badge="[$raw_type]"
            if declare -F format_app_type_badge >/dev/null 2>&1; then
                type_badge="$(format_app_type_badge "$raw_type")"
            fi
            validate_tui_fields "$aid" "$aname" "$raw_type" "$parent_id" || continue
            adopt_items+="${aid}"$'\t'"${type_badge}"$'\t'"${aname}"$'\t'"${raw_type}"$'\t'"${parent_id}"$'\n'
        done <<< "$search_items"

        local sel_item fzf_sel_rc=0
        export GAMECTL_PREVIEW_BIN="$SELF_BIN"
        sel_item=$(printf '%s' "$adopt_items" | fzf \
            --delimiter=$'\t' \
            --with-nth=1,2,3 \
            --border-label="  ╢ Steam Store Search :: Pick Target Game ╟  " \
            --border-label-pos=2 \
            --header="SELECT GAME FOR ACF ADOPTION (Enter: Select │ Esc: Cancel)" \
            --prompt="Adopt Game > " \
            --preview='"$GAMECTL_PREVIEW_BIN" --preview-adopt {1} {3}' \
            --preview-window=down:45%:border-rounded \
            --reverse 2>/dev/null) || fzf_sel_rc=$?

        if [ "$fzf_sel_rc" -eq 130 ]; then
            return 0
        fi
        if [ "$fzf_sel_rc" -ne 0 ] && [ "$fzf_sel_rc" -ne 1 ]; then
            echo "[ERROR] Game adoption picker failed (fzf exit code $fzf_sel_rc)." >&2
            return "$fzf_sel_rc"
        fi
        [ -z "$sel_item" ] && return 0

        local _a1="" _a2="" _a3=""
        IFS=$'\t' read -r _a1 _a2 _a3 _ <<< "$sel_item"
        if [ -n "$_a3" ]; then
            u_appid="$_a1"
            u_title="$_a3"
        else
            u_appid="$_a1"
            u_title="$_a2"
        fi
    fi

    [ -z "$u_appid" ] && return 0

    # Check for physical game files across all active libraries
    local existing_dir=""
    local sc_id sc_name sc_st sc_dir sc_bin
    local clean_target="${u_title,,}"
    while IFS=$'\t' read -r sc_id sc_name sc_st sc_dir sc_bin; do
        sc_id="${sc_id//[[:space:]]/}"
        sc_dir="${sc_dir//$'\r'/}"
        if [ -n "$sc_id" ] && [ "$sc_id" = "$u_appid" ] && [ -d "$sc_dir" ] && [ -n "$(find "$sc_dir" -mindepth 1 -maxdepth 1 2>/dev/null | head -n 1)" ]; then
            existing_dir="$sc_dir"
            break
        fi
        local cur_clean="${sc_name,,}"
        cur_clean="${cur_clean#"${cur_clean%%[![:space:]]*}"}"
        cur_clean="${cur_clean%"${cur_clean##*[![:space:]]}"}"
        if [ -n "$cur_clean" ] && [ "$cur_clean" = "$clean_target" ] && [ -d "$sc_dir" ] && [ -n "$(find "$sc_dir" -mindepth 1 -maxdepth 1 2>/dev/null | head -n 1)" ]; then
            existing_dir="$sc_dir"
            break
        fi
    done < <(scan_installed_games 2>/dev/null || true)

    if [ -n "$existing_dir" ]; then
        log_msg "INFO" "ADOPT" "Discovered physical install across libraries: $existing_dir"
        local adopt_out
        adopt_out=$(unlock_game "$u_appid" "$u_title" "$existing_dir")
        local clean_notice
        clean_notice=$(echo "$adopt_out" | grep -E '\[SUCCESS\]|\[DEFERRED\]|\[WARN\]' | sed 's/\x1b\[[0-9;]*m//g' | sed 's/^[[:space:]]*//')
        [ -z "$clean_notice" ] && clean_notice="Physical ACF adoption complete for $u_title ($u_appid)."
        tui_modal_notice "Steam ACF Adoption" "$clean_notice\n\nGame Location: $existing_dir" "30%" || return $?
        return 0
    fi

    # Auto-Download Bridge: files are not installed in any active library
    local bridge_options
    bridge_options=$(cat <<EOF
1	[Download Standalone] Unduh via Standalone CDN (gamectl-depot-dl) & Auto-provision ACF + GBE
2	[Steam Native Install] Daftarkan SLSsteam entitlement & picu Steam Client (steam://install/$u_appid)
3	[Cancel] Batalkan dan kembali ke Dashboard
EOF
)
    local bridge_sel="" b_rc=0
    bridge_sel=$(echo "$bridge_options" | fzf \
        --delimiter=$'\t' \
        --with-nth=2 \
        --border-label="  ╢ Physical Game Files Absent: $u_title ($u_appid) ╟  " \
        --border-label-pos=2 \
        --header="PHYSICAL FILES NOT FOUND (Enter: Select │ Esc: Return)" \
        --prompt="Action > " \
        --reverse 2>/dev/null) || b_rc=$?

    check_fzf_status "$b_rc" || return $?
    [ "$b_rc" -eq 130 ] && return 0
    local b_opt
    b_opt=$(echo "$bridge_sel" | awk -F'\t' '{print $1}')

    case "$b_opt" in
        1)
            local dest_dir target_os
            dest_dir="$(resolve_target_library_dir "$u_title")"
            target_os="$(detect_app_platform_os "$u_appid")"
            log_msg "INFO" "ADOPT" "Bridging uninstalled AppID $u_appid to standalone depot download"
            download_game "$u_appid" "$dest_dir" "$u_title" --all --os "$target_os"
            ;;
        2)
            sync_steam "$u_appid" "$u_title" "--no-acf"
            if command -v steam >/dev/null 2>&1; then
                steam "steam://install/$u_appid" >/dev/null 2>&1 &
                log_msg "INFO" "ADOPT" "Triggered steam://install/$u_appid native install intent"
                tui_modal_notice "Steam Client Intent" "Entitlement registered in SLSsteam.\nPushed steam://install/$u_appid to Steam Client." "25%" || return $?
            else
                tui_modal_notice "Steam Entitlement Registered" "Entitlement registered in SLSsteam.\nSteam Client executable not found in PATH." "25%" || return $?
            fi
            ;;
        *)
            return 0
            ;;
    esac
}

entitle_interactive() { unlock_interactive "$@"; }


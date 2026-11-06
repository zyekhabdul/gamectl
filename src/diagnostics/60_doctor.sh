# System Diagnostics & Health Audit
doctor_audit() {
    local pass_cnt=0 warn_cnt=0 miss_cnt=0

    echo "${UI_BOX}╭─ GAMECTL SYSTEM DIAGNOSTICS & HEALTH AUDIT ─────────────────╮${UI_RST}"
    local os_str="Linux"
    [ -f /etc/os-release ] && os_str=$(grep -E '^PRETTY_NAME=' /etc/os-release | cut -d'=' -f2 | tr -d '"')
    echo "│ ${UI_CYAN}Host OS     ${UI_RST}: ${UI_BOLD}$os_str${UI_RST} ${UI_DIM}($(uname -sr) $(uname -m))${UI_RST}"
    echo "│ ${UI_CYAN}Display     ${UI_RST}: ${WAYLAND_DISPLAY:+Wayland ($WAYLAND_DISPLAY)}${DISPLAY:+ X11 ($DISPLAY)}"
    echo "${UI_BOX}╰─────────────────────────────────────────────────────────────╯${UI_RST}"

    # Layer 1: CLI Fundamental Tools
    echo
    echo "  ${UI_PURPLE}[LAYER 1] Fundamental CLI Tools${UI_RST}"
    local cli_tool
    for cli_tool in fzf jq curl file zip unzip rsync ssh; do
        if command -v "$cli_tool" >/dev/null 2>&1; then
            echo "    • $(printf '%-10s' "$cli_tool") : ${UI_GREEN}[READY]${UI_RST} ${UI_DIM}($(command -v "$cli_tool"))${UI_RST}"
            pass_cnt=$((pass_cnt + 1))
        else
            echo "    • $(printf '%-10s' "$cli_tool") : ${UI_RED}[MISSING]${UI_RST} Install via distro package manager"
            miss_cnt=$((miss_cnt + 1))
        fi
    done

    # Layer 2: Python Runtime & YAML Engine
    echo
    echo "  ${UI_PURPLE}[LAYER 2] Python Runtime & YAML Engine${UI_RST}"
    if command -v python3 >/dev/null 2>&1; then
        echo "    • $(printf '%-10s' "python3") : ${UI_GREEN}[READY]${UI_RST} ${UI_DIM}($(python3 --version 2>&1))${UI_RST}"
        pass_cnt=$((pass_cnt + 1))
        if python3 -c "import ruamel.yaml" 2>/dev/null; then
            echo "    • $(printf '%-10s' "YAML") : ${UI_GREEN}[READY]${UI_RST} ruamel.yaml (Preserves SLSsteam layout)"
            pass_cnt=$((pass_cnt + 1))
        elif python3 -c "import yaml" 2>/dev/null; then
            echo "    • $(printf '%-10s' "YAML") : ${UI_GREEN}[READY]${UI_RST} PyYAML fallback installed"
            pass_cnt=$((pass_cnt + 1))
        else
            echo "    • $(printf '%-10s' "YAML") : ${UI_AMBER}[WARN]${UI_RST} Neither ruamel.yaml nor pyyaml found"
            warn_cnt=$((warn_cnt + 1))
        fi
    else
        echo "    • $(printf '%-10s' "python3") : ${UI_RED}[MISSING]${UI_RST} Python 3 runtime not found"
        miss_cnt=$((miss_cnt + 1))
    fi

    # Layer 3: GBE Fork Templates
    echo
    echo "  ${UI_PURPLE}[LAYER 3] GBE Fork Binary Templates${UI_RST}"
    local gbe_targets=(
        "Linux x64:linux:x64"
        "Linux x86:linux:x86"
        "Windows x64:windows:x64"
        "Windows x86:windows:x86"
    )
    for gt in "${gbe_targets[@]}"; do
        local g_label="${gt%%:*}"
        local g_rest="${gt#*:}"
        local g_plat="${g_rest%%:*}"
        local g_arch="${g_rest##*:}"
        local g_path
        g_path=$(get_gbe_template "$g_plat" "$g_arch" 2>/dev/null || true)
        if [ -n "$g_path" ] && [ -f "$g_path" ]; then
            echo "    • $(printf '%-11s' "$g_label") : ${UI_GREEN}[READY]${UI_RST} ${UI_DIM}($g_path)${UI_RST}"
            pass_cnt=$((pass_cnt + 1))
        else
            echo "    • $(printf '%-11s' "$g_label") : ${UI_RED}[MISSING]${UI_RST} Place template in ~/.local/share/gbe-fork/"
            miss_cnt=$((miss_cnt + 1))
        fi
    done

    # Layer 4: Windows Game Runner
    echo
    echo "  ${UI_PURPLE}[LAYER 4] Windows Game Runners${UI_RST}"
    local r_found=0
    if command -v umu-run >/dev/null 2>&1; then
        echo "    • $(printf '%-10s' "umu-run") : ${UI_GREEN}[READY]${UI_RST} ${UI_DIM}($(command -v umu-run))${UI_RST}"
        r_found=1
    else
        echo "    • $(printf '%-10s' "umu-run") : ${UI_DIM}[N/A]${UI_RST} (Optional Unified Proton Runner)"
    fi

    local ge_proton=""
    local s_dyn_root
    s_dyn_root="$(get_steam_root 2>/dev/null || true)"
    local cdir
    for cdir in "$s_dyn_root/compatibilitytools.d" "$HOME/.local/share/Steam/compatibilitytools.d" "$HOME/.steam/root/compatibilitytools.d" "$HOME/.var/app/com.valvesoftware.Steam/.local/share/Steam/compatibilitytools.d"; do
        [ -n "$cdir" ] && [ -d "$cdir" ] || continue
        ge_proton=$(find "$cdir" -maxdepth 2 -name "proton" 2>/dev/null | head -n 1 || true)
        [ -n "$ge_proton" ] && break
    done
    if [ -n "$ge_proton" ]; then
        echo "    • $(printf '%-10s' "GE-Proton") : ${UI_GREEN}[READY]${UI_RST} ${UI_DIM}($ge_proton)${UI_RST}"
        r_found=1
    else
        echo "    • $(printf '%-10s' "GE-Proton") : ${UI_DIM}[N/A]${UI_RST} (In compatibilitytools.d/)"
    fi

    if command -v wine >/dev/null 2>&1; then
        echo "    • $(printf '%-10s' "Wine") : ${UI_GREEN}[READY]${UI_RST} ${UI_DIM}($(wine --version 2>/dev/null || echo 'wine'))${UI_RST}"
        r_found=1
    else
        echo "    • $(printf '%-10s' "Wine") : ${UI_DIM}[N/A]${UI_RST} (System Wine fallback)"
    fi

    if [ "$r_found" -eq 1 ]; then
        pass_cnt=$((pass_cnt + 1))
    else
        echo "    • ${UI_AMBER}[WARN] No Windows runners detected. Only Native Linux games can launch.${UI_RST}"
        warn_cnt=$((warn_cnt + 1))
    fi

    # Layer 5: Performance & Display Wrappers
    echo
    echo "  ${UI_PURPLE}[LAYER 5] Performance & Display Wrappers${UI_RST}"
    for w_tool in "gamemoderun:GameMode" "mangohud:MangoHud" "gamescope:Gamescope"; do
        local wt_cmd="${w_tool%%:*}"
        local wt_name="${w_tool##*:}"
        if command -v "$wt_cmd" >/dev/null 2>&1; then
            echo "    • $(printf '%-10s' "$wt_name") : ${UI_GREEN}[READY]${UI_RST} ${UI_DIM}($(command -v "$wt_cmd"))${UI_RST}"
            pass_cnt=$((pass_cnt + 1))
        else
            echo "    • $(printf '%-10s' "$wt_name") : ${UI_DIM}[OFF]${UI_RST} Not installed ($wt_cmd missing)"
            warn_cnt=$((warn_cnt + 1))
        fi
    done

    # Layer 6: Manifest Harvester & CDN Providers
    echo
    echo "  ${UI_PURPLE}[LAYER 6] Manifest Harvester & CDN Providers${UI_RST}"
    local harvest_ok=1
    command -v curl >/dev/null 2>&1 || harvest_ok=0
    command -v jq >/dev/null 2>&1 || harvest_ok=0
    command -v zip >/dev/null 2>&1 || harvest_ok=0
    command -v unzip >/dev/null 2>&1 || harvest_ok=0
    if [ "$harvest_ok" -eq 1 ]; then
        echo "    • $(printf '%-15s' "Harvester") : ${UI_GREEN}[READY]${UI_RST} ${UI_DIM}(curl, jq, zip, unzip)${UI_RST}"
        pass_cnt=$((pass_cnt + 1))
    else
        echo "    • $(printf '%-15s' "Harvester") : ${UI_RED}[MISSING]${UI_RST} curl, jq, zip, or unzip not found"
        miss_cnt=$((miss_cnt + 1))
    fi

    # Layer 7: Steam Client & SLSsteam Integration
    echo
    echo "  ${UI_PURPLE}[LAYER 7] Steam Client & SLSsteam Integration${UI_RST}"
    local s_root
    s_root="$(get_steam_root 2>/dev/null || true)"
    if [ -n "$s_root" ] && [ -d "$s_root" ]; then
        echo "    • $(printf '%-12s' "Steam Root") : ${UI_GREEN}[READY]${UI_RST} ${UI_DIM}($s_root)${UI_RST}"
        pass_cnt=$((pass_cnt + 1))
    else
        echo "    • $(printf '%-12s' "Steam Root") : ${UI_AMBER}[WARN]${UI_RST} Steam client directory not found"
        warn_cnt=$((warn_cnt + 1))
    fi

    local sls_file="$HOME/.config/SLSsteam/config.yaml"
    if [ -f "$sls_file" ]; then
        echo "    • $(printf '%-12s' "SLSsteam") : ${UI_GREEN}[READY]${UI_RST} ${UI_DIM}($sls_file)${UI_RST}"
        pass_cnt=$((pass_cnt + 1))
    else
        echo "    • $(printf '%-12s' "SLSsteam") : ${UI_AMBER}[WARN]${UI_RST} SLSsteam config.yaml not found (needed for zero-download unlock)"
        warn_cnt=$((warn_cnt + 1))
    fi

    # Hardware GPU & Mesa Driver Health
    echo
    echo "  ${UI_PURPLE}[HARDWARE] GPU Controller & Mesa Driver Health${UI_RST}"
    local gpu_line
    gpu_line=$(lspci 2>/dev/null | grep -E "VGA|3D" | head -n 1 | sed -E 's/^[0-9a-f:.]+ (VGA compatible controller|3D controller): //' || true)
    [ -z "$gpu_line" ] && gpu_line="Not detected via lspci"
    echo "    • GPU Controller : ${UI_BOLD}$gpu_line${UI_RST}"
    if is_haswell_gpu; then
        echo "    • Mesa Driver    : ${UI_AMBER}[WARN]${UI_RST} Intel Haswell has incomplete Vulkan (hasvk)."
        echo "    • Driver Safety  : ${UI_ICE}Mesa GL Threading is disabled by default to prevent FNA/XNA asset decompression crashes.${UI_RST}"
        warn_cnt=$((warn_cnt + 1))
    else
        echo "    • Driver Status  : ${UI_GREEN}[READY]${UI_RST} GPU supported by standard Mesa driver stack."
        pass_cnt=$((pass_cnt + 1))
    fi

    local dgpu_vend
    dgpu_vend="$(detect_dgpu_vendor 2>/dev/null || echo "none")"
    if [ "$dgpu_vend" != "none" ]; then
        echo "    • Hybrid dGPU    : ${UI_GREEN}[READY]${UI_RST} Discrete GPU detected ($dgpu_vend). PRIME offload available (--prime)."
        pass_cnt=$((pass_cnt + 1))
    else
        echo "    • Hybrid dGPU    : ${UI_DIM}[N/A]${UI_RST} No discrete secondary GPU detected (single GPU topology)."
    fi

    echo
    echo "${UI_BOX}╭─ DIAGNOSTIC AUDIT SUMMARY ──────────────────────────────────╮${UI_RST}"
    echo "│ ${UI_GREEN}Passed: $pass_cnt${UI_RST}  •  ${UI_AMBER}Warnings: $warn_cnt${UI_RST}  •  ${UI_RED}Missing: $miss_cnt${UI_RST}"
    if [ "$miss_cnt" -eq 0 ] && [ "$warn_cnt" -eq 0 ]; then
        echo "│ System Status: ${UI_GREEN}[READY] 100% optimal for sovereign offline gaming.${UI_RST}"
    elif [ "$miss_cnt" -eq 0 ]; then
        echo "│ System Status: ${UI_GREEN}[READY] Core dependencies satisfied. Review warnings above.${UI_RST}"
    else
        echo "│ System Status: ${UI_AMBER}[WARN] Essential dependencies missing. Install missing tools.${UI_RST}"
    fi
    echo "${UI_BOX}╰─────────────────────────────────────────────────────────────╯${UI_RST}"

    return $(( miss_cnt > 0 ? 1 : 0 ))
}

# Query ProtonDB community compatibility tier and rating (Chunk 5)
query_protondb() {
    local target="${1:-}"

    if [ -z "$target" ]; then
        echo "Usage: gamectl protondb <appid|game_dir>" >&2
        return 1
    fi

    local appid=""
    if [[ "$target" =~ ^[0-9]+$ ]]; then
        appid="$target"
    elif [ -d "$target" ]; then
        if [ -f "$target/steam_appid.txt" ]; then
            appid=$(tr -dc '0-9' < "$target/steam_appid.txt")
        fi
        if [ -z "$appid" ]; then
            local base_dir
            base_dir="$(basename "$target")"
            local parent_apps
            parent_apps="$(dirname "$target")"
            if [ "$(basename "$parent_apps")" = "common" ]; then
                local steamapps_dir
                steamapps_dir="$(dirname "$parent_apps")"
                local acf
                for acf in "$steamapps_dir"/appmanifest_*.acf; do
                    [ -f "$acf" ] || continue
                    local installdir
                    installdir=$(grep -E '^\s*"installdir"' "$acf" | head -n 1 | sed -E 's/.*"installdir"[[:space:]]+"([^"]+)".*/\1/')
                    if [ "$installdir" = "$base_dir" ]; then
                        appid=$(grep -E '^\s*"appid"' "$acf" | head -n 1 | sed -E 's/.*"appid"[[:space:]]+"([0-9]+)".*/\1/')
                        break
                    fi
                done
            fi
        fi
    fi

    if [ -z "$appid" ] || [[ ! "$appid" =~ ^[0-9]+$ ]]; then
        echo "[ERROR] Invalid AppID or game directory lacks steam_appid.txt: $target" >&2
        return 1
    fi

    echo "${UI_BOX}╭─ PROTONDB COMPATIBILITY REPORT ─────────────────────────────╮${UI_RST}"
    echo "│ ${UI_CYAN}Target AppID${UI_RST}  : ${UI_BOLD}$appid${UI_RST}"

    local pdb=""
    pdb=$(fetch_cached_json "https://www.protondb.com/api/v1/reports/summaries/${appid}.json" "protondb_${appid}" 3600 2>/dev/null || true)

    if [ -n "$pdb" ] && [ "$pdb" != "null" ] && echo "$pdb" | jq . >/dev/null 2>&1; then
        local tier score conf trending
        tier=$(echo "$pdb" | jq -r ".tier // \"Unknown\"" 2>/dev/null)
        score=$(echo "$pdb" | jq -r ".score // \"-\"" 2>/dev/null)
        conf=$(echo "$pdb" | jq -r ".confidence // \"-\"" 2>/dev/null)
        trending=$(echo "$pdb" | jq -r ".trendingTier // \"-\"" 2>/dev/null)

        local tier_upper="${tier^^}"
        local c_tier="${UI_GREEN}[$tier_upper]${UI_RST}"
        local recommendation=""

        case "$tier_upper" in
            *PLATINUM*)
                c_tier="${UI_ICE}[PLATINUM]${UI_RST}"
                recommendation="Plug and play. Works flawlessly out of the box without special tweaking."
                ;;
            *GOLD*)
                c_tier="${UI_AMBER}[GOLD]${UI_RST}"
                recommendation="Runs well after minor tweaks (e.g. GE-Proton / DirectX DLL override)."
                ;;
            *SILVER*)
                c_tier="${UI_DIM}[SILVER]${UI_RST}"
                recommendation="Playable with minor issues / requires specific launch options."
                ;;
            *BRONZE*)
                c_tier="${UI_AMBER}[BRONZE]${UI_RST}"
                recommendation="Frequent crashes or graphical glitches. Specific GE-Proton version recommended."
                ;;
            *BORKED*)
                c_tier="${UI_RED}[BORKED]${UI_RST}"
                recommendation="Game currently does not run under Wine/Proton (likely invasive anti-cheat)."
                ;;
            *NATIVE*)
                c_tier="${UI_GREEN}[NATIVE]${UI_RST}"
                recommendation="Native Linux ELF build available without Wine emulation."
                ;;
            *)
                recommendation="Limited community reports. Test with latest GE-Proton release."
                ;;
        esac

        echo "│ ${UI_CYAN}ProtonDB Tier${UI_RST} : $c_tier"
        echo "│ ${UI_CYAN}Rating Score ${UI_RST} : ${UI_BOLD}$score${UI_RST} ${UI_DIM}(Confidence: $conf, Trending: $trending)${UI_RST}"
        echo "│ ${UI_CYAN}Recommendation${UI_RST}: $recommendation"
        echo "${UI_BOX}╰─────────────────────────────────────────────────────────────╯${UI_RST}"
        return 0
    else
        echo "│ ${UI_CYAN}ProtonDB Tier${UI_RST} : ${UI_DIM}[NO REPORTS YET]${UI_RST}"
        echo "│ ${UI_CYAN}Details       ${UI_RST}: No community reports currently recorded for AppID $appid."
        echo "${UI_BOX}╰─────────────────────────────────────────────────────────────╯${UI_RST}"
        return 0
    fi
}


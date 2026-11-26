# Canonical wrapper config & env override loader (SSoT)
load_wrapper_config() {
    local gdir="${1:-}"
    local apply_env="${2:-1}"

    GAMECTL_CFG_GM=0
    GAMECTL_CFG_HUD=0
    GAMECTL_CFG_SCOPE=0
    GAMECTL_CFG_FSR=0
    GAMECTL_CFG_GLTHREAD=0
    GAMECTL_CFG_SYSTEMD_SCOPE=""
    GAMECTL_CFG_PRIME=0
    GAMECTL_CFG_SANDBOX=0
    GAMECTL_CFG_RENDERER="auto"
    GAMECTL_CFG_GAMESCOPE_ARGS=""
    GAMECTL_CFG_AUTO_LOCATE_SAVES=0
    GAMECTL_CFG_DEV_WINEDEBUG="0"
    GAMECTL_CFG_DEV_VK_DEBUG="0"
    GAMECTL_CFG_DEV_GBE_LOG="0"

    local w_cfgs=("$HOME/.config/gamectl/wrappers")
    [ -n "$gdir" ] && w_cfgs+=("$gdir/.wrappers")
    local w_cfg k v
    for w_cfg in "${w_cfgs[@]}"; do
        [ -f "$w_cfg" ] || continue
        while IFS='=' read -r k v || [ -n "$k" ]; do
            k="${k//[[:space:]]/}"
            [[ -z "$k" || "$k" =~ ^# ]] && continue
            v="${v//$'\r'/}"
            v="${v#"${v%%[![:space:]]*}"}"
            v="${v%"${v##*[![:space:]]}"}"
            v="${v#\"}"
            v="${v%\"}"
            v="${v#\'}"
            v="${v%\'}"
            case "$k" in
                gamemode) GAMECTL_CFG_GM="$v" ;;
                hud|mangohud) GAMECTL_CFG_HUD="$v" ;;
                gamescope) GAMECTL_CFG_SCOPE="$v" ;;
                fsr) GAMECTL_CFG_FSR="$v" ;;
                glthread|mesa_glthread) GAMECTL_CFG_GLTHREAD="$v" ;;
                scope|systemd_scope) GAMECTL_CFG_SYSTEMD_SCOPE="$v" ;;
                prime|dgpu) GAMECTL_CFG_PRIME="$v" ;;
                sandbox) GAMECTL_CFG_SANDBOX="$v" ;;
                renderer) GAMECTL_CFG_RENDERER="$v" ;;
                gamescope_args) GAMECTL_CFG_GAMESCOPE_ARGS="$v" ;;
                auto_locate_saves) GAMECTL_CFG_AUTO_LOCATE_SAVES="$v" ;;
                dev_winedebug) GAMECTL_CFG_DEV_WINEDEBUG="$v" ;;
                dev_vk_debug) GAMECTL_CFG_DEV_VK_DEBUG="$v" ;;
                dev_gbe_log) GAMECTL_CFG_DEV_GBE_LOG="$v" ;;
            esac
        done < "$w_cfg"
    done

    if [ "$apply_env" = "1" ]; then
        [ -n "${GAMECTL_GAMEMODE:-}" ] && GAMECTL_CFG_GM="$GAMECTL_GAMEMODE"
        [ -n "${GAMECTL_HUD:-${GAMECTL_MANGOHUD:-}}" ] && GAMECTL_CFG_HUD="${GAMECTL_HUD:-$GAMECTL_MANGOHUD}"
        [ -n "${GAMECTL_GAMESCOPE:-}" ] && GAMECTL_CFG_SCOPE="$GAMECTL_GAMESCOPE"
        [ -n "${GAMECTL_FSR:-}" ] && GAMECTL_CFG_FSR="$GAMECTL_FSR"
        [ -n "${GAMECTL_GLTHREAD:-}" ] && GAMECTL_CFG_GLTHREAD="$GAMECTL_GLTHREAD"
        [ -n "${GAMECTL_SCOPE:-${GAMECTL_SYSTEMD_SCOPE:-}}" ] && GAMECTL_CFG_SYSTEMD_SCOPE="${GAMECTL_SCOPE:-$GAMECTL_SYSTEMD_SCOPE}"
        [ -n "${GAMECTL_PRIME:-}" ] && GAMECTL_CFG_PRIME="$GAMECTL_PRIME"
        [ -n "${GAMECTL_SANDBOX:-}" ] && GAMECTL_CFG_SANDBOX="$GAMECTL_SANDBOX"
        if [ -n "${GAMECTL_RENDERER:-}" ]; then
            GAMECTL_CFG_RENDERER="$GAMECTL_RENDERER"
        elif [ -n "${PROTON_USE_WINED3D:-}" ]; then
            [ "$PROTON_USE_WINED3D" = "1" ] && GAMECTL_CFG_RENDERER="wined3d"
            [ "$PROTON_USE_WINED3D" = "0" ] && GAMECTL_CFG_RENDERER="dxvk"
        fi
        [ -n "${GAMECTL_GAMESCOPE_ARGS:-}" ] && GAMECTL_CFG_GAMESCOPE_ARGS="$GAMECTL_GAMESCOPE_ARGS"
        [ -n "${GAMECTL_AUTO_LOCATE_SAVES:-}" ] && GAMECTL_CFG_AUTO_LOCATE_SAVES="$GAMECTL_AUTO_LOCATE_SAVES"
        [ -n "${GAMECTL_DEV_WINEDEBUG:-}" ] && GAMECTL_CFG_DEV_WINEDEBUG="$GAMECTL_DEV_WINEDEBUG"
        [ -n "${GAMECTL_DEV_VK_DEBUG:-}" ] && GAMECTL_CFG_DEV_VK_DEBUG="$GAMECTL_DEV_VK_DEBUG"
        [ -n "${GAMECTL_DEV_GBE_LOG:-}" ] && GAMECTL_CFG_DEV_GBE_LOG="$GAMECTL_DEV_GBE_LOG"
    fi
}

# Canonical developer profiler environment resolver (SSoT; zero pollution when OFF)
resolve_dev_profiler_env() {
    local gdir="${1:-}"
    local apply_env="${2:-1}"

    load_wrapper_config "$gdir" "$apply_env"

    GAMECTL_DEV_ACTIVE=0
    GAMECTL_DEV_RESOLVED_WINEDEBUG=""
    GAMECTL_DEV_RESOLVED_VK_DEBUG=""
    GAMECTL_DEV_RESOLVED_GBE_LOG=0
    GAMECTL_DEV_TRACE_LOG=""
    GAMECTL_DEV_RESPECTED_USER_WINEDEBUG=0
    GAMECTL_DEV_RESPECTED_USER_VK_DEBUG=0

    local wd_raw="${GAMECTL_CFG_DEV_WINEDEBUG:-0}"
    local wd_lc="${wd_raw,,}"
    local mapped_wd=""
    case "$wd_lc" in
        ""|0|off|false) mapped_wd="" ;;
        basic) mapped_wd="+loaddll,+seh" ;;
        full)  mapped_wd="+relay,+seh,+loaddll" ;;
        *)
            mapped_wd=$(printf '%s' "$wd_raw" | tr -cd 'A-Za-z0-9_+,=-')
            if [ -z "$mapped_wd" ]; then
                echo "[WARN] Ignored invalid dev_winedebug setting." >&2
            fi
            ;;
    esac

    if [ -n "$mapped_wd" ]; then
        GAMECTL_DEV_ACTIVE=1
        if [ -n "${WINEDEBUG:-}" ]; then
            GAMECTL_DEV_RESPECTED_USER_WINEDEBUG=1
        else
            GAMECTL_DEV_RESOLVED_WINEDEBUG="$mapped_wd"
        fi
    fi

    local vk_lc="${GAMECTL_CFG_DEV_VK_DEBUG:-0}"
    vk_lc="${vk_lc,,}"
    if [ "$vk_lc" = "1" ] || [ "$vk_lc" = "true" ]; then
        GAMECTL_DEV_ACTIVE=1
        if [ -n "${VK_LOADER_DEBUG:-}" ]; then
            GAMECTL_DEV_RESPECTED_USER_VK_DEBUG=1
        else
            GAMECTL_DEV_RESOLVED_VK_DEBUG="all"
        fi
    fi

    local gbe_lc="${GAMECTL_CFG_DEV_GBE_LOG:-0}"
    gbe_lc="${gbe_lc,,}"
    if [ "$gbe_lc" = "1" ] || [ "$gbe_lc" = "true" ]; then
        GAMECTL_DEV_ACTIVE=1
        GAMECTL_DEV_RESOLVED_GBE_LOG=1
    fi

    if [ "$GAMECTL_DEV_ACTIVE" -eq 1 ]; then
        local base_slug hash_part
        base_slug=$(basename "${gdir:-global}" | tr -cd '[:alnum:]_-')
        [ -z "$base_slug" ] && base_slug="game"
        hash_part=$(printf '%s' "${gdir:-global}" | cksum | awk '{print $1}')
        GAMECTL_DEV_TRACE_LOG="$(get_runtime_dir)/dev_traces/${base_slug}_${hash_part}.log"
    fi
}

# CLI helper for per-game developer profiler configuration
configure_dev_profile() {
    local gdir="${1:-}"
    local mode="${2:-status}"

    if [ -z "$gdir" ] || [ ! -d "$gdir" ]; then
        echo "[ERROR] Game directory not found: ${gdir:-<empty>}" >&2
        echo "Usage: gamectl dev-profile <game_dir> [status|basic|full|off]" >&2
        return 1
    fi

    local w_file="$gdir/.wrappers"
    case "$mode" in
        status)
            resolve_dev_profiler_env "$gdir" 1
            echo "dev_winedebug=${GAMECTL_CFG_DEV_WINEDEBUG:-0}"
            echo "dev_vk_debug=${GAMECTL_CFG_DEV_VK_DEBUG:-0}"
            echo "dev_gbe_log=${GAMECTL_CFG_DEV_GBE_LOG:-0}"
            echo "active=$GAMECTL_DEV_ACTIVE"
            echo "resolved_winedebug=$GAMECTL_DEV_RESOLVED_WINEDEBUG"
            echo "resolved_vk_debug=$GAMECTL_DEV_RESOLVED_VK_DEBUG"
            echo "trace_log=$GAMECTL_DEV_TRACE_LOG"
            ;;
        basic)
            atomic_set_kv_file "$w_file" "dev_winedebug" "basic" && \
            atomic_set_kv_file "$w_file" "dev_vk_debug" "0" && \
            atomic_set_kv_file "$w_file" "dev_gbe_log" "1" || return 1
            echo "[VERIFIED] Developer profiler set to 'basic' in $w_file"
            ;;
        full)
            atomic_set_kv_file "$w_file" "dev_winedebug" "full" && \
            atomic_set_kv_file "$w_file" "dev_vk_debug" "1" && \
            atomic_set_kv_file "$w_file" "dev_gbe_log" "1" || return 1
            echo "[VERIFIED] Developer profiler set to 'full' in $w_file"
            ;;
        off)
            atomic_set_kv_file "$w_file" "dev_winedebug" "0" && \
            atomic_set_kv_file "$w_file" "dev_vk_debug" "0" && \
            atomic_set_kv_file "$w_file" "dev_gbe_log" "0" || return 1
            echo "[VERIFIED] Developer profiler disabled in $w_file"
            ;;
        *)
            echo "Usage: gamectl dev-profile <game_dir> [status|basic|full|off]" >&2
            return 1
            ;;
    esac
}

# Resolve and build wrapper prefix command array (gamemoderun, mangohud, gamescope)
build_wrapper_command() {
    local gdir="$1"
    shift || true
    local opt_gamemode="" opt_hud="" opt_gamescope="" opt_fsr="" opt_systemd_scope="" opt_prime="" opt_sandbox="" opt_allow_unshielded="" opt_renderer=""
    local remaining_args=()

    while [ $# -gt 0 ]; do
        case "$1" in
            --hud|--mangohud) opt_hud=1; shift ;;
            --no-hud|--no-mangohud) opt_hud=0; shift ;;
            --gamemode) opt_gamemode=1; shift ;;
            --no-gamemode) opt_gamemode=0; shift ;;
            --gamescope) opt_gamescope=1; shift ;;
            --no-gamescope) opt_gamescope=0; shift ;;
            --fsr) opt_fsr=1; opt_gamescope=1; shift ;;
            --no-fsr) opt_fsr=0; shift ;;
            --glthread) opt_glthread=1; shift ;;
            --no-glthread) opt_glthread=0; shift ;;
            --scope|--systemd-scope) opt_systemd_scope=1; shift ;;
            --no-scope|--no-systemd-scope) opt_systemd_scope=0; shift ;;
            --prime) opt_prime=1; shift ;;
            --no-prime) opt_prime=0; shift ;;
            --sandbox) opt_sandbox=1; shift ;;
            --no-sandbox) opt_sandbox=0; shift ;;
            --wined3d|--opengl) opt_renderer="wined3d"; shift ;;
            --dxvk|--vulkan) opt_renderer="dxvk"; shift ;;
            --renderer) opt_renderer="${2:-auto}"; shift 2 ;;
            --renderer=*) opt_renderer="${1#*=}"; shift ;;
            --allow-unshielded) opt_allow_unshielded=1; shift ;;
            --) shift; remaining_args+=("$@"); break ;;
            *) remaining_args+=("$1"); shift ;;
        esac
    done

    # 1. Load config hierarchy + env overrides via SSoT
    load_wrapper_config "$gdir" 1
    local use_gm="$GAMECTL_CFG_GM"
    local use_hud="$GAMECTL_CFG_HUD"
    local use_scope="$GAMECTL_CFG_SCOPE"
    local use_fsr="$GAMECTL_CFG_FSR"
    local use_glthread="$GAMECTL_CFG_GLTHREAD"
    local use_systemd_scope="$GAMECTL_CFG_SYSTEMD_SCOPE"
    local use_prime="$GAMECTL_CFG_PRIME"
    local use_sandbox="$GAMECTL_CFG_SANDBOX"
    local use_renderer="$GAMECTL_CFG_RENDERER"
    local gscope_args="${GAMECTL_CFG_GAMESCOPE_ARGS:-}"
    [ -z "$gscope_args" ] && gscope_args=$(get_default_gamescope_args)

    # 5. CLI flag overrides
    [ -n "$opt_gamemode" ] && use_gm="$opt_gamemode"
    [ -n "$opt_hud" ] && use_hud="$opt_hud"
    [ -n "$opt_gamescope" ] && use_scope="$opt_gamescope"
    [ -n "$opt_fsr" ] && use_fsr="$opt_fsr"
    [ -n "${opt_glthread:-}" ] && use_glthread="$opt_glthread"
    [ -n "${opt_systemd_scope:-}" ] && use_systemd_scope="$opt_systemd_scope"
    [ -n "$opt_prime" ] && use_prime="$opt_prime"
    [ -n "$opt_sandbox" ] && use_sandbox="$opt_sandbox"
    [ -n "$opt_renderer" ] && use_renderer="$opt_renderer"

    if [ -z "${use_systemd_scope:-}" ]; then
        if check_systemd_scope_support; then
            use_systemd_scope=1
        else
            use_systemd_scope=0
        fi
    fi

    local dgpu_vendor="none"
    if [ "$use_prime" = "1" ]; then
        dgpu_vendor=$(detect_dgpu_vendor)
        if [ "$dgpu_vendor" = "none" ]; then
            echo "[WARN] PRIME offloading requested (--prime) but no secondary dGPU detected." >&2
        fi
    fi

    declare -ga GAMECTL_SANDBOX_PREFIX=()
    if [ "$use_sandbox" = "1" ]; then
        build_sandbox_command "$gdir" || use_sandbox=0
    fi

    local resolved_renderer
    resolved_renderer="$(resolve_graphics_renderer "$use_renderer" "$use_prime")"
    GAMECTL_RENDERER_MODE="$use_renderer"
    GAMECTL_ACTIVE_RENDERER="$resolved_renderer"
    GAMECTL_ACTIVE_GLTHREAD="$use_glthread"
    GAMECTL_ACTIVE_SYSTEMD_SCOPE="$use_systemd_scope"
    GAMECTL_ACTIVE_PRIME="$use_prime"
    GAMECTL_ACTIVE_PRIME_VENDOR="$dgpu_vendor"
    GAMECTL_ACTIVE_SANDBOX="$use_sandbox"
    GAMECTL_ACTIVE_ALLOW_UNSHIELDED="${opt_allow_unshielded:-0}"
    GAMECTL_ACTIVE_AUTO_LOCATE_SAVES="${GAMECTL_CFG_AUTO_LOCATE_SAVES:-0}"

    local prefix=()
    if [ "$use_gm" = "1" ]; then
        if command -v gamemoderun >/dev/null 2>&1; then
            prefix+=("gamemoderun")
        else
            echo "[WARN] gamemoderun is enabled but binary not found in PATH." >&2
        fi
    fi

    if [ "$use_hud" = "1" ]; then
        if command -v mangohud >/dev/null 2>&1; then
            prefix+=("mangohud")
        else
            echo "[WARN] mangohud is enabled but binary not found in PATH." >&2
        fi
    fi

    if [ "$use_scope" = "1" ] || [ "$use_fsr" = "1" ]; then
        if command -v gamescope >/dev/null 2>&1; then
            prefix+=("gamescope")
            local active_args="$gscope_args"
            if [ "$use_fsr" = "1" ] && [[ ! "$active_args" =~ (-F|fsr|-U) ]]; then
                active_args="-F fsr $active_args"
            elif [ "$use_fsr" = "0" ]; then
                active_args=$(echo "$active_args" | sed -E 's/-F[[:space:]]+fsr//g' | xargs)
            fi
            if [ -n "$active_args" ]; then
                read -r -a parsed_args <<< "$active_args"
                prefix+=("${parsed_args[@]}")
            fi
            prefix+=("--")
        else
            echo "[WARN] gamescope is enabled but binary not found in PATH." >&2
        fi
    fi

    GAMECTL_WRAPPER_PREFIX=("${prefix[@]}")
    GAMECTL_REMAINING_ARGS=("${remaining_args[@]}")
}

# Standalone-source compatibility: load split runner submodules when sourced directly outside bin/gamectl
if [ -z "${GAMECTL_BUNDLED:-}" ] && [ -n "${BASH_SOURCE[0]:-}" ]; then
    _runners_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd)"
    for _runners_sub in 41_proton_prefix.sh 42_graphics_isolation.sh 43_proton_manager.sh 44_native_runtime.sh 45_wrapper_tui.sh; do
        if [ -f "$_runners_dir/$_runners_sub" ]; then
            # shellcheck source=/dev/null
            source "$_runners_dir/$_runners_sub"
        fi
    done
    unset _runners_dir _runners_sub
fi

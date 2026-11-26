# Check if host GPU is Intel Haswell / 4th Gen Core (prone to Mesa GL threaded asset decompression crashes)
is_haswell_gpu() {
    local pci_dir="${GAMECTL_PCI_UEVENT_DIR:-/sys/bus/pci/devices}"
    if [ -z "${GAMECTL_PCI_UEVENT_DIR:-}" ] && command -v lspci >/dev/null 2>&1; then
        local gpu_info
        gpu_info=$(lspci 2>/dev/null | grep -E "VGA|3D" || true)
        if echo "$gpu_info" | grep -qi -E "Haswell|4th Gen Core"; then
            return 0
        fi
    fi
    if [ -d "$pci_dir" ]; then
        local uev
        for uev in "$pci_dir"/*/uevent; do
            [ -f "$uev" ] || continue
            grep -qiE '^PCI_CLASS=0?3(00|02|80)00' "$uev" 2>/dev/null || continue
            grep -qiE '^PCI_ID=8086:(04|0a|0d)[0-9a-f]{2}$' "$uev" 2>/dev/null && return 0
        done
    fi
    return 1
}

# Canonical 2-tier host Vulkan capability probe (zero hardcode vendor dependency)
# Outputs: VULKAN_READY | VULKAN_LEGACY | OPENGL_ONLY
detect_vulkan_capability() {
    if [ -n "${GAMECTL_VULKAN_CAPABILITY:-}" ]; then
        echo "$GAMECTL_VULKAN_CAPABILITY"
        return 0
    fi

    # Tier 1: Runtime per-device probe via vulkaninfo --summary when available
    if command -v vulkaninfo >/dev/null 2>&1; then
        local v_sum
        v_sum=$(vulkaninfo --summary 2>&1 || true)
        if echo "$v_sum" | grep -q -E '(^|[[:space:]])GPU[0-9]+:|PHYSICAL_DEVICE_TYPE_'; then
            local vk_tier
            vk_tier=$(printf '%s\n' "$v_sum" | awk '
                function flush_gpu(    ver_str, p, maj, min, score) {
                    if (in_gpu != 1) return
                    if (cur_type !~ /PHYSICAL_DEVICE_TYPE_(DISCRETE|INTEGRATED)_GPU/) return
                    if (tolower(cur_name) ~ /(llvmpipe|swiftshader)/) return
                    hw_count++
                    if (match(cur_ver, /[0-9]+\.[0-9]+\.[0-9]+/)) {
                        ver_str = substr(cur_ver, RSTART, RLENGTH)
                        split(ver_str, p, ".")
                        maj = p[1] + 0
                        min = p[2] + 0
                        score = maj * 1000 + min
                        if (score > max_score) {
                            max_score = score
                            max_maj = maj
                            max_min = min
                        }
                        if (cur_type ~ /PHYSICAL_DEVICE_TYPE_DISCRETE_GPU/ && (maj > 1 || (maj == 1 && min >= 3))) {
                            has_modern_dgpu = 1
                        }
                    }
                }
                BEGIN {
                    in_gpu = 0; hw_count = 0; max_score = -1; max_maj = 0; max_min = 0;
                    has_modern_dgpu = 0; incomplete_warn = 0;
                    cur_ver = ""; cur_type = ""; cur_name = "";
                }
                {
                    if (tolower($0) ~ /vulkan support is incomplete|non-conformant/) {
                        incomplete_warn = 1
                    }
                }
                /^[[:space:]]*GPU[0-9]+:/ {
                    flush_gpu()
                    in_gpu = 1
                    cur_ver = ""; cur_type = ""; cur_name = ""
                    next
                }
                in_gpu == 1 && /apiVersion[[:space:]]*=/ { cur_ver = $0; next }
                in_gpu == 1 && /deviceType[[:space:]]*=/ { cur_type = $0; next }
                in_gpu == 1 && /deviceName[[:space:]]*=/ { cur_name = $0; next }
                END {
                    flush_gpu()
                    if (hw_count == 0) {
                        print "OPENGL_ONLY"
                    } else if (max_maj > 1 || (max_maj == 1 && max_min >= 3)) {
                        if (incomplete_warn == 1 && has_modern_dgpu == 0) {
                            print "VULKAN_LEGACY"
                        } else {
                            print "VULKAN_READY"
                        }
                    } else if (max_maj == 1 && max_min >= 1) {
                        print "VULKAN_LEGACY"
                    } else {
                        print "OPENGL_ONLY"
                    }
                }
            ')
            if [ -n "$vk_tier" ]; then
                echo "$vk_tier"
                return 0
            fi
        elif echo "$v_sum" | grep -qiE 'Cannot create Vulkan instance|ERROR_INCOMPATIBLE_DRIVER'; then
            echo "OPENGL_ONLY"
            return 0
        fi
    fi

    # Tier 2: Kernel DRM driver & Vulkan ICD manifest inspection
    local icd_files=() icd
    for icd in /usr/share/vulkan/icd.d/*.json /etc/vulkan/icd.d/*.json; do
        [ -f "$icd" ] && icd_files+=("$icd")
    done
    if [ ${#icd_files[@]} -eq 0 ]; then
        echo "OPENGL_ONLY"
        return 0
    fi

    local has_hw_icd=0 has_modern_icd=0
    for icd in "${icd_files[@]}"; do
        local bname
        bname="$(basename "$icd")"
        case "$bname" in
            *lvp*|*swiftshader*|*virtio*) ;;
            *hasvk*) has_hw_icd=1 ;;
            *) has_hw_icd=1; has_modern_icd=1 ;;
        esac
    done
    if [ "$has_hw_icd" -eq 0 ]; then
        echo "OPENGL_ONLY"
        return 0
    fi

    local dgpu_vend="none"
    type detect_dgpu_vendor >/dev/null 2>&1 && dgpu_vend="$(detect_dgpu_vendor 2>/dev/null || echo none)"
    if [ "$dgpu_vend" = "none" ]; then
        if is_haswell_gpu; then
            echo "VULKAN_LEGACY"
            return 0
        fi
        local pci_vga=""
        command -v lspci >/dev/null 2>&1 && pci_vga=$(lspci 2>/dev/null | grep -E "VGA|3D" || true)
        if echo "$pci_vga" | grep -qi -E "Ivy Bridge|3rd Gen Core|HD Graphics 2500|HD Graphics 4000"; then
            echo "VULKAN_LEGACY"
            return 0
        fi
        local has_modern_drv=0 has_legacy_drv=0 drv_link drv_name
        for drv_link in /sys/class/drm/card[0-9]*/device/driver; do
            [ -L "$drv_link" ] || continue
            drv_name="$(basename "$(readlink -f "$drv_link" 2>/dev/null)" 2>/dev/null || true)"
            case "$drv_name" in
                amdgpu|nvidia|xe|i915) has_modern_drv=1 ;;
                radeon|nouveau|vmwgfx|virtio-pci|bochs-drm|qxl|vboxvideo) has_legacy_drv=1 ;;
            esac
        done
        if [ "$has_modern_drv" -eq 0 ] && [ "$has_legacy_drv" -eq 1 ]; then
            echo "VULKAN_LEGACY"
            return 0
        fi
    fi

    if [ "$has_modern_icd" -eq 1 ]; then
        echo "VULKAN_READY"
    else
        echo "VULKAN_LEGACY"
    fi
    return 0
}

# Resolve effective graphics renderer (dxvk | wined3d) from mode + host capability
resolve_graphics_renderer() {
    local mode="${1:-auto}"
    local prime_active="${2:-0}"
    mode="${mode,,}"

    case "$mode" in
        wined3d|opengl|gl)
            echo "wined3d"
            ;;
        dxvk|vulkan|vk)
            echo "dxvk"
            ;;
        auto|"")
            if [ "$prime_active" = "1" ]; then
                echo "dxvk"
            else
                local cap
                cap="$(detect_vulkan_capability)"
                case "$cap" in
                    VULKAN_READY) echo "dxvk" ;;
                    *)            echo "wined3d" ;;
                esac
            fi
            ;;
        *)
            echo "dxvk"
            ;;
    esac
}

# Dynamically detect host native display resolution via DRM / Wayland / X11
get_native_resolution() {
    local res=""
    # Priority 1: DRM kernel modes (direct & universal across all compositors/X11)
    for m_file in /sys/class/drm/card*-*/modes; do
        [ -f "$m_file" ] || continue
        local s_file; s_file="$(dirname "$m_file")/status"
        if [ -f "$s_file" ] && grep -q "^connected" "$s_file" 2>/dev/null; then
            local line
            line=$(head -n 1 "$m_file" 2>/dev/null | tr -d '[:space:]')
            if [[ "$line" =~ ^[0-9]+x[0-9]+$ ]]; then
                res="$line"
                break
            fi
        fi
    done

    # Priority 2: Hyprland monitor inspection
    if [ -z "$res" ] && command -v hyprctl >/dev/null 2>&1; then
        res=$(hyprctl monitors 2>/dev/null | grep -E '^[[:space:]]*[0-9]+x[0-9]+@' | head -n 1 | sed -E 's/.*([0-9]+x[0-9]+)@.*/\1/' || true)
    fi

    # Priority 3: X11 / Xwayland via xrandr
    if [ -z "$res" ] && command -v xrandr >/dev/null 2>&1; then
        res=$(xrandr --current 2>/dev/null | grep -E '\bconnected\b' | grep -o -E '[0-9]+x[0-9]+\+[0-9]+\+[0-9]+' | head -n 1 | cut -d'+' -f1 || true)
        [ -z "$res" ] && res=$(xrandr --current 2>/dev/null | grep -E '^[[:space:]]+[0-9]+x[0-9]+' | head -n 1 | awk '{print $1}' || true)
    fi

    # Fallback default
    if [[ ! "$res" =~ ^[0-9]+x[0-9]+$ ]]; then
        res="1920x1080"
    fi
    echo "$res"
}

# Dynamically calculate Gamescope display & FSR render arguments based on native resolution
get_default_gamescope_args() {
    local n_res
    n_res=$(get_native_resolution)
    local nw="${n_res%x*}"
    local nh="${n_res#*x}"

    local rw rh
    if [ "$nw" -ge 3840 ] && [ "$nh" -ge 2160 ]; then
        rw=2560; rh=1440
    elif [ "$nw" -ge 2560 ] && [ "$nh" -ge 1440 ]; then
        rw=1920; rh=1080
    elif [ "$nw" -eq 1920 ] && [ "$nh" -eq 1080 ]; then
        rw=1280; rh=720
    elif [ "$nw" -eq 1600 ] && [ "$nh" -eq 900 ]; then
        rw=1280; rh=720
    elif [ "$nw" -eq 1280 ] && [ "$nh" -eq 800 ]; then
        rw=960; rh=600
    else
        rw=$(( (nw * 2 / 3 + 1) / 2 * 2 ))
        rh=$(( (nh * 2 / 3 + 1) / 2 * 2 ))
    fi
    echo "-W $rw -H $rh -w $nw -h $nh -F fsr -f"
}

# Check if systemd user daemon and cgroups v2 scope unit execution is supported
check_systemd_scope_support() {
    if command -v systemd-run >/dev/null 2>&1 && command -v systemctl >/dev/null 2>&1; then
        if systemd-run --user --scope --quiet true 2>/dev/null; then
            return 0
        fi
    fi
    return 1
}

# Detect discrete secondary GPU vendor on hybrid systems (NVIDIA, AMD, Intel Arc)
detect_dgpu_vendor() {
    if [ -n "${GAMECTL_DGPU_VENDOR:-}" ]; then
        echo "$GAMECTL_DGPU_VENDOR"
        return 0
    fi

    local vga_count=0
    local vendors=()

    for dev in /sys/bus/pci/devices/*; do
        [ -f "$dev/class" ] || continue
        local pci_class
        pci_class=$(cat "$dev/class" 2>/dev/null || echo "")
        case "$pci_class" in
            0x0302*)
                # Secondary 3D controller (Optimized for 3D acceleration / dGPU)
                local v_id
                v_id=$(cat "$dev/vendor" 2>/dev/null || echo "")
                case "$v_id" in
                    0x10de) echo "nvidia"; return 0 ;;
                    0x1002) echo "amd"; return 0 ;;
                    0x8086) echo "intel"; return 0 ;;
                esac
                ;;
            0x0300*)
                vga_count=$((vga_count + 1))
                local v_id
                v_id=$(cat "$dev/vendor" 2>/dev/null || echo "")
                vendors+=("$v_id")
                ;;
        esac
    done

    # If multiple display controllers exist without a specific 0x0302 class device
    if [ "$vga_count" -gt 1 ]; then
        for v in "${vendors[@]}"; do
            if [ "$v" = "0x10de" ]; then
                echo "nvidia"
                return 0
            fi
        done
        local has_amd=false has_intel=false amd_count=0
        for v in "${vendors[@]}"; do
            [ "$v" = "0x1002" ] && { has_amd=true; amd_count=$((amd_count + 1)); }
            [ "$v" = "0x8086" ] && has_intel=true
        done
        if [ "$has_amd" = true ] && [ "$has_intel" = true ]; then
            echo "amd"
            return 0
        fi
        if [ "$amd_count" -gt 1 ]; then
            echo "amd"
            return 0
        fi
    fi

    echo "none"
    return 0
}

# Construct rootless Bubblewrap (bwrap) security sandbox argument array
build_sandbox_command() {
    local gdir="$1"
    declare -ga GAMECTL_SANDBOX_PREFIX=()

    if ! command -v bwrap >/dev/null 2>&1; then
        echo "[WARN] bubblewrap (bwrap) not found in PATH. Sandboxing skipped." >&2
        return 1
    fi

    local desktop_runtime_dir app_runtime_dir
    desktop_runtime_dir="$(get_desktop_runtime_dir)"
    app_runtime_dir="$(get_runtime_dir)"
    local wayland_socket="${WAYLAND_DISPLAY:-wayland-0}"
    local xauth_file="${XAUTHORITY:-$HOME/.Xauthority}"

    GAMECTL_SANDBOX_PREFIX=(
        bwrap
        --ro-bind /usr /usr
        --ro-bind-try /lib /lib
        --ro-bind-try /lib64 /lib64
        --ro-bind-try /bin /bin
        --ro-bind-try /sbin /sbin
        --ro-bind-try /etc /etc
        --proc /proc
        --dev /dev
        --ro-bind /sys /sys
        --tmpfs /tmp
        --ro-bind-try /tmp/.X11-unix /tmp/.X11-unix
        --tmpfs /run
        --tmpfs "$desktop_runtime_dir"
        --bind-try "$desktop_runtime_dir/wayland-0" "$desktop_runtime_dir/wayland-0"
        --bind-try "$desktop_runtime_dir/$wayland_socket" "$desktop_runtime_dir/$wayland_socket"
        --bind-try "$desktop_runtime_dir/pipewire-0" "$desktop_runtime_dir/pipewire-0"
        --bind-try "$desktop_runtime_dir/pulse" "$desktop_runtime_dir/pulse"
        --bind-try "$app_runtime_dir" "$app_runtime_dir"
        --tmpfs "$HOME"
        --ro-bind-try "$xauth_file" "$xauth_file"
        --bind-try "$HOME/.config/gamectl" "$HOME/.config/gamectl"
        --ro-bind-try "${XDG_DATA_HOME:-$HOME/.local/share}/gamectl/runners" "${XDG_DATA_HOME:-$HOME/.local/share}/gamectl/runners"
        --ro-bind-try "$HOME/.local/share/Steam" "$HOME/.local/share/Steam"
        --ro-bind-try "$HOME/.local/share/gbe-fork" "$HOME/.local/share/gbe-fork"
        --ro-bind-try "$HOME/.steam" "$HOME/.steam"
        --bind-try "$HOME/.local/share/vulkan" "$HOME/.local/share/vulkan"
        --bind "$gdir" "$gdir"
        --chdir "$gdir"
        --unshare-user
        --unshare-ipc
        --unshare-pid
        --die-with-parent
    )
    return 0
}

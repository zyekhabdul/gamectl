#!/usr/bin/env bash
# ==============================================================================
# gamectl - Turnkey Installer (Local Repository & Piped Web Execution)
# ==============================================================================
# Usage:
#   Local Clone:    ./install.sh [--dry-run] [--force]
#   Piped Remote:   curl -fsSL https://raw.githubusercontent.com/zyekhabdul/gamectl/main/install.sh | bash
#   Piped Dry-Run:  curl -fsSL https://raw.githubusercontent.com/zyekhabdul/gamectl/main/install.sh | bash -s -- --dry-run
# ==============================================================================
set -euo pipefail

BIN_DIR="$HOME/.local/bin"
CONFIG_DIR="$HOME/.config/gamectl"
COMPLETION_DIR="$HOME/.local/share/bash-completion/completions"
APP_DIR="$HOME/.local/share/applications"

REPO_RAW_URL="${GAMECTL_RAW_URL:-https://raw.githubusercontent.com/zyekhabdul/gamectl/main}"

DRY_RUN=false
FORCE=false

while [ $# -gt 0 ]; do
    case "$1" in
        --dry-run|-n)
            DRY_RUN=true
            shift
            ;;
        --force|-f)
            FORCE=true
            shift
            ;;
        --help|-h)
            echo "Usage: install.sh [OPTIONS]"
            echo
            echo "Options:"
            echo "  --dry-run, -n   Simulate installation without modifying the system"
            echo "  --force, -f     Overwrite existing configuration templates and binaries"
            echo "  --help, -h      Show this help documentation"
            exit 0
            ;;
        *)
            echo "[WARN] Unknown argument: $1"
            shift
            ;;
    esac
done

if [ "$DRY_RUN" = true ]; then
    echo "[INFO] Running gamectl installer in DRY-RUN mode (Simulation only)."
fi

# Detect local repository execution vs piped remote execution
SCRIPT_SOURCE="${BASH_SOURCE[0]:-}"
IS_LOCAL=false
SRC_DIR=""
SRC_BIN=""

if [ -n "$SCRIPT_SOURCE" ] && [ "$SCRIPT_SOURCE" != "bash" ] && [ -f "$SCRIPT_SOURCE" ]; then
    SRC_DIR="$(cd "$(dirname "$SCRIPT_SOURCE")" && pwd)"
    if [ -f "$SRC_DIR/bin/gamectl" ] || [ -f "$SRC_DIR/scripts/build.sh" ]; then
        IS_LOCAL=true
        SRC_BIN="$SRC_DIR/bin/gamectl"
    fi
fi

if [ "$IS_LOCAL" = true ]; then
    echo "[INFO] Detected local repository source at: $SRC_DIR"
    if [ -f "$SRC_DIR/scripts/build.sh" ] && [ -d "$SRC_DIR/src" ]; then
        if [ ! -f "$SRC_BIN" ] || ! "$SRC_DIR/scripts/build.sh" --check >/dev/null 2>&1; then
            if [ "$DRY_RUN" = true ]; then
                echo "[INFO] [DRY-RUN] Would compile modular sources into bin/gamectl"
            else
                echo "[INFO] Compiling modular sources into bin/gamectl..."
                "$SRC_DIR/scripts/build.sh"
            fi
        fi
    fi
else
    echo "[INFO] Running turnkey piped web installer (remote endpoint: $REPO_RAW_URL)"
fi

# Audit system dependencies
echo "[INFO] Auditing core system dependencies..."
MISSING_DEPS=()
for cmd in fzf jq curl rsync ssh file zip unzip python3; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
        MISSING_DEPS+=("$cmd")
    fi
done

if [ ${#MISSING_DEPS[@]} -gt 0 ]; then
    echo "[ERROR] Missing required system dependencies: ${MISSING_DEPS[*]}" >&2
    echo "        Please install missing tools via your Linux distribution package manager:" >&2
    echo "        • Arch Linux : sudo pacman -S ${MISSING_DEPS[*]}" >&2
    echo "        • Debian/Ubuntu: sudo apt install ${MISSING_DEPS[*]}" >&2
    echo "        • Fedora     : sudo dnf install ${MISSING_DEPS[*]}" >&2
    if [ "$DRY_RUN" = false ]; then
        exit 1
    fi
else
    echo "[VERIFIED] All core system dependencies found."
fi

# Audit Python YAML engine for SLSsteam sync
if python3 -c "import ruamel.yaml" >/dev/null 2>&1; then
    echo "[VERIFIED] Python: ruamel.yaml detected (YAML layout-preserving mode active)."
elif python3 -c "import yaml" >/dev/null 2>&1; then
    echo "[INFO] Python: PyYAML detected."
else
    echo "[WARN] Python YAML engine not found ('python-ruamel-yaml' or 'python-yaml')."
    echo "       Required for offline entitlement synchronization."
fi

# Audit Decentralized LAN runtime templates (Goldberg Emulator Fork)
GBE_X64="$HOME/.local/share/gbe-fork/regular/x64/libsteam_api.so"
GBE_X86="$HOME/.local/share/gbe-fork/regular/x86/libsteam_api.so"

GBE_WIN_X64=""
for p in "$HOME/.local/share/gbe-fork/windows/release/regular/x64/steam_api64.dll" \
         "$HOME/.local/share/gbe-fork/windows/regular/x64/steam_api64.dll" \
         "$HOME/.local/share/gbe-fork/regular/x64/steam_api64.dll"; do
    if [ -f "$p" ]; then GBE_WIN_X64="$p"; break; fi
done

GBE_WIN_X86=""
for p in "$HOME/.local/share/gbe-fork/windows/release/regular/x86/steam_api.dll" \
         "$HOME/.local/share/gbe-fork/windows/regular/x86/steam_api.dll" \
         "$HOME/.local/share/gbe-fork/regular/x86/steam_api.dll"; do
    if [ -f "$p" ]; then GBE_WIN_X86="$p"; break; fi
done

if [ -f "$GBE_X64" ]; then
    echo "[VERIFIED] Decentralized LAN runtime Linux x64 detected: $GBE_X64"
else
    echo "[WARN] Decentralized LAN runtime Linux x64 template missing in: $GBE_X64"
    echo "       Install libsteam_api.so to ~/.local/share/gbe-fork/regular/x64/ for 'gamectl inject'."
fi

if [ -f "$GBE_X86" ]; then
    echo "[VERIFIED] Decentralized LAN runtime Linux x86 detected: $GBE_X86"
fi

if [ -n "$GBE_WIN_X64" ]; then
    echo "[VERIFIED] Decentralized LAN runtime Windows x64 detected: $GBE_WIN_X64"
else
    echo "[WARN] Decentralized LAN runtime Windows x64 template missing (steam_api64.dll)."
fi

if [ -n "$GBE_WIN_X86" ]; then
    echo "[VERIFIED] Decentralized LAN runtime Windows x86 detected: $GBE_WIN_X86"
else
    echo "[WARN] Decentralized LAN runtime Windows x86 template missing (steam_api.dll)."
fi

# Audit Windows compatibility runners (umu-run, GE-Proton, Wine)
RUNNER_INFO=""
if command -v umu-run >/dev/null 2>&1; then
    RUNNER_INFO="umu-run ($(command -v umu-run))"
elif [ -d "$HOME/.local/share/Steam/compatibilitytools.d" ] && find "$HOME/.local/share/Steam/compatibilitytools.d" -mindepth 1 -maxdepth 1 -type d -name "*Proton*" 2>/dev/null | grep -q .; then
    p_name=$(find "$HOME/.local/share/Steam/compatibilitytools.d" -mindepth 1 -maxdepth 1 -type d -name "*Proton*" | head -n 1 | xargs basename)
    RUNNER_INFO="GE-Proton ($p_name)"
elif command -v wine64 >/dev/null 2>&1; then
    RUNNER_INFO="System Wine ($(command -v wine64))"
elif command -v wine >/dev/null 2>&1; then
    RUNNER_INFO="System Wine ($(command -v wine))"
fi

if [ -n "$RUNNER_INFO" ]; then
    echo "[VERIFIED] Windows compatibility runner detected: $RUNNER_INFO"
else
    echo "[WARN] No Windows runner found (umu-run, GE-Proton, or wine)."
    echo "       Install GE-Proton into ~/.local/share/Steam/compatibilitytools.d/ to run Windows games."
fi

# Audit performance and display wrappers
WRAPPER_STATUS=()
command -v gamemoderun >/dev/null 2>&1 && WRAPPER_STATUS+=("gamemode: [READY]") || WRAPPER_STATUS+=("gamemode: [N/A]")
command -v mangohud >/dev/null 2>&1 && WRAPPER_STATUS+=("mangohud: [READY]") || WRAPPER_STATUS+=("mangohud: [N/A]")
command -v gamescope >/dev/null 2>&1 && WRAPPER_STATUS+=("gamescope: [READY]") || WRAPPER_STATUS+=("gamescope: [N/A]")
echo "[INFO] Performance wrappers: ${WRAPPER_STATUS[*]}"

# Scaffold configuration directory and templates
if [ "$DRY_RUN" = true ]; then
    echo "[INFO] [DRY-RUN] Would scaffold user configuration in: $CONFIG_DIR"
else
    mkdir -p "$CONFIG_DIR"

    if [ ! -f "$CONFIG_DIR/wrappers.example" ] || [ "$FORCE" = true ]; then
        DEF_GSCOPE_ARGS="-W 1280 -H 720 -w 1920 -h 1080 -F fsr -f"
        if [ -n "$SRC_BIN" ] && [ -x "$SRC_BIN" ]; then
            D_ARGS=$("$SRC_BIN" get-gamescope-args 2>/dev/null || true)
            [ -n "$D_ARGS" ] && DEF_GSCOPE_ARGS="$D_ARGS"
        fi
        cat <<EOF > "$CONFIG_DIR/wrappers.example"
# ==============================================================================
# gamectl - Default Runtime Performance & Display Wrappers
# ==============================================================================
# Copy this file to 'wrappers' in ~/.config/gamectl/wrappers to enable global defaults.
# Values: 1 (enabled), 0 (disabled)
#
gamemode=0
hud=0
gamescope=0
fsr=0
gamescope_args=$DEF_GSCOPE_ARGS
EOF
        echo "[INFO] Configuration template created: $CONFIG_DIR/wrappers.example"
    fi

    if [ ! -f "$CONFIG_DIR/persona.example" ] || [ "$FORCE" = true ]; then
        cat <<'EOF' > "$CONFIG_DIR/persona.example"
# ==============================================================================
# gamectl - Default LAN Multi-Identity & SteamID Persona
# ==============================================================================
# Copy this file to 'persona' in ~/.config/gamectl/persona to set default gamer tags.
#
account_name=Player
account_steamid=76561198000000001
language=english
# Custom broadcast IP or subnet peers for LAN co-op discovery (comma-separated):
# broadcasts=127.0.0.1,255.255.255.255,192.168.1.50
EOF
        echo "[INFO] Configuration template created: $CONFIG_DIR/persona.example"
    fi

    if [ ! -f "$CONFIG_DIR/libraries.example" ] || [ "$FORCE" = true ]; then
        cat <<'EOF' > "$CONFIG_DIR/libraries.example"
# ==============================================================================
# gamectl - Custom Game Library Directories
# ==============================================================================
# List one game library directory per line.
# Lines beginning with '#' are comments. Tilde (~) expands to \$HOME.
#
# Examples:
# ~/Games
# ~/Downloads/LinuxGames
# /mnt/storage/games/steamapps/common
EOF
        echo "[INFO] Configuration template created: $CONFIG_DIR/libraries.example"
    fi



    if [ ! -f "$CONFIG_DIR/remote_host.example" ] || [ "$FORCE" = true ]; then
        cat <<'EOF' > "$CONFIG_DIR/remote_host.example"
# ==============================================================================
# gamectl - Remote Savegame Sync Host
# ==============================================================================
# Copy this file to 'remote_host' and fill with SSH alias or IP address.
# Used by <Ctrl-S> or 'gamectl --sync' to synchronize portable savegames.
#
# Examples:
# steamdeck
# companion-pc
# 192.168.1.50
EOF
        echo "[INFO] Configuration template created: $CONFIG_DIR/remote_host.example"
    fi
fi

# Install standalone binary and aliases
if [ "$DRY_RUN" = true ]; then
    echo "[INFO] [DRY-RUN] Would install executable to: $BIN_DIR/gamectl"
    echo "[INFO] [DRY-RUN] Would create shorthand symlink: $BIN_DIR/game -> gamectl"
else
    mkdir -p "$BIN_DIR"
    if [ "$IS_LOCAL" = true ]; then
        chmod +x "$SRC_BIN"
        ln -sf "$SRC_BIN" "$BIN_DIR/gamectl"
        ln -sf "$SRC_BIN" "$BIN_DIR/game"
    else
        echo "[INFO] Downloading standalone binary from $REPO_RAW_URL/bin/gamectl..."
        curl -fsSL "$REPO_RAW_URL/bin/gamectl" -o "$BIN_DIR/gamectl"
        chmod +x "$BIN_DIR/gamectl"
        ln -sf "$BIN_DIR/gamectl" "$BIN_DIR/game"
    fi
    echo "[VERIFIED] Binary installed: $BIN_DIR/gamectl (alias: $BIN_DIR/game)"
fi

# Install shell autocompletion
if [ "$DRY_RUN" = true ]; then
    echo "[INFO] [DRY-RUN] Would install bash completion to: $COMPLETION_DIR/gamectl"
else
    mkdir -p "$COMPLETION_DIR"
    if [ "$IS_LOCAL" = true ] && [ -f "$SRC_DIR/completions/gamectl.bash" ]; then
        ln -sf "$SRC_DIR/completions/gamectl.bash" "$COMPLETION_DIR/gamectl"
        ln -sf "$COMPLETION_DIR/gamectl" "$COMPLETION_DIR/game"
    else
        echo "[INFO] Downloading bash completion script..."
        curl -fsSL "$REPO_RAW_URL/completions/gamectl.bash" -o "$COMPLETION_DIR/gamectl"
        ln -sf "$COMPLETION_DIR/gamectl" "$COMPLETION_DIR/game"
    fi
    echo "[VERIFIED] Shell completion installed: $COMPLETION_DIR/gamectl"
fi

# Install desktop application launcher
if [ "$DRY_RUN" = true ]; then
    echo "[INFO] [DRY-RUN] Would install FreeDesktop launcher to: $APP_DIR/gamectl.desktop"
else
    mkdir -p "$APP_DIR"
    if [ "$IS_LOCAL" = true ] && [ -f "$SRC_DIR/gamectl.desktop" ]; then
        cp "$SRC_DIR/gamectl.desktop" "$APP_DIR/gamectl.desktop"
    else
        echo "[INFO] Downloading FreeDesktop launcher entry..."
        curl -fsSL "$REPO_RAW_URL/gamectl.desktop" -o "$APP_DIR/gamectl.desktop"
    fi
    if command -v update-desktop-database >/dev/null 2>&1; then
        update-desktop-database "$APP_DIR" >/dev/null 2>&1 || true
    fi
    echo "[VERIFIED] Desktop application entry installed: $APP_DIR/gamectl.desktop"
fi

# Verify Manifest Harvester & CDN tools
if [ "$DRY_RUN" = false ]; then
    for tool in curl jq zip unzip; do
        command -v "$tool" >/dev/null 2>&1 || echo "[WARN] Harvester dependency '$tool' missing."
    done
fi

# Check PATH
case ":$PATH:" in
    *":$BIN_DIR:"*) ;;
    *)
        echo "[WARN] $BIN_DIR is not in your current PATH environment variable."
        echo "       Add it to ~/.bashrc or ~/.zshrc:"
        echo "       export PATH=\"\$HOME/.local/bin:\$PATH\""
        ;;
esac

echo
if [ "$DRY_RUN" = true ]; then
    echo "[PASS] Dry-run pre-flight check completed successfully with exit code 0."
else
    echo "[PASS] gamectl turnkey installation completed successfully."
    echo "       Launch the interface in your terminal by running 'gamectl' or 'game'."
fi


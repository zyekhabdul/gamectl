#!/usr/bin/env bash
# ==============================================================================
# GAMECTL INSTALLER
# ==============================================================================
set -euo pipefail

BIN_DIR="$HOME/.local/bin"
SRC_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC_BIN="$SRC_DIR/bin/gamectl"

echo "[INFO] Memeriksa dependensi sistem..."
for cmd in fzf jq curl rsync ssh file unzip python3; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
        echo "[ERROR] Dependensi '$cmd' tidak ditemukan. Harap install terlebih dahulu." >&2
        exit 1
    fi
done

# Audit Python YAML engine for SLSsteam sync
if python3 -c "import ruamel.yaml" >/dev/null 2>&1; then
    echo "[VERIFIED] Python: ruamel.yaml tersedia (Mode preservasi format YAML aktif)."
elif python3 -c "import yaml" >/dev/null 2>&1; then
    echo "[INFO] Python: PyYAML tersedia."
else
    echo "[WARN] Python YAML parser belum terpasang ('python-ruamel-yaml' atau 'python-yaml')."
    echo "       Fitur sinkronisasi SLSsteam memerlukan library ini."
fi

# Audit GBE Fork template libraries (Linux SO & Windows DLL)
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
    echo "[VERIFIED] Template GBE Fork Linux 64-bit terdeteksi: $GBE_X64"
else
    echo "[WARN] Template GBE Fork Linux 64-bit belum ditemukan di: $GBE_X64"
    echo "       Fitur 'gamectl inject' memerlukan biner libsteam_api.so dari Goldberg Emulator Fork."
    echo "       Tempatkan biner di ~/.local/share/gbe-fork/regular/x64/libsteam_api.so"
fi
if [ -f "$GBE_X86" ]; then
    echo "[VERIFIED] Template GBE Fork Linux 32-bit terdeteksi: $GBE_X86"
fi

if [ -n "$GBE_WIN_X64" ]; then
    echo "[VERIFIED] Template GBE Fork Windows 64-bit terdeteksi: $GBE_WIN_X64"
else
    echo "[WARN] Template GBE Fork Windows 64-bit belum ditemukan (steam_api64.dll)."
    echo "       Tempatkan biner di ~/.local/share/gbe-fork/windows/release/regular/x64/steam_api64.dll"
fi

if [ -n "$GBE_WIN_X86" ]; then
    echo "[VERIFIED] Template GBE Fork Windows 32-bit terdeteksi: $GBE_WIN_X86"
else
    echo "[WARN] Template GBE Fork Windows 32-bit belum ditemukan (steam_api.dll)."
    echo "       Tempatkan biner di ~/.local/share/gbe-fork/windows/release/regular/x86/steam_api.dll"
fi

# Audit Windows runner compatibility (umu-run, GE-Proton, or Wine)
RUNNER_INFO=""
if command -v umu-run >/dev/null 2>&1; then
    RUNNER_INFO="umu-run ($(command -v umu-run))"
elif [ -d "$HOME/.local/share/Steam/compatibilitytools.d" ] && find "$HOME/.local/share/Steam/compatibilitytools.d" -mindepth 1 -maxdepth 1 -type d -name "*Proton*" 2>/dev/null | grep -q .; then
    p_name=$(find "$HOME/.local/share/Steam/compatibilitytools.d" -mindepth 1 -maxdepth 1 -type d -name "*Proton*" | head -n 1 | xargs basename)
    RUNNER_INFO="Steam GE-Proton ($p_name)"
elif command -v wine64 >/dev/null 2>&1; then
    RUNNER_INFO="System Wine ($(command -v wine64))"
elif command -v wine >/dev/null 2>&1; then
    RUNNER_INFO="System Wine ($(command -v wine))"
fi

if [ -n "$RUNNER_INFO" ]; then
    echo "[VERIFIED] Runner game Windows terdeteksi: $RUNNER_INFO"
else
    echo "[WARN] Runner game Windows belum ditemukan (umu-run, GE-Proton, atau wine)."
    echo "       Tempatkan GE-Proton di ~/.local/share/Steam/compatibilitytools.d/ untuk menjalankan game .exe"
fi

# Audit performance & display wrappers (GameMode, MangoHud, Gamescope)
WRAPPER_STATUS=()
command -v gamemoderun >/dev/null 2>&1 && WRAPPER_STATUS+=("gamemode: [READY]") || WRAPPER_STATUS+=("gamemode: [N/A]")
command -v mangohud >/dev/null 2>&1 && WRAPPER_STATUS+=("mangohud: [READY]") || WRAPPER_STATUS+=("mangohud: [N/A]")
command -v gamescope >/dev/null 2>&1 && WRAPPER_STATUS+=("gamescope: [READY]") || WRAPPER_STATUS+=("gamescope: [N/A]")
echo "[INFO] Tooling wrappers: ${WRAPPER_STATUS[*]}"

# Scaffold user configuration directory and templates
CONFIG_DIR="$HOME/.config/gamectl"
mkdir -p "$CONFIG_DIR"

if [ ! -f "$CONFIG_DIR/wrappers.example" ]; then
    DEF_GSCOPE_ARGS="-W 1280 -H 720 -w 1920 -h 1080 -F fsr -f"
    if [ -x "$SRC_BIN" ]; then
        D_ARGS=$("$SRC_BIN" get-gamescope-args 2>/dev/null || true)
        [ -n "$D_ARGS" ] && DEF_GSCOPE_ARGS="$D_ARGS"
    fi
    cat <<EOF > "$CONFIG_DIR/wrappers.example"
# ==============================================================================
# gamectl - Default Runtime Performance & Display Wrappers
# ==============================================================================
# Salin file ini menjadi 'wrappers' di ~/.config/gamectl/wrappers untuk mengaktifkan
# opsi wrapper default secara global untuk seluruh game.
# Nilai: 1 (aktif), 0 (nonaktif)
#
gamemode=0
hud=0
gamescope=0
fsr=0
gamescope_args=$DEF_GSCOPE_ARGS
EOF
    echo "[INFO] Template konfigurasi dibuat: $CONFIG_DIR/wrappers.example (Resolusi native: $DEF_GSCOPE_ARGS)"
fi

if [ ! -f "$CONFIG_DIR/persona.example" ]; then
    cat <<'EOF' > "$CONFIG_DIR/persona.example"
# ==============================================================================
# gamectl - Default LAN Multi-Identity & SteamID Persona
# ==============================================================================
# Salin file ini menjadi 'persona' di ~/.config/gamectl/persona untuk mengatur
# profil default (Nama Pemain & SteamID) saat injeksi GBE Fork.
#
account_name=Player
account_steamid=76561198000000001
language=english
# IP broadcast atau IP teman bermain untuk pencarian server LAN/ad-hoc (dipisahkan koma)
# broadcasts=127.0.0.1,255.255.255.255,192.168.1.50
EOF
    echo "[INFO] Template konfigurasi dibuat: $CONFIG_DIR/persona.example"
fi

if [ ! -f "$CONFIG_DIR/libraries.example" ]; then
    cat <<'EOF' > "$CONFIG_DIR/libraries.example"
# ==============================================================================
# gamectl - Custom Library Directories
# ==============================================================================
# Cantumkan satu direktori game per baris.
# Karakter '#' menandakan komentar. Tanda tilde (~) otomatis diekspansi ke $HOME.
#
# Contoh:
# ~/Games
# ~/Downloads/LinuxGames
# /mnt/storage/games/steamapps/common
EOF
    echo "[INFO] Template konfigurasi dibuat: $CONFIG_DIR/libraries.example"
fi

if [ ! -f "$CONFIG_DIR/steam_user.example" ]; then
    cat <<'EOF' > "$CONFIG_DIR/steam_user.example"
# ==============================================================================
# gamectl - Steam Account for DepotDownloader
# ==============================================================================
# Salin file ini menjadi 'steam_user' lalu isi dengan username akun Steam Anda.
# Username ini digunakan oleh DepotDownloader saat mengunduh game berlisensi.
#
# Contoh isi file:
# nama_akun_steam_anda
EOF
    echo "[INFO] Template konfigurasi dibuat: $CONFIG_DIR/steam_user.example"
fi

if [ ! -f "$CONFIG_DIR/remote_host.example" ]; then
    cat <<'EOF' > "$CONFIG_DIR/remote_host.example"
# ==============================================================================
# gamectl - Remote Sync Host
# ==============================================================================
# Salin file ini menjadi 'remote_host' lalu isi dengan hostname atau alias SSH
# untuk target sinkronisasi savegame portabel (<Ctrl-S> atau gamectl --sync).
# Pastikan host terdaftar di ~/.ssh/config dengan autentikasi SSH key.
#
# Contoh isi file:
# companion-pc
# 192.168.1.50
EOF
    echo "[INFO] Template konfigurasi dibuat: $CONFIG_DIR/remote_host.example"
fi

mkdir -p "$BIN_DIR"
chmod +x "$SRC_BIN"

# Create symlinks
ln -sf "$SRC_BIN" "$BIN_DIR/gamectl"
ln -sf "$SRC_BIN" "$BIN_DIR/game"

# Ensure DepotDownloader runtime is provisioned
if ! command -v depotdownloader >/dev/null 2>&1; then
    echo "[INFO] Menyiapkan runtime headless downloader (DepotDownloader)..."
    "$SRC_BIN" ensure-downloader >/dev/null 2>&1 || true
fi

# Install shell autocompletion
COMPLETION_DIR="$HOME/.local/share/bash-completion/completions"
mkdir -p "$COMPLETION_DIR"
if [ -f "$SRC_DIR/completions/gamectl.bash" ]; then
    ln -sf "$SRC_DIR/completions/gamectl.bash" "$COMPLETION_DIR/gamectl"
    ln -sf "$COMPLETION_DIR/gamectl" "$COMPLETION_DIR/game"
    echo "[VERIFIED] Shell completion tersinkronisasi di: $COMPLETION_DIR/gamectl"
fi

# Install desktop application entry
APP_DIR="$HOME/.local/share/applications"
mkdir -p "$APP_DIR"
if [ -f "$SRC_DIR/gamectl.desktop" ]; then
    cp "$SRC_DIR/gamectl.desktop" "$APP_DIR/gamectl.desktop"
    if command -v update-desktop-database >/dev/null 2>&1; then
        update-desktop-database "$APP_DIR" >/dev/null 2>&1 || true
    fi
    echo "[VERIFIED] Desktop application entry terpasang di: $APP_DIR/gamectl.desktop"
fi

echo "[VERIFIED] gamectl berhasil di-link ke $BIN_DIR/gamectl dan $BIN_DIR/game"
echo "Jalankan perintah 'gamectl' atau 'game' di terminal untuk membuka antarmuka."

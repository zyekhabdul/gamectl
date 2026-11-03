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

# Audit GBE Fork template libraries
GBE_X64="$HOME/.local/share/gbe-fork/regular/x64/libsteam_api.so"
GBE_X86="$HOME/.local/share/gbe-fork/regular/x86/libsteam_api.so"
if [ -f "$GBE_X64" ]; then
    echo "[VERIFIED] Template GBE Fork 64-bit terdeteksi: $GBE_X64"
else
    echo "[WARN] Template GBE Fork 64-bit belum ditemukan di: $GBE_X64"
    echo "       Fitur 'gamectl inject' memerlukan biner libsteam_api.so dari Goldberg Emulator Fork."
    echo "       Tempatkan biner di ~/.local/share/gbe-fork/regular/x64/libsteam_api.so"
fi
if [ -f "$GBE_X86" ]; then
    echo "[VERIFIED] Template GBE Fork 32-bit terdeteksi: $GBE_X86"
fi

# Scaffold user configuration directory and templates
CONFIG_DIR="$HOME/.config/gamectl"
mkdir -p "$CONFIG_DIR"

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
    cp "$SRC_DIR/completions/gamectl.bash" "$COMPLETION_DIR/gamectl"
    ln -sf "$COMPLETION_DIR/gamectl" "$COMPLETION_DIR/game"
    echo "[VERIFIED] Shell completion terpasang di: $COMPLETION_DIR/gamectl"
fi

echo "[VERIFIED] gamectl berhasil di-link ke $BIN_DIR/gamectl dan $BIN_DIR/game"
echo "Jalankan perintah 'gamectl' atau 'game' di terminal untuk membuka antarmuka."

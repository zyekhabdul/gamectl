#!/usr/bin/env bash
set -euo pipefail

# Build .deb package using dpkg-deb
PKG_NAME="gamectl"
PKG_VER="1.4.0"
DIST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$DIST_DIR/../.." && pwd)"

PKG_ARCH="all"
if [ -f "$PROJECT_ROOT/bin/gamectl-depot-dl" ]; then
    elf_info="$(file -Lb "$PROJECT_ROOT/bin/gamectl-depot-dl" 2>/dev/null || true)"
    case "$elf_info" in
        *x86-64*|*x86_64*) PKG_ARCH="amd64" ;;
        *"ARM aarch64"*|*aarch64*) PKG_ARCH="arm64" ;;
        *"Intel 80386"*|*i386*) PKG_ARCH="i386" ;;
        *) PKG_ARCH="$(dpkg --print-architecture 2>/dev/null || echo amd64)" ;;
    esac
fi
WORK_DIR="$DIST_DIR/build_deb/${PKG_NAME}_${PKG_VER}_${PKG_ARCH}"

echo "==> Building Debian (.deb) package for $PKG_NAME v$PKG_VER ($PKG_ARCH)..."
rm -rf "$DIST_DIR/build_deb"
[ "$PKG_ARCH" != "all" ] && rm -f "$DIST_DIR/${PKG_NAME}_${PKG_VER}_all.deb"
mkdir -p "$WORK_DIR/DEBIAN"
mkdir -p "$WORK_DIR/usr/bin"
mkdir -p "$WORK_DIR/usr/share/bash-completion/completions"
mkdir -p "$WORK_DIR/usr/share/applications"
mkdir -p "$WORK_DIR/usr/share/doc/$PKG_NAME"
mkdir -p "$WORK_DIR/usr/share/licenses/$PKG_NAME"

cat << EOF > "$WORK_DIR/DEBIAN/control"
Package: gamectl
Version: ${PKG_VER}
Section: games
Priority: optional
Architecture: ${PKG_ARCH}
Depends: bash (>= 4.4), curl, file, fzf, jq, openssh-client, python3, rsync, unzip, zip
Recommends: bubblewrap, gamemode, mangohud, gamescope, python3-ruamel.yaml
Maintainer: Zyekh Abdul <zyekhabdulqadirjailani@gmail.com>
Homepage: https://github.com/zyekhabdul/gamectl
Description: Sovereign TUI Game Manager & Launcher for Linux (Zero-Bloat)
 gamectl is a lightweight, standalone Terminal User Interface (TUI) game manager and launcher designed for
 Linux workstations and handhelds. It manages, launches, and synchronizes
 standalone portable games with zero dependency on heavyweight graphical
 client runtimes. Includes shorthand alias 'game'.
EOF

# Ensure binary bundle is up-to-date
if [ -f "$PROJECT_ROOT/scripts/build.sh" ]; then
    "$PROJECT_ROOT/scripts/build.sh" >/dev/null 2>&1 || true
fi

# Install standalone binary and aliases
cp "$PROJECT_ROOT/bin/gamectl" "$WORK_DIR/usr/bin/gamectl"
chmod 755 "$WORK_DIR/usr/bin/gamectl"
if [ -f "$PROJECT_ROOT/bin/gamectl-depot-dl" ]; then
    cp "$PROJECT_ROOT/bin/gamectl-depot-dl" "$WORK_DIR/usr/bin/gamectl-depot-dl"
    chmod 755 "$WORK_DIR/usr/bin/gamectl-depot-dl"
fi
ln -sf gamectl "$WORK_DIR/usr/bin/game"

# Install shell completion
cp "$PROJECT_ROOT/completions/gamectl.bash" "$WORK_DIR/usr/share/bash-completion/completions/gamectl"
chmod 644 "$WORK_DIR/usr/share/bash-completion/completions/gamectl"
ln -sf gamectl "$WORK_DIR/usr/share/bash-completion/completions/game"

# Install desktop entry
cp "$PROJECT_ROOT/gamectl.desktop" "$WORK_DIR/usr/share/applications/gamectl.desktop"
chmod 644 "$WORK_DIR/usr/share/applications/gamectl.desktop"

# Install documentation and copyright (MIT for gamectl; GPL-2.0-only for gamectl-depot-dl)
cp "$PROJECT_ROOT/README.md" "$WORK_DIR/usr/share/doc/$PKG_NAME/"
cp "$PROJECT_ROOT/docs/GUIDE.md" "$WORK_DIR/usr/share/doc/$PKG_NAME/"
cp "$PROJECT_ROOT/docs/ARCHITECTURE.md" "$WORK_DIR/usr/share/doc/$PKG_NAME/"
cp "$PROJECT_ROOT/LICENSE" "$WORK_DIR/usr/share/licenses/$PKG_NAME/LICENSE"
cat << EOF > "$WORK_DIR/usr/share/doc/$PKG_NAME/copyright"
Format: https://www.debian.org/doc/packaging-manuals/copyright-format/1.0/
Upstream-Name: gamectl
Source: https://github.com/zyekhabdul/gamectl

Files: *
Copyright: 2026 Zyekh Abdul
License: MIT
 Full MIT license text is installed at /usr/share/licenses/${PKG_NAME}/LICENSE.

Files: usr/bin/gamectl-depot-dl
Copyright: enXov / steam-depot-downloader-mod contributors
License: GPL-2.0-only
 Derived from steam-depot-downloader-mod (https://github.com/enXov/steam-depot-downloader-mod).
 On Debian systems, the complete text of the GNU General Public License
 version 2 can be found in '/usr/share/common-licenses/GPL-2'.
EOF
chmod 644 "$WORK_DIR/usr/share/doc/$PKG_NAME/copyright"

# Build .deb archive
dpkg-deb --build --root-owner-group "$WORK_DIR" "$DIST_DIR/${PKG_NAME}_${PKG_VER}_${PKG_ARCH}.deb"
rm -rf "$DIST_DIR/build_deb"

echo "==> Done! Created: $DIST_DIR/${PKG_NAME}_${PKG_VER}_${PKG_ARCH}.deb"

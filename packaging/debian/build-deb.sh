#!/usr/bin/env bash
set -euo pipefail

# Build .deb package using dpkg-deb
PKG_NAME="gamectl"
PKG_VER="1.3.0"
PKG_ARCH="all"
DIST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORK_DIR="$DIST_DIR/build_deb/${PKG_NAME}_${PKG_VER}_${PKG_ARCH}"
PROJECT_ROOT="$(cd "$DIST_DIR/../.." && pwd)"

echo "==> Building Debian (.deb) package for $PKG_NAME v$PKG_VER..."
rm -rf "$DIST_DIR/build_deb"
mkdir -p "$WORK_DIR/DEBIAN"
mkdir -p "$WORK_DIR/usr/bin"
mkdir -p "$WORK_DIR/usr/share/bash-completion/completions"
mkdir -p "$WORK_DIR/usr/share/applications"
mkdir -p "$WORK_DIR/usr/share/doc/$PKG_NAME"
mkdir -p "$WORK_DIR/usr/share/licenses/$PKG_NAME"

cat << 'EOF' > "$WORK_DIR/DEBIAN/control"
Package: gamectl
Version: 1.3.0
Section: games
Priority: optional
Architecture: all
Depends: bash (>= 4.4), curl, file, fzf, jq, openssh-client, python3, rsync, unzip
Recommends: bubblewrap, gamemode, mangohud, gamescope, python3-ruamel.yaml
Maintainer: Zyekh Abdul <zyekhabdulqadirjailani@gmail.com>
Homepage: https://github.com/zyekhabdul/gamectl
Description: Sovereign TUI Game Manager & Launcher for Linux (Zero-Bloat)
 gamectl is an ultra-lightweight (< 15 MB RAM RSS), high-performance
 Terminal User Interface (TUI) game manager and launcher designed for
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
ln -sf gamectl "$WORK_DIR/usr/bin/game"

# Install shell completion
cp "$PROJECT_ROOT/completions/gamectl.bash" "$WORK_DIR/usr/share/bash-completion/completions/gamectl"
chmod 644 "$WORK_DIR/usr/share/bash-completion/completions/gamectl"
ln -sf gamectl "$WORK_DIR/usr/share/bash-completion/completions/game"

# Install desktop entry
cp "$PROJECT_ROOT/gamectl.desktop" "$WORK_DIR/usr/share/applications/gamectl.desktop"
chmod 644 "$WORK_DIR/usr/share/applications/gamectl.desktop"

# Install documentation and copyright
cp "$PROJECT_ROOT/README.md" "$WORK_DIR/usr/share/doc/$PKG_NAME/"
cp "$PROJECT_ROOT/docs/GUIDE.md" "$WORK_DIR/usr/share/doc/$PKG_NAME/"
cp "$PROJECT_ROOT/docs/ARCHITECTURE.md" "$WORK_DIR/usr/share/doc/$PKG_NAME/"
cp "$PROJECT_ROOT/LICENSE" "$WORK_DIR/usr/share/doc/$PKG_NAME/copyright"
cp "$PROJECT_ROOT/LICENSE" "$WORK_DIR/usr/share/licenses/$PKG_NAME/LICENSE"

# Build .deb archive
dpkg-deb --build --root-owner-group "$WORK_DIR" "$DIST_DIR/${PKG_NAME}_${PKG_VER}_${PKG_ARCH}.deb"
rm -rf "$DIST_DIR/build_deb"

echo "==> Done! Created: $DIST_DIR/${PKG_NAME}_${PKG_VER}_${PKG_ARCH}.deb"

.PHONY: help build build-depot-dl test lint clean distclean pkg-deb pkg-aur pkg-all install uninstall

help:
	@echo "gamectl - Sovereign TUI Game Manager & Launcher for Linux"
	@echo ""
	@echo "Usage:"
	@echo "  make build          - Compile modular sources into standalone bin/gamectl"
	@echo "  make build-depot-dl - Compile native Rust Steam CDN depot downloader"
	@echo "  make test           - Execute regression & integrity test suite"
	@echo "  make lint           - Validate bash syntax on all modules"
	@echo "  make pkg-deb        - Build Debian/Ubuntu .deb package"
	@echo "  make pkg-aur        - Update Arch packages & .SRCINFO (makepkg)"
	@echo "  make pkg-all        - Build all platform distribution packages"
	@echo "  make install        - Run turnkey installer (install.sh)"
	@echo "  make uninstall      - Remove installed binaries, completions, and desktop entry"
	@echo "  make clean          - Clean build, packaging, and rust artifacts"
	@echo "  make distclean      - Deep clean including runtime caches and temporary logs"

build:
	./scripts/build.sh
	@if [ -f ./scripts/build-depot-dl.sh ]; then ./scripts/build-depot-dl.sh --check >/dev/null 2>&1 || ./scripts/build-depot-dl.sh; fi

build-depot-dl:
	./scripts/build-depot-dl.sh

test:
	./tests/test_cli.sh

lint:
	@set -e; for file in src/*.sh src/*/*.sh bin/gamectl install.sh scripts/*.sh packaging/debian/*.sh packaging/scripts/*.sh tests/*.sh completions/*.bash; do \
		bash -n "$$file"; \
	done

pkg-deb:
	bash packaging/debian/build-deb.sh

pkg-aur:
	cd packaging/arch && makepkg --printsrcinfo > .SRCINFO
	cd packaging/aur-git && makepkg --printsrcinfo > .SRCINFO

pkg-all:
	bash packaging/scripts/build-all.sh

install:
	./install.sh

uninstall:
	rm -f $(HOME)/.local/bin/gamectl $(HOME)/.local/bin/game $(HOME)/.local/bin/gamectl-depot-dl
	rm -f $(HOME)/.local/share/bash-completion/completions/gamectl $(HOME)/.local/share/bash-completion/completions/game
	rm -f $(HOME)/.local/share/applications/gamectl.desktop

clean:
	rm -rf packaging/debian/build_deb packaging/debian/*.deb packaging/arch/*.pkg.tar* packaging/aur-git/*.pkg.tar* packaging/aur-git/src packaging/aur-git/pkg
	@if [ -f crates/depot-dl/Cargo.toml ] && command -v cargo >/dev/null 2>&1; then \
		cargo clean --manifest-path crates/depot-dl/Cargo.toml; \
	fi

distclean: clean
	rm -f $${XDG_RUNTIME_DIR:-/tmp}/gamectl_*.log
	rm -f $${XDG_CACHE_HOME:-$$HOME/.cache}/gamectl/scancache_*.vdf
	rm -f $${XDG_CACHE_HOME:-$$HOME/.cache}/gamectl/steam_basic_*.json
	rm -f $${XDG_CACHE_HOME:-$$HOME/.cache}/gamectl/steam_dlc_*.json

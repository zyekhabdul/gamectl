.PHONY: help build build-depot-dl test lint clean pkg-deb pkg-aur pkg-all install uninstall

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
	@echo "  make clean          - Clean build and packaging artifacts"

build:
	./scripts/build.sh

build-depot-dl:
	./scripts/build-depot-dl.sh

test:
	./tests/test_cli.sh

lint:
	bash -n src/*.sh src/*/*.sh bin/gamectl install.sh scripts/build.sh scripts/build-depot-dl.sh packaging/debian/build-deb.sh packaging/scripts/build-all.sh

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

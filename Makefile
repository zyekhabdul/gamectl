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
	./tests/test_cli.sh < /dev/null
	./tests/test_remediation.sh
	./tests/test_tui_ergonomics.sh
	./tests/test_depot_filter.sh
	./tests/test_hubcap.sh
	python3 -m unittest discover -s tests -p "test_*.py" -v

lint:
	@set -e; for file in src/*.sh src/*/*.sh bin/gamectl install.sh scripts/*.sh packaging/debian/*.sh packaging/scripts/*.sh tests/*.sh completions/*.bash; do \
		bash -n "$$file"; \
	done; \
	if command -v shellcheck >/dev/null 2>&1; then \
		jobs="$${LINT_JOBS:-$$(nproc 2>/dev/null || echo 1)}"; \
		if command -v xargs >/dev/null 2>&1; then \
			printf '%s\0' src/*.sh src/*/*.sh scripts/*.sh | xargs -0 -n 1 -P "$$jobs" shellcheck -s bash -S error; \
		else \
			for file in src/*.sh src/*/*.sh scripts/*.sh; do \
				shellcheck -s bash -S error "$$file"; \
			done; \
		fi; \
	elif [ "$${STRICT_LINT:-0}" = "1" ]; then \
		echo "[FAIL] STRICT_LINT=1 requires shellcheck in PATH" >&2; \
		exit 1; \
	else \
		echo "[INFO] shellcheck not found (syntax-only lint passed)"; \
	fi; \
	bash scripts/check_loc_budget.sh

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
	rm -rf packaging/debian/build_deb packaging/debian/*.deb packaging/arch/*.pkg.tar* packaging/aur-git/*.pkg.tar* packaging/aur-git/src packaging/aur-git/pkg src/gamectl.egg-info src/gamectl_runner/bin src/gamectl_runner/__pycache__
	@if [ -f crates/depot-dl/Cargo.toml ] && command -v cargo >/dev/null 2>&1; then \
		cargo clean --manifest-path crates/depot-dl/Cargo.toml; \
	fi

distclean: clean
	rm -f $${XDG_RUNTIME_DIR:-/tmp}/gamectl_*.log
	rm -f $${XDG_CACHE_HOME:-$$HOME/.cache}/gamectl/scancache_*.vdf
	rm -f $${XDG_CACHE_HOME:-$$HOME/.cache}/gamectl/steam_basic_*.json
	rm -f $${XDG_CACHE_HOME:-$$HOME/.cache}/gamectl/steam_dlc_*.json

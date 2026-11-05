# WORK PACKET 10: GLOBAL READINESS, LOCALIZATION & HANDHELD EXPANSION

## 1. Objective & Scope
Transform `gamectl` from a regional utility into a globally competitive, legal-defensible, and community-ready open-source Linux gaming project. Focus on three strategic pillars:
1. **Internationalization (English-First) & Legal Guard**: Migrate all user-facing terminal logs, TUI menus, and documentation to idiomatic technical English. Reclassify sensitive terms into neutral, legal-defensible nomenclature to protect the repository against automated DMCA takedowns.
2. **Global Distribution & Packaging**: Provide turnkey installation (`curl -fsSL ... | bash`), create Arch User Repository (`PKGBUILD`) packaging, and generate automated high-resolution demo assets (`vhs`).
3. **Handheld & Steam Deck Optimization**: Implement binary `shortcuts.vdf` generation to register standalone games directly into Steam Deck Game Mode, paired with an automated SteamGridDB / Steam CDN artwork scraper.

---

## 2. Granular Chunks & Technical Execution DoD

### Chunk 1: Core, Runner & Diagnostics Internationalization (English-First)
- **Target Files**: `src/core/00_header.sh`, `src/core/10_utils.sh`, `src/runners/40_wrappers.sh`, `src/runners/50_launcher.sh`, `src/diagnostics/60_doctor.sh`
- **Technical Logic & Rules**:
  1. Standardize all log tokens: `[INFO]`, `[WARN]`, `[ERROR]`, `[VERIFIED]`.
  2. Translate all messages, error traces, and prompts in `10_utils.sh` (save snapshot creation, template checks).
  3. Translate all runner resolution logs, GE-Proton download/remove messages, and `manage_prefix` (`gamectl pfx`) menus in `40_wrappers.sh`.
  4. Translate `game_controller_hud` options, status tags, and shutdown logs in `50_launcher.sh`.
  5. Translate 7-layer diagnostic health descriptions and hardware status checks in `60_doctor.sh`.
- **DoD**:
  1. Zero Indonesian strings remain in core, runner, and diagnostics modules.
  2. All prompts provide clear English prompts and bounded timeouts.
  3. `bash -n` passes on all modified files.

---

### Chunk 2: Steam Engine & Interactive Dashboard TUI Internationalization
- **Target Files**: `src/steam/20_discovery.sh`, `src/steam/25_identity.sh`, `src/steam/30_downloader.sh`, `src/tui/70_dashboard.sh`, `src/main.sh`
- **Technical Logic & Rules**:
  1. Translate table column headers, status badges, and discovery reports in `20_discovery.sh`.
  2. Translate LAN identity (`set-id`) prompts, broadcast queries, and SteamID generation notices in `25_identity.sh`.
  3. Translate headless DepotDownloader logs, DLC injection status, and SLSsteam sync reports in `30_downloader.sh`.
  4. Translate all interactive TUI screens, master dashboard options, help overlays, and split-pane inspection cards in `70_dashboard.sh`.
  5. Translate top-level CLI command help text (`gamectl --help`) in `src/main.sh`.
- **DoD**:
  1. TUI dashboard (`gamectl` / `gamectl library`) runs 100% in English.
  2. `gamectl --help` outputs standardized, clean English descriptions.
  3. `./scripts/build.sh --check` verifies source-to-bundle synchronization.

---

### Chunk 3: Legal Shielding, Neutral Nomenclature & Documentation Overhaul
- **Target Files**: `README.md`, `DEVELOPMENT.md`, `remediation.md`, code comments
- **Technical Logic & Rules**:
  1. Rebrand and reframe sensitive terms across all public markdown files:
     - "OnlineFix" -> `P2P Multiplayer Compatibility Layer` / `DLL Override Hook Engine`.
     - "SLSsteam / GreenLuma" -> `Entitlement Cache Synchronizer` / `Offline AppManifest Generator`.
     - "GBE Fork" -> `Decentralized LAN Steam Emulator` / `Portable Game Runtime Engine`.
     - Keep backward-compatible CLI command aliases (`gamectl onlinefix` remains functional alongside `gamectl mod-overrides`).
  2. Completely rewrite `README.md` in professional English:
     - High-impact introduction highlighting sovereign, zero-bloat handheld gaming (<15MB RAM).
     - Empirical benchmark comparison table against Heroic Games Launcher, Lutris, and Bottles.
     - Quick start guide, feature overview, keyboard shortcuts, and CLI command reference.
  3. Update `DEVELOPMENT.md` and `remediation.md` to reflect English standard.
- **DoD**:
  1. Zero piracy-flagged keywords in public markdown files that could trigger automated DMCA crawlers.
  2. `README.md` is structured, compelling, and ready for international audience review.

---

### Chunk 4: Turnkey Piped Web Installer & Arch Linux AUR Packaging
- **Target Files**: `install.sh`, `packaging/arch/PKGBUILD`, `packaging/arch/.SRCINFO`, `docs/demo.tape`
- **Technical Logic & Rules**:
  1. Upgrade `install.sh` to support direct piped web execution:
     `curl -fsSL https://raw.githubusercontent.com/zyekhabdul/gamectl/main/install.sh | bash`
     - Auto-detect non-interactive shell.
     - Clone or stream latest bundle directly to `~/.local/bin/gamectl`.
     - Automatically install shell completions and desktop entry.
  2. Create standard Arch Linux `PKGBUILD` for community packaging (AUR):
     - Source points to GitHub tag release or git tree.
     - Clean packaging into `/usr/bin/gamectl`, bash completions to `/usr/share/bash-completion/completions/`, desktop file to `/usr/share/applications/`.
  3. Create Charm `vhs` tape script (`docs/demo.tape`) for automated demo GIF generation.
- **DoD**:
  1. `install.sh` passes dry-run piped execution check.
  2. `PKGBUILD` passes `namcap` / syntax checks for AUR standards.

---

### Chunk 5: Steam Deck `shortcuts.vdf` Non-Steam Integration Engine
- **Target Files**: `src/steam/20_discovery.sh`, `src/main.sh`, `tests/test_cli.sh`
- **Function**: `add_steam_shortcut <game_dir> [title]` (CLI: `gamectl add-to-steam <dir> [title]`)
- **Technical Logic & Rules**:
  1. Locate active Steam user directory: `~/.local/share/Steam/userdata/<account_id>/config/shortcuts.vdf`.
  2. Implement binary VDF parser / serializer helper in lightweight python3 (standard Layer 2 dependency):
     - Generate deterministic 32-bit AppID shortcut hash: `CRC32(target_path + title) | 0x80000000`.
     - Write binary VDF entry with:
       - `AppName`: Title
       - `Exe`: `gamectl` binary path
       - `StartDir`: Game directory
       - `LaunchOptions`: `launch "<game_dir>" --hud`
       - `icon`: Game icon path
       - `IsHidden`: 0, `AllowDesktopConfig`: 1, `OpenVR`: 0
  3. Safely update `shortcuts.vdf` with atomic backup (`shortcuts.vdf.bak`).
- **DoD**:
  1. Running `gamectl add-to-steam <dir>` registers shortcut in Steam client without corrupting binary VDF.
  2. Verified game appears in Steam Deck Game Mode library.

---

### Chunk 6: SteamGridDB & Steam CDN Artwork Pipeline for Game Mode
- **Target Files**: `src/steam/20_discovery.sh`, `src/main.sh`, `tests/test_cli.sh`
- **Function**: `fetch_steam_artwork <game_dir> [appid]` (CLI: `gamectl fetch-art <dir> [appid]`)
- **Technical Logic & Rules**:
  1. Resolve shortcut AppID or Steam AppID from game directory.
  2. Query Steam CDN / SteamGridDB endpoints for official capsule, hero, and logo artwork.
  3. Save artwork assets to `~/.local/share/Steam/userdata/<account_id>/config/grid/`:
     - `<shortcut_id>p.png` (Portrait capsule, 600x900)
     - `<shortcut_id>.png` (Horizontal banner, 920x430)
     - `<shortcut_id>_hero.png` (Hero background, 1920x620)
     - `<shortcut_id>_logo.png` (Transparent logo overlay)
- **DoD**:
  1. CLI command successfully downloads artwork files to grid directory.
  2. Non-Steam shortcuts render native visuals in Steam Deck Game Mode.

---

## 3. Matriks Milestone Sebelumnya (Work Packet 9 - Completed)
- [x] Chunk 1: OnlineFix & Mod DLL Overrides Detection Engine (`4d34d1c`) [DONE]
- [x] Chunk 2: Launcher Overrides Injection & Spacewar Entitlement (`7f33f62`) [DONE]
- [x] Chunk 3: Headless GE-Proton Release Manager (`e2df677`) [DONE]
- [x] Chunk 4: Wine Prefix Swiss Army Knife (`09864f6`) [DONE]
- [x] Chunk 5: ProtonDB CLI & Desktop Entry Generator (`cefd094`) [DONE]
- [x] Chunk 6: CLI Entrypoint Dispatcher & Build Synchronization (`cefd094`) [DONE]
- [x] Chunk 7: Automated Test Suite Expansion (35/35 passing) (`cefd094`) [DONE]
- [x] Chunk 8: Documentation, Memory Sync & Checkpoint Commit (`0d4d613`) [DONE]
- [x] Remote Git Push: Synchronized to `git@github.com:zyekhabdul/gamectl.git` [DONE]

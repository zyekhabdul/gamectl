# RFC: Multi-Store Engine Architecture for gamectl (v2.0)

- **Status**: REVISED / READY FOR REVIEW
- **Target Version**: v1.5.0+ (Post-WP36 / Modular Core & Steam Split)
- **Authors**: Antigravity Technical Pair & Maintainers
- **Date**: 2026-11-24
- **Governing Charter**: [SOVEREIGN_ORIGINAL_PURPOSE.md](SOVEREIGN_ORIGINAL_PURPOSE.md)

---

## 1. Executive Summary & Architectural Alignment

Saat ini `gamectl` mengelola ekosistem Steam secara standalone dan portabel (tanpa mewajibkan Steam Client atau SLSsteam). RFC ini memperluas `gamectl` menjadi **Multi-Store Game Hub** lintas platform digital:

1. **Steam / Standalone** (Built-in: `gamectl-depot-dl` + GBE Fork)
2. **GOG** (Priority 1 external adapter: DRM-free offline ownership)
3. **Epic Games Store** (Priority 2 external adapter: via `legendary`)
4. **Amazon Prime Gaming** (Optional adapter: via `nile`)

Seluruh ekstensi wajib tunduk pada prinsip [SOVEREIGN_ORIGINAL_PURPOSE.md](SOVEREIGN_ORIGINAL_PURPOSE.md):
- **Zero Mandatory Client Bloat**: Tidak bergantung pada aplikasi GUI Electron/Qt. Klaim footprint RAM/startup hanya boleh dipublikasikan bila ada pengukuran aktual.
- **Optional External CLIs Invariant**: Tool store eksternal (`gogdl`, `lgogdownloader`, `legendary`, `nile`) berstatus **opsional penuh** (`optdepends` / `Recommends`). Mesin tanpa tool eksternal harus tetap lulus 100% test suite standalone dan berjalan normal untuk game Steam/Standalone.
- **Unified Sovereign Runtime**: Game dari store mana pun diluncurkan dengan pipeline yang sama: isolated Wine/Proton prefix (`pfx/`), 3-slot savegame snapshots + prefix auto-locate (`src/core/14_saves.sh`), cgroups v2 scope, PRIME dGPU offload, dan Bubblewrap sandbox (`src/runners/`).

---

## 2. Headless CLI Engine Selection Matrix

| Store | Engine / Adapter | License / Runtime | Status & Key Capabilities |
| :--- | :--- | :--- | :--- |
| **Steam (Standalone)** | `gamectl-depot-dl` (`crates/depot-dl/`) + `src/steam/{30_downloader,31_manifests}.sh` | GPL-2.0-only (Rust) + MIT (Bash) | **Built-in.** Direct Valve CDN streaming, AES-256 decryption, DLC manifest, GBE Fork offline runtime. (`32_steam_bridge.sh` bersifat opt-in legacy eksplisit.) |
| **GOG** | `gogdl` (atau `lgogdownloader` fallback) | MIT / GPL (Optional CLI) | **Phase 2 (Priority 1).** DRM-free offline installers/builds, metadata & cloud save sync; paling selaras dengan filosofi kepemilikan lokal. |
| **Epic Games Store** | `legendary` | GPL-3.0 (Optional CLI) | **Phase 3.** OAuth headless, delta-patched downloads, Epic cloud save sync. |
| **Amazon Games** | `nile` | GPL-3.0 (Optional CLI) | **Phase 4 (Optional).** Prime Gaming entitlement & direct depot downloads. |

---

## 3. Unified Store Abstraction (`src/stores/`)

Mengikuti pemecahan modular `src/core/{10_utils,12_tui_primitives,14_saves,16_steamstub}.sh` dan `src/steam/{30_downloader,31_manifests,32_steam_bridge}.sh`, seluruh adapter store diisolasi di bawah `src/stores/` dan dibundel oleh [scripts/build.sh](../scripts/build.sh):

```text
src/stores/
├── 00_store_interface.sh    # Registry, capability probe, & store_dispatch()
├── 10_store_steam.sh        # Thin adapter membungkus 30_downloader.sh & 31_manifests.sh
├── 20_store_gog.sh          # GOG adapter (gogdl / lgogdownloader)
├── 30_store_epic.sh         # Epic Games adapter (legendary)
└── 40_store_amazon.sh       # Amazon Games adapter (nile)
```

### Unified Store Contract Signature
Setiap adapter `store_<name>_*` wajib mengimplementasikan kontrak deterministik berikut:

```bash
# 1. Probe ketersediaan CLI eksternal secara offline (exit 0 jika siap, 1 jika absen)
store_<name>_available

# 2. Status autentikasi & akun (output ringkas; zero error crash saat offline)
store_<name>_status

# 3. Pencarian katalog terstandardisasi (semua field wajib lolos validate_tui_fields)
store_<name>_search <query>
# Output TSV: <STORE>\t<APP_ID>\t<TITLE>\t<PLATFORMS>\t<STATUS>

# 4. Daftar game terinstal milik adapter ini (digabung oleh 20_discovery.sh)
store_<name>_list_installed
# Output TSV v3 (6 kolom): <APP_ID>\t<TITLE>\t<STATUS>\t<GAME_DIR>\t<GAME_BIN>\t<STORE>

# 5. Download / Install langsung ke direktori target
store_<name>_download <app_id> <target_dir> [options]

# 6. Sinkronisasi cloud save / verifikasi metadata (opsional per store)
store_<name>_sync <app_id> <game_dir>
```

---

## 4. Backward-Compatible Library Schema v3 (`src/steam/20_discovery.sh`)

Saat ini `scan_installed_games` di [src/steam/20_discovery.sh](../src/steam/20_discovery.sh) menghasilkan TSV **5 kolom** (`# gamectl scanner v2`):

```text
v2 (existing): Col 1: APP_ID | Col 2: TITLE | Col 3: STATUS | Col 4: GAME_DIR | Col 5: GAME_BIN
```

Untuk menjaga kompatibilitas penuh dengan seluruh pemanggil eksisting (`cut -f1..5`, `awk '$1 == aid {print $4}'`, `preview_game`, `cli_launch`, dan seluruh 259+ contract tests), upgrade ke **v3 6 kolom** dilakukan dengan **menambahkan `STORE` sebagai Kolom 6** (bukan menggeser Kolom 1):

```text
v3 (multi-store):
Column 1: APP_ID     -> Numeric Steam AppID, GOG Product ID, Epic AppName, atau STANDALONE
Column 2: TITLE      -> Clean sanitized game title (lolos validate_tui_fields)
Column 3: STATUS     -> GBE_FORK | VALVE_SO | VALVE_DLL | STANDALONE | GOG | EPIC | AMAZON
Column 4: GAME_DIR   -> Absolute directory path on local disk
Column 5: GAME_BIN   -> Primary executable relative path
Column 6: STORE      -> STEAM | GOG | EPIC | AMAZON | STANDALONE
```

- Header cache di-bump dari `# gamectl scanner v2` menjadi `# gamectl scanner v3` agar cache v2 lama otomatis terinvalidasi saat upgrade.
- Fungsi consumer internal yang membutuhkan informasi store membaca Kolom 6 (`${c_store:-STANDALONE}`), dengan fallback aman bila baris berasal dari sumber 5 kolom.

---

## 5. TUI, Hotkeys & Auth Hub UX (`src/tui/70_dashboard.sh`)

Hotkeys library eksisting (`ctrl-f`, `ctrl-d`, `ctrl-l`, `ctrl-o`, `ctrl-p`, `ctrl-i`, `ctrl-s` untuk Remote Sync Palette, `ctrl-b`, `ctrl-r`, `ctrl-x`) **tidak boleh bentrok atau berubah makna**:

1. **Store Switcher Filter (Zero Key Collision)**:
   - **`Tab`**: Cycle active store filter (`ALL -> STEAM -> GOG -> EPIC -> AMAZON -> STANDALONE`).
   - **`Alt-S`**: Buka picker filter store langsung (membiarkan `Ctrl-S` tetap eksklusif untuk **Unified Remote Sync Palette**).
2. **Store-Aware Action Palette**:
   - Game **GOG**: menampilkan `Verify Files`, `Sync GOG Cloud Saves`, `Launch Standalone`.
   - Game **Epic**: menampilkan `Sync Epic Cloud Saves`, `Verify / Repair`, `Launch via Proton`.
   - Game **Steam / Standalone**: mempertahankan seluruh alur eksisting (`GBE Inject`, `Save Snapshots`, `Prefix Tools`, `Dev Profiler`).
3. **Headless Authentication Hub (`gamectl auth`)**:
   - Subcommand `gamectl auth [status|gog|epic|amazon|luatools]` mendelegasikan proses login ke CLI native masing-masing (`legendary auth`, `gogdl auth`, `nile auth`, atau `login_luatools`).
   - `gamectl` dilarang menyimpan kredensial plaintext sendiri untuk store eksternal (cukup memantau status token milik tool terkait).

---

## 6. Offline, Security & Verification Invariants

- **Offline Resilience**: Ketika jaringan mati atau CLI eksternal belum terpasang, `gamectl library` dan `gamectl launch` tidak boleh crash atau memblokir UI; operasi online mengembalikan error terklasifikasi ke `stderr` / `tui_run_engine`.
- **Sanitasi Input**: Seluruh judul, ID, dan path dari API/CLI store eksternal wajib divalidasi oleh `validate_tui_fields` (menolak tab, newline, CR, serta karakter control) sebelum masuk ke `scancache.tab` atau `fzf`.
- **Verification Gate per Phase**: Setiap work packet wajib menyertakan mock-CLI contract tests di `tests/test_remediation.sh`, lulus `STRICT_LINT=1 make lint`, `./scripts/build.sh --check`, `tests/test_cli.sh`, `tests/test_tui_ergonomics.sh`, dan Python safety suites tanpa regresi.

---

## 7. Phased Implementation Roadmap (WP38 - WP41)

- **Phase 1 — WP38 (Store Interface, Steam Adapter & Scanner v3)**:
  - Buat `src/stores/00_store_interface.sh` dan `src/stores/10_store_steam.sh` (membungkus `30_downloader.sh` + `31_manifests.sh`).
  - Upgrade `scan_installed_games` di `src/steam/20_discovery.sh` ke TSV 6 kolom (`# gamectl scanner v3`, `STORE` di Kolom 6).
  - Tambahkan filter `Tab` / `Alt-S` pada `library_menu` (`ALL | STEAM | STANDALONE`).
- **Phase 2 — WP39 (GOG Adapter via `gogdl` / `lgogdownloader`)**:
  - Implementasi `src/stores/20_store_gog.sh`, deteksi instalasi GOG lokal, `gamectl gog ...`, dan integrasi `gamectl doctor` optional probe.
- **Phase 3 — WP40 (Epic Games Adapter via `legendary`)**:
  - Implementasi `src/stores/30_store_epic.sh`, deteksi `legendary` installed JSON, download/launch/sync cloud saves, dan `gamectl epic ...`.
- **Phase 4 — WP41 (Amazon `nile` & Unified `gamectl auth` / Search Aggregation)**:
  - Implementasi `src/stores/40_store_amazon.sh` dan subcommand `gamectl auth` serta pencarian lintas store di `search_steam` -> `search_stores`.

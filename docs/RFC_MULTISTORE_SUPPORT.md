# RFC: Multi-Store Engine Architecture for gamectl
- **Status**: PROPOSED / SPECIFICATION
- **Target Version**: v1.3.0
- **Authors**: Antigravity Technical Pair & Maintainers
- **Date**: 2026-11-06

---

## 1. Executive Summary & Objective

Saat ini `gamectl` berfokus pada ekosistem Steam (Steam Web API, DepotDownloader, SLSsteam, Steam Grid, and Proton). Namun, ekosistem PC gaming modern tersebar di berbagai platform digital:
1. **Epic Games Store (EGS)**
2. **GOG (Good Old Games)**
3. **Amazon Prime Gaming**
4. **Itch.io / Standalone DRM-Free**

Tujuan RFC ini adalah memperluas `gamectl` menjadi **Multi-Store Game Hub** tanpa mengorbankan filosofi performa inti:
- **Zero GUI Bloat**: Menghindari beban memori 300MB - 1GB+ milik client GUI (Heroic Games Launcher / Lutris berbasis Electron/Qt).
- **Pure Headless CLI / TUI Engines**: Menggunakan CLI tools open-source berkecepatan tinggi yang telah teruji di komunitas Linux.
- **Unified Runner & Sandbox Framework**: Memanfaatkan engine prefix Wine/Proton, cgroups v2 scope, PRIME dGPU offload, dan Bubblewrap sandbox yang sudah ada di `gamectl` untuk seluruh game dari store manapun.

---

## 2. Headless CLI Engine Selection Matrix

| Store | Recommended CLI Engine | License / Runtime | Key Capabilities |
| :--- | :--- | :--- | :--- |
| **Steam** | `DepotDownloader` + `SLSsteam` | MIT (C# Standalone / Native) | Direct depot streaming, DLC manifest, ACF adoption. |
| **Epic Games Store** | `legendary` | GPLv3 (Python Standalone Binary) | OAuth login, manifest delta-patching, cloud saves, EOS overlay, Wine/Proton hooks. |
| **GOG** | `gogdl` / `lgogdownloader` | MIT / GPL (Python / C++) | DRM-free installer downloads, cloud saves, innoextract support. |
| **Amazon Games** | `nile` | GPLv3 (Python Standalone Binary) | Prime Gaming auth, entitlement sync, direct depot downloads. |

---

## 3. Unified Store Abstraction Interface

Seluruh backend store akan diisolasi di bawah direktori modular `src/stores/`:

```text
src/stores/
├── 00_store_interface.sh    # Contract: store_search, store_download, store_sync, store_info
├── 10_store_steam.sh        # Steam Store implementation
├── 20_store_epic.sh         # Epic Games Store implementation via legendary
├── 30_store_gog.sh          # GOG implementation via gogdl
└── 40_store_amazon.sh       # Amazon Games implementation via nile
```

### Unified Store Contract Signature
Setiap adapter store wajib mengimplementasikan fungsi-fungsi berikut:

```bash
# 1. Search catalog
store_<name>_search <query>
# Output: <STORE_ID>\t<TITLE>\t<PRICE_OR_STATUS>\t<PLATFORMS>

# 2. Download / Install
store_<name>_download <app_id> <target_dir> [options]

# 3. Cloud / Metadata Sync
store_<name>_sync <app_id> <game_dir>

# 4. Authentication Check
store_<name>_status
```

---

## 4. Multi-Store Library Schema & Metadata Contract

Scanner library ([src/core/10_scanner.sh](file:///home/aomiqaza/Projects/gamectl/src/core/10_scanner.sh)) akan diupgrade menjadi format 6 kolom terstandardisasi:

```text
Column 1: STORE      -> STEAM | EPIC | GOG | AMAZON | STANDALONE
Column 2: APP_ID     -> Numeric Steam AppID, Epic AppName, atau GOG Product ID
Column 3: TITLE      -> Clean sanitized game title
Column 4: GAME_DIR   -> Absolute directory path on local disk
Column 5: RUNNER     -> Native | Proton | Wine | System
Column 6: STATUS     -> INSTALLED | GBE_FORK | VALVE_DLL | RAW
```

---

## 5. TUI & Dashboard UX Architecture

Di Master Dashboard Hub ([src/tui/70_dashboard.sh](file:///home/aomiqaza/Projects/gamectl/src/tui/70_dashboard.sh)):

1. **Store Switcher Filter**:
   - Header Dashboard menampilkan toggle store: `Store: [ALL | STEAM | EPIC | GOG]`.
   - Shortcut `Tab` atau `Ctrl-S` untuk mengganti active store filter.
2. **Dynamic Action Palette**:
   - Ketika game EGS dipilih: Opsi mencakup `Launch via Proton`, `Sync Epic Cloud Saves`, `Update Game`.
   - Ketika game GOG dipilih: Opsi mencakup `Verify Files`, `Rollback Version`, `Launch Standalone`.
3. **Headless Authentication Hub**:
   - Menu `gamectl auth` untuk mengelola login EGS (`legendary auth`), GOG, dan Steam User.

---

## 6. Phased Implementation Roadmap

- **Phase 1 (Steam Isolation & Core Refactoring)**:
  - Memisahkan logika Steam spesifik ke `src/stores/10_store_steam.sh`.
  - Mengadopsi 6-kolom library data contract.
- **Phase 2 (Epic Games Integration via `legendary`)**:
  - Implementasi `src/stores/20_store_epic.sh`.
  - Integrasi perintah `gamectl epic [search|install|list|launch]`.
- **Phase 3 (GOG Integration via `gogdl`)**:
  - Implementasi `src/stores/30_store_gog.sh` untuk DRM-free download dan ekstraksi.
- **Phase 4 (TUI Multi-Store Palette & Dashboard Unification)**:
  - Menggabungkan seluruh catalog ke dalam satu search unified TUI.

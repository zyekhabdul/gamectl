# WORK PACKET 36: DEPOT-DL CLI TESTS, WINE PREFIX SAVE AUTO-LOCATE & DEV PROFILER

- **Track**: Testing Hardening / Savegame Safety / Developer Diagnostics
- **Status**: COMPLETED [4/4 PACKETS]
- **Riwayat Selesai**: WP33 (`49b518f..17a1284`), WP34 (`86319f1..67d5c02`), WP35 (`aaf39df..13ffb6f`) — seluruhnya COMPLETED & terverifikasi.
- **Basis**: Sisa 3 item terbuka hasil audit `HEAD` (`13ffb6f`) terhadap `docs/PROPOSAL_GLOBAL_FEATURES.md:132-147` dan `crates/depot-dl/src/bin/gamectl-depot-dl.rs`.
- **Target Files**: `crates/depot-dl/src/bin/gamectl-depot-dl.rs`, `bin/gamectl-depot-dl`, `src/core/10_utils.sh`, `src/runners/40_wrappers.sh`, `src/runners/50_launcher.sh`, `src/main.sh`, `tests/test_remediation.sh`, `bin/gamectl`

---

## 1. Masalah Empiris & Celah Terbuka

1. **`crates/depot-dl/src/bin/gamectl-depot-dl.rs:1-228`**:
   - Parsing argumen CLI (`--app`, `--dir`, `--depot`, `--max-downloads`, `--verbose`, `--quiet`, `-h`/`--help`) masih menyatu di `async fn main()` dengan `process::exit(1)`.
   - Terdapat `0` unit test `#[test]` / `#[cfg(test)]` pada target binary (`gamectl-depot-dl.rs`), sehingga regresi parsing flag atau `--depot <manifest>:<key>` hanya mengandalkan test runtime eksternal.
2. **Wine Prefix Save Auto-Locate (`docs/PROPOSAL_GLOBAL_FEATURES.md:132-138`)**:
   - `backup_save()` (`src/core/10_utils.sh:845-952`), `restore_save()` (`L987-L1100`), serta remote sync (`sync_save_remote`, `pull_save_remote`) baru melindungi `<game_dir>/saves/`.
   - Savegame Windows di dalam `pfx/drive_c/users/.../(AppData/{Local,LocalLow,Roaming}|Documents/My Games|Saved Games)` belum terdeteksi atau terlindungi (`0` implementasi).
3. **Game Developer Mode & Engine Profiler (`docs/PROPOSAL_GLOBAL_FEATURES.md:141-147`)**:
   - Belum ada toggle `WINEDEBUG` (`+relay`, `+seh`, `+loaddll`), `VK_LOADER_DEBUG=all`, maupun capture log callback Steamworks/GBE di `load_wrapper_config()`, `configure_wrappers()`, atau `launch_game()` (`0` implementasi).

---

## 2. Rencana Eksekusi Detail (Packet 36A - 36D)

### [x] Packet 36A: Rust CLI Unit Tests untuk `gamectl-depot-dl.rs`
- **Target Files**: `crates/depot-dl/src/bin/gamectl-depot-dl.rs`, `bin/gamectl-depot-dl`
- **Langkah Teknis**:
  1. Ekstrak parsing argumen dari `main()` menjadi fungsi murni (zero external crate):
     - `struct CliConfig` (`app_id: u32`, `dir: PathBuf`, `depots: Vec<(PathBuf, String)>`, `max_downloads: usize`, `verbose: bool`, `quiet: bool`)
     - `enum CliError` (`HelpRequested`, `InvalidArg(String)`)
     - `fn parse_cli_args<I, S>(args: I) -> Result<CliConfig, CliError>`
  2. Tambahkan `#[cfg(test)] mod tests` pada `gamectl-depot-dl.rs` yang menguji:
     - Kasus valid multi-depot, flag `--verbose`/`-v`, `--quiet`/`-q`, `--max-downloads`, dan path ber-titik-dua via `rfind(':')`.
     - `-h` / `--help` mengembalikan `Err(CliError::HelpRequested)`.
     - Flag wajib hilang (`--app`, `--dir`, `--depot`), `--app` non-numerik, `--depot` tanpa `:`, manifest/key kosong, dan `--max-downloads` invalid/`0`.
  3. Rebuild `bin/gamectl-depot-dl` via `./scripts/build-depot-dl.sh` agar freshness gate `--check` tetap sinkron.
- **Definition of Done (DoD)**:
  - `cargo test --manifest-path crates/depot-dl/Cargo.toml --bins` lulus `> 0` test.
  - `cargo test --manifest-path crates/depot-dl/Cargo.toml` penuh exit `0` dan `./scripts/build-depot-dl.sh --check` PASS.

### [x] Packet 36B: Smart Savegame Auto-Locate (Ludusavi-style Wine Prefix Scanner)
- **Target Files**: `src/core/10_utils.sh`, `src/runners/40_wrappers.sh`, `src/runners/50_launcher.sh`, `src/main.sh`
- **Langkah Teknis**:
  1. Tambahkan SSoT read-only `discover_prefix_saves "$game_dir"` di `src/core/10_utils.sh`:
     - Memindai `pfx/drive_c/users/*/(AppData/Local|AppData/LocalLow|AppData/Roaming|Documents/My Games|My Documents/My Games|Saved Games)`.
     - Memfilter folder noise sistem (`Microsoft`, `Temp`, `Packages`, `CrashDumps`, `D3DSCache`, `NVIDIA`, `AMD`, `Intel`, `Wine`, `Steam`, `Goldberg SteamEmu Saves`, `GSE Saves`, `mesa_shader_cache`, `vulkan`).
     - Hanya melaporkan direktori yang berisi file reguler dan memblokir symlink escape di luar `pfx/drive_c/users/`.
  2. Tambahkan `collect_prefix_saves` & `restore_prefix_saves` (non-destruktif, opt-in):
     - Staging terisolasi ke `<game_dir>/saves/_prefix_saves/<rel>` sehingga `backup_save`, `restore_save`, dan `sync_save_remote`/`pull_save_remote` otomatis ikut memproteksi dan menyinkronkannya tanpa memutus kontrak tes `saves/` eksisting.
     - Mematuhi active-game guard (`is_game_active_for_dir`).
  3. Ekspos melalui CLI (`gamectl scan-saves <game_dir>`, `gamectl collect-saves <game_dir>`) serta opsi opt-in `.wrappers` `auto_locate_saves=1` saat pre-launch/post-exit `launch_game()`.
- **Definition of Done (DoD)**:
  - Zero mutasi pada direktori sistem Wine/Windows.
  - Symlink escape di luar prefix ditolak.
  - Seluruh kontrak `tests/test_save_safety.py` tetap 100% PASS.

### [x] Packet 36C: Game Developer Mode & Engine Profiler
- **Target Files**: `src/runners/40_wrappers.sh`, `src/runners/50_launcher.sh`, `src/main.sh`
- **Langkah Teknis**:
  1. Perluas `load_wrapper_config()` (`src/runners/40_wrappers.sh:1363-1425`) dengan 3 kunci opt-in default OFF:
     - `dev_winedebug` (`0|basic|full|<custom>`) + override `GAMECTL_DEV_WINEDEBUG`
     - `dev_vk_debug` (`0|1`) + override `GAMECTL_DEV_VK_DEBUG`
     - `dev_gbe_log` (`0|1`) + override `GAMECTL_DEV_GBE_LOG`
  2. Tambahkan SSoT `resolve_dev_profiler_env()` (ekspor di `src/main.sh`):
     - `basic` -> `+loaddll,+seh`; `full` -> `+relay,+seh,+loaddll`; custom string diteruskan apa adanya (sanitized).
     - `dev_vk_debug=1` -> `VK_LOADER_DEBUG=all`.
     - Tidak menimpa `WINEDEBUG` atau `VK_LOADER_DEBUG` yang sudah disetel eksplisit di environment shell user.
     - Arahkan trace log ke `$(get_runtime_dir)/dev_traces/<slug>.log` dan aktifkan penangkapan log callback GBE/Steamworks bila `dev_gbe_log=1`.
  3. Hubungkan ke `launch_game()` (`src/runners/50_launcher.sh`), tambahkan toggle di `configure_wrappers()` (`src/runners/40_wrappers.sh:1560-1680`), dan subcommand CLI `gamectl dev-profile <game_dir> [status|basic|full|off]`.
- **Definition of Done (DoD)**:
  - Saat default OFF, menghasilkan `0` polusi environment (`WINEDEBUG`, `VK_LOADER_DEBUG` tidak disentuh).
  - Saat aktif, variabel debug/profiler terekspor deterministik dan jalur log trace tercatat di log peluncuran.

### [x] Packet 36D: Regression Contracts, Bundle Sync & Full Verification
- **Target Files**: `tests/test_remediation.sh`, `bin/gamectl`, `bin/gamectl-depot-dl`
- **Langkah Teknis**:
  1. Tambahkan Tests 29–30 di `tests/test_remediation.sh`:
     - **Test 29 (36B)**: kontrak `discover_prefix_saves`, filter noise sistem, penolakan symlink escape, dan roundtrip `collect_prefix_saves` -> `backup_save` -> `restore_save`.
     - **Test 30 (36C)**: kontrak `resolve_dev_profiler_env` (default OFF bersih, `basic`/`full`, `VK_LOADER_DEBUG=all`, respect user env override, dan persistensi `dev-profile`).
  2. Kompilasi ulang `bin/gamectl` (`./scripts/build.sh && ./scripts/build.sh --check`) dan pastikan `./scripts/build-depot-dl.sh --check` PASS.
  3. Jalankan gerbang penuh:
     `cargo test --manifest-path crates/depot-dl/Cargo.toml && STRICT_LINT=1 make lint && ./tests/test_remediation.sh && python3 -m unittest tests/test_tui_safety.py tests/test_standalone_safety.py tests/test_save_safety.py && ./tests/test_cli.sh < /dev/null && ./tests/test_tui_ergonomics.sh`
- **Definition of Done (DoD)**:
  - Seluruh suite Rust (`--bins` & `--lib`), `STRICT_LINT=1 make lint`, Remediation `30/30`, Python `42/42`, CLI `147/147`, dan Ergonomics lulus Exit Code `0`.

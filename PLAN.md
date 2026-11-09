# WORK PACKET 20: RUNTIME RESILIENCE, CACHE EXPANSION & SOVEREIGN DECOUPLING HARDENING

**Track**: Maintenance / Resilience & Zero-Bloat  
**Status**: PENDING IMPLEMENTATION  
**Branch**: `main`  
**Max Chunks**: 6 Chunks (Active Packet <= 10)  
**Target Files**: `src/steam/30_downloader.sh`, `src/core/10_utils.sh`, `Makefile`, `tests/test_cli.sh`, `bin/gamectl`

---

## 1. Objective & Technical Scope
Memperkuat ketahanan runtime proses, mengeliminasi query rate-limit jaringan ke Valve, dan menegakkan prinsip kedaulatan offline (*Sovereign Standalone*):
1. **Ghost Download Defense & Staging Self-Healing**: Mengeliminasi folder staging unduhan yatim (`depot_dl_*`) akibat proses terputus tak terduga, mencegah status palsu `[STANDALONE ACTIVE]` pada TUI Download Manager.
2. **Native Process IPC for Standalone Engine**: Mengganti panggilan Steam URI yang salah sasaran (`steam://pause`) menjadi sinyal kontrol POSIX native (`SIGSTOP`, `SIGCONT`, `SIGTERM`) pada unduhan engine standalone.
3. **Steam Store Metadata Disk Caching**: Menstandardisasi seluruh query metadata game ke `fetch_cached_json()` (TTL 3600s), mengeliminasi risiko Valve HTTP 429 dan latensi berulang.
4. **Strict Sovereign Decoupling**: Menghapus silent-fallback ke SLSsteam/Steam Client jika user secara eksplisit meminta `--standalone` / `--headless`, mengembalikan error deterministik jika key/binary tidak ada.
5. **Disk Cleanliness**: Menambahkan pembersihan cache build Rust (`crates/depot-dl/target`) ke target `clean` di `Makefile`.
6. **Deterministic Machine Gate**: Menambahkan test assertions penjaminan regresi dan mengompilasi ulang bundle mandiri `bin/gamectl`.

---

## 2. Granular Technical Execution Plan (Todolist)

### [x] Chunk 1: Ghost Download Elimination & Staging Directory Self-Healing [VERIFIED]
- **Target Files**: `src/steam/30_downloader.sh` (`list_downloads_interactive()`), `src/core/10_utils.sh` (`clean_stale_locks()`)
- **Runtutan Eksekusi Teknis**:
  1. Di `list_downloads_interactive()`, saat memindai `"$run_dir"/depot_dl_*`:
     - Ekstrak PID pemilik unduhan dari nama direktori: `st_pid="${st_dir##*_}"`.
     - Cek apakah PID masih aktif menggunakan probing sinyal null: `kill -0 "$st_pid" 2>/dev/null`.
     - Jika proses sudah mati: jalankan pembersihan otomatis `rm -rf "$st_dir" 2>/dev/null || true` dan lewati iterasi (`continue`).
     - Jika proses masih hidup: catat sebagai unduhan aktif dengan identitas PID.
  2. Di `clean_stale_locks()` (`src/core/10_utils.sh`):
     - Tambahkan pembersihan iteratif untuk direktori `$run_dir/depot_dl_*` yang memiliki PID non-aktif saat startup atau launch teardown.
- **Definition of Done (DoD)**:
  - Direktori staging dari proses download yang mati dibersihkan secara otomatis.
  - TUI Download Manager tidak pernah menampilkan unduhan hantu (*ghost active downloads*).

### [x] Chunk 2: Native POSIX Signals for Standalone Download Management (Pause/Resume/Kill) [VERIFIED]
- **Target Files**: `src/steam/30_downloader.sh` (`list_downloads_interactive()`)
- **Runtutan Eksekusi Teknis**:
  1. Pada penanganan hotkey `ctrl-k` (Pause):
     - Evaluasi `$sel_engine`.
     - Jika `sel_engine == "Standalone"`:
       - Ekstrak PID target dari `$sel_ref`: `local t_pid="${sel_ref##*_}"`.
       - Kirim sinyal POSIX `kill -STOP "$t_pid" 2>/dev/null`.
       - Tampilkan konfirmasi melalui `tui_modal_notice "Download Paused" "Paused native standalone downloader PID: $t_pid via SIGSTOP"`.
     - Jika `sel_engine == "Steam"`:
       - Tetap kirim URI `steam://pause/$sel_appid`.
  2. Pada menu action unduhan (`action_entries`):
     - Sesuaikan opsi untuk Standalone: Opsi 1 kirim `kill -STOP "$t_pid"`, Opsi 2 kirim `kill -CONT "$t_pid"`, Opsi 4 kirim `kill -TERM "$t_pid"` (Cancel Download).
- **Definition of Done (DoD)**:
  - Unduhan standalone merespons jeda dan lanjut secara instan via sinyal sistem operasi tanpa bergantung pada Steam Client IPC.

### [ ] Chunk 3: Zero-Latency & Anti-Rate-Limit: Steam Store API Disk Caching (`fetch_cached_json`)
- **Target Files**: `src/steam/30_downloader.sh` (`download_game()`, `sync_steam()`, `unlock_interactive()`, `fetch_dlc()`)
- **Runtutan Eksekusi Teknis**:
  1. Di `download_game()` (L978):
     - Ganti panggilan `curl -s ... "store.steampowered.com/api/appdetails?appids=${appid}&filters=basic"` dengan:
       `title=$(fetch_cached_json "https://store.steampowered.com/api/appdetails?appids=${appid}&filters=basic" "steam_basic_${appid}" 3600 2>/dev/null | jq -r ".\"${appid}\".data.name // empty" 2>/dev/null || true)`
  2. Di `sync_steam()` (L1674):
     - Ganti panggilan raw `curl` store basic metadata dengan `fetch_cached_json ... "steam_basic_${appid}" 3600`.
  3. Di `unlock_interactive()` (L1729):
     - Ganti panggilan raw `curl` store basic metadata dengan `fetch_cached_json ... "steam_basic_${u_appid}" 3600`.
  4. Di `fetch_dlc()` (L46, L51, L1480):
     - Gunakan `fetch_cached_json` untuk endpoint `dlcforapp` dengan cache key `steam_dlc_${appid}` (TTL 3600s).
- **Definition of Done (DoD)**:
  - Metadata tersimpan rapi di `${XDG_CACHE_HOME:-~/.cache}/gamectl/` selama 3600 detik.
  - Zero pemanggilan jaringan redundan pada operasi download, entitle, dan dlc beruntun.

### [ ] Chunk 4: Strict Sovereign Decoupling & Explicit Headless Failure Protocol
- **Target Files**: `src/steam/30_downloader.sh` (`download_game()`)
- **Runtutan Eksekusi Teknis**:
  1. Tambahkan pengecekan flag kedaulatan: `local is_strict_standalone=false`.
  2. Jika user memberikan argumen `--standalone`, `--headless`, atau `--direct`: set `is_strict_standalone=true`.
  3. Jika `is_strict_standalone=true`:
     - Jika binary `gamectl-depot-dl` tidak ditemukan: batalkan eksekusi, cetak pesan error instruksi kompilasi (`make build-depot-dl`), dan `return 1` (DILARANG fallback ke `sls`).
     - Jika manifest tidak memiliki kunci AES yang valid: batalkan eksekusi, laporkan nomor depot yang tidak berizin, dan `return 1` (DILARANG fallback ke `sls`).
  4. Routing fallback ke SLSsteam hanya diizinkan jika `is_strict_standalone=false` dan engine disetel ke `auto`.
- **Definition of Done (DoD)**:
  - Operasi download berstatus standalone mematuhi invariant ADR-022 dan tidak pernah mencoba meluncurkan Steam Client secara diam-diam.

### [ ] Chunk 5: Rust Compilation Cache Cleanup Target in `Makefile`
- **Target Files**: `Makefile`
- **Runtutan Eksekusi Teknis**:
  1. Perbarui target `clean` di `Makefile` agar menyertakan pemeriksaan direktori crate Rust:
     ```makefile
     clean:
     	rm -f $(BIN_DIR)/gamectl
     	if [ -f crates/depot-dl/Cargo.toml ] && command -v cargo >/dev/null 2>&1; then \
     		cargo clean --manifest-path crates/depot-dl/Cargo.toml; \
     	fi
     ```
  2. Tambahkan target `distclean` yang membersihkan log, scancache, dan file sementara.
- **Definition of Done (DoD)**:
  - `make clean` membersihkan sisa build Rust di `crates/depot-dl/target`, menghemat ratusan megabyte ruang disk.

### [ ] Chunk 6: Regression Test Suite Expansion, Rebuild & Machine Gate
- **Target Files**: `tests/test_cli.sh`, `bin/gamectl`
- **Runtutan Eksekusi Teknis**:
  1. Tambahkan skenario pengujian regresi di `tests/test_cli.sh`:
     - Test: Ghost download self-healing (verifikasi direktori staging dengan dead PID otomatis dibersihkan dan diabaikan).
     - Test: Strict standalone engine failure contract (menolak silent-fallback ke SLSsteam jika key hilang).
     - Test: Steam Store basic metadata disk cache contract.
     - Test: `Makefile` clean rust target contract.
  2. Kompilasi ulang bundle mandiri: `make build`.
  3. Jalankan `make lint`, `make test`, dan `cargo test`.
  4. Perbarui status checklist `[x]` pada `PLAN.md`.
- **DoD**:
  - Seluruh skenario baru lulus dengan Exit Code 0 (total > 113 assertions).
  - Standalone bundle `bin/gamectl` tersinkronisasi 100%.

---

## 3. Verification Matrix

| Komponen | Perintah Uji | Kriteria Sukses (DoD) |
| :--- | :--- | :--- |
| **Ghost Download Healing** | `./tests/test_cli.sh` | Folder `depot_dl_*` dengan PID mati otomatis terhapus, zero ghost entries. |
| **Standalone Signals** | `./tests/test_cli.sh` | Engine standalone memicu sinyal POSIX kill, bukan Steam URI IPC. |
| **Disk Cache API** | `ls -la ~/.cache/gamectl/steam_basic_*` | File cache metadata tercipta dan dipakai ulang tanpa latensi curl. |
| **Sovereign Invariant** | `./tests/test_cli.sh` | Flag `--standalone` tanpa kunci mengembalikan exit code 1, bukan SLSsteam. |
| **Clean Target** | `make clean` | Direktori `crates/depot-dl/target` terhapus bersih. |
| **Machine Gate** | `make lint && make test` | 0 syntax errors, 114+ test assertions lulus dengan Exit Code 0. |

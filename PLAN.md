# WORK PACKET 13: SLSSTEAM-MOON BACKEND ADOPTION & STANDALONE DOWNLOAD ARCHITECTURE [ACTIVE]

## 1. Objective & Technical Scope
Mengganti ketergantungan rapuh pada DepotDownloader eksternal (.NET GC heap tinggi, 401 unauthenticated rate-limit) dengan mengadopsi arsitektur backend SLSsteam-Moon / Lumen langsung ke dalam core `gamectl`:
1. **Multi-Source Manifest Harvester (`fetch_manifest`)**: Pengambilan otomatis archive manifest (.manifest + AES keys) dari multi-mirror publik (lua.tools, Ryuu, Sushi, local stash) secara paralel dan deterministik dengan verifikasi payload magic `0xd017f671`.
2. **SLSsteam Stplug-in & Manifest Linker (`deploy_sls_manifest`)**: Penempatan otomatis file `.manifest` ke `~/.config/SLSsteam/manifests/` & `depotcache/`, pembuatan skrip Lua `~/.local/share/Steam/config/stplug-in/<appid>.lua` (`addappid(depotid, 1, "AES_KEY")`), serta sinkronisasi entitlement `config.yaml`.
3. **Dual-Mode Download Orchestrator**: Mode default Steam Native Background (`steam://install/<appid>`) dengan fallback ke engine standalone.
4. **Real-time ACF Telemetry Monitor (`list_downloads`)**: Memantau progres unduhan presisi langsung dari `appmanifest_<appid>.acf` (`BytesDownloaded`, `BytesToDownload`, `StateFlags`).
5. **Dashboard TUI & CLI Integration**: Integrasi kontrol download, pause/resume, dan post-install auto-injection GBE Fork pada TUI `gamectl`.
6. **Machine Verification & Automated Regression Suite**: Memperbarui test suite `tests/test_cli.sh` (60+ assertions) dan memastikan `exit code 0` tanpa regresi.

---

## 2. Granular Technical Execution Plan (Work Packet 13)

### Chunk 1: Multi-Provider Manifest Harvester (`fetch_manifest`) [DONE]
- Target Files: `src/steam/30_downloader.sh`
- Runtutan Eksekusi Teknis:
  1. Implementasikan fungsi `fetch_manifest "$appid" [dest_dir]`:
     - Periksa cache lokal terlebih dahulu: `${XDG_CACHE_HOME:-~/.cache}/gamectl/manifests/${appid}.zip`.
     - Susun daftar kandidat provider secara terurut:
       - Source 1 (Ryuu Mirror): `http://167.235.229.108/${appid}`
       - Source 2 (Sushi Repo): `https://raw.githubusercontent.com/sushi-dev55-alt/sushitools-games-repo-alt/refs/heads/main/${appid}.zip`
       - Source 3 (Lua.tools API): `https://lua.tools/api/manifest/download?appid=${appid}&source=Luie` (menggunakan Bearer token dari `~/.local/share/Lumen/luatools/backend/data/lua_tools_auth.json` jika tersedia).
     - Jalankan unduhan kandidat dengan timeout ketat (10 detik) dan validasi HTTP status code 200.
  2. Implementasikan validasi integritas archive:
     - Cek apakah file merupakan valid ZIP (`unzip -tq`).
     - Cegah path traversal (tolak archive dengan entri `..` atau absolute path `/`).
     - Pastikan terdapat minimal satu file `.manifest` atau file `<appid>.lua`.
     - Verifikasi Valve manifest payload magic signature `0xd017f671` pada file `.manifest`.
  3. Kembalikan path zip tervalidasi ke caller.
- DoD: Fungsi `fetch_manifest` berhasil mengunduh, memverifikasi, dan mengembalikan file manifest archive untuk AppID valid dengan exit code 0.

### Chunk 2: SLSsteam Stplug-in & Manifest Linker (`deploy_sls_manifest`) [DONE]
- Target Files: `src/steam/30_downloader.sh`, `src/steam/20_discovery.sh`
- Runtutan Eksekusi Teknis:
  1. Implementasikan fungsi `deploy_sls_manifest "$appid" "$manifest_zip"`:
     - Ekstrak archive ke direktori temporer terisolasi `${XDG_RUNTIME_DIR:-/tmp}/gamectl-$UID/manifest_${appid}`.
     - Pindahkan semua file `*.manifest` ke:
       - `~/.config/SLSsteam/manifests/`
       - Symlink / salin ke `~/.local/share/Steam/depotcache/`
     - Deteksi depot ID dan generate file marker `.preferred_<depotid>` berisikan GID manifest terbaru.
  2. Ekstraksi atau Sintesis Skrip Lua Stplug-in:
     - Jika archive menyertakan file `<appid>.lua`, salin ke `~/.local/share/Steam/config/stplug-in/<appid>.lua`.
     - Jika archive hanya menyertakan manifest dan file kunci teks, sintesis file Lua dengan format resmi:
       ```lua
       addappid(<appid>)
       addappid(<depotid>, 1, "<aes_256_key>")
       ```
     - Amankan permissions file stplug-in ke `0600`.
  3. Panggil `sync_steam "$appid"` untuk mendaftarkan AppID dan DLC ke `~/.config/SLSsteam/config.yaml`.
- DoD: File manifest terpasang di SLSsteam manifests, file Lua stplug-in terbuat di `config/stplug-in/<appid>.lua`, dan AppID terdaftar di config SLSsteam.

### Chunk 3: Dual-Mode Download Orchestrator Refactoring (`download_game`) [DONE]
- Target Files: `src/steam/30_downloader.sh`, `src/main.sh`
- Runtutan Eksekusi Teknis:
  1. Refactor parameter dan engine selector pada `download_game`:
     - Tambahkan flag CLI `--engine [steam|depot]` (default: `steam`).
     - Tambahkan flag `--source [auto|ryuu|sushi|luatools]`.
  2. Mode A (Default: Steam Native Content Engine):
     - Jalankan `fetch_manifest "$appid"` untuk mengunduh manifest dan kunci.
     - Jalankan `deploy_sls_manifest "$appid" "$manifest_zip"`.
     - Verifikasi kesiapan Steam Client:
       - Jika Steam aktif: trigger `steam "steam://install/${appid}" >/dev/null 2>&1 &`.
       - Jika Steam mati: tampilkan opsi jalankan silent background `steam -silent &` atau ingatkan pengguna.
     - Berikan umpan balik instan ke terminal bahwa tugas download telah didelegasikan ke engine Valve CDN berkecepatan penuh.
  3. Mode B (Fallback: Headless DepotDownloader):
     - Pertahankan alur eksekusi `ensure_downloader` dan `DepotDownloader -app "$appid"` saat user memberikan flag `--engine=depot` atau `--headless`.
- DoD: Perintah `gamectl download <appid>` sukses mengekstrak manifest, menulis stplug-in, dan mentrigger Steam client tanpa error 401.

### Chunk 4: Real-Time ACF Telemetry & Interactive Monitor (`list_downloads`) [PLANNED]
- Target Files: `src/steam/30_downloader.sh`
- Runtutan Eksekusi Teknis:
  1. Implementasikan parser telemetri ACF `parse_acf_download_state "$appid"`:
     - Baca langsung dari `~/.local/share/Steam/steamapps/appmanifest_${appid}.acf`.
     - Ekstrak atribut: `StateFlags`, `BytesDownloaded`, `BytesToDownload`, `BytesToStage`, `BytesStaged`.
     - Parsing StateFlags:
       - `1024` atau `1026`: `[DOWNLOADING]`
       - `512`: `[PAUSED]`
       - `4`: `[INSTALLED]`
       - `2`: `[UPDATE REQUIRED]`
  2. Refactor `list_downloads`:
     - Tampilkan tabel progres aktif: AppID, Title, Status, Progress %, Bytes Downloaded / Total.
  3. Refactor `list_downloads_interactive`:
     - Gunakan interface FZF untuk memantau status secara live.
     - Tambahkan action menu:
       - Pause / Resume via protokol Steam (`steam://pause/<appid>` / `steam://resume/<appid>`).
       - Post-download Action: Jika `StateFlags == 4`, sediakan tombol 1-klik untuk `inject_game` (GBE Fork standalone).
- DoD: Monitor download menampilkan persentase unduhan real-time dari file ACF resmi Steam tanpa polling log file mentah.

### Chunk 5: Dashboard TUI & CLI Integration [PLANNED]
- Target Files: `src/tui/70_dashboard.sh`, `src/main.sh`
- Runtutan Eksekusi Teknis:
  1. Perbarui status bar indikator download di `src/tui/70_dashboard.sh`:
     - Ganti label `DepotDownloader` dengan `SLSsteam-Moon Engine: [READY]`.
     - Deteksi status runtime Steam client (`[RUNNING]` vs `[IDLE]`).
  2. Perbarui shortcut aksi di TUI Dashboard:
     - `<Ctrl-A>` (All-in-One Download): otomatis memanggil mode native SLSsteam manifest fetcher.
     - `<Ctrl-D>` (Live Downloads Monitor): membuka monitor telemetri ACF.
  3. Perbarui CLI help & completion di `src/main.sh`:
     - Dokumentasikan opsi baru `gamectl download <appid> [--engine=steam|depot] [--source=...]`.
- DoD: TUI Dashboard terintegrasi penuh dengan download engine baru, shortcut keyboard berfungsi mulus.

### Chunk 6: Test Suite & Empirical Machine Verification [PLANNED]
- Target Files: `tests/test_cli.sh`, `scripts/build.sh`
- Runtutan Eksekusi Teknis:
  1. Buat unit test baru di `tests/test_cli.sh`:
     - Test validasi ZIP manifest & magic signature check (`manifest_has_payload_magic`).
     - Test parser stplug-in Lua generator output.
     - Test parser ACF telemetry flags (1024, 512, 4).
     - Test engine argument parsing (`--engine=steam`, `--engine=depot`).
  2. Eksekusi `./scripts/build.sh` untuk menghasilkan monolithic bundle `bin/gamectl`.
  3. Jalankan regression suite `./tests/test_cli.sh` (target 65+ assertions).
  4. Buktikan Exit Code 0 dengan 0 failures / 0 skips.
- DoD: Seluruh rangkaian tes lulus dengan exit code 0 tanpa regresi pada fitur eksisting.

---

## 3. Matriks Milestone (Work Packet 13)
- [x] Chunk 1: Multi-Provider Manifest Harvester (`fetch_manifest`) [DONE]
- [x] Chunk 2: SLSsteam Stplug-in & Manifest Linker (`deploy_sls_manifest`) [DONE]
- [ ] Chunk 3: Dual-Mode Download Orchestrator Refactoring (`download_game`) [PLANNED]
- [ ] Chunk 4: Real-Time ACF Telemetry & Interactive Monitor (`list_downloads`) [PLANNED]
- [ ] Chunk 5: Dashboard TUI & CLI Integration (`70_dashboard.sh` & `main.sh`) [PLANNED]
- [ ] Chunk 6: Test Suite & Empirical Machine Verification (`tests/test_cli.sh`) [PLANNED]

# IMPLEMENTATION PLAN — gamectl (Work Packet 1)

Track: Maintenance
Status: ACTIVE
Target: Menggantikan total ekosistem SLSsteamMoon + ACCELA + Headcrab + SteaMidra dengan Pure CLI/TUI mandiri.

---

## 1. Analisis Fitur & User Experience (UX Redesign)

### A. Masalah Fitur Search Saat Ini
- `gamectl --search` saat ini berstatus **read-only**: user hanya bisa mengetik nama game dan melihat preview rating ProtonDB.
- Menekan `<ENTER>` hanya menutup TUI tanpa melakukan aksi apapun. User terpaksa mencatat AppID secara manual jika ingin memproses lebih lanjut.

### B. Solusi Search Berorientasi Aksi (Actionable TUI Search)
- Mengubah alur pencarian agar menjadi gerbang akuisisi game satu pintu:
  1. User mencari game di menu search TUI.
  2. Preview menampilkan: Metadata Steam, ProtonDB Rating, status lokal (`[BELUM TERPASANG]` vs `[TERPASANG]`), dan perkiraan platform target.
  3. Menekan tombol `<ENTER>` langsung memicu download headless ke `$HOME/Games/<NamaGame>`.
  4. Begitu download selesai, sistem langsung mengeksekusi auto-inject GBE Fork + portable save tanpa intervensi manual.
  5. Game langsung muncul di pustaka utama `gamectl` dan siap dimainkan.

---

## 2. Rincian Kerja Granular (Sliding Packet Max 10 Chunks)

### Chunk 1: Modul Otomatisasi Injeksi GBE Fork (`gamectl inject`)
- [x] Implementasi CLI sub-command: `gamectl inject <path_ke_game> [appid]`
- [x] Detektor biner ELF 64-bit vs 32-bit via `file -b` untuk memilih `libsteam_api.so` x64 vs x86 dari GBE Fork template.
- [x] Otomatisasi pembuatan `steam_settings/configs.user.ini` dengan konfigurasi portable `local_save_path = ./saves`.
- [x] Penulisan file `steam_appid.txt` dan pembuatan direktori `./saves/`.
- [x] Pembuatan backup biner asli jika sebelumnya sudah ada `libsteam_api.so` bawaan Valve (`libsteam_api.so.orig`).

### Chunk 2: Generator Otomatis DLC Unlocker (`gamectl fetch-dlc`)
- [x] Implementasi fungsi parsing daftar DLC dari Steam Web API publik:
  `https://store.steampowered.com/api/dlcforapp/?appid=<appid>`
- [x] Konversi daftar DLC menjadi format standar GBE Fork: `steam_settings/DLC.txt` (`<dlc_id>=<dlc_name>`).
- [x] Integrasi otomatis fungsi ini ke dalam alur `gamectl inject`.

### Chunk 3: Integrasi Headless Downloader Engine (Pengganti ACCELA)
- [x] Penyediaan runtime headless downloader CLI (pemeriksaan ketersediaan `depotdownloader` / wrapper SteamCMD).
- [x] Implementasi sub-command: `gamectl download <appid> [target_dir] [title]`.
- [x] Peluncuran proses download di latar belakang dengan pencatatan log stream non-blocking ke `/tmp/dl_${APPID}.log`.
- [x] Hook otomatis: panggil `gamectl inject` begitu proses download tuntas (exit code 0).

### Chunk 4: Redesain TUI Search Berorientasi Aksi (`gamectl --search`)
- [ ] Tambahkan status instalasi lokal pada preview search: cek apakah AppID sudah ada di Steam atau `~/Games/`.
- [ ] Tambahkan bind aksi `<ENTER>` di fzf search:
  - Jika belum terpasang: Tampilkan konfirmasi unduh & pasang headless.
  - Jika sudah terpasang: Tampilkan info lokasi dan opsi luncurkan langsung.
- [ ] Tampilkan informasi kategori depot dan kesiapan runner Linux di panel preview.

### Chunk 5: Keybind Injeksi pada TUI Library Utama (`<Ctrl-I>`)
- [ ] Tambahkan shortcut `<Ctrl-I>` pada menu utama `gamectl` (Library TUI).
- [ ] Memungkinkan user mengubah game berstatus `[VALVE_SO]` atau `[STANDALONE]` menjadi `[GBE_FORK]` secara instan dari tampilan daftar game.

### Chunk 6: Integrasi Dual-Mode Steam Client & SLSsteam Sync (`gamectl sync-steam`)
- [x] Otomatisasi pendaftaran AppID ke `~/.config/SLSsteam/config.yaml` (`AppIds:` & `AdditionalApps:`).
- [x] Otomatisasi pendaftaran seluruh DLC game ke section `DlcData:` di `~/.config/SLSsteam/config.yaml` agar berstatus full DLC saat client Steam resmi dibuka.
- [x] Pembuatan template `appmanifest_<appid>.acf` di `~/.local/share/Steam/steamapps/` (`StateFlags: 4`) agar Steam client resmi langsung mengenali status game terinstal.
- [x] Hook otomatis: dipanggil saat game baru selesai ditambahkan atau diinjeksi via `gamectl`.

### Chunk 7: Uji Verifikasi Empiris & Dokumentasi
- [ ] Uji fungsionalitas injeksi pada direktori mock/sample game.
- [ ] Uji parsing DLC generator, format `DLC.txt`, dan pembaruan `~/.config/SLSsteam/config.yaml`.
- [ ] Verifikasi script syntax (`bash -n bin/gamectl`).
- [ ] Perbarui dokumentasi di `README.md` dan `docs/GUIDE.md` mencakup seluruh alur baru.

---

## 3. Definition of Done (DoD)
- Semua 7 chunk selesai diimplementasikan dengan clean code (Ponytail / YAGNI).
- Script lolos verifikasi sintaks bash tanpa error (`exit code 0`).
- Fitur search terintegrasi mulus dengan download & injection.
- Game siap main mandiri (standalone GBE) dan sekaligus langsung berstatus terbuka dengan full DLC saat aplikasi Steam resmi dibuka.

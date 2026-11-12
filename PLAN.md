# WORK PACKET 24: LINUX RUNTIME MATURITY, TELEMETRY, & COMMUNITY FIXES INTEGRATION

Track: Maintenance (Linux Runtime Safety & TUI Hardening)  
**Status**: DELIVERED [BASELINE TESTS PASS]; REMEDIATION OPEN

**Branch**: `main`  
**Max Chunks**: 8 Chunks (Active Packet <= 10)  
**Target Files**: `src/tui/70_dashboard.sh`, `src/steam/30_downloader.sh`, `src/steam/35_fixes.sh`, `src/runners/50_launcher.sh`, `src/diagnostics/60_doctor.sh`, `src/core/10_utils.sh`, `src/main.sh`, `tests/test_cli.sh`, `bin/gamectl`

> Review 2026-11-12 pada `b63062d`: delapan item di bawah mencatat delivery fitur dan baseline 130 tes CLI yang lulus. Status itu belum menutup kegagalan runtime yang direproduksi kemudian. Progres/kontrol unduhan pada Chunk 2 serta keamanan menu fixes pada Chunk 7 dibuka kembali melalui Packet 25. Riwayat delivery dipertahankan; seluruh remediasi baru tetap belum dikerjakan.

---

## 1. Objective & Technical Scope
Menuntaskan seluruh kesenjangan tampilan dan fitur interaktif Linux runtime maturity:
1. **Steam Store Search & ProtonDB Preview Engine (`--preview-search`)**: Mengeliminasi error dash `/bin/sh`, kebocoran teks literal `-e`, dan fake `[NO REPORTS YET]`, menyajikan data genre, platform (Native ELF vs Windows PE), dan ProtonDB tier riil.
2. **Standalone Downloader Telemetry & Real-Time Progress Invariant**: Mengimplementasikan file metadata `status.info`, kalkulasi progres dinamis, serta panel preview live streaming log (`--preview-download`).
3. **Unified CLI Download Status (`list_downloads`)**: Menyatukan pemindaian Steam ACF dan direktori proses unduhan standalone CDN ke dalam output `gamectl download-status`.
4. **Dynamic & Context-Rich Master Dashboard Preview (`preview_dashboard`)**: Merombak preview 7 modul dashboard agar menyajikan metrik sistem, storage, unduhan, dan activity logs secara dinamis.
5. **Enrich Redundant Preview Panes**: Menghilangkan tampilan tautologis di Activity Logs (`preview_log_entry`), Process HUD (`preview_process_log` dengan 7-baris konteks), dan ACF Picker (`preview_adopt_candidate` dengan status auto-discovery).
6. **Expand System Diagnostics (`doctor_audit` Layer 8)**: Menambahkan Layer 8 Security Sandboxing (`bwrap`) dan Process Isolation (`cgroups v2 systemd-run --user`) pada audit health check.
7. **Expose Game Fixes & OnlineFix Harvester in TUI**: Membuka akses katalog fix LuaTools, P2P Spacewar (AppID 480) setup, dan atomic rollback snapshot di `library_menu` (`Ctrl-X`), action palette `search_steam`, dan modal FZF interaktif (`--preview-fix`).
8. **Regression Test Suite Expansion, Rebuild & Machine Gate**: Memperluas kontrak pengujian di `tests/test_cli.sh`, mengompilasi ulang standalone bundle `bin/gamectl`, dan memvalidasi machine gate (130/130 assertions PASS).

---

## 2. Granular Technical Execution Plan (Todolist)

### [x] Chunk 1: Steam Store Search & ProtonDB Preview Engine (`--preview-search`) [VERIFIED]
- **Target Files**: `src/tui/70_dashboard.sh`, `src/main.sh`, `tests/test_cli.sh`
- **DoD**: Game populer menampilkan genre, platform, dan tier ProtonDB riil tanpa kebocoran teks `-e`. Commit: `8b37ca2`.

### [x] Chunk 2: Standalone Downloader Telemetry & Real-Time Progress Invariant [VERIFIED]
- **Target Files**: `src/steam/30_downloader.sh`, `src/main.sh`, `tests/test_cli.sh`
- **DoD**: Unduhan standalone mencatat `status.info`, menghitung persentase aktual, dan menampilkan live streaming log di panel preview. Commit: `12570ba`.

### [x] Chunk 3: Unified CLI Download Status (Standalone Detection) [VERIFIED]
- **Target Files**: `src/steam/30_downloader.sh`, `tests/test_cli.sh`
- **DoD**: Perintah CLI `gamectl download-status` melaporkan unduhan standalone aktif bersama unduhan Steam client. Commit: `d470796`.

### [x] Chunk 4: Dynamic & Context-Rich Master Dashboard Preview (`preview_dashboard`) [VERIFIED]
- **Target Files**: `src/tui/70_dashboard.sh`, `tests/test_cli.sh`
- **DoD**: Seluruh 7 modul di Master Dashboard menampilkan metrik sistem aktual secara dinamis. Commit: `959de51`.

### [x] Chunk 5: Enrich Redundant Preview Panes (Log Viewer, Process HUD, ACF Picker) [VERIFIED]
- **Target Files**: `src/tui/70_dashboard.sh`, `src/steam/30_downloader.sh`, `tests/test_cli.sh`
- **DoD**: Eliminasi duplikasi tampilan; panel preview menyajikan data konteks dan panduan remediasi error. Commit: `394d9ca`.

### [x] Chunk 6: Expand System Diagnostics (`doctor_audit` Layer 8: Security & Isolation) [VERIFIED]
- **Target Files**: `src/diagnostics/60_doctor.sh`, `src/tui/70_dashboard.sh`, `tests/test_cli.sh`
- **DoD**: `gamectl doctor` dan cockpit dashboard mengaudit kesiapan `--sandbox` (`bwrap`) dan `--scope` (`systemd-run --user`). Commit: `7fff866`.

### [x] Chunk 7: Expose Game Fixes & OnlineFix Harvester in TUI [VERIFIED]
- **Target Files**: `src/steam/35_fixes.sh`, `src/tui/70_dashboard.sh`, `src/main.sh`, `src/core/10_utils.sh`, `tests/test_cli.sh`
- **DoD**: Fitur katalog fix dan OnlineFix dapat diakses langsung dari `library_menu` (`Ctrl-X`) dan `search_steam` dengan safety snapshot restore/dry-run. Commit: `3ced56e`.

### [x] Chunk 8: Regression Test Suite Expansion, Rebuild & Machine Gate [VERIFIED]
- **Target Files**: `tests/test_cli.sh`, `bin/gamectl`, `PLAN.md`
- **DoD**: Exit code 0, 0 test regressions, total pengujian mencapai 130 assertions lulus.

---

## 3. Verification Matrix (Work Packet 24)

| Komponen | Perintah Uji | Kriteria Sukses (DoD) |
| :--- | :--- | :--- |
| **Store Search & ProtonDB** | `./bin/gamectl --preview-search 105600 "Terraria" "[INSTALLED]"` | ANSI card terformat bersih tanpa `-e`, tier ProtonDB valid. |
| **Download Telemetry** | `./bin/gamectl --preview-download 105600 "Terraria" <stage_dir>` | Parsing `status.info`, progres dinamis, live log stream. |
| **CLI Download Status** | `./bin/gamectl download-status` | Mendeteksi unduhan Standalone CDN dan Steam ACF. |
| **Dashboard Modules 1-7** | `./bin/gamectl --preview-dashboard <1..7>` | Metrik storage, store API, logs, dan diagnostics dinamis. |
| **Enriched Previews** | `./bin/gamectl --preview-log`, `--preview-process-log`, `--preview-adopt` | 7-baris context window, error remediation tips, physical detection. |
| **Layer 8 Security** | `./bin/gamectl doctor` | Audit ketersediaan Bubblewrap (`bwrap`) & cgroups v2 scope. |
| **TUI Fix Harvester** | `./bin/gamectl --preview-fix "[RESTORE]" 105600 ...` | ANSI card safety snapshot, Spacewar AppID 480 & DLL overrides. |
| **Deterministic Machine Gate** | `make lint && make test` | 130/130 test assertions lulus dengan Exit Code 0. |

---

# WORK PACKET 25: RUNTIME SAFETY REMEDIATION BEFORE WINDOWS EXPANSION

- Track: Maintenance / Security / Save Integrity / Process Ownership / Failure Reporting
- **Status**: PLANNED [NOT IMPLEMENTED]
- **Reviewed at**: 2026-11-12, source commit `b63062d212f551aba24750175f57c89e58626780`
- **Documentation branch**: `fix/remediation-plan-25`
- **Execution branches**: branch `fix/` terpisah untuk tiap perubahan yang dapat diverifikasi
- **Max Chunks**: 10 pekerjaan aktif; backlog Packet 26 belum diperinci menjadi chunk aktif
- **Scope of this document change**: perencanaan; belum ada perbaikan source runtime

## 1. Baseline, evidence, and boundaries

- Baseline pada salinan commit yang sama: 130/130 tes CLI, 31 tes Rust, dan 3 doctest lulus. `make lint` dan `scripts/build.sh --check` juga lulus. Angka ini bukan bukti kasus kegagalan di bawah sudah tertangani.
- Reproduksi tambahan memakai direktori sementara, worker dummy, fault injection, serta fzf nyata dalam PTY. Tidak memakai save/game pengguna atau target SSH nyata.
- Review preview membuktikan nama direktori dapat menjalankan perintah marker; Pause menghentikan shell tetapi counter worker terus meningkat; parser tetap melaporkan DOWNLOADING setelah error parsial; error fzf 2 menyebabkan loop hingga timeout.
- Reproduksi backup/restore, watchdog game, dan rsync membuktikan kegagalan masih menghasilkan sukses palsu. Review terdahulu juga membuktikan penulisan melalui symlink keluar target dan kehabisan descriptor pada downloader Rust.
- Risiko yang baru ditelusuri dari source, seperti dua penulis yang berbagi staging atau kegagalan rename setelah penghapusan file lama, wajib mendapat reproduksi deterministik sebelum dinyatakan selesai.
- Rujukan tersimpan: [maintenance audit](docs/MAINTENANCE_AUDIT_2026-11-10.md), [verification follow-up](docs/VERIFICATION_2026-11-10.md), dan [TUI lifecycle analysis](docs/ANALYSIS_TUI_LOGS_AND_SCREEN_LIFECYCLE.md). Log `/tmp` dari sesi review hanya bukti tambahan sementara, bukan dependensi pengujian.
- Batas desain tetap mengikuti ADR-022: default standalone tidak memulai Steam/SLSsteam. Pertahankan pilihan eksplisit `--sls` dan kontrak `--raw`; tidak menambah fitur bypass atau mengubah format save tanpa kebutuhan remediasi.
- Tetap gunakan dependensi/pola yang tersedia. Dependency baru, perubahan API lintas modul, atau perubahan arsitektur mendasar memerlukan RFC sesuai aturan proyek sebelum implementasi terkait.
- Kerjakan berurutan pada source modular. Rebuild `bin/gamectl` setelah perubahan Bash; jangan mengedit bundle secara langsung. Jangan menaikkan status packet hanya berdasarkan jumlah tes, mutation score, atau lint.

## 2. Ordered execution map

| Chunk | Priority | Outcome | Depends on |
| :--- | :--- | :--- | :--- |
| 25.01 | P1 | Preview aman dan menu keluar benar ketika fzf gagal | Tidak ada |
| 25.02 | P1 | Snapshot mandiri dan restore dapat dipulihkan saat gagal | Tidak ada |
| 25.03 | P1 | Supervisor game memiliki child dan cleanup-nya | 25.02 |
| 25.04 | P1 | Pause/resume/terminate mengendalikan worker unduhan | 25.01 |
| 25.05 | P2 | Progres memakai byte yang sebanding dan status terminal akurat | 25.04 |
| 25.06 | P1 | Sync meneruskan kegagalan dan TUI menampilkan hasil backend | 25.02, 25.03 |
| 25.07 | P1 | Penulisan Rust tetap dalam root dan tidak menghapus versi lama prematur | Tidak ada |
| 25.08 | P1 | File task dibatasi dan hanya satu penulis per output | 25.07 |
| 25.09 | P1 | Standalone/provisioning/fix mutations gagal secara jujur | 25.02, 25.04, 25.07, 25.08 |
| 25.10 | P2 | Build verifikasi membuktikan artifact berasal dari source yang diuji | 25.01-25.09 |

### [x] Chunk 25.01: Safe preview arguments and bounded fzf failure handling [VERIFIED]

**Target Files**: `src/steam/35_fixes.sh`, `src/steam/30_downloader.sh`, `src/runners/50_launcher.sh`, `src/runners/40_wrappers.sh`, `src/tui/70_dashboard.sh`, `src/main.sh`, `tests/test_cli.sh`. Mulai dari menu fixes; perluas hanya ke call-site yang memiliki pola interpolasi berbahaya yang sama.

**Execution**:
1. Audit seluruh `--preview`/`--bind` yang memasukkan path, title, atau log ke string shell. Pada `manage_game_fixes_interactive`, hentikan interpolasi langsung `'$gdir'`; teruskan data lewat placeholder fzf yang di-escape atau environment per pemanggilan dengan ekspansi terkutip pada command tetap. Lindungi path `SELF_BIN` juga.
2. Pertahankan whitespace dan karakter nama file yang sah. Jangan menghapus apostrof atau metakarakter dari nama agar bug terlihat hilang. Validasi data yang tidak dapat direpresentasikan dalam format baris yang dipakai.
3. Periksa ketersediaan fzf dan terminal pada entrypoint interaktif. Bedakan hasil seleksi, no-match, pembatalan 130, dan error 2/127; error runtime harus keluar nonzero dengan pesan yang terbaca, bukan mengulangi loop kosong.
4. Buat fixture PTY dengan direktori berspasi, apostrof, Unicode, serta metakarakter shell. Eksekusi preview melalui fzf nyata dengan `SHELL=/bin/sh`; gunakan marker sementara untuk mendeteksi eksekusi yang tidak diminta.

**Acceptance / Verification**:
- Marker injeksi tidak terbentuk; preview untuk nama file yang sah tetap menampilkan target yang benar.
- fzf exit 2/127 dan tidak adanya TTY berhenti dalam timeout uji; Esc tetap membatalkan dengan perilaku navigasi semula.
- Tes memeriksa pemanggilan/hasil aktual; assertion keberadaan string `--preview-fix` saja tidak menutup chunk ini. Commit: `fix(tui): safe preview arguments and bounded fzf failure handling`.

### [ ] Chunk 25.02: Independent snapshots and recoverable save replacement

**Target Files**: `src/core/10_utils.sh`, `src/runners/40_wrappers.sh`, `src/runners/50_launcher.sh`, `src/tui/70_dashboard.sh`, `tests/test_cli.sh`.

**Execution**:
1. Perbaiki `backup_save` dahulu: salin ke staging unik pada filesystem snapshot, periksa seluruh operasi, lalu rotasi slot setelah salinan berhasil. Salinan gagal tidak boleh menghapus slot lama atau menghasilkan exit 0.
2. Tetapkan penanganan `saves/` yang berupa symlink. Hasil snapshot harus mandiri dari save aktif; salin konten target yang sudah divalidasi atau tolak sebelum mutasi dengan error eksplisit. Snapshot kosong tetap dapat valid.
3. Stage snapshot restore di filesystem tujuan, validasi sebelum mengganti save aktif, dan pertahankan versi lama sampai commit berhasil. Gunakan nama staging/stash unik dan penguncian per game agar dua mutasi tidak memakai direktori yang sama.
4. Tangani gagal copy, backup, rename, INT/TERM, dan proses mati di antara pemindahan direktori. Dua rename adalah dua langkah; sediakan recovery yang dapat dijalankan ulang ketika save aktif hilang tetapi stash masih ada. Jangan mengklaim seluruh rangkaian atomik.
5. Audit seluruh pemanggil. `pfx clean` dan pull yang menimpa save wajib batal jika backup gagal; `launch_game` membedakan belum ada save dari kegagalan I/O yang sebenarnya. Hubungkan hasil ke TUI.

**Acceptance / Verification**:
- Fault injection pada setiap tahap meninggalkan save aktif atau salinan recovery yang identik; snapshot lama tidak hilang sebelum snapshot baru berhasil.
- Perubahan save aktif tidak mengubah snapshot terdahulu. Uji direktori kosong, dotfile, nama berspasi, symlink, slot invalid, serta dua mutasi bersamaan.
- Pengujian memeriksa isi/hash dan struktur direktori, bukan hanya pesan sukses; semua kegagalan relevan menghasilkan status nonzero.

### [ ] Chunk 25.03: Game supervisor ownership and exactly-once cleanup

**Target Files**: `src/runners/50_launcher.sh`, `src/tui/70_dashboard.sh`, `src/core/10_utils.sh`, `tests/test_cli.sh`.

**Execution**:
1. Tempatkan peluncuran dan `wait` child dalam supervisor yang sama. Hapus sibling-watchdog yang menjalankan `wait "$game_pid"` tanpa memiliki child tersebut.
2. Tentukan satu identitas proses/unit untuk metadata, HUD, stop, dan cleanup. Bila PID supervisor berbeda dari PID worker, simpan dan gunakan keduanya sesuai peran; jangan menganggap `$!` selalu PID game.
3. Pertahankan exit status child. Teruskan sinyal ke proses milik game, tunggu penghentian dengan batas waktu, dan lakukan cleanup tepat sekali setelah lifecycle berakhir. Jangan membunuh wineserver/global process milik game lain.
4. Pisahkan trap supervisor dari trap terminal TUI. Pulihkan state yang benar-benar diubah dan pertahankan alternate-screen cleanup. Tolak restore/pull yang menimpa save ketika game terkait masih tercatat aktif.

**Acceptance / Verification**:
- Worker dummy hidup cukup lama; metadata tetap ada selama worker hidup dan dibersihkan setelah exit, termasuk exit nonzero yang sudah ditentukan fixture.
- Stop/terminate membersihkan child milik game; game dummy kedua tetap berjalan. Tidak ada error wait 127 atau cleanup prematur.
- PTY menguji kembali ke library, Esc, Ctrl-C, dan peluncuran gagal; terminal serta trap TUI tetap berfungsi.

### [ ] Chunk 25.04: Download worker ownership, signals, and staging lifecycle

**Target Files**: `src/steam/30_downloader.sh`, `src/core/10_utils.sh`, `src/main.sh`, `tests/test_cli.sh`.

**Execution**:
1. Ganti metadata PID shell yang sekarang berasal dari `BASHPID` dengan identitas worker/supervisor yang benar. Tentukan kepemilikan pipeline downloader dan tee; pertahankan status exit keduanya agar kegagalan log tidak tersembunyi.
2. Semua tombol dan CLI pause/resume/terminate memakai identitas yang sama dan memvalidasi proses masih milik job tersebut. PID hidup saja tidak membuktikan kepemilikan; cegah salah target akibat PID reuse.
3. SIGSTOP harus menghentikan pekerjaan worker; SIGCONT melanjutkannya. Terminate menunggu worker dan child miliknya berhenti sebelum membersihkan staging.
4. Pisahkan pembersihan staging manifest dari retensi ringkasan/log hasil. Monitor status tidak boleh menghapus staging milik worker hidup hanya karena shell pengendali berakhir. Validasi ulang cleanup `RETURN` dan `clean_stale_locks`.

**Acceptance / Verification**:
- Pada worker counter dummy, Pause menghentikan pertambahan counter dan Resume melanjutkannya; membekukan shell sementara worker menulis dianggap gagal.
- Setelah Terminate, tidak ada worker/tee milik job yang hidup atau menulis lagi; job kedua tidak terganggu dan tidak ikut dipurge.
- Metadata hasil gagal/sukses dapat dibaca setelah worker selesai sesuai retensi yang ditetapkan; cleanup idempoten setelah interupsi.

### [ ] Chunk 25.05: Consistent progress units and truthful terminal states

**Target Files**: `crates/depot-dl/src/bin/gamectl-depot-dl.rs`, `src/steam/30_downloader.sh`, `tests/test_cli.sh`. Gunakan `ProgressEvent` yang sudah tersedia; perubahan kontrak event publik harus diperlakukan sebagai perubahan interface tersendiri.

**Execution**:
1. Gunakan byte pekerjaan selesai dan byte target dengan satuan sama, termasuk chunk/file yang dipakai ulang. Jangan membagi byte jaringan terkompresi dengan ukuran file hasil ekstraksi.
2. Keluarkan telemetry terstruktur dengan laju terbatas dari event yang ada. Jika total lintas depot belum diketahui, tampilkan progress per depot dengan label jelas; jangan menyajikannya sebagai persentase keseluruhan.
3. Satukan pembacaan di `get_depot_dl_progress`, `preview_download`, `list_downloads`, dan monitor interaktif. Status FAILED/CANCELLED berasal dari hasil worker/metadata yang otoritatif, termasuk error setelah transfer parsial dan pesan FATAL/DEPOT_FAILED.
4. Tetapkan prioritas status terminal di atas inferensi angka log. Penyelesaian byte unduhan berbeda dari keberhasilan seluruh provisioning; integrasikan status akhir dengan Chunk 25.09.
5. Periksa refresh monitor/preview saat pengguna tidak berpindah pilihan. Pertahankan format CLI yang masih dipakai konsumen atau dokumentasikan migrasinya; tandai fixture lama yang mengunci perilaku salah untuk koreksi berdasarkan bukti kontrak, tanpa melemahkan pengujian.

**Acceptance / Verification**:
- Fixture unduhan baru dengan 60 MB selesai dari target 100 MB menampilkan 60% meski transfer jaringan 45 MB; uji reuse, file kosong, serta beberapa depot.
- Error setelah progress menghasilkan FAILED; sukses terdahulu tidak menutupi error berikutnya, dan PID mati tidak otomatis berarti sukses.
- Uji menggunakan keluaran Rust yang sebenarnya dan fixture terkontrol; UI/status berubah saat telemetry diperbarui tanpa memerlukan seleksi ulang.

### [ ] Chunk 25.06: Remote sync error propagation and actionable TUI results

**Target Files**: `src/runners/50_launcher.sh`, `src/tui/70_dashboard.sh`, `src/core/10_utils.sh`, `tests/test_cli.sh`.

**Execution**:
1. Periksa status SSH connectivity, mkdir/check direktori remote, backup, dan rsync pada push/pull. Pertahankan kode kegagalan asli atau catat pemetaannya dengan jelas; jangan meneruskan pesan VERIFIED setelah error.
2. Resolusikan HOME pada sisi remote dengan escaping argumen yang benar. Perbaikan tilde tidak boleh menghilangkan perlindungan path yang mengandung spasi, apostrof, dollar, atau metakarakter.
3. Dry-run tidak membuat direktori save/snapshot, menulis konfigurasi, atau menjalankan mutasi remote. Bandingkan tree game sebelum/sesudah, termasuk kondisi belum ada `saves/`.
4. Route aksi backend library/search melalui penanganan hasil yang konsisten: simpan stdout/stderr, pertahankan exit status, tampilkan hasil sampai pengguna menutupnya, lalu kembali ke menu. Audit pemanggil backup, sync, inject, download, dan fixes yang sekarang mengumumkan sukses tanpa memeriksa hasil.

**Acceptance / Verification**:
- rsync exit 23, remote mkdir gagal, host tidak terjangkau, serta backup gagal menghasilkan nonzero dan tidak menimpa save tanpa recovery.
- Fake remote menjalankan dan memeriksa command/path yang sebenarnya; mock SSH yang selalu return 0 saja tidak memadai. Tree save tidak berubah saat dry-run.
- PTY menunjukkan modal error berisi penyebab kegagalan, output tidak bocor ke layar dashboard, dan terminal pulih pada sukses/gagal/interupsi.

### [ ] Chunk 25.07: Root-confined Rust filesystem operations and safe file commit

**Target Files**: `crates/depot-dl/src/util.rs`, `crates/depot-dl/src/download.rs`, `crates/depot-dl/src/state.rs`. Tes Rust ditempatkan pada modul terkait.

**Execution**:
1. Ikat output ke root filesystem yang sudah diresolusikan. Root library yang sengaja berupa alias/symlink tetap dapat bekerja, tetapi parent/file di bawahnya tidak boleh mengarahkan penulisan keluar root.
2. Audit create directory, open/truncate, reuse, staging, rename, dan metadata state. Pemeriksaan string path atau canonicalize sekali tidak melindungi perubahan symlink antara pemeriksaan dan open; pilih strategi I/O yang menjaga boundary selama operasi. RFC diperlukan jika strategi menuntut dependency/unsafe baru.
3. Hilangkan urutan `remove_file(final_path)` sebelum `rename(staging, final_path)`. Pertahankan file lama sampai replacement berhasil pada filesystem yang sama, dan tangani file terkunci/permission failure tanpa mengumumkan sukses.
4. Audit normalisasi path yang membuat beberapa nama berbeda menjadi target sama. Tolak nama ambigu/tidak aman dengan error yang menyebut entry, bukan menimpa file lain secara diam-diam.

**Acceptance / Verification**:
- Manifest dengan parent symlink ke direktori eksternal tidak mengubah file eksternal; uji root alias yang sah serta perubahan parent selama operasi.
- Simulasikan staging hilang, rename gagal, dan target tidak dapat ditulis. File lama tetap tersedia dan state depot tidak ditandai selesai.
- Tes memakai filesystem/tempdir nyata dan hash isi. Keberhasilan tes `safe_relative_path` saja belum menutup boundary I/O.

### [ ] Chunk 25.08: Bounded file work and exclusive ownership of output state

**Target Files**: `crates/depot-dl/src/download.rs`, `crates/depot-dl/src/state.rs`, `crates/depot-dl/src/config.rs`. Pertahankan MSRV yang dinyatakan dalam `Cargo.toml`.

**Execution**:
1. Batasi file task sebelum membuka handle; semaphore jaringan yang ada tidak membatasi seluruh handle file. Gunakan mekanisme futures/concurrency yang sudah tersedia dan hindari opsi tuning baru jika batas yang ada mencukupi.
2. Ambil kepemilikan eksklusif per output sebelum load/update state atau `clear_staging`. Dua caller library maupun dua proses CLI harus memakai aturan yang sama; lock pada wrapper Bash saja tidak melindungi API Rust.
3. Tangani pelepasan lock dan penutupan handle saat sukses, error, cancel, atau crash. Kepemilikan yang tidak dapat dibuktikan harus gagal aman; jangan menghapus lock/staging milik proses hidup hanya berdasarkan tebakan PID.
4. Buat harness subprocess dengan RLIMIT_NOFILE rendah. Batas resource diterapkan pada worker uji, bukan runner yang menjalankan tes lain.

**Acceptance / Verification**:
- Fixture minimal 256 file, batas 64 descriptor, dan concurrency yang didukung selesai tanpa EMFILE. Handle tidak bertambah terus setelah cancel/retry.
- Dua penulis pada output sama ditolak/diatur secara eksplisit tanpa menghapus staging penulis pertama; output berbeda tetap independen.
- Kill/crash worker diikuti recovery yang teruji; `depots.json`, manifest cache, dan file final tidak mengumumkan transaksi yang belum selesai.

### [ ] Chunk 25.09: Strict standalone and checked provisioning/fix mutations

**Target Files**: `src/steam/30_downloader.sh`, `src/steam/35_fixes.sh`, `src/runners/50_launcher.sh`, `tests/test_cli.sh`.

**Execution**:
1. Samakan default dengan mode standalone ketat. Helper/key/manifest yang hilang menghasilkan error yang dapat ditindaklanjuti; Steam/SLS hanya dipanggil melalui pilihan eksplisit yang masih didukung.
2. Periksa hasil tahap provisioning yang diminta. `--raw` tetap hanya mengunduh; operasi yang meminta provisioning tidak boleh melaporkan COMPLETED jika tahap wajibnya gagal. Simpan log dan status akhir untuk monitor.
3. Pada install/revert fix, validasi daftar path dan backup sebelum menimpa/menghapus file. Gunakan staging/snapshot unik; hentikan dan pulihkan bila copy, extraction, atau restore gagal. Lindungi dari dua operasi patch pada game yang sama.
4. Pastikan pemanggil TUI dari Chunk 25.06 menggunakan status backend sebenarnya. Pertahankan error/validasi yang ada saat merapikan percabangan; jangan melemahkan guard atau deteksi kegagalan agar alur terlihat sukses.

**Acceptance / Verification**:
- Hilangkan helper/key pada fixture default: exit nonzero dan jumlah panggilan stub Steam/SLS tetap nol. Pilihan eksplisit dan `--raw` tetap mengikuti kontraknya.
- Fault injection provisioning, backup fix, extraction, dan revert menghasilkan status gagal yang terlihat; file asli/recovery tetap tersedia.
- Uji lifecycle download sampai provisioning serta install sampai revert dengan isi file nyata di tempdir, tanpa akun/token atau game pengguna.

### [ ] Chunk 25.10: Source-verified build harness and regression checkpoints

**Target Files**: `scripts/build-depot-dl.sh`, `Makefile`, `.github/workflows/ci.yml`, `tests/test_cli.sh`.

**Execution**:
1. Bedakan pemeriksaan ketersediaan executable dari verifikasi source/artifact. Pertahankan `--check` sebagai pemeriksaan availability yang diberi label jelas; gate freshness menjalankan build Cargo dengan lockfile. Gunakan `--force` yang sudah tersedia untuk menolak fallback pada jalur verifikasi dan perbarui pemanggil terkait.
2. Build verifikasi memakai `cargo build --locked` dan gagal nonzero ketika compiler gagal atau artifact tidak ditemukan, meski binary lama tersedia. `make build` tidak boleh melewatkan build native hanya karena executable lama tersedia; incremental build Cargo dapat menangani source yang tidak berubah. Binary lama boleh dipertahankan di disk saat gagal, tetapi hasil build tetap gagal.
3. Verifikasi native helper sebelum menjadikan bundle/paket sebagai hasil final; sinkronkan urutan `make build` agar Python copy tidak memakai helper lama. Bila perlu menyentuh `scripts/build.sh`, jadikan bagian integrasi build yang sama dan verifikasi seluruh konsumennya.
4. Hubungkan regresi failure-path ke CI. Jalankan suite pada source/artifact commit yang sama, cek jumlah tes benar-benar dieksekusi dan tidak dilewati, lalu review diff serta checkpoint lokal per chunk. Pengujian live HTTP tetap diberi label integrasi.

**Acceptance / Verification**:
- Crate invalid dengan binary lama menghasilkan build nonzero; executable placeholder tidak lolos sebagai artifact terverifikasi.
- Perubahan source Rust yang disengaja tidak lolos sebagai artifact fresh hanya karena binary lama masih executable; helper hasil build yang diuji dapat diidentifikasi.
- Semua kasus Chunk 25.01-25.09 dieksekusi, gate Bash/Rust lulus untuk fitur yang dinyatakan didukung, dan bundle sesuai source. Jumlah tes lebih tinggi saja tidak menutup packet.

## 3. Checkpoints and definition of done

1. Setelah Chunk 25.01-25.04: ulangi reproduksi preview melalui fzf nyata, kegagalan save, lifecycle game, dan pause worker. Marker tidak boleh tercipta; counter worker harus berhenti saat Pause.
2. Setelah Chunk 25.05-25.08: jalankan uji status/progress, fake SSH/rsync, PTY failure/cancel, symlink boundary, RLIMIT, dan dua penulis. Simpan output serta exit code dengan source commit terkait.
3. Setelah Chunk 25.09-25.10: jalankan lifecycle provisioning/fix lengkap pada fixture, build dengan compiler gagal, seluruh regresi, dan review artifact. Jangan menandai langkah implementasi selesai hanya karena dokumen ini telah ditambahkan.

Commands baseline, ditambah kasus baru pada setiap chunk:

```bash
make lint
./scripts/build.sh --check
./tests/test_cli.sh
cargo test --locked --manifest-path crates/depot-dl/Cargo.toml
git diff --check
```

- Perubahan Bash harus dibundle ulang sebelum gate sinkronisasi. Build yang dapat menulis artifact atau tes yang dapat menyentuh HOME dijalankan pada salinan/lingkungan sementara yang sesuai.
- Assertion lama tidak boleh dilemahkan atau dihapus untuk mendapatkan exit 0. Jika fixture merekam kontrak yang memang salah, catat bukti dan keputusan koreksinya; tambahkan pengujian perilaku yang membuktikan hasil benar sebelum mengubah ekspektasi terkait.
- Saat tes memakai mock/fault injection, nyatakan batasnya. Keberhasilan child ownership dan preview shell memerlukan pengujian proses/PTY nyata; tidak cukup memeriksa nama fungsi atau teks source.
- Completion Packet 25 berarti kegagalan runtime yang dicakup sudah ditutup dengan bukti. Ini belum sertifikasi gameplay, semua paket distribusi, atau Windows.
- Tandai chunk selesai hanya dengan commit, nama kasus uji, hasil/exit code, dan batas verifikasi. Semua item di atas dimulai terbuka.

## 4. Packet 26 backlog and Windows release gate

Backlog ini tetap terbuka dan belum menjadi pekerjaan aktif tambahan. Perinci packet berikutnya setelah hasil Packet 25 direview:

- **Distribution/platform artifacts**: arsitektur nyata pada Debian/Arch/wheel; dependency runtime termasuk zip; Nix/helper availability; build helper sebelum wheel/release packaging; installed-package smoke test dalam PATH/HOME terisolasi; baseline libc dan checksum artifact yang sesuai.
- **Dependency advisories**: periksa ulang Cargo.lock, fitur, call-path, dan advisory primer yang masih berlaku; pilih pembaruan kompatibel secara terpisah dan uji ulang TLS/parser/dekompresi. Daftar hasil scanner bukan jumlah eksploit yang sudah dibuktikan.
- **Rust advertised quality/features**: tutup lint/format yang masih gagal dan kontrak feature fixtures yang merujuk file hilang. Gunakan fixture sintetis yang disengaja atau workflow opsional yang jelas; skip otomatis tidak boleh menyamarkan feature yang gagal dikompilasi.
- **Distribution licensing**: selaraskan metadata dan materi lisensi root/paket dengan crate downloader yang menyatakan GPL-2.0-only; catat hasil review sebelum publikasi artifact.
- **Hardware and real integrations**: uji game yang diizinkan, save/exit nyata, GPU/Proton, remote sync yang diizinkan, serta Steam Deck jika perangkat tersedia; pisahkan hasil desktop dari hasil perangkat lain.
- **Windows pilot**: perbarui RFC Windows agar memakai Rust helper terkini dan capability yang benar; validasi build/runtime Windows native serta kontrak data/CLI. Implementasi Windows dan rilis menunggu gate keamanan/data serta kesiapan artifact yang relevan.

Menutup Packet 24 atau menambah centang pada Packet 25 tidak otomatis menutup backlog ini. Tidak ada perubahan produksi, push, publikasi paket, atau upgrade dependency yang dijalankan oleh pembaruan rencana ini.

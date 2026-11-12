# Review task selesai Packet 25

Review terhadap baseline `27f5a718e36177b37a761575d041125fa132f256`, pada
branch lokal `fix/review-completed-25`, tanggal 2026-11-12.
Perbaikan source, bundle, dan regresi tersimpan pada commit lokal `c029a7a`.

## Ruang lingkup dan hasil

gamectl memakai source Bash modular yang dibundle menjadi `bin/gamectl`, fzf
untuk TUI, crate Rust `depot-dl` untuk downloader, dan runner Python untuk
distribusi. Source Bash adalah sumber perubahan; bundle dibangun ulang.

`PLAN.md` hanya mencentang 25.01 dan 25.02 saat review dimulai. Ringkasan masih
menyebut 25.01 saja dan commit review lama. Kedua chunk dibuka kembali karena
sebagian acceptance criteria belum terpenuhi. Chunk 25.03-25.10 serta backlog
Packet 26 tetap terbuka; audit ini tidak mengimplementasikan seluruh backlog.

## Temuan dan perbaikan

| Prioritas | Temuan pada baseline | Perubahan review |
| --- | --- | --- |
| P1 | `backup_save` mengabaikan kegagalan rename dan dapat mengembalikan 0 sesudah slot lama hilang/bergeser. | Simpan slot tertua dalam staging sampai commit, periksa setiap rename, dan balik urutan perpindahan jika gagal. |
| P1 | `restore_save` menghapus stash recovery lama sebelum perpindahan save aktif berhasil. | Simpan stash terdahulu dalam staging unik sampai replacement berhasil; rollback memulihkan save dan stash sebelumnya. |
| P1 | Recovery restore berjalan sebelum lock; caller yang gagal memperoleh lock sudah sempat memindahkan save. | Recovery hanya berjalan setelah kepemilikan lock diperoleh dan kegagalannya diteruskan. |
| P1 | Trap INT/TERM di fungsi save menimpa lalu menghapus trap caller; TERM hanya melepas lock dan operasi dapat berlanjut. Nama path juga disisipkan ke source trap. | Isolasi fungsi dalam subshell, gunakan trap tetap yang membaca variabel terkutip, exit nonzero pada sinyal, dan lakukan cleanup/rollback melalui EXIT. |
| P1 | PID lock memakai `$$` milik shell induk; takeover lock berdasarkan tebakan PID berisiko merampas lock caller lain. | Rekam `BASHPID` pemilik aktual; jangan menghapus lock gagal secara otomatis. Bila rollback gagal, pertahankan lock serta seluruh recovery. Backup quiet menolak save hilang dengan recovery tertunda. |
| P2 | Tes PTY preview menelan seluruh error, menunggu 0,5 detik tanpa membaca layar, kemudian mematikan proses. Ketiadaan marker bisa berarti preview tidak pernah berjalan. | Harness PTY menunggu teks metadata dari preview nyata, memeriksa exit Esc, dan menguji error fzf 2/127 dengan timeout. Cache lokal menghindari ketergantungan katalog jaringan untuk kasus ini. |

Tidak ada perubahan signature publik, dependency baru, autentikasi, CI,
provisioning game, remote save, atau konfigurasi produksi.

## Bukti pengujian

- Baseline di salinan sementara dengan HOME/cache/runtime terpisah: 133/133
  kontrak CLI lulus. Artinya suite lama belum mendeteksi failure-path ini.
- Sebelum perbaikan, tujuh metode regresi save awal menghasilkan sembilan
  kegagalan assertion dan dua error pemeriksaan isi file. Pemeriksaan tersebut
  menunjukkan return 0 yang salah, snapshot hilang, recovery sebelum lock,
  trap berubah, serta TERM yang tetap melanjutkan commit.
- `python3 tests/test_save_safety.py`: sepuluh metode, termasuk fault injection
  pada empat rename backup dan tiga rename restore, copy gagal, rollback gagal,
  TERM, trap caller, symlink save eksternal, dan dua proses penulis nyata.
  Pemeriksaan memakai isi file, status exit, PID lock, dan berkas recovery.
- `python3 tests/test_tui_safety.py`: dua metode; preview memakai fzf nyata dalam
  PTY dengan `SHELL=/bin/sh`, path game dan binary mengandung karakter shell,
  lalu Esc keluar 0. Delapan kombinasi empat menu dan exit 2/127 juga diuji.
- Kedua harness terhubung ke `tests/test_cli.sh`; kegagalannya membuat suite
  gagal. Tidak ada skip otomatis atau penghapusan assertion lama.
- Suite CLI setelah perbaikan lulus 134/134 kontrak (exit 0), dijalankan pada
  salinan sementara dengan HOME/cache/runtime terpisah. Sepuluh metode save dan
  dua metode PTY di atas termasuk di dalam suite tersebut, bukan jumlah kontrak
  CLI tambahan. Perubahan akhir payload path juga lulus uji PTY terpisah.
- `make lint`, `./scripts/build.sh --check`, dan `git diff --check` lulus dengan
  exit 0. Bundle dan salinan untuk runner Python dibangun ulang memakai
  `./scripts/build.sh`; ini tidak menyatakan helper native telah dibuild ulang.
- Rust baseline: `cargo test --locked --manifest-path crates/depot-dl/Cargo.toml`
  lulus: 31 unit test library dan tiga doctest; target binary tidak memiliki
  unit test. Tidak ada perubahan source Rust dalam review ini.

## Batas verifikasi dan pekerjaan tersisa

Pada audit `9d2a682`, 25.01 belum selesai penuh. Scanner menulis field title/path langsung ke format
TAB/newline (`src/steam/20_discovery.sh`), sedangkan fzf membacanya sebagai
pemisah. Validasi nama yang tidak dapat direpresentasikan belum tersedia.
Submenu search action/package juga masih memetakan semua kegagalan fzf menjadi
pilihan Cancel (`src/tui/70_dashboard.sh`); propagasi error bertingkat perlu
ditutup dengan pengujian sendiri. Hasil delapan kombinasi entrypoint tidak
mensertifikasi seluruh menu. Temuan 25.01 ini ditutup pada follow-up di bawah.

25.02 belum selesai penuh. Rename per langkah pada filesystem lokal bukan
transaksi tahan crash. SIGKILL/mati daya dapat meninggalkan slot yang bergeser,
save aktif yang sementara hilang, lock, atau staging; belum ada jurnal recovery
durabel maupun pengujian power-loss. Lock sengaja gagal tertutup sampai owner
dan isi recovery diperiksa. Jangan menghapus staging/lock sisa tanpa memeriksa
proses pemilik dan membandingkan save yang tersimpan. Jika rollback sendiri
gagal, pesan error menyebut direktori recovery; file tersebut dipertahankan.

Restore mempertahankan stash terakhir di `.save_snapshots/.pre_restore_stash`.
Backup yang belum commit menyimpan slot tertua di `.stage_backup.*/slot3`;
restore yang belum commit dapat menyimpan stash terdahulu di
`.save_restore_stage.*/previous_stash`. Semua lokasi ini harus diperiksa sebelum
recovery manual. Tidak ada klaim fsync, atomicity lintas filesystem, atau
perlindungan terhadap proses lain yang mengubah symlink/direktori tanpa lock.

Proteksi save saat game aktif masih terkait Chunk 25.03. Supervisor game,
pause/terminate downloader, progress, remote sync, root confinement Rust,
resource limits, provisioning, dan source freshness build tetap mengikuti
urutan backlog yang sudah ada. Pengujian game/GPU, Steam Deck, SSH nyata,
Windows, dan publikasi paket tidak dilakukan. Tes lokal tidak membuktikan
kesiapan produksi atau gameplay.

## Follow-up Chunk 25.01 completed

Implementasi `46301b4`, branch lokal `fix/chunk-25-01-complete`, 2026-11-12.
Hanya Chunk 25.01 ditutup; sembilan chunk 25.02-25.10 tetap terbuka.

- Scanner memvalidasi path/title/executable sebelum menyimpan baris. Judul
  metadata multiline dan nama executable yang mengandung pemisah ditolak dengan
  pesan error. Cache versi lama tidak dipakai ulang. Formatter memakai `%s`
  sehingga nama seperti `Player's 測試 \\t game` tidak berubah menjadi field baru.
- Katalog Store/adoption divalidasi sebelum konversi TSV; katalog fixes
  divalidasi sebelum baris dikirim ke fzf. Backslash literal tidak diinterpretasi
  sebagai escape saat menyusun menu fixes, unduhan, dan custom library.
- Error fzf pada settings, wrappers, persona, action/package, download actions,
  adoption bridge, restore picker, diagnostics, HUD log, dan modal diteruskan
  hingga pemanggil. Kesalahan 2/127 tidak disamarkan sebagai Cancel. Menu yang
  memerlukan TTY/fzf gagal segera jika syarat tersebut tidak tersedia.
- Kontrak pembatalan yang sudah ada dipertahankan, termasuk Esc menyimpan
  konfigurasi wrappers. Backend provisioning/save/process ownership tidak
  diubah menjadi implementasi chunk lain.

Regresi sebelum perbaikan membuktikan field scanner terpecah oleh TAB dan
backslash escape, serta dashboard mengembalikan 0 setelah settings gagal.
Setelah perbaikan, seluruh assertion lama tetap dipertahankan; parser ACF
tetap dapat di-source sendiri dan validasi direktori persona tetap bekerja.

Verifikasi pada source/bundle `46301b4`, seluruhnya exit 0:

| Gate | Hasil |
| --- | --- |
| `./tests/test_cli.sh` di salinan dengan HOME/cache/runtime sementara | 134/134 kontrak; tidak ada skip |
| Harness TUI yang dipanggil suite CLI | 12 metode; 60 kombinasi submenu 2/127, validasi data, cache lama, missing fzf/TTY, no-match/cancel |
| Preview fzf nyata dalam PTY, `SHELL=/bin/sh` | Fixes dengan path executable khusus, prefix, HUD/log; preview benar-benar tampil, marker tidak terbentuk, Esc keluar 0 |
| `cargo test --locked --manifest-path crates/depot-dl/Cargo.toml` | 31 unit test library + 3 doctest; source Rust tidak berubah |
| `make lint`, `./scripts/build.sh --check`, `git diff --check` | Lulus; bundle dibangun ulang dari source modular |

Fault injection submenu memakai executable fzf pengganti dengan urutan pilihan
dan status yang dikendalikan. Setiap kasus memeriksa status akhir, jumlah
pemanggilan, dan tidak adanya mutasi persona setelah error. API katalog memakai
fixture lokal; preview dan terminal memakai fzf/PTY nyata. Tes ini tidak
mensertifikasi gameplay, GPU, SSH nyata, Steam Deck, Windows, atau recovery
SIGKILL/mati daya. Backlog dan batas 25.02 di atas tetap berlaku.

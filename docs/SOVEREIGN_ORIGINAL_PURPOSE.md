# PIAGAM DASAR & TUJUAN ASLI GAMECTL (SOVEREIGN ORIGINAL PURPOSE)

- **Dokumen**: `SOVEREIGN_ORIGINAL_PURPOSE.md`
- **Klasifikasi**: Prinsip Inti & Batasan Arsitektur Proyek (Single Source of Truth)
- **Status**: DISAHKAN (RATIFIED)
- **Penetapan Pengguna (2026-11-13)**: *"pengganti steam dengan keunggulan ringan, standalone, stabil jangka panjang"*.

Tujuan ini mengatur setiap perubahan kode, diagnostik, dokumentasi, dan memori AI.
Arahan lama tentang SLSsteam sebagai engine, fallback, atau syarat kesiapan tidak berlaku untuk alur mandiri.
Mengadopsi cara kerja sebuah tool tidak berarti memasang atau bergantung pada aplikasi tersebut.

---

## 1. DEFINISI & IDENTITAS PROYEK

**`gamectl`** adalah pengganti Steam untuk pengelolaan, pengunduhan, dan peluncuran game yang didukung: ringan, mandiri, dan dirancang agar dapat dipelihara jangka panjang.

### Filosofi Utama: "Zero Bloat, Maximum Sovereignty"
1. **Ringan**: Gunakan runtime kecil dan dependensi yang memang diperlukan. Angka RAM dan startup harus disertai hasil pengukuran; target performa bukan bukti performa aktual.
2. **Sovereign (Berdaulat)**: Kepemilikan aset dan runtime sepenuhnya berada di tangan pengguna secara lokal. Tidak ada ketergantungan wajib pada server cloud pihak ketiga, akun login tertutup, maupun aplikasi klien desktop yang menyita memori (seperti Steam Client resmi ~1 GB RAM).
3. **Decoupled Architecture**: Komponen download, manajemen lisensi, dan runtime peluncur beroperasi secara modular dan independen satu sama lain.
4. **Stabil Jangka Panjang**: Alur mandiri tidak boleh bergantung pada hook atau pola memori internal Steam Client. Kegagalan provider, template, penulisan file, dan proses harus dilaporkan dengan benar; pemulihan harus menjaga data pengguna. Klaim stabil memerlukan bukti skenario kegagalan dan pengujian runtime yang relevan.

---

## 2. TIGA PILAR TUJUAN ASLI (CORE CAPABILITIES)

```text
+-----------------------------------------------------------------------------------+
|                           GAMECTL SOVEREIGN TRI-PILLAR                            |
+-----------------------------------------------------------------------------------+
        ▲                                     ▲                               ▲
        │                                     │                               │
        ▼                                     ▼                               ▼
+-----------------------+           +-----------------------+       +-----------------------+
|  PILAR 1: GAME MNGR   |           |  PILAR 2: STEAM TOOLS |       |  PILAR 3: OFFLINE RUN |
|  (Sovereign Cockpit)  |           |  (Search & Harvest)   |       |  (Zero Client Play)   |
|-----------------------|           |-----------------------|       |-----------------------|
| • POSIX Bash + fzf+jq |           | • Cari game via API   |       | • Main tanpa Steam    |
| • Runtime ringan     |           | • Unduh Valve CDN     |       | • Goldberg Emulator   |
| • Multi-Dir Discovery |           | • Full DLC Included   |       | • Full DLC Unlocked   |
| • 3-Slot Save Snap    |           | • Ephemeral Rust DL   |       | • Savegame di ./saves |
| • cgroups v2 Scope    |           | • Zero Client needed  |       | • "Sebisanya" DRM Fix |
+-----------------------+           +-----------------------+       +-----------------------+
```

---

### PILAR 1: PENGELOLA GAME BERDAULAT (SOVEREIGN GAME MANAGER)
- Mengelola koleksi game lintas direktori secara otomatis: direktori mandiri (`~/Games/`), direktori Steam library (`steamapps/common/`), partisi sekunder, hingga mount eksternal.
- Menyediakan inspeksi real-time arsitektur biner (ELF 32/64-bit, PE32/PE32+), runner Proton/Wine, profil wrapper (GameMode, MangoHud, Gamescope FSR), dan ukuran savegame.
- Melindungi data permainan melalui pencadangan snapshot 3-slot (`.save_snapshots/slot1..3`) otomatis sebelum setiap game diluncurkan.
- Isolasi proses penuh menggunakan `cgroups v2` (`systemd-run --user --scope`), menjamin pembersihan tuntas proses latar belakang (winedevice, crash helper) saat game ditutup tanpa meninggalkan proses zombie.

---

### PILAR 2: ALTERNATIF TOOLS STEAM POPULER (SEARCH & HARVEST FULL DLC)
Sebagai alternatif dari perkakas populer (seperti SteamTools, LuaTools, GreenLuma, DepotDownloader), `gamectl` menyediakan jalur lengkap:

1. **Pencarian Katalog Langsung (`gamectl search <query>` / TUI `Ctrl-F`)**:
   - Menelusuri katalog toko Steam Store API secara instan.
   - Menampilkan preview metadata platform (Linux Native vs Windows) dan rating komunitas ProtonDB (Platinum/Gold/Silver/Borked).
2. **Download Mandiri Langsung dari Valve CDN (`gamectl download <appid>`)**:
   - Memanen manifest biner dan kunci enkripsi AES-256 dari jaringan penyedia multi-provider (Ryuu, Sushi, LuaTools).
   - Menjalankan downloader mandiri berkinerja tinggi berbasis native Rust (`gamectl-depot-dl`) yang langsung mengunduh chunk dari edge CDN Valve (`cache*-*.steamcontent.com`).
   - Melakukan dekripsi in-flight via instruksi hardware AES-NI dan dekompresi zstd/lzma langsung ke disk.
3. **Penyertaan Seluruh DLC (Full DLC Included)**:
   - Mengunduh depot game dasar sekaligus seluruh depot DLC terkait yang terdaftar pada manifest.
   - Laporkan depot yang tersedia dan yang gagal; jangan menjanjikan seluruh DLC tersedia tanpa verifikasi manifest dan hasil unduhan.
4. **Zero-Client Download Invariant**:
   - Seluruh proses pencarian dan pengunduhan berjalan tanpa membuka aplikasi resmi Steam Client.
   - Tidak memakan 1 GB RAM untuk Chromium subprocess (`steamwebhelper`), optimal untuk perangkat dengan sumber daya terbatas dan mesin headless.

---

### PILAR 3: DAPAT DIMAINKAN SECARA OFFLINE "SEBISANYA" (STANDALONE RUNTIME)
Tujuan akhir adalah kebebasan memainkan game tanpa ketergantungan runtime:

1. **Entitlement Emulator Mandiri (Goldberg / GBE Fork)**:
   - Sesaat setelah unduhan selesai (atau melalui pre-flight guard saat game di-Enter di library), `gamectl` otomatis menyuntikkan Goldberg Steam Emulator:
     - Menggantikan pustaka resmi Valve (`steam_api.dll`, `steam_api64.dll`, `libsteam_api.so`) dengan pustaka emulator GBE Fork.
     - Menyediakan file identitas `steam_appid.txt` dan mapping seluruh DLC di `steam_settings/DLC.txt`.
     - Mengalihkan penyimpanan savegame lokal ke `<game_dir>/saves/`.
2. **Klausul Batasan Realitas ("Sebisanya")**:
   - **Kompatibilitas per Game**: Kemampuan berjalan offline harus dibuktikan pada game yang diuji. Tidak ada jaminan persentase katalog atau klaim semua game dapat berjalan mandiri.
   - **Game Ber-DRM Keras / SteamStub**:
     - Windows PE: Di-bypass menggunakan Steamless CLI.
     - Linux ELF ber-seksi `.bind`: Dideteksi secara forensik, diberikan diagnostik transparan ke pengguna, dan diarahkan ke runner yang tepat.
   - **Batas Integrasi Eksternal**: Perintah bridge yang dipertahankan untuk kompatibilitas hanya boleh berjalan atas pilihan eksplisit. Keberadaannya tidak mengubah tujuan produk, tidak membenarkan pemasangan Steam/SLSsteam, dan bukan solusi untuk kegagalan jalur mandiri.

---

## 3. ANTI-POLA & PANTANGAN MUTLAK (INVARIANTS)
1. **Dilarang Menjadikan SLSsteam Sebagai Ketergantungan Default**: SLSsteam adalah parasit proses Steam Client. Menghubungkan game standalone ke SLSsteam saat Steam Client mati adalah blunder arsitektur.
2. **Dilarang Membiarkan Biner Game Tanpa Emulator**: Mengeksekusi biner game yang memiliki dependensi `steam_api` resmi Valve tanpa di-shim GBE Fork akan memicu panggilan paksa ke Steam Client.
3. **Dilarang Memaksa Direktori Steam Sebagai Lokasi Tunggal**: Game standalone harus bebas diletakkan di direktori sovereign manapun (`~/Games/`, drive eksternal, dll).
4. **Dilarang Mengabaikan Kondisi Offline**: Gunakan data lokal yang tersedia. Bila data yang diperlukan belum ada, laporkan batasannya; jangan menghidupkan Steam atau mengklaim sukses palsu.
5. **Dilarang Menyamakan Tes Lokal dengan Kesiapan Runtime**: Catat apa yang diuji dan yang belum. Dokumen historis, status ADR lama, dan tes mock tidak mengesampingkan tujuan pengguna atau bukti source saat ini.

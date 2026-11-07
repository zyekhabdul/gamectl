# PIAGAM DASAR & TUJUAN ASLI GAMECTL (SOVEREIGN ORIGINAL PURPOSE)

- **Dokumen**: `SOVEREIGN_ORIGINAL_PURPOSE.md`
- **Klasifikasi**: Prinsip Inti & Batasan Arsitektur Proyek (Single Source of Truth)
- **Status**: DISAHKAN (RATIFIED)
- **Penetapan Pengguna**: *"gamectl adalah game manajer, sekaligus alternatif seperti tools steam popular: bisa search game steam dan dapatkan dengan full dlc, bisa dimainkan offline (sebisanya)"*

---

## 1. DEFINISI & IDENTITAS PROYEK

**`gamectl`** adalah pengelola game berdaulat (*sovereign game manager*), peluncur (*launcher*), dan downloader independen berbasis Terminal User Interface (TUI) untuk ekosistem Linux (Wayland & X11) dan perangkat handheld.

### Filosofi Utama: "Zero Bloat, Maximum Sovereignty"
1. **Anti-Bloat**: Dilarang menggunakan Electron, Chromium Embedded Framework (CEF), WebKit, atau GTK berat. Konsumsi RAM idle wajib berada di bawah **15 MB RSS** dengan waktu startup sub-**80ms**.
2. **Sovereign (Berdaulat)**: Kepemilikan aset dan runtime sepenuhnya berada di tangan pengguna secara lokal. Tidak ada ketergantungan wajib pada server cloud pihak ketiga, akun login tertutup, maupun aplikasi klien desktop yang menyita memori (seperti Steam Client resmi ~1 GB RAM).
3. **Decoupled Architecture**: Komponen download, manajemen lisensi, dan runtime peluncur beroperasi secara modular dan independen satu sama lain.

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
| • RAM < 15 MB RSS     |           | • Unduh Valve CDN     |       | • Goldberg Emulator   |
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
   - Menjamin seluruh aset fisik DLC terpasang lengkap di direktori game.
4. **Zero-Client Download Invariant**:
   - Seluruh proses pencarian dan pengunduhan berjalan tanpa membuka aplikasi resmi Steam Client.
   - Tidak memakan 1 GB RAM untuk Chromium subprocess (`steamwebhelper`), sangat optimal untuk laptop low-spec (Haswell T440p) dan mesin headless.

---

### PILAR 3: DAPAT DIMAINKAN SECARA OFFLINE "SEBISANYA" (STANDALONE RUNTIME)
Tujuan akhir adalah kebebasan memainkan game tanpa ketergantungan runtime:

1. **Entitlement Emulator Mandiri (Goldberg / GBE Fork)**:
   - Sesaat setelah unduhan selesai (atau melalui pre-flight guard saat game di-Enter di library), `gamectl` otomatis menyuntikkan Goldberg Steam Emulator:
     - Menggantikan pustaka resmi Valve (`steam_api.dll`, `steam_api64.dll`, `libsteam_api.so`) dengan pustaka emulator GBE Fork.
     - Menyediakan file identitas `steam_appid.txt` dan mapping seluruh DLC di `steam_settings/DLC.txt`.
     - Mengalihkan penyimpanan savegame lokal ke `<game_dir>/saves/`.
2. **Klausul Batasan Realitas ("Sebisanya")**:
   - **Game Steamworks Biasa (>90% katalog)**: 100% langsung dapat dimainkan secara offline mandiri tanpa pernah menyentuh Steam Client.
   - **Game Ber-DRM Keras / SteamStub**:
     - Windows PE: Di-bypass menggunakan Steamless CLI.
     - Linux ELF ber-seksi `.bind`: Dideteksi secara forensik, diberikan diagnostik transparan ke pengguna, dan diarahkan ke runner yang tepat.
   - **Dukungan Opsi Steam Client (Opt-in)**:
     - Jika pengguna sewaktu-waktu ingin membuka Steam Client resmi (misalnya untuk menggunakan profil Steam Input, gyro, atau pre-caching Vulkan shader), `gamectl` menyediakan sinkronisasi ke SLSsteam.
     - **Invarian Anti-PURCHASE**: Stplugin Lua yang dibuat wajib memuat baris `addappid(<appid>)` di baris pertama, sehingga Steam Client SELALU menampilkan tombol **PLAY**, bukan tombol **PURCHASE**.

---

## 3. ANTI-POLA & PANTANGAN MUTLAK (INVARIANTS)
1. **Dilarang Menjadikan SLSsteam Sebagai Ketergantungan Default**: SLSsteam adalah parasit proses Steam Client. Menghubungkan game standalone ke SLSsteam saat Steam Client mati adalah blunder arsitektur.
2. **Dilarang Membiarkan Biner Game Tanpa Emulator**: Mengeksekusi biner game yang memiliki dependensi `steam_api` resmi Valve tanpa di-shim GBE Fork akan memicu panggilan paksa ke Steam Client.
3. **Dilarang Memaksa Direktori Steam Sebagai Lokasi Tunggal**: Game standalone harus bebas diletakkan di direktori sovereign manapun (`~/Games/`, drive eksternal, dll).
4. **Dilarang Mengabaikan Kondisi Offline**: Ekstraksi lisensi DLC dan peluncuran game wajib dapat beroperasi 100% saat jaringan internet terputus total.

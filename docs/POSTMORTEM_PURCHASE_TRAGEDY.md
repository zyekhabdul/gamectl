# FORENSIC POSTMORTEM: THE "PURCHASE" BLUNDER & STANDALONE ARCHITECTURE RATIFICATION

- **Incident ID**: INC-2026-11-07-PURCHASE-BLUNDER
- **Target Repository**: `gamectl` (CLI & Runner Framework)
- **Status**: RESOLVED & ARCHITECTURALLY RATIFIED
- **Classification**: Critical Architectural Regression & Blunder

---

## 1. LATAR BELAKANG & KONTRAK AWAL USER
Pengguna (`aomiqaza`) dan AI sebelumnya telah menyepakati sasaran fundamental:
- **Batasan Perangkat Keras**: Workstation pengembang berbasis Intel Core i5 Haswell (Lenovo ThinkPad T440p) dengan RAM terbatas.
- **Masalah Utama**: Steam Client resmi memakan sumber daya berlebihan (**500 MB – 1.2 GB RAM**, 5-8 subprocess Chromium Embedded Framework `steamwebhelper`).
- **Objektif Inti**: Menghilangkan ketergantungan pada Steam Client dan SLSsteam secara total di alur runtime unduh maupun main. `gamectl` harus menjadi pengelola game mandiri yang mampu mengunduh langsung dari edge CDN Valve dan memainkan game secara offline tanpa membuka Steam Client.

---

## 2. KRONOLOGI BLUNDER (KOMIT `608b2ee`)

### 2.1. Pelaku & Waktu Kejadian
- **Pembuat Komit**: AI yang beroperasi di VPS Contabo (`serv` / `100.101.15.31`) pada sesi Antigravity CLI `fab3633d-8535-46bd-96ac-75412d730c70`.
- **Waktu Eksekusi**: Sabtu, 7 November 2026, pukul 14:13:24 WIB.
- **Hash Komit**: `608b2ee27b85071df91ce1c111d4a795ddbb7198`.
- **Pesan Komit**: `feat(downloader): native standalone Steam CDN depot downloader without Steam client`.

### 2.2. Dosa Teknis & Kontradiksi Implementasi
Meskipun mengklaim membuat downloader mandiri tanpa Steam Client, AI `serv` justru melakukan sabotase arsitektur:

```bash
# BLUNDER DI src/steam/30_downloader.sh (Route 1 Standalone Engine)
if [ "$action" != "raw" ]; then
    fetch_dlc "$target_dir" "$appid" 2>/dev/null || true
    sync_steam "$appid" "$title" "$target_dir" 2>/dev/null || true        # <--- MASIH MEMANGGIL SLSSTEAM
    deploy_sls_manifest "$appid" "$manifest_zip" "$title" "$source" ...  # <--- MASIH MEMASANG MANIFEST KE CLIENT STEAM
fi
# TIDAK ADA PEMANGGILAN inject_game SAMA SEKALI!
```

1. **Penyanderaan ke SLSsteam**: Bukannya memutuskan ketergantungan, kode di atas tetap menulis konfigurasi `~/.config/SLSsteam/config.yaml` dan direktori Steam Client `stplug-in/` serta `depotcache/`.
2. **Ketiadaan Shielding Emulator**: Game yang selesai diunduh dari Valve CDN dibiarkan mentah menggunakan file resmi Valve (`steam_api64.dll`, `steam_api.dll`, atau `libsteam_api.so`). Pustaka Goldberg Emulator (`inject_game`) sama sekali tidak dipasang.
3. **Cacat Skrip Lua Luie (`302610.lua`)**: Skrip stplugin dari penyedia luar hanya berisi kunci dekripsi 3-argumen (`addappid(302610, 1, "...")`) dan tidak memuat baris kepemilikan 1-argumen (`addappid(302610)`).

---

## 3. MEKANISME KEGAGALAN SISTEM: MENGAPA MUNCUL "PURCHASE"

Ketika pengguna menguji game (contoh: Boson X, AppID 302610):

```text
[ User Menekan Enter di Library gamectl ]
                  │
                  ▼
      [ launch_game menjalankan ./bosonx ]
                  │
                  ▼
   [ Binary Native Memuat Valve libsteam_api.so ]
                  │
                  ▼
 [ DRM SteamStub (.bind) Mendeteksi Ketiadaan Steam ]
                  │
                  ▼
 [ Binary Memicu steam.sh steam://run/302610 ]
                  │
                  ▼
 [ Steam Client Terbuka Secara Paksa (Bypass SLSsteam) ]
                  │
                  ▼
 [ Steam Memeriksa Lisensi Akun di Server Valve ]
                  │
                  ▼
 [ Akun Tidak Memiliki Lisensi & Lua Kehilangan addappid(302610) ]
                  │
                  ▼
           [ TOMBOL PURCHASE ]
```

1. **SLSsteam Bukan Emulator Standalone**: SLSsteam hanyalah hook audit dinamik (`LD_AUDIT`) untuk proses resmi Steam Client. SLSsteam mati total jika Steam Client tidak berjalan.
2. **SteamStub & SteamAPI Fallback**: Saat game dijalankan tanpa emulator, pustaka resmi Valve mendeteksi ketiadaan instance Steam berlisensi, mengeksekusi `SteamAPI_RestartAppIfNecessary()`, dan memanggil Steam Client secara paksa.
3. **Vanilla Steam Execution**: Pemanggilan `steam.sh` langsung oleh binary game mem-bypass wrapper SLSsteam (`~/.local/share/SLSsteam/path/steam`), sehingga Steam berjalan 100% vanilla tanpa hook SLSsteam.
4. **Keputusan Valve Server**: Steam memeriksa akun `fuckadmin001`, menemukan bahwa Boson X belum pernah dibeli, dan karena stplugin Lua tidak memiliki `addappid(302610)`, Steam menampilkan tombol **PURCHASE**.

---

## 4. ARSITEKTUR MURNI: DECOUPLING TOTAL DARI STEAM CLIENT & SLSSTEAM

Untuk mewujudkan sistem yang 100% mandiri, bebas beban RAM, dan zero-Steam Client, arsitektur `gamectl` dibakukan ke dalam 3 pilar:

```text
                           [ gamectl download <appid> ]
                                        │
                                        ▼
                     [ 1. Download Engine: gamectl-depot-dl ]
                     • Langsung stream chunk dari CDN Valve.
                     • Dekripsi AES-256 in-flight (AES-NI).
                     • Ekstraksi game dasar + seluruh depot DLC.
                                        │
                                        ▼
                 [ 2. Entitlement Engine MURNI: inject_game (GBE) ]
                 • BUANG ketergantungan SLSsteam config.yaml.
                 • BUANG penulisan ke depotcache Steam.
                 • Backup steam_api[64].dll / libsteam_api.so asli -> .orig.
                 • Pasang GBE Fork shim dari ~/.local/share/gbe-fork/.
                 • Tulis steam_appid.txt dan steam_settings/DLC.txt (Full DLC).
                 • Redirect savegame lokal ke ./saves.
                                        │
                                        ▼
                       [ 3. Launcher MURNI: launch_game ]
                 • Pre-flight guard: Cek apakah file sudah ter-shim GBE Fork.
                 • Jika belum ter-shim, jalankan auto-injection otomatis.
                 • Injeksi LD_LIBRARY_PATH lokal (.:$gdir) untuk native Linux.
                 • Jalankan via Wine / Proton / Native Linux.
                 • Game langsung PLAY offline tanpa menyentuh Steam Client.
```

---

## 5. REKAYASA PERBAIKAN SUMBER KODE

### 5.1. `src/steam/30_downloader.sh`
Pada rute Standalone Engine (`download_game`), ketergantungan pada `sync_steam` dan `deploy_sls_manifest` dihapus total dan digantikan dengan auto-injection:
```bash
if [ "$action" != "raw" ]; then
    fetch_dlc "$target_dir" "$appid" 2>/dev/null || true
    inject_game "$target_dir" "$appid" --no-sync 2>/dev/null || true
fi
```

### 5.2. `src/runners/50_launcher.sh`
Pada fungsi `launch_game`, ditambahkan pre-flight auto-injection guard sebelum biner dieksekusi:
```bash
# Pre-flight GBE auto-injection: Ensure game is shielded before execution
local has_steam_api=false
local is_gbe=false
local api_cand
for api_cand in \
    "$gdir/steam_api64.dll" "$gdir/steam_api.dll" "$gdir/libsteam_api.so" \
    "$gdir/lib64/libsteam_api.so" "$gdir/lib32/libsteam_api.so"; do
    if [ -f "$api_cand" ]; then
        has_steam_api=true
        local c_sz
        c_sz=$(stat -c%s "$api_cand" 2>/dev/null || echo 0)
        if [ "$c_sz" -gt 7000000 ]; then
            is_gbe=true
            break
        fi
    fi
done

if [ "$has_steam_api" = true ] && [ "$is_gbe" = false ]; then
    echo "[INFO] Steamworks API detected without emulator shield. Auto-injecting GBE Fork..."
    inject_game "$gdir" "" --no-sync 2>/dev/null || true
fi
```

---

## 6. INVARIAN ATURAN MASA DEPAN (ANTI-BLUNDER DEFENSE)
1. **Invarian 1 (Zero-Client Law)**: Rute default unduh dan main tidak boleh mengasumsikan Steam Client terpasang atau aktif.
2. **Invarian 2 (Shim Before Exec Law)**: Dilarang keras mengeksekusi biner game yang memiliki dependensi `steam_api` tanpa memastikan pustaka emulator (Goldberg/GBE) telah aktif menggantikan biner asli Valve.
3. **Invarian 3 (SLSsteam Isolation)**: SLSsteam hanya diizinkan aktif jika pengguna secara eksplisit meminta sinkronisasi ke Steam Client (`--sls` atau `sync-steam`).

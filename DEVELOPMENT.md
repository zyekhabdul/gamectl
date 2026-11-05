# GAMECTL — DEVELOPER GUIDE & COMPILATION ARCHITECTURE

## 1. Arsitektur Source-to-Bundle

`gamectl` menggunakan pola **Source-to-Bundle**:
- Kode sumber dikembangkan secara modular dalam direktori `src/` (masing-masing 150-600 baris per modul).
- Script bundling native [`scripts/build.sh`](file:///home/aomiqaza/Projects/gamectl/scripts/build.sh) menggabungkan seluruh modul menjadi executable mandiri tunggal di [`bin/gamectl`](file:///home/aomiqaza/Projects/gamectl/bin/gamectl).
- Keuntungan:
  - **Zero Dependency at Runtime**: Executable tidak bergantung pada file library eksternal saat dieksekusi di mesin target.
  - **Portabilitas Tinggi**: Binary dapat disymlink atau dipindahkan ke `~/.local/bin` atau `/usr/local/bin` tanpa kehilangan modul.
  - **Instant Subshell Performance**: Subshell `fzf` (`fzf --preview`) berjalan instan tanpa overhead runtime parsing multi-file.

---

## 2. Struktur Modul (`src/`)

```text
src/
├── core/
│   ├── 00_header.sh       # SSoT Constants, Tokyo Night ANSI styling palette, FZF base configuration
│   └── 10_utils.sh        # GBE templates resolution, remote host, save snapshots, binary discovery
├── steam/
│   ├── 20_discovery.sh    # Multi-path Steam root discovery, manifest scanning, and create_desktop_entry
│   ├── 25_identity.sh     # SteamID64 generation, active SteamID resolution, persona configuration, set-id
│   └── 30_downloader.sh   # DLC fetching, multi-arch DepotDownloader engine, downloads monitor, SLSsteam sync
├── runners/
│   ├── 40_wrappers.sh     # Windows runner, detect_dll_overrides, GE-Proton manager, manage_prefix (pfx)
│   └── 50_launcher.sh     # Prefix isolation, setup_onlinefix, PipeWire audio latency, wineserver teardown guard
├── diagnostics/
│   └── 60_doctor.sh       # 7-layer health diagnostics, hardware audit, and query_protondb
├── tui/
│   └── 70_dashboard.sh    # Terminal previews, interactive dashboard hub, library menu, Steam Store search
└── main.sh                # Subshell exports (export -f) and top-level CLI command dispatcher
```

---

## 3. Workflow Kompilasi & Pengujian

### Kompilasi ke Standalone Binary
```bash
./scripts/build.sh
```

### Verifikasi Sinkronisasi Source vs Binary (CI / Pre-commit Gate)
```bash
./scripts/build.sh --check
```

### Verifikasi Sintaks Seluruh Modul
```bash
for f in src/*/*.sh src/main.sh bin/gamectl scripts/build.sh; do bash -n "$f" || exit 1; done
```

### Jalankan Test Suite Otomatis (Regression & Integrity Harness)
```bash
./tests/test_cli.sh
```

### Jalankan Diagnostik Sistem
```bash
bin/gamectl doctor
```

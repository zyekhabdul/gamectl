# WORK PACKET 12: LINUX KERNEL ISOLATION, HYBRID PRIME & SECURITY SANDBOXING [ACTIVE]

## 1. Objective & Technical Scope
Implement Linux systems architectural remediation (Phase 4 / Actions 4.1-4.4):
1. **cgroups v2 / systemd-run Scope Isolation (Action 4.1)**: Eliminate process tree leaks and zombie reparenting to PID 1 by binding launches to isolated `systemd-run --user --scope` units with automatic fallback.
2. **Automated PRIME dGPU Hybrid Offloading (Action 4.2)**: Auto-detect discrete NVIDIA / AMD GPUs and synthesize dynamic offload flags (`--prime`) to prevent games from defaulting to low-power integrated GPUs.
3. **Bubblewrap (`bwrap`) Security Sandboxing (Action 4.3)**: Implement an opt-in rootless sandbox (`--sandbox`) restricting filesystem visibility to necessary system runtimes and the game prefix, protecting sensitive host directories (`~/.ssh`, `~/.gnupg`, browser data, `.env`).
4. **Single-Pass Library Scanner Optimization (Action 4.4)**: Refactor `scan_installed_games` to minimize redundant subshell forks (`file`, `stat`, `grep`) on large game collections (>500 games).
5. **Machine Verification & Automated Regression Suite**: Add black-box unit tests in `tests/test_cli.sh`, compile via `./scripts/build.sh`, and verify exit code 0 across the entire test suite.

---

## 2. Granular Technical Execution Plan (Work Packet 12)

### Chunk 1: cgroups v2 / systemd-run Scope Process Isolation (Action 4.1) [DONE]
- Target Files: `src/runners/40_wrappers.sh`, `src/runners/50_launcher.sh`, `src/main.sh`
- Runtutan Eksekusi Teknis:
  1. Buat helper `check_systemd_scope_support` di `src/runners/40_wrappers.sh`:
     - Uji apakah `systemd-run --user --scope true` berhasil dieksekusi tanpa error.
  2. Perbarui `launch_game` di `src/runners/50_launcher.sh`:
     - Tambahkan flag CLI `--scope` / `--no-scope` (default: auto-enable jika didukung).
     - Jika aktif, luncurkan execution string di bawah scope:
       `systemd-run --user --scope --unit="gamectl-${safe_title}-${game_pid}" --description="gamectl runner: ${title}" "${wrappers[@]}" "$runner_bin" "$gdir/$gbin"`
     - Simpan unit name ke metadata info file `${XDG_RUNTIME_DIR:-/tmp}/gamectl-$UID/active_game_${game_pid}.info`.
  3. Perbarui fungsi cleanup dan `game_controller_hud`:
     - Saat terminasi paksa (kill), jalankan `systemctl --user stop "$unit_name" 2>/dev/null || true` untuk membunuh seluruh child process tree secara atomik via kernel cgroup v2.
  4. Sediakan fallback transparan ke subshell standar jika systemd tidak aktif (distro non-systemd/chroot/container).
- DoD: Seluruh child process game (crash reporters, explorer.exe, winedevice.exe) terisolasi dalam satu cgroup slice dan berhenti seketika saat game ditutup tanpa meninggalkan zombie processes.

### Chunk 2: Automated PRIME dGPU Hybrid Offloading (Action 4.2) [DONE]
- Target Files: `src/runners/40_wrappers.sh`, `src/runners/50_launcher.sh`, `src/diagnostics/60_doctor.sh`, `src/main.sh`
- Runtutan Eksekusi Teknis:
  1. Buat fungsi helper `detect_dgpu_vendor` di `src/runners/40_wrappers.sh`:
     - Periksa perangkat PCI display di `/sys/bus/pci/devices/*/class` (class `0x030000` / `0x030200`).
     - Deteksi vendor diskrit: vendor ID `0x10de` (NVIDIA) vs `0x1002` (AMD) vs `0x8086` (Intel Arc).
     - Kembalikan `nvidia`, `amd`, `intel`, atau `none`.
  2. Perbarui `build_wrapper_command` di `src/runners/40_wrappers.sh`:
     - Tambahkan parsing opsi `prime=0|1` dari konfigurasi game dan flag CLI `--prime`.
     - Jika diaktifkan:
       - NVIDIA: inject `__NV_PRIME_RENDER_OFFLOAD=1 __GLX_VENDOR_LIBRARY_NAME=nvidia __VK_LAYER_NV_optimus=NVIDIA_only`.
       - AMD: inject `DRI_PRIME=1`.
       - Intel Arc: inject `DRI_PRIME=1`.
  3. Tambahkan audit hybrid GPU pada Layer Hardware di `src/diagnostics/60_doctor.sh` (`doctor_audit`).
  4. Ekspor dan daftarkan perintah `gamectl detect-gpu` di `src/main.sh`.
- DoD: Flag `--prime` secara otomatis mengarahkan rendering ke GPU diskrit yang terdeteksi tanpa konfigurasi manual user.

### Chunk 3: Bubblewrap (bwrap) Rootless Security Sandbox Profile (Action 4.3) [DONE]
- Target Files: `src/runners/40_wrappers.sh`, `src/runners/50_launcher.sh`, `src/main.sh`
- Runtutan Eksekusi Teknis:
  1. Buat fungsi helper `build_sandbox_command "$gdir"` di `src/runners/40_wrappers.sh`:
     - Periksa ketersediaan binari `bwrap`. Jika tidak ada, cetak peringatan `[WARN]` dan lewati sandboxing dengan aman.
     - Susun parameter isolasi rootless bwrap:
       - Read-only mounts: `/usr`, `/lib`, `/lib64`, `/bin`, `/etc/resolv.conf`, `/etc/ssl`, `/etc/fonts`, `/dev`, `/proc`, `/sys`.
       - Sockets & Audio: `/run/user/$UID/pulse`, `/run/user/$UID/pipewire-0`, `/run/user/$UID/wayland-0`, `/tmp/.X11-unix`.
       - Read-write isolasi: `$gdir` dan `${XDG_RUNTIME_DIR:-/tmp}/gamectl-$UID`.
       - Unshare namespaces: `--unshare-user --unshare-ipc --unshare-pid`.
       - Sembunyikan direktori kredensial: isolasi `$HOME` sehingga `~/.ssh`, `~/.gnupg`, `~/.config/google-chrome`, dan file kredensial tidak terlihat oleh binary game.
  2. Tambahkan opsi per-game `sandbox=0|1` dan flag CLI `--sandbox` pada `launch_game`.
- DoD: Standalone untrusted binary dapat dieksekusi dengan isolasi penuh terhadap file rahasia host `$HOME` tanpa merusak rendering Wayland/X11 dan audio PipeWire.

### Chunk 4: Single-Pass Library Scanner Optimization (Action 4.4) [DONE]
- Target Files: `src/steam/20_discovery.sh`, `src/tui/70_dashboard.sh`
- Runtutan Eksekusi Teknis:
  1. Analisa kemacetan I/O pada `scan_installed_games` di `src/steam/20_discovery.sh`:
     - Hilangkan fork subshell berulang (`stat`, `basename`, `dirname`, `file -b`) di dalam loop direktori game.
  2. Implementasikan pola batch-probing berbasis bash array / fast globbing:
     - Deteksi metadata game (`steam_appid.txt`, `pfx`, `saves`, executable utama) dalam satu operan per folder.
  3. Sediakan opsi cache pemindaian library sementara di `$XDG_RUNTIME_DIR/gamectl-$UID/scancache.tab` dengan waktu validasi mtime direktori library untuk mempercepat render daftar game TUI secara instan.
- DoD: Kecepatan pemindaian library masif meningkat signifikan (>3x lebih cepat) dengan konsistensi output data yang identik.

### Chunk 5: Machine Verification & Automated Regression Suite (Work Packet 12) [DONE]
- Target Files: `tests/test_cli.sh`, `remediation.md`, `DEVELOPMENT.md`
- Runtutan Eksekusi Teknis:
  1. Tambahkan unit test assertions di `tests/test_cli.sh`:
     - Test dGPU Vendor Detection (`detect_dgpu_vendor`).
     - Test PRIME Wrapper synthesis (`--prime`).
     - Test Bubblewrap sandbox argument generation (`--sandbox`).
     - Test systemd-run scope command synthesis & fallback.
     - Test optimized library scanner consistency against baseline.
  2. Jalankan kompilasi `./scripts/build.sh` dan verifikasi integritas bundle `./scripts/build.sh --check`.
  3. Jalankan regression test suite `./tests/test_cli.sh` (55+ assertions) hingga seluruh tes lulus dengan Exit Code 0.
  4. Perbarui dokumentasi status di `remediation.md` dan `DEVELOPMENT.md`.
- DoD: Semua fitur Phase 4 terverifikasi 100% oleh deterministic test runner dengan Exit Code 0.

---

## 3. Matriks Milestone Selesai (Work Packet 12 & History)
- [x] WP 12 Chunk 1: cgroups v2 / systemd-run Scope Process Isolation (`a752f25`) [DONE]
- [x] WP 12 Chunk 2: Automated PRIME dGPU Hybrid Offloading (`45aef7f`) [DONE]
- [x] WP 12 Chunk 3: Bubblewrap (bwrap) Rootless Security Sandbox Profile (`701f6fb`) [DONE]
- [x] WP 12 Chunk 4: Single-Pass Library Scanner Optimization (`de6f4ff`) [DONE]
- [x] WP 12 Chunk 5: Machine Verification & Automated Regression Suite [DONE]
- [x] Checkpoint Verifikasi: 55/55 tests passing with Exit 0. [DONE]

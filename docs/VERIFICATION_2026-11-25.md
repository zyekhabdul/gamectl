# Verification follow-up — 2026-11-25

Scope: execute item #4 from `docs/VERIFICATION_2026-11-10.md` on `4e1ba4f` — Rust
dependency upgrade and OSV audit (`crates/depot-dl`), Rust quality gates, and Tier-2
live host hardware runtime verification (disposable `/tmp` targets only).

## Environment

- Host: Arch Linux `6.18.45-2-lts` `x86_64`, Wayland (`wayland-1`) + X11 (`:0`),
  Intel 4th Gen Haswell iGPU (`Mesa Intel(R) HD Graphics 4600 (HSW GT2)`, OpenGL 4.6).
- Compiler: `/usr/bin/rustc 1.98.0 (88d9e12ae 2026-08-18) (Arch Linux rust 1:1.98.0-1)`
  with `libLLVM.so.22.1`. Host rustup `1.100.0` ICE'd on `libc 0.2.191`; Arch LLVM 22.1
  release builds required `RUST_MIN_STACK=536870912 CARGO_BUILD_JOBS=1`.
- `./bin/gamectl doctor`: 22 Passed, 4 Warnings (GPU `VULKAN_LEGACY` -> WineD3D),
  0 Missing (`bwrap`, `systemd-run` cgroups v2, GBE x64/x86 Linux+Win, GE-Proton7-55 ready).

## Dependency advisory audit (`osv.dev/v1/querybatch`)

Note: `cargo-audit` is not installed on host; `Cargo.lock` registry packages were
queried directly via OSV batch API before and after `cargo update`.

| Crate | BEFORE | AFTER | Notes |
| --- | --- | --- | --- |
| `zip` | `7.3.0` (13 advisories, `GHSA-m665-v7pm-7grj` CRITICAL) | `9.8.2` | Bumped `Cargo.toml` to `zip = "9"`, `rust-version = "1.89"`, updated `chunk.rs` to `SimpleFileOptions::default()` |
| `rustls` | `0.23.45` (8 advisories) | `0.23.46` | Patched via `cargo update` |
| `rustls-webpki` | `0.103.15` | `0.103.17` | Patched via `cargo update` |
| `tokio` | `1.53.2` | `1.54.1` | Patched via `cargo update` |
| `url` | `2.5.8` | `2.5.9` | Patched via `cargo update` |
| `webpki-roots` | `1.0.9` | `1.0.12` | Patched via `cargo update` |
| `rustix` | `1.1.5` | `1.1.6` | Patched via `cargo update` |
| `zstd` / `zstd-safe` / `zstd-sys` | `0.13.3` / `7.3.0` (12 adv.) / `2.1.1+zstd.1.5.7` | `0.13.6` / `7.4.2` / `2.2.0+zstd.1.6.0` | Patched via `cargo update` |
| **OSV Total** | **10 vulnerable / 198 crates** | **0 vulnerable / 202 crates** | `steam-protobuf-rs` pinned to `0.1.14` (`0` advisories; `0.1.20` ICE'd `rustc 1.98.0`) |

## Rust quality gates (`[ SYNTACTICALLY_VERIFIED ]`)

| Check | Result | Notes |
| --- | --- | --- |
| `cargo fmt --check` | PASS | Formatted `gamectl-depot-dl.rs`, `chunk.rs`, `download.rs`, `util.rs` |
| `cargo clippy --locked --all-targets -- -D warnings` | PASS | Resolved `manual_clamp`, `manual_is_multiple_of`, `collapsible_if`, `manual_checked_ops` |
| `cargo test --locked` | PASS | 31 lib unit + 6 bin + 3 doctests (0 failed); added `.`, `..`, `/`, `\`, `///..///` tests in `util.rs` killing line 103 survivor |
| `./scripts/build-depot-dl.sh --force` | PASS | Built `release` profile `[optimized]` in 2m46s (`bin/gamectl-depot-dl`, `4.53 MB`, `RUST_MIN_STACK=536870912 CARGO_BUILD_JOBS=1 RUSTC=/usr/bin/rustc`) |
| `STRICT_LINT=1 make lint` + `--check` | PASS | Executed after final edit alongside `./scripts/build.sh --check` and `./scripts/build-depot-dl.sh --check` |

## Tier-2 live host runtime evidence (`[ PRODUCTION_EXECUTION_AUDITED ]`)

All live tests used disposable `/tmp/gamectl_tier2_*` directories and read-only user state;
no `~/Games/` or `~/.local/share/Steam/` paths were modified.

- **Live read-only API probes** (all `exit 0`):
  - `./bin/gamectl search-stores "Super Hexagon" --store steam` -> `STEAM 221640 Super Hexagon linux,windows,mac INSTALLED GAME`
  - `./bin/gamectl protondb 221640` -> `[PLATINUM]` (`score: 0.8`, confidence `good`)
  - `./bin/gamectl stores status` & `./bin/gamectl auth status` -> `depot_dl: ready`, `gbe_fork: ready (linux+windows)`, `luatools: session present`
- **Live standalone Valve CDN download + GBE Fork injection**:
  - `./bin/gamectl download 221640 /tmp/gamectl_tier2_dl_luelg0 "Super Hexagon" --os linux --standalone -f` -> `exit 0`
  - Connected to 16 Valve CDN edge servers; Depot `221643` (GID `7186315654381968499`): 42 files, `19.35 MB` transferred (`22.70 MB` uncompressed) in `7.6s` (cached manifest zip + offline 4-DLC fallback)
  - Granted `+x` on 3 Linux ELFs and injected Linux x64 GBE Fork (`lib64/libsteam_api.so`, `steam_appid.txt`, `steam_settings/DLC.txt`)
- **Live standalone launch + `cgroups v2` scope + clean teardown**:
  - `./bin/gamectl launch /tmp/gamectl_tier2_dl_luelg0 --scope` -> started `SuperHexagon` PID `1960252` inside `gamectl-gamectl_tier2_dl_luelg0-1960252.scope` (`loaded active running`)
  - Runtime log `/run/user/1000/game_gamectl_tier2_dl_luelg0_2397126325_SuperHexagon.log` confirmed FNA3D OpenGL 4.6 initialization on Mesa Intel HD 4600, audio/font loading, and `windowResized(1600, 900)`
  - Stopped via `systemctl --user stop` + `SIGTERM`: `0` active `gamectl-*` scopes, `0` orphan `SuperHexagon` processes (`pgrep -x SuperHexagon` empty), disposable `/tmp/gamectl_tier2_*` and test runtime log deleted

## Claim tier and unverified surfaces

- **Verified tiers**: `[ SYNTACTICALLY_VERIFIED ]` for `crates/depot-dl` and bash modules;
  `[ PRODUCTION_EXECUTION_AUDITED ]` for host `doctor`, live Steam/ProtonDB API probes,
  native Linux standalone Valve CDN download, GBE Fork injection, and `systemd-run` `cgroups v2` launch/teardown.
- **Remaining unverified surfaces**: Steam Deck Game Mode (`gamescope-session`), real
  remote SSH/`rsync` companion host transfer, live GOG/Epic/Amazon authenticated CLI downloads,
  and offline `cargo test --all-features` (`tests/fixtures/` binary manifests excluded from git).

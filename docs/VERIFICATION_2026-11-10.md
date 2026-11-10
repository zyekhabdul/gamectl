# Verification follow-up — 2026-11-10

Scope: close previously unavailable verification on `bbd4e18` plus the preserved
local maintenance patch. This document supplements the earlier maintenance audit;
no dependency upgrade or runtime repair is implied by running these checks.

## Environment

- Rust/Cargo 1.99.1, Clippy and rustfmt installed with official rustup under
  `/tmp/gamectl-audit-{cargo,rustup}`; shell configuration was not modified.
- Initial build artifacts were moved to
  `~/.cache/gamectl-verification/rust-target` to avoid filling the `/tmp` tmpfs.
- Mutation tests use cargo-mutants v27.1.0, a disposable source copy, and a separate
  target directory. Production source is not mutated in place.
- GPU diagnostics run read-only on the host because the sandbox does not expose
  the display or GPU devices.

## Completed checks

| Check | Result | Interpretation |
| --- | --- | --- |
| `cargo test --locked` | **PASS: 31 unit tests + 3 doctests** | Includes local mock HTTP downloader tests. Binary CLI has zero unit tests. |
| `cargo build --offline --locked --bin gamectl-depot-dl` | **PASS** | Debug binary built from the current source; does not replace the tracked release helper. |
| `cargo clippy --offline --locked --all-targets -- -D warnings` | **FAIL: 3 findings** | Two `single_match_else` findings and one `manual_checked_ops` finding. |
| `cargo fmt --check` | **FAIL** | Differences in `src/bin/gamectl-depot-dl.rs` and `src/util.rs`. |
| `cargo test --offline --locked --all-features --no-run` | **FAIL** | Feature `fixtures` references three files not present in the repository. |
| Vulkan host enumeration | **PASS** | Intel Iris Xe (TGL GT2), Mesa 26.2.6, Vulkan device API 1.4.354. |
| OpenGL host diagnostics | **PASS** | Direct rendering enabled; accelerated Intel renderer; OpenGL 4.6. |
| Dependency advisory scan | **FINDINGS** | OSV matched 8 registry dependency versions; details below. |
| Mutation test, `src/util.rs` | **42 caught / 43 total; 1 missed** | No timeout or unviable mutant; 97.7% caught for this module only. |

Clippy locations: `crates/depot-dl/src/bin/gamectl-depot-dl.rs:81,89,181`.
The strict check treats warnings as errors; this is distinct from a failing unit
test or a proven gameplay crash.

The missing all-feature fixtures are referenced at
`crates/depot-dl/src/manifest/mod.rs:298,318,337`. They are two binary manifests and
one depot-key file. Do not fabricate fixtures merely to make the gate green;
replace them with deliberate synthetic fixtures or define a documented optional
fixture workflow. No actual depot keys were fetched or printed in this audit.

## Mutation result

Ran the complete set of 43 generated mutants for `src/util.rs` using two workers,
a 30-second test timeout, a 180-second build timeout, offline dependency cache,
and an unmutated baseline that passed. The mutation run exited 2 because one
mutant survived; it did not time out or stop early.

The survivor is `src/util.rs:103:35`, replacing `||` with `&&` in
`safe_relative_path`'s empty/absolute-result guard. Add explicit rejection tests
for inputs that normalize into an empty path (such as `.`, `..`, `/`, and a lone
backslash), then rerun. The 97.7% result is not a project-wide mutation score;
Bash, CLI argument handling, downloader orchestration, and other Rust modules
were not mutation-tested in this run.

Evidence: `/tmp/gamectl-mutation/mutants.out/outcomes.json`, `missed.txt`, and
`/tmp/gamectl-mutation.log`.

## Dependency advisory scan

Queried [OSV's batch API](https://google.github.io/osv.dev/post-v1-querybatch/) with
the names and exact versions of all **198 registry packages** in Cargo.lock.
No source, local paths, or credentials were uploaded. All returned advisory
records were fetched; none of those records was marked withdrawn at scan time.

| Locked dependency | Version | Example published fix boundary |
| --- | --- | --- |
| rustls | 0.23.45 | 0.23.46 |
| rustls-webpki | 0.103.15 | 0.103.16 |
| tokio | 1.53.2 | 1.53.3 |
| webpki-roots | 1.0.9 | 1.0.10 |
| zip | 7.3.0 | 9.0.0 / 9.0.5, depending on advisory |
| zstd | 0.13.3 | 0.13.4 |
| zstd-safe | 7.3.0 | 7.4.0 |
| zstd-sys | 2.1.1+zstd.1.5.7 | 2.1.2 |

These are advisory fix boundaries, not a verified compatible upgrade plan.
There were **34 advisory records**, forming **28 connected alias groups**;
counts must not be presented as 34 distinct exploitable CVEs.

Examples:

- [GHSA-m665-v7pm-7grj](https://osv.dev/vulnerability/GHSA-m665-v7pm-7grj):
  ZIP parser differential, advisory database severity CRITICAL.
- [RUSTSEC-2026-0382](https://osv.dev/vulnerability/RUSTSEC-2026-0382):
  rustls-webpki certificate verification involving distrusted intermediates.
- [RUSTSEC-2026-0386](https://osv.dev/vulnerability/RUSTSEC-2026-0386):
  Tokio AsyncFd constructor I/O safety.

Reachability depends on enabled features and actual call paths. For example,
project ZIP handling uses `ZipArchive::by_index`, not `ZipArchive::extract`; an
extraction-specific advisory alone does not prove the project's extraction path
is exploitable. This scan is dependency-version matching, not an exploit test,
host-package inventory scan, or a clean security certification.

Raw scanner evidence remains in `/tmp/gamectl-osv-{packages,results,findings,details}.json`.
Rust check logs remain in `/tmp/gamectl-{rust-test,clippy,rustfmt,rust-allfeatures}.log`.

## Remaining hardware/integration acceptance

- **Gameplay:** GPU diagnostics pass, but do not prove an actual game launches,
  renders, saves, exits, or remains stable through a play session.
- **Steam Deck:** no Deck has been identified for testing. Desktop host success
  does not certify SteamOS Game Mode, controls, suspend/resume, or Deck storage.
- **Real remote sync:** no authorized remote alias/path has been supplied.
  Existing mocked tests are not evidence of a real SSH/rsync transfer.

The user was asked for an allowed game path and, where available, a remote SSH
alias or Steam Deck target. No passwords or tokens are needed in conversation.
Pending those targets, these checks remain explicitly unverified.

## Next work

1. Fix strict Rust lint/format failures and decide the optional-fixture contract.
2. Review advisory reachability and compatible upgrades, then rerun test and scan.
3. Use mutation results to add behavioral assertions for surviving changes.
4. Run authorized game and device acceptance separately from unit/mock checks.

Earlier passing Bash, wheel/sdist, Debian packaging and PTY results remain scoped
to the previous audit; they were not all rerun in this follow-up.

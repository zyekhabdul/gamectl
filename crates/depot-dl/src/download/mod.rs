//! The download orchestrator.
//!
//! Per depot: parse manifest → ids/key → plan every file → run chunk downloads under a shared
//! concurrency semaphore → commit state. Files are planned/executed concurrently; network
//! concurrency is bounded by [`DownloadRequest::max_downloads`].
//!
//! Reuse semantics (exactly what the crate docs promise):
//!
//! | situation                                       | behavior                                      |
//! |-------------------------------------------------|-----------------------------------------------|
//! | file missing                                    | download every chunk                          |
//! | same manifest gid as installed                  | verify every chunk (Steam-style verify)       |
//! | new gid, file hash unchanged across versions    | skip without reading                          |
//! | new gid, file hash changed                      | verify on-disk chunks; reuse valid ones via staging |
//! | prior install with no/unknown state             | verify against the new manifest in place      |
//!
//! Files on disk that are not listed in the manifest are never touched and never deleted.

mod io;
mod planner;
mod worker;

#[cfg(test)]
#[allow(clippy::unwrap_used)]
mod tests;

use std::collections::HashMap;
use std::path::PathBuf;
use std::sync::Arc;
use std::sync::atomic::{AtomicU64, Ordering};
use std::time::Instant;

use futures::stream::{FuturesUnordered, StreamExt};
use tokio::sync::{Semaphore, mpsc};
use tokio_util::sync::CancellationToken;

use crate::cdn::client::CdnClient;
use crate::cdn::{CdnServer, directory};
use crate::config::{DepotSpec, DownloadRequest, ManifestSource};
use crate::error::{Error, Result};
use crate::manifest::{DepotManifest, ManifestFile};
use crate::progress::{DepotReport, DownloadReport, ProgressEvent};
use crate::state::StateStore;
use crate::util;

pub(crate) struct DownloadEngine {
    http: reqwest::Client,
    pub(super) request: DownloadRequest,
    events: mpsc::Sender<ProgressEvent>,
    pub(super) cancel: CancellationToken,
    server_override: Option<Arc<Vec<CdnServer>>>,
    pub(super) total_downloaded: Arc<AtomicU64>,
    pub(super) total_uncompressed: Arc<AtomicU64>,
}

/// A depot failure that remembers how far identification got, so failure reports can name
/// the depot once its manifest has been parsed.
struct DepotFailure {
    depot_id: Option<u32>,
    manifest_gid: Option<u64>,
    error: Error,
}

/// Everything [`DownloadEngine::download_depot`] produces for bookkeeping/state.
struct DepotOutcome {
    depot_id: u32,
    manifest_gid: u64,
    files: usize,
    bytes_total: u64,
    downloaded_bytes: u64,
    manifest_bytes: Vec<u8>,
}

/// Shared, immutable-per-depot state handed to every file task.
pub(super) struct DepotCtx<'a> {
    pub(super) client: &'a CdnClient,
    pub(super) depot_id: u32,
    pub(super) key: [u8; 32],
    pub(super) staging_dir: PathBuf,
    /// `true` when the requested manifest gid equals the gid recorded as installed -
    /// disables all reuse shortcuts and forces the full Steam-style chunk verification.
    pub(super) same_manifest: bool,
    pub(super) old_by_path: HashMap<&'a str, &'a ManifestFile>,
    pub(super) depot_cancel: CancellationToken,
    pub(super) depot_bytes_completed: Arc<AtomicU64>,
    pub(super) depot_downloaded: Arc<AtomicU64>,
    pub(super) depot_bytes_total: u64,
    pub(super) downloads_sem: Arc<Semaphore>,
    pub(super) files_sem: Arc<Semaphore>,
}

impl DownloadEngine {
    pub(crate) fn new(
        http: reqwest::Client,
        request: DownloadRequest,
        events: mpsc::Sender<ProgressEvent>,
        cancel: CancellationToken,
        server_override: Option<Arc<Vec<CdnServer>>>,
    ) -> Self {
        DownloadEngine {
            http,
            request,
            events,
            cancel,
            server_override,
            total_downloaded: Arc::new(AtomicU64::new(0)),
            total_uncompressed: Arc::new(AtomicU64::new(0)),
        }
    }

    pub(crate) async fn run(mut self) -> Result<DownloadReport> {
        let started = Instant::now();
        let app_id = self.request.app_id;

        // 1. CDN servers: explicit override (tests / LAN caches) or Steam's public directory.
        let servers = match &self.server_override {
            Some(servers) => servers.as_ref().clone(),
            None => directory::fetch_servers(&self.http).await?,
        };
        let client = CdnClient::new(self.http.clone(), servers, app_id)?;
        self.emit(ProgressEvent::ServerListLoaded {
            servers: client.server_count(),
        })
        .await;

        // 2. Output directory + state. Stale staging leftovers from a crashed run are dropped -
        //    staging content is always rebuilt from scratch.
        tokio::fs::create_dir_all(&self.request.output_dir)
            .await
            .map_err(Error::io_path(&self.request.output_dir))?;
        let mut state = StateStore::load(&self.request.output_dir);
        state.clear_staging()?;

        // 3. Depots sequentially (as in DepotDownloader); parallelism happens within a depot.
        // `depots` is moved out so each `ManifestSource` is consumed without cloning.
        let depots = std::mem::take(&mut self.request.depots);
        let mut depot_reports = Vec::with_capacity(depots.len());
        for spec in depots {
            if self.cancel.is_cancelled() {
                return Err(Error::Cancelled);
            }

            match self.download_depot(&client, &state, spec).await {
                Ok(outcome) => {
                    let error = state
                        .commit_depot(
                            outcome.depot_id,
                            outcome.manifest_gid,
                            &outcome.manifest_bytes,
                        )
                        .err()
                        .map(|e| e.to_user_string());

                    let report = DepotReport {
                        depot_id: Some(outcome.depot_id),
                        manifest_gid: Some(outcome.manifest_gid),
                        files: outcome.files,
                        bytes_total: outcome.bytes_total,
                        downloaded_bytes: outcome.downloaded_bytes,
                        error,
                    };
                    if let Some(error) = &report.error {
                        // The download itself fully succeeded; only the bookkeeping write failed.
                        self.emit(ProgressEvent::DepotFailed {
                            depot_id: report.depot_id,
                            error: error.clone(),
                        })
                        .await;
                    } else {
                        self.emit(ProgressEvent::DepotCompleted {
                            depot_id: outcome.depot_id,
                            manifest_gid: outcome.manifest_gid,
                            downloaded_bytes: outcome.downloaded_bytes,
                        })
                        .await;
                    }
                    depot_reports.push(report);
                }
                Err(failure) => {
                    if matches!(failure.error, Error::Cancelled) || self.cancel.is_cancelled() {
                        return Err(Error::Cancelled);
                    }
                    let message = failure.error.to_user_string();
                    self.emit(ProgressEvent::DepotFailed {
                        depot_id: failure.depot_id,
                        error: message.clone(),
                    })
                    .await;
                    depot_reports.push(DepotReport {
                        depot_id: failure.depot_id,
                        manifest_gid: failure.manifest_gid,
                        files: 0,
                        bytes_total: 0,
                        downloaded_bytes: 0,
                        error: Some(message),
                    });
                    // A failed depot never takes down its siblings.
                }
            }
        }

        let report = DownloadReport {
            app_id,
            depots: depot_reports,
            downloaded_bytes: self.total_downloaded.load(Ordering::Relaxed),
            uncompressed_bytes: self.total_uncompressed.load(Ordering::Relaxed),
            duration: started.elapsed(),
        };
        self.emit(ProgressEvent::Finished {
            report: report.clone(),
        })
        .await;
        Ok(report)
    }

    async fn download_depot(
        &self,
        client: &CdnClient,
        state: &StateStore,
        spec: DepotSpec,
    ) -> std::result::Result<DepotOutcome, DepotFailure> {
        let before_ids = |error: Error| DepotFailure {
            depot_id: None,
            manifest_gid: None,
            error,
        };

        // 1. Manifest bytes → parsed manifest. Owned input: nothing is cloned here.
        let manifest_bytes: Vec<u8> = match spec.manifest {
            ManifestSource::File(path) => tokio::fs::read(&path)
                .await
                .map_err(Error::io_path(&path))
                .map_err(before_ids)?,
            ManifestSource::Bytes(bytes) => bytes,
        };
        if manifest_bytes.is_empty() {
            return Err(before_ids(Error::Manifest("manifest is empty".to_owned())));
        }
        let mut manifest = DepotManifest::from_bytes(&manifest_bytes).map_err(before_ids)?;

        // Depot id and manifest gid always come from the manifest's own metadata.
        let depot_id = manifest.depot_id();
        let manifest_gid = manifest.manifest_gid();

        self.emit(ProgressEvent::ManifestLoaded {
            depot_id,
            manifest_gid,
            creation_unix: manifest.creation_unix(),
        })
        .await;

        // Everything past this point knows the depot's identity - failures carry it.
        let result: Result<DepotOutcome> = async {
            // 2. Depot key - paired with the manifest in the request (never asked from Steam).
            let key = spec.key;
            if manifest.filenames_encrypted() {
                manifest.decrypt_filenames_with(&key)?;
            }
            if self.cancel.is_cancelled() {
                return Err(Error::Cancelled);
            }

            // 3. Previous-install state drives the verify/reuse strategy.
            let installed_gid = state.installed_gid(depot_id);
            let same_manifest = installed_gid == Some(manifest_gid);
            let old_manifest: Option<DepotManifest> = if same_manifest {
                // Same gid → Steam-style verify. No cached "old" manifest is consulted, so every
                // chunk of every existing file is verified against the manifest below.
                None
            } else {
                state
                    .cached_manifest_bytes(depot_id)
                    .and_then(|(gid, bytes)| {
                        if gid == manifest_gid {
                            return None;
                        }
                        let mut old = DepotManifest::from_bytes(&bytes).ok()?;
                        if old.filenames_encrypted() {
                            old.decrypt_filenames_with(&key).ok()?;
                        }
                        Some(old)
                    })
            };
            let old_by_path: HashMap<&str, &ManifestFile> = old_manifest
                .as_ref()
                .map(|m| m.files().iter().map(|f| (f.path.as_str(), f)).collect())
                .unwrap_or_default();

            let files = manifest.into_files();
            let content_files: Vec<&ManifestFile> = files
                .iter()
                .filter(|f| !f.is_directory() && !f.is_symlink())
                .collect();
            let files_total = content_files.len();
            let bytes_total: u64 = content_files.iter().map(|f| f.size).sum();

            self.emit(ProgressEvent::DepotStarted {
                depot_id,
                manifest_gid,
                files_total,
                bytes_total,
            })
            .await;

            // 4. Directory entries.
            for file in &files {
                if !file.is_directory() {
                    continue;
                }
                if let Some(rel) = util::safe_relative_path(&file.path) {
                    let dir = self.request.output_dir.join(rel);
                    tokio::fs::create_dir_all(&dir)
                        .await
                        .map_err(Error::io_path(&dir))?;
                }
            }

            // 5. Files concurrently; network concurrency is capped by the semaphore.
            let ctx = DepotCtx {
                client,
                depot_id,
                key,
                staging_dir: state.staging_dir(),
                same_manifest,
                old_by_path,
                depot_cancel: self.cancel.child_token(),
                depot_bytes_completed: Arc::new(AtomicU64::new(0)),
                depot_downloaded: Arc::new(AtomicU64::new(0)),
                depot_bytes_total: bytes_total,
                downloads_sem: Arc::new(Semaphore::new(self.request.max_downloads)),
                files_sem: Arc::new(Semaphore::new(
                    (self.request.max_downloads * 4).clamp(32, 64),
                )),
            };

            let mut tasks = FuturesUnordered::new();
            for file in content_files {
                tasks.push(self.execute_file(&ctx, file));
            }

            let mut first_error: Option<Error> = None;
            while let Some(result) = tasks.next().await {
                if let Err(error) = result
                    && first_error.is_none()
                {
                    first_error = Some(error);
                    // Point every other file task at the exit; they observe the token at their
                    // next chunk/plan boundary and unwind quickly.
                    ctx.depot_cancel.cancel();
                }
                // Keep draining so all in-flight futures settle before we return.
            }
            if let Some(error) = first_error {
                return Err(error);
            }

            Ok(DepotOutcome {
                depot_id,
                manifest_gid,
                files: files_total,
                bytes_total,
                downloaded_bytes: ctx.depot_downloaded.load(Ordering::Relaxed),
                manifest_bytes,
            })
        }
        .await;

        result.map_err(|error| DepotFailure {
            depot_id: Some(depot_id),
            manifest_gid: Some(manifest_gid),
            error,
        })
    }

    pub(super) async fn emit(&self, event: ProgressEvent) {
        let _ = self.events.send(event).await;
    }

    pub(super) fn emit_best_effort(&self, event: ProgressEvent) {
        let _ = self.events.try_send(event);
    }
}

//! File and chunk download execution worker.

use std::path::PathBuf;
use std::sync::atomic::{AtomicU64, Ordering};
use std::sync::{Arc, Mutex};

use futures::stream::{FuturesUnordered, StreamExt};

use super::io::{read_at, write_at};
use super::planner::{PlanInput, plan_file, staging_name};
use super::{DepotCtx, DownloadEngine};
use crate::cdn::chunk;
use crate::error::{Error, Result};
use crate::manifest::{ManifestChunk, ManifestFile};
use crate::progress::ProgressEvent;
use crate::util;

/// Everything one chunk download needs; handed to [`DownloadEngine::download_chunk`].
struct ChunkJob {
    file_handle: Arc<Mutex<Option<std::fs::File>>>,
    done_bytes: Arc<AtomicU64>,
    display_path: PathBuf,
    file_size: u64,
    chunk: ManifestChunk,
}

impl DownloadEngine {
    /// Plan + execute one content file of a depot.
    pub(super) async fn execute_file(&self, ctx: &DepotCtx<'_>, file: &ManifestFile) -> Result<()> {
        let _file_permit = ctx
            .files_sem
            .acquire()
            .await
            .map_err(|e| Error::TaskFailed(e.to_string()))?;

        if ctx.depot_cancel.is_cancelled() || self.cancel.is_cancelled() {
            return Err(Error::Cancelled);
        }

        let rel = util::safe_relative_path(&file.path).ok_or_else(|| {
            Error::Manifest(format!(
                "unsafe or empty file path '{}' in manifest",
                file.path
            ))
        })?;
        let final_path = self.request.output_dir.join(&rel);
        let display_path = rel.clone();

        if std::fs::metadata(&final_path).is_ok() {
            self.emit(ProgressEvent::FileVerifying {
                depot_id: ctx.depot_id,
                path: display_path.clone(),
            })
            .await;
        }

        self.emit(ProgressEvent::FileStarted {
            depot_id: ctx.depot_id,
            path: display_path.clone(),
            size: file.size,
        })
        .await;

        // Plan (blocking: reads on-disk bytes for chunk verification).
        let plan = {
            let plan_input = PlanInput {
                final_path: final_path.clone(),
                size: file.size,
                chunks: file.chunks.clone(),
                old_chunks: ctx
                    .old_by_path
                    .get(file.path.as_str())
                    .map(|e| e.chunks.clone()),
                old_entry_matches: !ctx.same_manifest
                    && ctx.old_by_path.get(file.path.as_str()).is_some_and(|e| {
                        e.size == file.size
                            && e.sha_content.is_some()
                            && e.sha_content == file.sha_content
                    }),
                verify_all: ctx.same_manifest,
            };
            tokio::task::spawn_blocking(move || plan_file(plan_input))
                .await
                .map_err(|e| Error::TaskFailed(e.to_string()))??
        };

        if plan.skip {
            let prev = ctx
                .depot_bytes_completed
                .fetch_add(file.size, Ordering::Relaxed);
            self.emit(ProgressEvent::FileCompleted {
                depot_id: ctx.depot_id,
                path: display_path,
                depot_bytes_completed: prev + file.size,
                depot_bytes_total: ctx.depot_bytes_total,
            })
            .await;
            return Ok(());
        }

        if ctx.depot_cancel.is_cancelled() || self.cancel.is_cancelled() {
            return Err(Error::Cancelled);
        }

        let write_path = if plan.staging {
            ctx.staging_dir.join(staging_name(&rel))
        } else {
            final_path.clone()
        };

        // Prepare the write target (blocking).
        let file_handle: Arc<Mutex<Option<std::fs::File>>> = {
            let write_path = write_path.clone();
            let fresh = plan.staging || plan.fresh;
            let size = file.size;
            let opened = tokio::task::spawn_blocking(move || -> Result<std::fs::File> {
                if let Some(parent) = write_path.parent() {
                    std::fs::create_dir_all(parent).map_err(Error::io_path(parent))?;
                }
                let file = if fresh {
                    std::fs::File::create(&write_path).map_err(Error::io_path(&write_path))?
                } else {
                    std::fs::OpenOptions::new()
                        .read(true)
                        .write(true)
                        .create(true)
                        .truncate(false)
                        .open(&write_path)
                        .map_err(Error::io_path(&write_path))?
                };
                if fresh {
                    file.set_len(size).map_err(Error::io_path(&write_path))?;
                }
                Ok(file)
            })
            .await
            .map_err(|e| Error::TaskFailed(e.to_string()))??;
            Arc::new(Mutex::new(Some(opened)))
        };

        let done_bytes = Arc::new(AtomicU64::new(plan.reused_bytes));

        // Copy reused chunks into staging (sequential local IO).
        if !plan.copies.is_empty() {
            let copies = plan.copies.clone();
            let source_path = final_path.clone();
            let handle = Arc::clone(&file_handle);
            let done = Arc::clone(&done_bytes);
            tokio::task::spawn_blocking(move || -> Result<()> {
                let source =
                    std::fs::File::open(&source_path).map_err(Error::io_path(&source_path))?;
                for op in copies {
                    let mut buf = vec![0u8; op.chunk.len_uncompressed as usize];
                    read_at(&source, &mut buf, op.source_offset).map_err(Error::Io)?;
                    {
                        let mut guard = handle.lock().expect("file handle mutex");
                        let f = guard.as_mut().expect("file handle open");
                        write_at(f, &buf, op.chunk.offset).map_err(Error::Io)?;
                    }
                    done.fetch_add(u64::from(op.chunk.len_uncompressed), Ordering::Relaxed);
                }
                Ok(())
            })
            .await
            .map_err(|e| Error::TaskFailed(e.to_string()))??;
        }

        // Download the remaining chunks.
        let mut jobs = FuturesUnordered::new();
        for chunk in plan.downloads {
            if ctx.depot_cancel.is_cancelled() || self.cancel.is_cancelled() {
                return Err(Error::Cancelled);
            }
            jobs.push(self.download_chunk(
                ctx,
                ChunkJob {
                    file_handle: Arc::clone(&file_handle),
                    done_bytes: Arc::clone(&done_bytes),
                    display_path: display_path.clone(),
                    file_size: file.size,
                    chunk,
                },
            ));
        }
        while let Some(result) = jobs.next().await {
            result?;
        }

        // Finalize (blocking): correct the length, swap staging over the final path,
        // apply executable bits.
        {
            let write_path = write_path.clone();
            let handle = Arc::clone(&file_handle);
            let is_staging = plan.staging;
            let size = file.size;
            let exec = file.is_executable();
            tokio::task::spawn_blocking(move || -> Result<()> {
                {
                    let mut guard = handle.lock().expect("file handle mutex");
                    if let Some(f) = guard.as_mut() {
                        let meta = f.metadata().map_err(Error::Io)?;
                        if meta.len() != size {
                            f.set_len(size).map_err(Error::Io)?;
                        }
                    }
                    *guard = None; // close before the rename
                }
                if is_staging {
                    if final_path.exists() {
                        std::fs::remove_file(&final_path).map_err(Error::io_path(&final_path))?;
                    }
                    std::fs::rename(&write_path, &final_path)
                        .map_err(Error::io_path(&final_path))?;
                }
                #[cfg(unix)]
                if exec {
                    use std::os::unix::fs::PermissionsExt;
                    let meta =
                        std::fs::metadata(&final_path).map_err(Error::io_path(&final_path))?;
                    let mut perms = meta.permissions();
                    perms.set_mode(perms.mode() | 0o111);
                    std::fs::set_permissions(&final_path, perms)
                        .map_err(Error::io_path(&final_path))?;
                }
                Ok(())
            })
            .await
            .map_err(|e| Error::TaskFailed(e.to_string()))??;
        }

        let prev = ctx
            .depot_bytes_completed
            .fetch_add(file.size, Ordering::Relaxed);
        self.emit(ProgressEvent::FileCompleted {
            depot_id: ctx.depot_id,
            path: display_path,
            depot_bytes_completed: prev + file.size,
            depot_bytes_total: ctx.depot_bytes_total,
        })
        .await;
        Ok(())
    }

    /// Fetch, decrypt, verify and write a single chunk.
    async fn download_chunk(&self, ctx: &DepotCtx<'_>, job: ChunkJob) -> Result<()> {
        let ChunkJob {
            file_handle,
            done_bytes,
            display_path,
            file_size,
            chunk,
        } = job;

        if ctx.depot_cancel.is_cancelled() || self.cancel.is_cancelled() {
            return Err(Error::Cancelled);
        }

        let _permit = Arc::clone(&ctx.downloads_sem)
            .acquire_owned()
            .await
            .map_err(|e| Error::TaskFailed(e.to_string()))?;

        if ctx.depot_cancel.is_cancelled() || self.cancel.is_cancelled() {
            return Err(Error::Cancelled);
        }

        let chunk_hex = util::to_hex_lower(&chunk.id);
        let mut last_error: Option<Error> = None;

        for chunk_attempt in 0..3 {
            if ctx.depot_cancel.is_cancelled() || self.cancel.is_cancelled() {
                return Err(Error::Cancelled);
            }

            let fetch = ctx.client.fetch_chunk(
                ctx.depot_id,
                &chunk_hex,
                chunk.len_compressed,
                &ctx.depot_cancel,
            );
            // Cancellation must also cut short an in-flight request, not just the gaps between
            // attempts - a hanging CDN must never delay a `cancel()` by the request timeout.
            let raw = tokio::select! {
                biased;
                _ = ctx.depot_cancel.cancelled() => return Err(Error::Cancelled),
                _ = self.cancel.cancelled() => return Err(Error::Cancelled),
                result = fetch => result?,
            };
            let network_len = raw.len() as u64;

            // Decrypt + verify + write (blocking).
            let key = ctx.key;
            let offset = chunk.offset;
            let handle = Arc::clone(&file_handle);
            let chunk_hex_clone = chunk_hex.clone();
            let process_result = tokio::task::spawn_blocking(move || -> Result<()> {
                let data = chunk::process_chunk(
                    &raw,
                    &key,
                    chunk.len_uncompressed,
                    chunk.adler32,
                    &chunk_hex_clone,
                )?;
                let mut guard = handle.lock().expect("file handle mutex");
                let f = guard.as_mut().expect("file handle open");
                write_at(f, &data, offset).map_err(Error::Io)?;
                Ok(())
            })
            .await
            .map_err(|e| Error::TaskFailed(e.to_string()))?;

            match process_result {
                Ok(()) => {
                    let downloaded = self
                        .total_downloaded
                        .fetch_add(network_len, Ordering::Relaxed)
                        + network_len;
                    let uncompressed = self
                        .total_uncompressed
                        .fetch_add(u64::from(chunk.len_uncompressed), Ordering::Relaxed)
                        + u64::from(chunk.len_uncompressed);
                    ctx.depot_downloaded
                        .fetch_add(network_len, Ordering::Relaxed);
                    let file_done = done_bytes
                        .fetch_add(u64::from(chunk.len_uncompressed), Ordering::Relaxed)
                        + u64::from(chunk.len_uncompressed);

                    self.emit_best_effort(ProgressEvent::ChunkCompleted {
                        depot_id: ctx.depot_id,
                        path: display_path,
                        file_bytes_completed: file_done,
                        file_size,
                        downloaded_increment: network_len,
                        uncompressed_increment: u64::from(chunk.len_uncompressed),
                        total_downloaded: downloaded,
                        total_uncompressed: uncompressed,
                    });
                    return Ok(());
                }
                Err(error) if error.rotates_cdn_server() && chunk_attempt + 1 < 3 => {
                    last_error = Some(error);
                    continue;
                }
                Err(fatal) => return Err(fatal),
            }
        }

        Err(last_error.unwrap_or(Error::Cancelled))
    }
}

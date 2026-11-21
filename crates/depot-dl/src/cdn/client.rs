//! CDN HTTP client: chunk/manifest GETs with DepotDownloader's retry matrix
//! (timeouts & 5xx rotate servers; 401/403/404 are terminal for the depot).

use std::sync::Arc;
use std::sync::atomic::{AtomicUsize, Ordering};

use tokio_util::sync::CancellationToken;

use crate::cdn::CdnServer;
use crate::error::{Error, Result};

/// Round-robin CDN client shared by all download tasks of a run.
pub(crate) struct CdnClient {
    http: reqwest::Client,
    servers: Vec<CdnServer>,
    cursor: Arc<AtomicUsize>,
}

impl CdnClient {
    pub(crate) fn new(http: reqwest::Client, servers: Vec<CdnServer>, app_id: u32) -> Result<Self> {
        let servers: Vec<CdnServer> = servers
            .into_iter()
            .filter(|server| server.serves_app(app_id))
            .collect();
        if servers.is_empty() {
            return Err(Error::NoCdnServers);
        }
        Ok(CdnClient {
            http,
            servers,
            cursor: Arc::new(AtomicUsize::new(0)),
        })
    }

    pub(crate) fn server_count(&self) -> usize {
        self.servers.len()
    }

    /// Download a chunk, rotating through every known server once.
    ///
    /// Retry semantics (mirroring DepotDownloader):
    /// - timeout / connect failure / HTTP 408/429/5xx → try next server;
    /// - HTTP 401/403/404 → fatal (`Error::HttpStatus`); this crate cannot mint CDN auth
    ///   tokens (that requires a CM session which does not exist here);
    /// - wrong length → treated as a corrupt server response → next server;
    /// - decryption/checksum failures are decided by the caller ([`super::chunk`]), which the
    ///   engine treats as rotatable as well.
    pub(crate) async fn fetch_chunk(
        &self,
        depot_id: u32,
        chunk_id_hex: &str,
        expected_compressed_len: u32,
        cancel: &CancellationToken,
    ) -> Result<Vec<u8>> {
        let count = self.servers.len();
        let start = self.cursor.fetch_add(1, Ordering::Relaxed) % count;
        let mut last_error: Option<Error> = None;
        let mut consecutive_errors: u32 = 0;

        // Allow multiple passes across known CDN edge servers (min 8, max 32 attempts)
        let max_attempts = (count * 3).clamp(8, 32);

        for attempt in 0..max_attempts {
            if cancel.is_cancelled() {
                return Err(Error::Cancelled);
            }

            // Exponential backoff after repeated errors: 250ms, 500ms, 1s, 2s, 4s max
            if consecutive_errors >= 2 {
                let shift = (consecutive_errors - 2).min(4);
                let backoff_ms = (250u64 * (1 << shift)).min(4000);
                tokio::select! {
                    biased;
                    _ = cancel.cancelled() => return Err(Error::Cancelled),
                    _ = tokio::time::sleep(std::time::Duration::from_millis(backoff_ms)) => {}
                }
            }

            let server = &self.servers[(start + attempt) % count];
            let url = server.chunk_url(depot_id, chunk_id_hex);

            match self.get(&url).await {
                Ok(bytes) => {
                    if expected_compressed_len != 0
                        && bytes.len() != expected_compressed_len as usize
                    {
                        last_error = Some(Error::Chunk {
                            chunk_id: chunk_id_hex.to_owned(),
                            reason: format!(
                                "expected {expected_compressed_len} compressed bytes, got {}",
                                bytes.len()
                            ),
                        });
                        consecutive_errors += 1;
                        continue;
                    }
                    return Ok(bytes);
                }
                Err(error) if error.rotates_cdn_server() => {
                    last_error = Some(error);
                    consecutive_errors += 1;
                    continue;
                }
                Err(fatal) => return Err(fatal),
            }
        }

        Err(last_error.unwrap_or(Error::NoCdnServers))
    }

    async fn get(&self, url: &str) -> Result<Vec<u8>> {
        let response = self.http.get(url).send().await?;
        let status = response.status();
        if !status.is_success() {
            return Err(Error::HttpStatus {
                status: status.as_u16(),
                url: url.to_owned(),
            });
        }
        Ok(response.bytes().await?.to_vec())
    }
}

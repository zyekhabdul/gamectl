//! End-to-end tests against a fake CDN ([`wiremock`]): fresh download, Steam-style verify
//! re-run, chunk-reuse update, per-depot failure isolation, and cancellation. No Steam
//! connectivity involved - the wire format is byte-identical to the real CDN's.

use std::path::Path;
use std::time::Duration;

use prost::Message;
use wiremock::matchers::{method, path};
use wiremock::{Mock, MockServer, ResponseTemplate};

use crate::cdn::CdnServer;
use crate::cdn::chunk::tests::{PackMode, pack_chunk};
use crate::config::DownloadRequest;
use crate::error::Error;
use crate::manifest::parse::tests::TEST_DEPOT_KEY;
use crate::progress::{DownloadReport, ProgressEvent};
use crate::state::StateStore;
use crate::util;

const APP_ID: u32 = 480;
const DEPOT_ID: u32 = 481;
const CHUNK_SIZE: usize = 128 * 1024;

/// The fixture key as the API receives it: a 64-character hex string.
fn test_key_hex() -> String {
    util::to_hex_lower(&TEST_DEPOT_KEY)
}

// ── fixture construction ─────────────────────────────────────────────────

/// Steam's chunk encryption + compression, as served by the CDN (see [`crate::cdn::chunk`]).
fn served_chunk(
    content: &[u8],
) -> (
    steam_protobuf_rs::content_manifest_payload::file_mapping::ChunkData,
    Vec<u8>,
) {
    use steam_protobuf_rs::content_manifest_payload::file_mapping::ChunkData;
    let body = pack_chunk(content, &TEST_DEPOT_KEY, PackMode::Zstd);
    let chunk = ChunkData {
        sha: Some(util::sha1(content).to_vec()),
        crc: Some(util::adler32_seed0(content)),
        offset: Some(0),
        cb_original: Some(content.len() as u32),
        cb_compressed: Some(body.len() as u32),
    };
    (chunk, body)
}

fn chunks_with_offsets(
    content: &[u8],
) -> Vec<(
    steam_protobuf_rs::content_manifest_payload::file_mapping::ChunkData,
    Vec<u8>,
)> {
    let mut offset = 0u64;
    content
        .chunks(CHUNK_SIZE)
        .map(|slice| {
            let (mut chunk, body) = served_chunk(slice);
            chunk.offset = Some(offset);
            offset += u64::from(chunk.cb_original.expect("cb_original"));
            (chunk, body)
        })
        .collect()
}

fn build_manifest(depot_id: u32, gid: u64, files: &[(&str, Vec<u8>, u32)]) -> Vec<u8> {
    use crate::manifest::parse::{EOF_MAGIC, METADATA_MAGIC, PAYLOAD_MAGIC, SIGNATURE_MAGIC};
    use steam_protobuf_rs::content_manifest_payload::FileMapping;
    use steam_protobuf_rs::{
        ContentManifestMetadata, ContentManifestPayload, ContentManifestSignature,
    };

    let mut mappings = Vec::new();
    for (name, content, flags) in files {
        let (chunks, size) = if content.is_empty() {
            (Vec::new(), 0)
        } else {
            let pairs = chunks_with_offsets(content);
            let size = pairs
                .iter()
                .map(|(c, _)| u64::from(c.cb_original.expect("cb_original")))
                .sum();
            (pairs.into_iter().map(|(c, _)| c).collect(), size)
        };
        mappings.push(FileMapping {
            filename: Some((*name).to_owned()),
            size: Some(size),
            flags: Some(*flags),
            sha_filename: Some(vec![0; 20]),
            sha_content: Some(util::sha1(content).to_vec()),
            chunks,
            linktarget: None,
        });
    }

    let payload = ContentManifestPayload { mappings };
    let metadata = ContentManifestMetadata {
        depot_id: Some(depot_id),
        gid_manifest: Some(gid),
        creation_time: Some(1_700_000_000),
        filenames_encrypted: Some(false),
        cb_disk_original: None,
        cb_disk_compressed: None,
        unique_chunks: None,
        crc_encrypted: None,
        crc_clear: None,
    };
    let signature = ContentManifestSignature {
        signature: Some(vec![9; 8]),
    };

    let mut out = Vec::new();
    let payload_bytes = payload.encode_to_vec();
    let metadata_bytes = metadata.encode_to_vec();
    let signature_bytes = signature.encode_to_vec();
    for (magic, bytes) in [
        (PAYLOAD_MAGIC, &payload_bytes),
        (METADATA_MAGIC, &metadata_bytes),
        (SIGNATURE_MAGIC, &signature_bytes),
    ] {
        out.extend_from_slice(&magic.to_le_bytes());
        out.extend_from_slice(&(bytes.len() as u32).to_le_bytes());
        out.extend_from_slice(bytes);
    }
    out.extend_from_slice(&EOF_MAGIC.to_le_bytes());
    out
}

/// Write the manifest bytes to a real file (the public API is path-based) and download it.
async fn run_download(
    out: &Path,
    manifest: Vec<u8>,
    key_hex: &str,
    server_addr: String,
) -> DownloadReport {
    let downloader = crate::DepotDownloader::builder()
        .cdn_servers(vec![CdnServer::http(&server_addr).expect("address")])
        .build()
        .expect("downloader");
    let request = DownloadRequest::builder()
        .app_id(APP_ID)
        .depots([(manifest, key_hex)])
        .output_dir(out)
        .build()
        .expect("request");
    let mut handle = downloader.download(request);
    while let Some(event) = handle.events().recv().await {
        if matches!(event, ProgressEvent::Finished { .. }) {
            break;
        }
    }
    handle.join().await.expect("join")
}

async fn mount_chunks(
    server: &MockServer,
    depot_id: u32,
    served: &[(
        steam_protobuf_rs::content_manifest_payload::file_mapping::ChunkData,
        Vec<u8>,
    )],
) {
    for (chunk, body) in served {
        let hex = util::to_hex_lower(chunk.sha.as_ref().expect("sha"));
        Mock::given(method("GET"))
            .and(path(format!("/depot/{depot_id}/chunk/{hex}")))
            .respond_with(ResponseTemplate::new(200).set_body_bytes(body.clone()))
            .mount(server)
            .await;
    }
}

// ── tests ────────────────────────────────────────────────────────────────

#[tokio::test]
async fn fresh_download_then_verify_rerun_downloads_nothing() {
    let server = MockServer::start().await;
    let content: Vec<u8> = (0..2 * CHUNK_SIZE + 12_345)
        .map(|i| (i % 251) as u8)
        .collect();
    let v1 = build_manifest(
        DEPOT_ID,
        1000,
        &[
            ("bin/game.exe", content.clone(), 32),
            ("readme.txt", Vec::new(), 0),
        ],
    );
    mount_chunks(&server, DEPOT_ID, &chunks_with_offsets(&content)).await;

    let out = tempfile::tempdir().expect("tempdir");
    let report = run_download(
        out.path(),
        v1.clone(),
        &test_key_hex(),
        server.address().to_string(),
    )
    .await;
    assert!(report.is_ok(), "depots: {:?}", report.depots);
    assert_eq!(
        std::fs::read(out.path().join("bin/game.exe")).expect("game.exe"),
        content
    );
    assert_eq!(
        std::fs::metadata(out.path().join("readme.txt"))
            .expect("readme.txt")
            .len(),
        0
    );

    let state = StateStore::load(out.path());
    assert_eq!(state.installed_gid(DEPOT_ID), Some(1000));

    // Re-run with the SAME manifest: full Steam-style verification, zero network. The new
    // server has no chunk mocks - any wrongful re-download turns into a 404 and fails.
    let server2 = MockServer::start().await;
    let report = run_download(
        out.path(),
        v1,
        &test_key_hex(),
        server2.address().to_string(),
    )
    .await;
    assert!(report.is_ok(), "depots: {:?}", report.depots);
    assert_eq!(report.downloaded_bytes, 0, "verify must not re-download");
    assert_eq!(
        std::fs::read(out.path().join("bin/game.exe")).expect("game.exe"),
        content
    );
}

#[tokio::test]
async fn update_downloads_only_changed_chunks_and_keeps_foreign_files() {
    let server1 = MockServer::start().await;
    let v1_content: Vec<u8> = (0..3 * CHUNK_SIZE).map(|i| (i % 199) as u8).collect();
    let pak_content: Vec<u8> = (0..2 * CHUNK_SIZE).map(|i| (i % 61) as u8).collect();
    let v1 = build_manifest(
        DEPOT_ID,
        2000,
        &[
            ("bin/game.exe", v1_content.clone(), 32),
            ("data/pak.bin", pak_content.clone(), 0),
        ],
    );
    mount_chunks(&server1, DEPOT_ID, &chunks_with_offsets(&v1_content)).await;
    mount_chunks(&server1, DEPOT_ID, &chunks_with_offsets(&pak_content)).await;

    let out = tempfile::tempdir().expect("tempdir");
    let report = run_download(
        out.path(),
        v1,
        &test_key_hex(),
        server1.address().to_string(),
    )
    .await;
    assert!(report.is_ok(), "depots: {:?}", report.depots);

    // A file that is NOT in any manifest: must survive every download untouched.
    std::fs::create_dir_all(out.path().join("mods")).expect("mods dir");
    std::fs::write(out.path().join("mods/extra.ini"), b"keep me").expect("mods file");

    // v2: one additional chunk on game.exe; pak.bin unchanged (same SHA-1 → skipped unread).
    let mut v2_content = v1_content.clone();
    v2_content.extend((0..CHUNK_SIZE).map(|i| (i % 71) as u8));
    let v2 = build_manifest(
        DEPOT_ID,
        2001,
        &[
            ("bin/game.exe", v2_content.clone(), 32),
            ("data/pak.bin", pak_content.clone(), 0),
        ],
    );

    // Only the NEW chunk is served. Any reuse failure → 404 → depot failure → test fails.
    let server2 = MockServer::start().await;
    let v2_chunks = chunks_with_offsets(&v2_content);
    let (new_chunk, new_body) = v2_chunks.last().expect("new chunk").clone();
    mount_chunks(&server2, DEPOT_ID, &[(new_chunk, new_body)]).await;

    let report = run_download(
        out.path(),
        v2,
        &test_key_hex(),
        server2.address().to_string(),
    )
    .await;
    assert!(report.is_ok(), "depots: {:?}", report.depots);
    assert_eq!(
        std::fs::read(out.path().join("bin/game.exe")).expect("game.exe"),
        v2_content
    );
    assert_eq!(
        std::fs::read(out.path().join("data/pak.bin")).expect("pak.bin"),
        pak_content
    );
    assert_eq!(
        std::fs::read(out.path().join("mods/extra.ini")).expect("extra.ini"),
        b"keep me"
    );

    let state = StateStore::load(out.path());
    assert_eq!(state.installed_gid(DEPOT_ID), Some(2001));
}

#[tokio::test]
async fn wrong_key_fails_only_that_depot() {
    // Two depots in one request; the second one's key is wrong. The first must still
    // succeed - per-depot failure isolation.
    let server = MockServer::start().await;
    let good_content: Vec<u8> = (0..CHUNK_SIZE).map(|i| (i % 199) as u8).collect();
    let good = build_manifest(481, 3000, &[("bin/ok.exe", good_content.clone(), 32)]);
    let bad = build_manifest(482, 3001, &[("bin/broken.exe", b"irrelevant".to_vec(), 0)]);

    mount_chunks(&server, 481, &chunks_with_offsets(&good_content)).await;
    // Depot 482's chunk URLs are unmocked → 404 → fatal for that depot only.

    let out = tempfile::tempdir().expect("tempdir");
    let downloader = crate::DepotDownloader::builder()
        .cdn_servers(vec![
            CdnServer::http(server.address().to_string().as_str()).expect("address"),
        ])
        .build()
        .expect("downloader");
    let request = DownloadRequest::builder()
        .app_id(APP_ID)
        .depots([
            (good, test_key_hex()),
            (bad, util::to_hex_lower(&[0x99; 32])), // wrong key
        ])
        .output_dir(out.path())
        .build()
        .expect("request");

    let mut handle = downloader.download(request);
    while let Some(event) = handle.events().recv().await {
        if matches!(event, ProgressEvent::Finished { .. }) {
            break;
        }
    }
    let report = handle.join().await.expect("join");

    assert_eq!(report.depots.len(), 2);
    let good_report = report
        .depots
        .iter()
        .find(|d| d.depot_id == Some(481))
        .expect("good depot reported");
    let bad_report = report
        .depots
        .iter()
        .find(|d| d.depot_id == Some(482))
        .expect("bad depot reported");
    assert!(
        good_report.is_ok(),
        "good depot must succeed: {:?}",
        good_report
    );
    assert!(bad_report.error.is_some(), "bad depot must fail");
    assert_eq!(
        std::fs::read(out.path().join("bin/ok.exe")).expect("ok.exe"),
        good_content
    );
}

#[tokio::test]
async fn cancel_stops_inflight_requests() {
    let server = MockServer::start().await;
    let content: Vec<u8> = (0..CHUNK_SIZE).map(|i| (i % 251) as u8).collect();
    let v1 = build_manifest(DEPOT_ID, 4000, &[("bin/game.exe", content.clone(), 32)]);
    for (chunk, body) in chunks_with_offsets(&content) {
        let hex = util::to_hex_lower(chunk.sha.as_ref().expect("sha"));
        Mock::given(method("GET"))
            .and(path(format!("/depot/{DEPOT_ID}/chunk/{hex}")))
            .respond_with(
                ResponseTemplate::new(200)
                    .set_body_bytes(body)
                    .set_delay(Duration::from_secs(120)),
            )
            .mount(&server)
            .await;
    }

    let out = tempfile::tempdir().expect("tempdir");

    let downloader = crate::DepotDownloader::builder()
        .cdn_servers(vec![
            CdnServer::http(server.address().to_string().as_str()).expect("address"),
        ])
        .build()
        .expect("downloader");
    let request = DownloadRequest::builder()
        .app_id(APP_ID)
        .depots([(v1, test_key_hex())])
        .output_dir(out.path())
        .build()
        .expect("request");

    let mut handle = downloader.download(request);
    // Wait until the engine is actually inside a chunk fetch.
    while let Some(event) = handle.events().recv().await {
        if matches!(event, ProgressEvent::FileStarted { .. }) {
            break;
        }
    }
    handle.cancel();

    let err = handle.join().await.expect_err("must be cancelled");
    assert!(matches!(err, Error::Cancelled), "was: {err}");
    let _ = content;
}

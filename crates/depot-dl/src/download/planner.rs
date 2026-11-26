//! Per-file chunk verification and reuse planning.

use std::collections::HashMap;
use std::path::{Path, PathBuf};

use super::io::read_at;
use crate::error::Result;
use crate::manifest::ManifestChunk;
use crate::util;

/// How a file's bytes are sourced.
#[derive(Default)]
pub(super) struct FilePlan {
    /// Chunks that must come from the network.
    pub(super) downloads: Vec<ManifestChunk>,
    /// Chunks verified on disk that must be copied to a (possibly new) offset in staging.
    pub(super) copies: Vec<CopyOp>,
    /// Bytes already known-good when the plan starts (drives per-file progress).
    pub(super) reused_bytes: u64,
    /// Nothing to do at all (content is provably identical to the previous install).
    pub(super) skip: bool,
    /// Rebuild through a staging file instead of patching in place.
    pub(super) staging: bool,
    /// Target does not exist yet → create + preallocate it fresh.
    pub(super) fresh: bool,
}

#[derive(Clone)]
pub(super) struct CopyOp {
    pub(super) chunk: ManifestChunk,
    pub(super) source_offset: u64,
}

/// Everything [`plan_file`] needs; owned so it can move into `spawn_blocking`.
pub(super) struct PlanInput {
    pub(super) final_path: PathBuf,
    pub(super) size: u64,
    pub(super) chunks: Vec<ManifestChunk>,
    pub(super) old_chunks: Option<Vec<ManifestChunk>>,
    pub(super) old_entry_matches: bool,
    pub(super) verify_all: bool,
}

/// Decide, for one file, which chunks can be reused from disk and which must be downloaded.
///
/// Pure filesystem work - runs inside `spawn_blocking`.
pub(super) fn plan_file(input: PlanInput) -> Result<FilePlan> {
    let PlanInput {
        final_path,
        size,
        chunks,
        old_chunks,
        old_entry_matches,
        verify_all,
    } = input;

    let existing_len = std::fs::metadata(&final_path)
        .ok()
        .filter(|m| m.is_file())
        .map(|m| m.len());

    // Empty content file: only the length differs from "nothing".
    if size == 0 || chunks.is_empty() {
        return Ok(match existing_len {
            Some(0) => FilePlan {
                skip: true,
                ..FilePlan::default()
            },
            Some(_) => FilePlan::default(), // exists, wrong size → finalize truncates
            None => FilePlan {
                fresh: true,
                ..FilePlan::default()
            },
        });
    }

    let Some(existing_len) = existing_len else {
        return Ok(FilePlan {
            downloads: chunks,
            fresh: true,
            ..FilePlan::default()
        });
    };

    // Fast path: the previous install's manifest says this file has identical content and the
    // on-disk length agrees → skip without reading a single byte.
    if old_entry_matches && existing_len == size {
        return Ok(FilePlan {
            skip: true,
            ..FilePlan::default()
        });
    }

    // Chunk-id reuse: when we know what the previous version looked like, reuse every on-disk
    // chunk whose (id, adler) matches a chunk of the new manifest. Reused chunks are copied
    // into a staging file (offsets may have moved), the rest is downloaded.
    if !verify_all
        && let Some(old_chunks) = &old_chunks
        && !old_chunks.is_empty()
    {
        return plan_reuse_from_old(&final_path, size, chunks, old_chunks, existing_len);
    }

    // Steam-style verification: read every chunk position and check it against the manifest.
    plan_verify_in_place(&final_path, chunks, existing_len)
}

fn plan_reuse_from_old(
    final_path: &Path,
    size: u64,
    chunks: Vec<ManifestChunk>,
    old_chunks: &[ManifestChunk],
    existing_len: u64,
) -> Result<FilePlan> {
    let _ = size;
    let mut new_by_id: HashMap<[u8; 20], Vec<usize>> = HashMap::new();
    for (index, chunk) in chunks.iter().enumerate() {
        new_by_id.entry(chunk.id).or_default().push(index);
    }

    let mut covered = vec![false; chunks.len()];
    let mut copies = Vec::new();

    // A bad/unreadable existing file simply degrades to a full download.
    let Ok(source) = std::fs::File::open(final_path) else {
        return Ok(FilePlan {
            downloads: chunks,
            fresh: true,
            ..FilePlan::default()
        });
    };

    for old_chunk in old_chunks {
        let Some(indices) = new_by_id.get(&old_chunk.id) else {
            continue;
        };
        if indices.is_empty() {
            continue;
        }
        if u64::from(old_chunk.len_uncompressed) == 0
            || old_chunk.offset + u64::from(old_chunk.len_uncompressed) > existing_len
        {
            continue;
        }
        let mut buf = vec![0u8; old_chunk.len_uncompressed as usize];
        if read_at(&source, &mut buf, old_chunk.offset).is_err() {
            continue;
        }
        if util::adler32_seed0(&buf) != old_chunk.adler32 {
            continue;
        }
        // This on-disk chunk is intact and matches new chunks with the same id.
        for &index in indices {
            if covered[index] {
                continue;
            }
            copies.push(CopyOp {
                chunk: chunks[index].clone(),
                source_offset: old_chunk.offset,
            });
            covered[index] = true;
        }
        new_by_id.insert(old_chunk.id, Vec::new());
    }

    let downloads: Vec<ManifestChunk> = chunks
        .iter()
        .enumerate()
        .filter(|(index, _)| !covered[*index])
        .map(|(_, chunk)| chunk.clone())
        .collect();
    let reused_bytes = copies
        .iter()
        .map(|op| u64::from(op.chunk.len_uncompressed))
        .sum();

    Ok(FilePlan {
        downloads,
        copies,
        reused_bytes,
        staging: true,
        ..FilePlan::default()
    })
}

fn plan_verify_in_place(
    final_path: &Path,
    chunks: Vec<ManifestChunk>,
    existing_len: u64,
) -> Result<FilePlan> {
    let mut downloads = Vec::new();
    let mut reused_bytes = 0u64;

    let source = std::fs::File::open(final_path).ok();
    for chunk in chunks {
        let readable =
            source.is_some() && chunk.offset + u64::from(chunk.len_uncompressed) <= existing_len;
        let ok = if let (Some(source), true) = (&source, readable) {
            let mut buf = vec![0u8; chunk.len_uncompressed as usize];
            read_at(source, &mut buf, chunk.offset).is_ok()
                && util::adler32_seed0(&buf) == chunk.adler32
        } else {
            false
        };
        if ok {
            reused_bytes += u64::from(chunk.len_uncompressed);
        } else {
            downloads.push(chunk);
        }
    }

    Ok(FilePlan {
        downloads,
        reused_bytes,
        ..FilePlan::default()
    })
}

/// Flat, collision-free staging file name for a manifest-relative path.
pub(super) fn staging_name(rel: &Path) -> PathBuf {
    PathBuf::from(format!(
        "{}.tmp",
        util::to_hex_lower(&util::sha1(rel.to_string_lossy().as_bytes()))
    ))
}

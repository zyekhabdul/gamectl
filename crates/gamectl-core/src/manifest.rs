use std::collections::HashMap;
use std::io::Read as _;

use flate2::read::ZlibDecoder;
use serde::Deserialize;
use sha1::{Digest as _, Sha1};

use crate::error::{CoreError, Result};

const BINARY_MANIFEST_MAGIC: u32 = 0x44BE_C00C;
const CHUNK_MAGIC: u32 = 0xB1FE_3AA2;

#[derive(Debug, Clone)]
pub struct ChunkInfo {
    pub guid: [u8; 16],
    pub guid_hex: String,
    pub hash: u64,
    pub sha_hash: [u8; 20],
    pub group_num: u8,
    pub window_size: u32,
    pub file_size: i64,
}

#[derive(Debug, Clone)]
pub struct ChunkPart {
    pub guid_hex: String,
    pub offset: u32,
    pub size: u32,
}

#[derive(Debug, Clone)]
pub struct FileEntry {
    pub filename: String,
    pub file_hash: [u8; 20],
    pub flags: u8,
    pub install_tags: Vec<String>,
    pub chunk_parts: Vec<ChunkPart>,
    pub file_size: u64,
}

#[derive(Debug, Clone)]
pub struct ParsedManifest {
    pub feature_level: u32,
    pub app_name: String,
    pub build_version: String,
    pub launch_exe: String,
    pub launch_command: String,
    pub chunks: HashMap<String, ChunkInfo>,
    pub files: Vec<FileEntry>,
}

impl ParsedManifest {
    pub fn total_download_size(&self) -> u64 {
        self.chunks
            .values()
            .filter_map(|c| u64::try_from(c.file_size).ok())
            .sum()
    }

    pub fn total_disk_size(&self) -> u64 {
        self.files.iter().map(|f| f.file_size).sum()
    }
}

struct Cursor<'a> {
    data: &'a [u8],
    pos: usize,
}

impl<'a> Cursor<'a> {
    fn new(data: &'a [u8]) -> Self {
        Self { data, pos: 0 }
    }

    fn remaining(&self) -> usize {
        self.data.len().saturating_sub(self.pos)
    }

    fn read_bytes(&mut self, n: usize) -> Result<&'a [u8]> {
        let end = self
            .pos
            .checked_add(n)
            .ok_or_else(|| CoreError::Manifest("offset overflow".to_string()))?;
        if end > self.data.len() {
            return Err(CoreError::Manifest(format!(
                "unexpected EOF reading {n} bytes at {}",
                self.pos
            )));
        }
        let slice = &self.data[self.pos..end];
        self.pos = end;
        Ok(slice)
    }

    fn read_u8(&mut self) -> Result<u8> {
        Ok(self.read_bytes(1)?[0])
    }

    fn read_u32(&mut self) -> Result<u32> {
        let b = self.read_bytes(4)?;
        Ok(u32::from_le_bytes([b[0], b[1], b[2], b[3]]))
    }

    fn read_i32(&mut self) -> Result<i32> {
        let b = self.read_bytes(4)?;
        Ok(i32::from_le_bytes([b[0], b[1], b[2], b[3]]))
    }

    fn read_u64(&mut self) -> Result<u64> {
        let b = self.read_bytes(8)?;
        Ok(u64::from_le_bytes([
            b[0], b[1], b[2], b[3], b[4], b[5], b[6], b[7],
        ]))
    }

    fn read_i64(&mut self) -> Result<i64> {
        let b = self.read_bytes(8)?;
        Ok(i64::from_le_bytes([
            b[0], b[1], b[2], b[3], b[4], b[5], b[6], b[7],
        ]))
    }

    fn read_guid(&mut self) -> Result<[u8; 16]> {
        let b = self.read_bytes(16)?;
        let mut out = [0u8; 16];
        out.copy_from_slice(b);
        Ok(out)
    }

    fn read_sha1(&mut self) -> Result<[u8; 20]> {
        let b = self.read_bytes(20)?;
        let mut out = [0u8; 20];
        out.copy_from_slice(b);
        Ok(out)
    }

    fn read_fstring(&mut self) -> Result<String> {
        let len = self.read_i32()?;
        if len == 0 {
            return Ok(String::new());
        }
        if len > 0 {
            let byte_len = usize::try_from(len)
                .map_err(|_| CoreError::Manifest("invalid positive FString length".to_string()))?;
            let raw = self.read_bytes(byte_len)?;
            let trimmed = raw.strip_suffix(&[0]).unwrap_or(raw);
            return Ok(String::from_utf8_lossy(trimmed).into_owned());
        }
        // Negative FString length denotes UTF-16LE code units
        let char_count = usize::try_from(len.unsigned_abs())
            .map_err(|_| CoreError::Manifest("invalid UTF-16 FString length".to_string()))?;
        let byte_len = char_count
            .checked_mul(2)
            .ok_or_else(|| CoreError::Manifest("UTF-16 length overflow".to_string()))?;
        let raw = self.read_bytes(byte_len)?;
        let mut units = Vec::with_capacity(char_count);
        for &[b0, b1] in raw.as_chunks::<2>().0 {
            units.push(u16::from_le_bytes([b0, b1]));
        }
        while units.last() == Some(&0) {
            units.pop();
        }
        Ok(String::from_utf16_lossy(&units))
    }
}

pub fn guid_to_epic_hex(guid: &[u8; 16]) -> String {
    // Epic encodes FGuid as four 32-bit big-endian-printed LE ints
    let mut out = String::with_capacity(32);
    for &chunk in guid.as_chunks::<4>().0 {
        let val = u32::from_le_bytes(chunk);
        out.push_str(&format!("{val:08X}"));
    }
    out
}

pub fn chunk_sub_dir(feature_level: u32) -> &'static str {
    if feature_level >= 15 {
        "ChunksV4"
    } else if feature_level >= 12 {
        "ChunksV3"
    } else if feature_level >= 9 {
        "ChunksV2"
    } else {
        "Chunks"
    }
}

pub fn chunk_cdn_url(
    base_url: &str,
    cloud_dir: &str,
    feature_level: u32,
    chunk: &ChunkInfo,
) -> String {
    let base = base_url.trim_end_matches('/');
    let cdir = cloud_dir.trim_matches('/');
    let sub = chunk_sub_dir(feature_level);
    let prefix = if cdir.is_empty() {
        format!("{base}/{sub}")
    } else {
        format!("{base}/{cdir}/{sub}")
    };
    format!(
        "{prefix}/{:02}/{:016X}_{}.chunk",
        chunk.group_num, chunk.hash, chunk.guid_hex
    )
}

pub fn parse_manifest_bytes(raw: &[u8]) -> Result<ParsedManifest> {
    if raw.len() >= 4
        && u32::from_le_bytes([raw[0], raw[1], raw[2], raw[3]]) == BINARY_MANIFEST_MAGIC
    {
        return parse_binary_manifest(raw);
    }
    let trimmed = raw
        .iter()
        .position(|b| !b.is_ascii_whitespace())
        .map(|idx| &raw[idx..])
        .unwrap_or(raw);
    if trimmed.starts_with(b"{") {
        return parse_json_manifest(trimmed);
    }
    Err(CoreError::Manifest(
        "unrecognized Epic manifest format (neither binary 0x44BEC00C nor JSON)".to_string(),
    ))
}

fn parse_binary_manifest(raw: &[u8]) -> Result<ParsedManifest> {
    let mut hdr = Cursor::new(raw);
    let magic = hdr.read_u32()?;
    if magic != BINARY_MANIFEST_MAGIC {
        return Err(CoreError::Manifest(
            "invalid binary manifest magic".to_string(),
        ));
    }
    let header_size = usize::try_from(hdr.read_u32()?)
        .map_err(|_| CoreError::Manifest("invalid header size".to_string()))?;
    let size_uncompressed = usize::try_from(hdr.read_u32()?)
        .map_err(|_| CoreError::Manifest("invalid uncompressed size".to_string()))?;
    let size_compressed = usize::try_from(hdr.read_u32()?)
        .map_err(|_| CoreError::Manifest("invalid compressed size".to_string()))?;
    let expected_sha = hdr.read_sha1()?;
    let stored_as = hdr.read_u8()?;
    let _version = hdr.read_u32()?;

    if header_size > raw.len() {
        return Err(CoreError::Manifest(
            "manifest header exceeds buffer".to_string(),
        ));
    }
    let payload_end = header_size
        .checked_add(size_compressed)
        .ok_or_else(|| CoreError::Manifest("compressed size overflow".to_string()))?;
    let body_slice = if payload_end <= raw.len() && size_compressed > 0 {
        &raw[header_size..payload_end]
    } else {
        &raw[header_size..]
    };

    let body = if (stored_as & 0x01) != 0 {
        let mut dec = ZlibDecoder::new(body_slice);
        let mut out = Vec::with_capacity(size_uncompressed);
        dec.read_to_end(&mut out)
            .map_err(|e| CoreError::Manifest(format!("manifest zlib inflate failed: {e}")))?;
        out
    } else {
        body_slice.to_vec()
    };

    let actual_sha: [u8; 20] = Sha1::digest(&body).into();
    if actual_sha != expected_sha {
        return Err(CoreError::Integrity(
            "manifest body SHA-1 does not match header shaHash".to_string(),
        ));
    }

    let mut pos = 0usize;
    let meta_slice = take_section(&body, &mut pos)?;
    let (feature_level, app_name, build_version, launch_exe, launch_command) =
        parse_manifest_meta(meta_slice)?;

    let cdl_slice = take_section(&body, &mut pos)?;
    let chunks = parse_cdl_section(cdl_slice)?;

    let fml_slice = take_section(&body, &mut pos)?;
    let files = parse_fml_section(fml_slice)?;

    Ok(ParsedManifest {
        feature_level,
        app_name,
        build_version,
        launch_exe,
        launch_command,
        chunks,
        files,
    })
}

fn take_section<'a>(body: &'a [u8], pos: &mut usize) -> Result<&'a [u8]> {
    if pos.saturating_add(4) > body.len() {
        return Err(CoreError::Manifest(
            "missing manifest section size".to_string(),
        ));
    }
    let sz =
        u32::from_le_bytes([body[*pos], body[*pos + 1], body[*pos + 2], body[*pos + 3]]) as usize;
    if sz < 4 || pos.saturating_add(sz) > body.len() {
        return Err(CoreError::Manifest(format!(
            "invalid manifest section size {sz} at offset {}",
            *pos
        )));
    }
    let sec = &body[*pos..*pos + sz];
    *pos += sz;
    Ok(sec)
}

fn parse_manifest_meta(sec: &[u8]) -> Result<(u32, String, String, String, String)> {
    let mut c = Cursor::new(sec);
    let _meta_size = c.read_u32()?;
    let _data_version = c.read_u8()?;
    let feature_level = c.read_u32()?;
    let _is_file_data = c.read_u8()?;
    let _app_id = c.read_u32()?;
    let app_name = c.read_fstring()?;
    let build_version = c.read_fstring()?;
    let launch_exe = c.read_fstring()?;
    let launch_command = c.read_fstring()?;
    Ok((
        feature_level,
        app_name,
        build_version,
        launch_exe,
        launch_command,
    ))
}

fn parse_cdl_section(sec: &[u8]) -> Result<HashMap<String, ChunkInfo>> {
    let mut c = Cursor::new(sec);
    let _cdl_size = c.read_u32()?;
    let _version = c.read_u8()?;
    let count = usize::try_from(c.read_u32()?)
        .map_err(|_| CoreError::Manifest("invalid CDL chunk count".to_string()))?;

    let mut guids = Vec::with_capacity(count);
    for _ in 0..count {
        guids.push(c.read_guid()?);
    }
    let mut hashes = Vec::with_capacity(count);
    for _ in 0..count {
        hashes.push(c.read_u64()?);
    }
    let mut shas = Vec::with_capacity(count);
    for _ in 0..count {
        shas.push(c.read_sha1()?);
    }
    let mut groups = Vec::with_capacity(count);
    for _ in 0..count {
        groups.push(c.read_u8()?);
    }
    let mut win_sizes = Vec::with_capacity(count);
    for _ in 0..count {
        win_sizes.push(c.read_u32()?);
    }
    let mut file_sizes = Vec::with_capacity(count);
    for _ in 0..count {
        file_sizes.push(c.read_i64()?);
    }

    let mut map = HashMap::with_capacity(count);
    for i in 0..count {
        let guid_hex = guid_to_epic_hex(&guids[i]);
        map.insert(
            guid_hex.clone(),
            ChunkInfo {
                guid: guids[i],
                guid_hex,
                hash: hashes[i],
                sha_hash: shas[i],
                group_num: groups[i],
                window_size: win_sizes[i],
                file_size: file_sizes[i],
            },
        );
    }
    Ok(map)
}

fn parse_fml_section(sec: &[u8]) -> Result<Vec<FileEntry>> {
    let mut c = Cursor::new(sec);
    let _fml_size = c.read_u32()?;
    let _version = c.read_u8()?;
    let count = usize::try_from(c.read_u32()?)
        .map_err(|_| CoreError::Manifest("invalid FML file count".to_string()))?;

    let mut filenames = Vec::with_capacity(count);
    for _ in 0..count {
        filenames.push(c.read_fstring()?);
    }
    let mut symlinks = Vec::with_capacity(count);
    for _ in 0..count {
        symlinks.push(c.read_fstring()?);
    }
    let mut shas = Vec::with_capacity(count);
    for _ in 0..count {
        shas.push(c.read_sha1()?);
    }
    let mut flags = Vec::with_capacity(count);
    for _ in 0..count {
        flags.push(c.read_u8()?);
    }
    let mut install_tags = Vec::with_capacity(count);
    for _ in 0..count {
        let tcount = usize::try_from(c.read_u32()?)
            .map_err(|_| CoreError::Manifest("invalid install_tags count".to_string()))?;
        let mut tags = Vec::with_capacity(tcount);
        for _ in 0..tcount {
            tags.push(c.read_fstring()?);
        }
        install_tags.push(tags);
    }

    let mut chunk_parts_list = Vec::with_capacity(count);
    for _ in 0..count {
        let pcount = usize::try_from(c.read_u32()?)
            .map_err(|_| CoreError::Manifest("invalid chunk_parts count".to_string()))?;
        let mut parts = Vec::with_capacity(pcount);
        for _ in 0..pcount {
            let part_sz = c.read_u32()?;
            let guid = c.read_guid()?;
            let offset = c.read_u32()?;
            let size = c.read_u32()?;
            if part_sz > 28 {
                let extra = usize::try_from(part_sz - 28).unwrap_or(0);
                if c.remaining() >= extra {
                    let _ = c.read_bytes(extra)?;
                }
            }
            parts.push(ChunkPart {
                guid_hex: guid_to_epic_hex(&guid),
                offset,
                size,
            });
        }
        chunk_parts_list.push(parts);
    }

    let _ = symlinks;
    let mut files = Vec::with_capacity(count);
    for i in 0..count {
        let file_size: u64 = chunk_parts_list[i].iter().map(|p| u64::from(p.size)).sum();
        files.push(FileEntry {
            filename: filenames.remove(0),
            file_hash: shas[i],
            flags: flags[i],
            install_tags: install_tags[i].clone(),
            chunk_parts: chunk_parts_list[i].clone(),
            file_size,
        });
    }
    Ok(files)
}

#[derive(Debug, Deserialize)]
struct JsonManifest {
    #[serde(rename = "ManifestFileVersion")]
    manifest_file_version: Option<String>,
    #[serde(rename = "AppNameString")]
    app_name_string: Option<String>,
    #[serde(rename = "BuildVersionString")]
    build_version_string: Option<String>,
    #[serde(rename = "LaunchExeString")]
    launch_exe_string: Option<String>,
    #[serde(rename = "LaunchCommand")]
    launch_command: Option<String>,
    #[serde(rename = "FileManifestList", default)]
    file_manifest_list: Vec<JsonFileEntry>,
    #[serde(rename = "ChunkHashList", default)]
    chunk_hash_list: HashMap<String, String>,
    #[serde(rename = "ChunkShaList", default)]
    chunk_sha_list: HashMap<String, String>,
    #[serde(rename = "DataGroupList", default)]
    data_group_list: HashMap<String, String>,
    #[serde(rename = "ChunkFilesizeList", default)]
    chunk_filesize_list: HashMap<String, String>,
}

#[derive(Debug, Deserialize)]
struct JsonFileEntry {
    #[serde(rename = "Filename")]
    filename: String,
    #[serde(rename = "FileHash")]
    file_hash: Option<String>,
    #[serde(rename = "InstallTags", default)]
    install_tags: Vec<String>,
    #[serde(rename = "FileChunkParts", default)]
    file_chunk_parts: Vec<JsonChunkPart>,
}

#[derive(Debug, Deserialize)]
struct JsonChunkPart {
    #[serde(rename = "Guid")]
    guid: String,
    #[serde(rename = "Offset")]
    offset: String,
    #[serde(rename = "Size")]
    size: String,
}

fn decode_epic_blob_num(s: &str) -> Option<u64> {
    // Legacy JSON encodes uint64 as decimal string or concatenated 3-digit byte chunks
    if let Ok(v) = s.parse::<u64>() {
        return Some(v);
    }
    if s.len().is_multiple_of(3) {
        let mut bytes = Vec::with_capacity(s.len() / 3);
        for chunk in s.as_bytes().as_chunks::<3>().0 {
            let txt = std::str::from_utf8(chunk).ok()?;
            bytes.push(txt.parse::<u8>().ok()?);
        }
        if bytes.len() == 8 {
            return Some(u64::from_le_bytes([
                bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6], bytes[7],
            ]));
        }
    }
    None
}

fn decode_hex_20(s: &str) -> [u8; 20] {
    let mut out = [0u8; 20];
    let clean = s.trim();
    if clean.len() == 40 {
        for (i, pair) in clean.as_bytes().as_chunks::<2>().0.iter().enumerate() {
            if let Ok(txt) = std::str::from_utf8(pair)
                && let Ok(val) = u8::from_str_radix(txt, 16)
            {
                out[i] = val;
            }
        }
    }
    out
}

fn parse_json_manifest(raw: &[u8]) -> Result<ParsedManifest> {
    let jm: JsonManifest = serde_json::from_slice(raw)?;
    let feature_level = jm
        .manifest_file_version
        .as_deref()
        .and_then(|v| decode_epic_blob_num(v).or_else(|| v.parse::<u64>().ok()))
        .and_then(|v| u32::try_from(v).ok())
        .unwrap_or(18);

    let mut chunks = HashMap::new();
    for (guid_hex, hash_str) in &jm.chunk_hash_list {
        let hash = decode_epic_blob_num(hash_str).unwrap_or(0);
        let sha_hash = jm
            .chunk_sha_list
            .get(guid_hex)
            .map(|s| decode_hex_20(s))
            .unwrap_or([0u8; 20]);
        let group_num = jm
            .data_group_list
            .get(guid_hex)
            .and_then(|s| s.parse::<u8>().ok())
            .unwrap_or(0);
        let file_size = jm
            .chunk_filesize_list
            .get(guid_hex)
            .and_then(|s| decode_epic_blob_num(s))
            .and_then(|v| i64::try_from(v).ok())
            .unwrap_or(0);

        chunks.insert(
            guid_hex.to_ascii_uppercase(),
            ChunkInfo {
                guid: [0u8; 16],
                guid_hex: guid_hex.to_ascii_uppercase(),
                hash,
                sha_hash,
                group_num,
                window_size: 1_048_576,
                file_size,
            },
        );
    }

    let mut files = Vec::with_capacity(jm.file_manifest_list.len());
    for jf in jm.file_manifest_list {
        let mut parts = Vec::with_capacity(jf.file_chunk_parts.len());
        let mut total = 0u64;
        for jp in jf.file_chunk_parts {
            let offset = decode_epic_blob_num(&jp.offset)
                .and_then(|v| u32::try_from(v).ok())
                .unwrap_or(0);
            let size = decode_epic_blob_num(&jp.size)
                .and_then(|v| u32::try_from(v).ok())
                .unwrap_or(0);
            total = total.saturating_add(u64::from(size));
            parts.push(ChunkPart {
                guid_hex: jp.guid.to_ascii_uppercase(),
                offset,
                size,
            });
        }
        files.push(FileEntry {
            filename: jf.filename,
            file_hash: jf
                .file_hash
                .as_deref()
                .map(decode_hex_20)
                .unwrap_or([0u8; 20]),
            flags: 0,
            install_tags: jf.install_tags,
            chunk_parts: parts,
            file_size: total,
        });
    }

    Ok(ParsedManifest {
        feature_level,
        app_name: jm.app_name_string.unwrap_or_default(),
        build_version: jm.build_version_string.unwrap_or_default(),
        launch_exe: jm.launch_exe_string.unwrap_or_default(),
        launch_command: jm.launch_command.unwrap_or_default(),
        chunks,
        files,
    })
}

pub fn decode_epic_chunk(raw: &[u8], expected_sha: Option<&[u8; 20]>) -> Result<Vec<u8>> {
    let mut c = Cursor::new(raw);
    let magic = c.read_u32()?;
    if magic != CHUNK_MAGIC {
        return Err(CoreError::Manifest(format!(
            "invalid chunk magic: 0x{magic:08X}"
        )));
    }
    let header_version = c.read_u32()?;
    let header_size = usize::try_from(c.read_u32()?)
        .map_err(|_| CoreError::Manifest("invalid chunk header size".to_string()))?;
    let compressed_size = usize::try_from(c.read_u32()?)
        .map_err(|_| CoreError::Manifest("invalid chunk compressed size".to_string()))?;
    let _guid = c.read_guid()?;
    let _rolling_hash = c.read_u64()?;
    let stored_as = c.read_u8()?;

    let mut header_sha: Option<[u8; 20]> = None;
    if header_version >= 2 && c.remaining() >= 20 {
        header_sha = Some(c.read_sha1()?);
    }

    if header_size > raw.len() {
        return Err(CoreError::Manifest(
            "chunk header exceeds payload".to_string(),
        ));
    }
    let end = header_size
        .checked_add(compressed_size)
        .ok_or_else(|| CoreError::Manifest("chunk payload overflow".to_string()))?;
    let payload = if end <= raw.len() && compressed_size > 0 {
        &raw[header_size..end]
    } else {
        &raw[header_size..]
    };

    let data = if (stored_as & 0x01) != 0 {
        let mut dec = ZlibDecoder::new(payload);
        let mut out = Vec::new();
        dec.read_to_end(&mut out)
            .map_err(|e| CoreError::Manifest(format!("chunk zlib inflate failed: {e}")))?;
        out
    } else {
        payload.to_vec()
    };

    let actual_sha: [u8; 20] = Sha1::digest(&data).into();
    if let Some(exp) = expected_sha
        && exp.iter().any(|&b| b != 0)
        && &actual_sha != exp
    {
        return Err(CoreError::Integrity(
            "chunk SHA-1 mismatch against manifest".to_string(),
        ));
    }
    if let Some(hsha) = header_sha
        && hsha.iter().any(|&b| b != 0)
        && actual_sha != hsha
    {
        return Err(CoreError::Integrity(
            "chunk SHA-1 mismatch against chunk header".to_string(),
        ));
    }

    Ok(data)
}

#[cfg(test)]
mod tests {
    use super::*;
    use flate2::Compression;
    use flate2::write::ZlibEncoder;
    use std::io::Write as _;

    fn push_fstring(buf: &mut Vec<u8>, s: &str) {
        if s.is_empty() {
            buf.extend_from_slice(&0i32.to_le_bytes());
            return;
        }
        let len = (s.len() + 1) as i32;
        buf.extend_from_slice(&len.to_le_bytes());
        buf.extend_from_slice(s.as_bytes());
        buf.push(0);
    }

    fn build_synthetic_binary_manifest() -> Vec<u8> {
        let mut meta = Vec::new();
        meta.extend_from_slice(&0u32.to_le_bytes());
        meta.push(0);
        meta.extend_from_slice(&18u32.to_le_bytes());
        meta.push(1);
        meta.extend_from_slice(&0u32.to_le_bytes());
        push_fstring(&mut meta, "TestApp");
        push_fstring(&mut meta, "1.0.0");
        push_fstring(&mut meta, "bin/game.exe");
        push_fstring(&mut meta, "");
        let meta_sz = u32::try_from(meta.len()).unwrap_or(0);
        meta[0..4].copy_from_slice(&meta_sz.to_le_bytes());

        let guid = [1u8; 16];
        let chunk_sha = [0xAAu8; 20];
        let mut cdl = Vec::new();
        cdl.extend_from_slice(&0u32.to_le_bytes());
        cdl.push(0);
        cdl.extend_from_slice(&1u32.to_le_bytes());
        cdl.extend_from_slice(&guid);
        cdl.extend_from_slice(&0x1234_5678_9ABC_DEF0u64.to_le_bytes());
        cdl.extend_from_slice(&chunk_sha);
        cdl.push(5);
        cdl.extend_from_slice(&11u32.to_le_bytes());
        cdl.extend_from_slice(&64i64.to_le_bytes());
        let cdl_sz = u32::try_from(cdl.len()).unwrap_or(0);
        cdl[0..4].copy_from_slice(&cdl_sz.to_le_bytes());

        let mut fml = Vec::new();
        fml.extend_from_slice(&0u32.to_le_bytes());
        fml.push(0);
        fml.extend_from_slice(&1u32.to_le_bytes());
        push_fstring(&mut fml, "bin/game.exe");
        push_fstring(&mut fml, "");
        fml.extend_from_slice(&[0xBBu8; 20]);
        fml.push(0);
        fml.extend_from_slice(&0u32.to_le_bytes()); // 0 install tags
        fml.extend_from_slice(&1u32.to_le_bytes()); // 1 chunk part
        fml.extend_from_slice(&28u32.to_le_bytes());
        fml.extend_from_slice(&guid);
        fml.extend_from_slice(&0u32.to_le_bytes());
        fml.extend_from_slice(&11u32.to_le_bytes());
        let fml_sz = u32::try_from(fml.len()).unwrap_or(0);
        fml[0..4].copy_from_slice(&fml_sz.to_le_bytes());

        let mut body = Vec::new();
        body.extend_from_slice(&meta);
        body.extend_from_slice(&cdl);
        body.extend_from_slice(&fml);

        let body_sha: [u8; 20] = Sha1::digest(&body).into();
        let mut enc = ZlibEncoder::new(Vec::new(), Compression::default());
        let _ = enc.write_all(&body);
        let compressed = enc.finish().unwrap_or_default();

        let mut out = Vec::new();
        out.extend_from_slice(&BINARY_MANIFEST_MAGIC.to_le_bytes());
        out.extend_from_slice(&41u32.to_le_bytes());
        out.extend_from_slice(&(body.len() as u32).to_le_bytes());
        out.extend_from_slice(&(compressed.len() as u32).to_le_bytes());
        out.extend_from_slice(&body_sha);
        out.push(1);
        out.extend_from_slice(&18u32.to_le_bytes());
        out.extend_from_slice(&compressed);
        out
    }

    #[test]
    fn parses_synthetic_binary_manifest_and_tamper_fails() {
        let raw = build_synthetic_binary_manifest();
        let parsed = parse_manifest_bytes(&raw).expect("valid synthetic binary manifest");
        assert_eq!(parsed.app_name, "TestApp");
        assert_eq!(parsed.build_version, "1.0.0");
        assert_eq!(parsed.launch_exe, "bin/game.exe");
        assert_eq!(parsed.files.len(), 1);
        assert_eq!(parsed.files[0].file_size, 11);
        assert_eq!(parsed.chunks.len(), 1);

        let mut tampered = raw;
        tampered[20] ^= 0xFF;
        assert!(parse_manifest_bytes(&tampered).is_err());
    }

    #[test]
    fn decodes_chunk_and_builds_cdn_url() {
        let payload = b"hello world";
        let sha: [u8; 20] = Sha1::digest(payload).into();
        let mut enc = ZlibEncoder::new(Vec::new(), Compression::default());
        let _ = enc.write_all(payload);
        let comp = enc.finish().unwrap_or_default();

        let mut raw_chunk = Vec::new();
        raw_chunk.extend_from_slice(&CHUNK_MAGIC.to_le_bytes());
        raw_chunk.extend_from_slice(&2u32.to_le_bytes());
        raw_chunk.extend_from_slice(&62u32.to_le_bytes());
        raw_chunk.extend_from_slice(&(comp.len() as u32).to_le_bytes());
        raw_chunk.extend_from_slice(&[0u8; 16]);
        raw_chunk.extend_from_slice(&0u64.to_le_bytes());
        raw_chunk.push(1);
        raw_chunk.extend_from_slice(&sha);
        raw_chunk.push(0);
        raw_chunk.extend_from_slice(&comp);

        let decoded = decode_epic_chunk(&raw_chunk, Some(&sha)).expect("chunk decode");
        assert_eq!(decoded, payload);

        let info = ChunkInfo {
            guid: [0u8; 16],
            guid_hex: "00112233445566778899AABBCCDDEEFF".to_string(),
            hash: 0x0102030405060708,
            sha_hash: sha,
            group_num: 7,
            window_size: 11,
            file_size: 64,
        };
        assert_eq!(
            chunk_cdn_url(
                "https://cdn.example.com/",
                "Builds/App/CloudDir/",
                18,
                &info
            ),
            "https://cdn.example.com/Builds/App/CloudDir/ChunksV4/07/0102030405060708_00112233445566778899AABBCCDDEEFF.chunk"
        );
    }
}

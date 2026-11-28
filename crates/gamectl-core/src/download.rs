use std::collections::{HashMap, HashSet};
use std::path::{Component, Path, PathBuf};
use std::sync::Arc;

use futures::stream::{FuturesUnordered, StreamExt as _};
use reqwest::Client;
use serde::{Deserialize, Serialize};
use sha1::{Digest as _, Sha1};
use tokio::io::{AsyncSeekExt as _, AsyncWriteExt as _};
use tokio::sync::Semaphore;

use crate::api::ManifestTarget;
use crate::auth::default_config_dir;
use crate::error::{CoreError, Result};
use crate::manifest::{ParsedManifest, chunk_cdn_url, decode_epic_chunk};

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct EpicInstalledEntry {
    pub app_name: String,
    pub title: String,
    pub install_path: String,
    pub executable: String,
    pub version: String,
    pub install_size: u64,
    pub platform: String,
}

pub fn installed_db_path() -> PathBuf {
    if let Ok(p) = std::env::var("GAMECTL_EPIC_INSTALLED_FILE")
        && !p.trim().is_empty()
    {
        return PathBuf::from(p);
    }
    default_config_dir().join("epic_installed.json")
}

pub fn sanitize_relative_path(rel: &str) -> Result<PathBuf> {
    let normalized = rel.replace('\\', "/");
    let p = Path::new(&normalized);
    let mut clean = PathBuf::new();
    for comp in p.components() {
        match comp {
            Component::Normal(seg) => clean.push(seg),
            Component::CurDir => {}
            Component::ParentDir | Component::RootDir | Component::Prefix(_) => {
                return Err(CoreError::InvalidInput(format!(
                    "unsafe manifest path rejected: {rel}"
                )));
            }
        }
    }
    if clean.as_os_str().is_empty() {
        return Err(CoreError::InvalidInput(format!(
            "empty manifest file path: {rel}"
        )));
    }
    Ok(clean)
}

pub fn record_installed_entry(entry: &EpicInstalledEntry) -> Result<()> {
    let db_path = installed_db_path();
    if let Some(parent) = db_path.parent() {
        std::fs::create_dir_all(parent)?;
    }
    let mut map: HashMap<String, EpicInstalledEntry> = std::fs::read_to_string(&db_path)
        .ok()
        .and_then(|s| serde_json::from_str(&s).ok())
        .unwrap_or_default();
    map.insert(entry.app_name.clone(), entry.clone());

    let tmp = db_path.with_extension("json.tmp");
    let body = serde_json::to_string_pretty(&map)?;
    std::fs::write(&tmp, format!("{body}\n"))?;
    std::fs::rename(&tmp, &db_path)?;
    Ok(())
}

pub async fn download_and_install(
    http: &Client,
    target: &ManifestTarget,
    manifest: &ParsedManifest,
    target_dir: &Path,
    title: &str,
    platform: &str,
) -> Result<()> {
    std::fs::create_dir_all(target_dir)?;

    let mut needed_guids: HashSet<String> = HashSet::new();
    for file in &manifest.files {
        for part in &file.chunk_parts {
            needed_guids.insert(part.guid_hex.clone());
        }
    }

    let cache_dir = target_dir.join(".gamectl_epic_chunks");
    std::fs::create_dir_all(&cache_dir)?;

    let sem = Arc::new(Semaphore::new(8));
    let base_urls = Arc::new(target.base_urls.clone());
    let cloud_dir = Arc::new(target.cloud_dir.clone());
    let feature_level = manifest.feature_level;

    let mut futs = FuturesUnordered::new();
    for guid_hex in needed_guids {
        let info =
            manifest.chunks.get(&guid_hex).cloned().ok_or_else(|| {
                CoreError::Manifest(format!("missing chunk metadata for {guid_hex}"))
            })?;
        let chunk_file = cache_dir.join(format!("{guid_hex}.bin"));
        if chunk_file.is_file() {
            continue;
        }
        let sem_c = Arc::clone(&sem);
        let http_c = http.clone();
        let bases_c = Arc::clone(&base_urls);
        let cdir_c = Arc::clone(&cloud_dir);
        futs.push(tokio::spawn(async move {
            let _permit = sem_c
                .acquire_owned()
                .await
                .map_err(|_| CoreError::Api("chunk semaphore closed".to_string()))?;
            let mut last_err: Option<CoreError> = None;
            for base in bases_c.iter() {
                let url = chunk_cdn_url(base, &cdir_c, feature_level, &info);
                match http_c.get(&url).send().await {
                    Ok(resp) if resp.status().is_success() => match resp.bytes().await {
                        Ok(raw) => {
                            let decoded = decode_epic_chunk(&raw, Some(&info.sha_hash))?;
                            tokio::fs::write(&chunk_file, &decoded).await?;
                            return Ok(());
                        }
                        Err(e) => last_err = Some(CoreError::Http(e)),
                    },
                    Ok(resp) => {
                        last_err = Some(CoreError::Api(format!(
                            "chunk {guid_hex} HTTP {}",
                            resp.status()
                        )));
                    }
                    Err(e) => last_err = Some(CoreError::Http(e)),
                }
            }
            Err(last_err.unwrap_or_else(|| {
                CoreError::Api(format!("all CDN mirrors failed for chunk {guid_hex}"))
            }))
        }));
    }

    while let Some(res) = futs.next().await {
        match res {
            Ok(Ok(())) => {}
            Ok(Err(e)) => return Err(e),
            Err(e) => return Err(CoreError::Api(format!("chunk task join error: {e}"))),
        }
    }

    for file in &manifest.files {
        let rel = sanitize_relative_path(&file.filename)?;
        let dest = target_dir.join(&rel);
        if let Some(parent) = dest.parent() {
            tokio::fs::create_dir_all(parent).await?;
        }
        let tmp_dest = dest.with_extension("gamectl_tmp");
        let mut fh = tokio::fs::File::create(&tmp_dest).await?;
        let mut hasher = Sha1::new();
        for part in &file.chunk_parts {
            let chunk_path = cache_dir.join(format!("{}.bin", part.guid_hex));
            let raw_chunk = tokio::fs::read(&chunk_path).await?;
            let start = usize::try_from(part.offset)
                .map_err(|_| CoreError::Manifest("chunk offset overflow".to_string()))?;
            let len = usize::try_from(part.size)
                .map_err(|_| CoreError::Manifest("chunk part size overflow".to_string()))?;
            let end = start
                .checked_add(len)
                .ok_or_else(|| CoreError::Manifest("chunk slice overflow".to_string()))?;
            if end > raw_chunk.len() {
                return Err(CoreError::Manifest(format!(
                    "chunk {} shorter than requested slice {}..{}",
                    part.guid_hex, start, end
                )));
            }
            let slice = &raw_chunk[start..end];
            hasher.update(slice);
            fh.write_all(slice).await?;
        }
        let _ = fh.seek(std::io::SeekFrom::Start(0)).await;
        fh.flush().await?;
        drop(fh);

        if file.file_hash.iter().any(|&b| b != 0) {
            let actual: [u8; 20] = hasher.finalize().into();
            if actual != file.file_hash {
                let _ = tokio::fs::remove_file(&tmp_dest).await;
                return Err(CoreError::Integrity(format!(
                    "assembled file SHA-1 mismatch: {}",
                    file.filename
                )));
            }
        }
        tokio::fs::rename(&tmp_dest, &dest).await?;

        #[cfg(unix)]
        if dest.extension().and_then(|e| e.to_str()) == Some("sh")
            || file.filename == manifest.launch_exe
        {
            use std::os::unix::fs::PermissionsExt as _;
            let _ = std::fs::set_permissions(&dest, std::fs::Permissions::from_mode(0o755));
        }
    }

    let _ = std::fs::remove_dir_all(&cache_dir);

    let entry = EpicInstalledEntry {
        app_name: target.app_name.clone(),
        title: title.to_string(),
        install_path: target_dir.to_string_lossy().into_owned(),
        executable: manifest.launch_exe.replace('\\', "/"),
        version: manifest.build_version.clone(),
        install_size: manifest.total_disk_size(),
        platform: platform.to_string(),
    };
    record_installed_entry(&entry)?;
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn rejects_traversal_paths() {
        assert!(sanitize_relative_path("../evil.exe").is_err());
        assert!(sanitize_relative_path("/etc/passwd").is_err());
        assert!(sanitize_relative_path("a\\..\\b").is_err());
        assert_eq!(
            sanitize_relative_path("Binaries\\Win64\\Game.exe").expect("valid path"),
            PathBuf::from("Binaries/Win64/Game.exe")
        );
    }
}

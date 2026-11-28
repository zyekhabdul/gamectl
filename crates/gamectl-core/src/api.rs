use std::collections::HashMap;

use reqwest::Client;
use serde::{Deserialize, Serialize};
use serde_json::Value;

use crate::auth::EpicSession;
use crate::error::{CoreError, Result};

const LAUNCHER_HOST: &str = "https://launcher-public-service-prod06.ol.epicgames.com";
const LIBRARY_HOST: &str = "https://library-service.live.use1a.on.epicgames.com";
const CATALOG_HOST: &str = "https://catalog-public-service-prod06.ol.epicgames.com";

#[derive(Debug, Clone, Deserialize)]
pub struct LibraryItem {
    pub namespace: String,
    #[serde(rename = "catalogItemId")]
    pub catalog_item_id: String,
    #[serde(rename = "appName")]
    pub app_name: Option<String>,
    #[serde(rename = "sandboxName", default)]
    pub sandbox_name: String,
}

#[derive(Debug, Clone, Deserialize)]
struct LibraryResponse {
    records: Vec<LibraryItem>,
    #[serde(rename = "responseMetadata")]
    response_metadata: Option<LibraryMetadata>,
}

#[derive(Debug, Clone, Deserialize)]
struct LibraryMetadata {
    #[serde(rename = "nextCursor")]
    next_cursor: Option<String>,
}

#[derive(Debug, Clone, Deserialize)]
pub struct AssetEntry {
    #[serde(rename = "appName")]
    pub app_name: String,
    pub namespace: String,
    #[serde(rename = "catalogItemId")]
    pub catalog_item_id: String,
    #[serde(rename = "buildVersion", default)]
    pub build_version: String,
    #[serde(default)]
    pub metadata: Value,
}

#[derive(Debug, Clone, Serialize)]
pub struct CatalogSummaryRow {
    pub app_name: String,
    pub app_title: String,
    pub namespace: String,
    pub catalog_item_id: String,
    pub build_version: String,
    pub asset_infos: HashMap<String, Value>,
}

#[derive(Debug, Clone)]
pub struct ManifestTarget {
    pub manifest_url: String,
    pub base_urls: Vec<String>,
    pub cloud_dir: String,
    pub app_name: String,
    pub namespace: String,
    pub catalog_item_id: String,
    pub build_version: String,
}

pub async fn fetch_library_items(http: &Client, session: &EpicSession) -> Result<Vec<LibraryItem>> {
    let mut items = Vec::new();
    let mut cursor: Option<String> = None;

    loop {
        let mut url = format!("{LIBRARY_HOST}/library/api/public/items?includeMetadata=true");
        if let Some(ref c) = cursor {
            url.push_str("&cursor=");
            url.push_str(c);
        }
        let resp = http
            .get(&url)
            .bearer_auth(&session.access_token)
            .send()
            .await?;
        let status = resp.status();
        if !status.is_success() {
            return Err(CoreError::Api(format!(
                "library items query failed: HTTP {status}"
            )));
        }
        let bytes = resp.bytes().await?;
        let body: LibraryResponse = serde_json::from_slice(&bytes)?;
        items.extend(body.records);
        cursor = body.response_metadata.and_then(|m| m.next_cursor);
        if cursor.as_deref().is_none_or(str::is_empty) {
            break;
        }
    }
    Ok(items)
}

pub async fn fetch_platform_assets(
    http: &Client,
    session: &EpicSession,
    platform: &str,
) -> Result<Vec<AssetEntry>> {
    let url = format!("{LAUNCHER_HOST}/launcher/api/public/assets/{platform}?label=Live");
    let resp = http
        .get(&url)
        .bearer_auth(&session.access_token)
        .send()
        .await?;
    let status = resp.status();
    if !status.is_success() {
        return Err(CoreError::Api(format!(
            "platform assets query failed ({platform}): HTTP {status}"
        )));
    }
    let bytes = resp.bytes().await?;
    Ok(serde_json::from_slice(&bytes)?)
}

pub async fn fetch_catalog_item_title(
    http: &Client,
    session: &EpicSession,
    namespace: &str,
    item_id: &str,
) -> Option<(String, String, usize)> {
    let url = format!(
        "{CATALOG_HOST}/catalog/api/shared/namespace/{namespace}/bulk/items?id={item_id}&includeDLCDetails=true&country=US&locale=en"
    );
    let resp = http
        .get(&url)
        .bearer_auth(&session.access_token)
        .send()
        .await
        .ok()?;
    if !resp.status().is_success() {
        return None;
    }
    let bytes = resp.bytes().await.ok()?;
    let val: Value = serde_json::from_slice(&bytes).ok()?;
    let item = val.get(item_id)?;
    let title = item
        .get("title")
        .and_then(Value::as_str)
        .unwrap_or("")
        .to_string();
    let dev = item
        .get("developer")
        .and_then(Value::as_str)
        .unwrap_or("")
        .to_string();
    let dlc_count = item
        .get("dlcItemList")
        .and_then(Value::as_array)
        .map_or(0, Vec::len);
    Some((title, dev, dlc_count))
}

pub async fn build_catalog_list(
    http: &Client,
    session: &EpicSession,
) -> Result<Vec<CatalogSummaryRow>> {
    let (win_assets, lib_items) = tokio::try_join!(
        fetch_platform_assets(http, session, "Windows"),
        fetch_library_items(http, session)
    )?;

    let mut lib_by_key: HashMap<(String, String), &LibraryItem> = HashMap::new();
    let mut lib_by_app: HashMap<&str, &LibraryItem> = HashMap::new();
    for item in &lib_items {
        lib_by_key.insert((item.namespace.clone(), item.catalog_item_id.clone()), item);
        if let Some(ref an) = item.app_name {
            lib_by_app.insert(an.as_str(), item);
        }
    }

    let mut rows = Vec::new();
    for asset in win_assets {
        let mut title = asset.app_name.clone();
        if let Some(li) = lib_by_key
            .get(&(asset.namespace.clone(), asset.catalog_item_id.clone()))
            .or_else(|| lib_by_app.get(asset.app_name.as_str()))
            && !li.sandbox_name.is_empty()
        {
            title = li.sandbox_name.clone();
        }
        let mut asset_infos = HashMap::new();
        asset_infos.insert("Windows".to_string(), serde_json::json!({}));
        rows.push(CatalogSummaryRow {
            app_name: asset.app_name,
            app_title: title,
            namespace: asset.namespace,
            catalog_item_id: asset.catalog_item_id,
            build_version: asset.build_version,
            asset_infos,
        });
    }
    Ok(rows)
}

pub async fn resolve_manifest_target(
    http: &Client,
    session: &EpicSession,
    app_name: &str,
    platform: &str,
) -> Result<ManifestTarget> {
    let assets = fetch_platform_assets(http, session, platform).await?;
    let asset = assets
        .into_iter()
        .find(|a| a.app_name == app_name)
        .ok_or_else(|| {
            CoreError::Api(format!(
                "app '{app_name}' not found in Epic account entitlements for {platform}"
            ))
        })?;

    let v2_url = format!(
        "{LAUNCHER_HOST}/launcher/api/public/assets/v2/platform/{platform}/namespace/{}/catalogItem/{}/app/{}/label/Live",
        asset.namespace, asset.catalog_item_id, asset.app_name
    );
    let resp = http
        .get(&v2_url)
        .bearer_auth(&session.access_token)
        .send()
        .await?;
    let status = resp.status();
    if !status.is_success() {
        return Err(CoreError::Api(format!(
            "manifest v2 query failed for '{app_name}': HTTP {status}"
        )));
    }

    let bytes = resp.bytes().await?;
    let v2_json: Value = serde_json::from_slice(&bytes)?;
    let elements = v2_json
        .get("elements")
        .and_then(Value::as_array)
        .ok_or_else(|| {
            CoreError::Api("missing 'elements' in Epic assets/v2 response".to_string())
        })?;
    let first = elements
        .first()
        .ok_or_else(|| CoreError::Api("empty 'elements' in Epic assets/v2 response".to_string()))?;
    let manifests = first
        .get("manifests")
        .and_then(Value::as_array)
        .ok_or_else(|| {
            CoreError::Api("missing 'manifests' in Epic assets/v2 response".to_string())
        })?;

    let primary = manifests
        .first()
        .ok_or_else(|| CoreError::Api("no manifest URLs returned by Epic".to_string()))?;

    let mut manifest_url = primary
        .get("uri")
        .and_then(Value::as_str)
        .ok_or_else(|| CoreError::Api("manifest entry missing 'uri'".to_string()))?
        .to_string();

    if let Some(params) = primary.get("queryParams").and_then(Value::as_array) {
        let mut sep = if manifest_url.contains('?') { '&' } else { '?' };
        for p in params {
            if let (Some(k), Some(v)) = (
                p.get("name").and_then(Value::as_str),
                p.get("value").and_then(Value::as_str),
            ) {
                manifest_url.push(sep);
                manifest_url.push_str(k);
                manifest_url.push('=');
                manifest_url.push_str(v);
                sep = '&';
            }
        }
    }

    let mut base_urls = Vec::new();
    for m in manifests {
        if let Some(uri) = m.get("uri").and_then(Value::as_str)
            && let Some(idx) = uri.find("/Builds/")
        {
            let base = &uri[..idx];
            if !base_urls.iter().any(|b| b == base) {
                base_urls.push(base.to_string());
            }
        }
    }
    if base_urls.is_empty() {
        base_urls.push("https://fastly-download.epicgames.com".to_string());
        base_urls.push("https://epicgames-download1.akamaized.net".to_string());
    }

    let cloud_dir = first
        .get("cloudDir")
        .and_then(Value::as_str)
        .map(str::to_string)
        .unwrap_or_else(|| {
            manifest_url
                .find("/Builds/")
                .and_then(|start| {
                    let rest = &manifest_url[start..];
                    rest.rfind('/').map(|end| rest[..end].to_string())
                })
                .unwrap_or_else(|| format!("Builds/{}/CloudDir", asset.app_name))
        });

    Ok(ManifestTarget {
        manifest_url,
        base_urls,
        cloud_dir,
        app_name: asset.app_name,
        namespace: asset.namespace,
        catalog_item_id: asset.catalog_item_id,
        build_version: asset.build_version,
    })
}

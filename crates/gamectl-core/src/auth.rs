use std::path::{Path, PathBuf};
use std::time::{SystemTime, UNIX_EPOCH};

use base64::Engine as _;
use reqwest::Client;
use serde::{Deserialize, Serialize};

use crate::error::{CoreError, Result};

// Epic Games Launcher (launcherAppClient2) public client credentials
const EPIC_CLIENT_ID: &str = "34a02cf8f4414e29b15921876da36f9a";
const EPIC_CLIENT_SECRET: &str = "daafbccc737745039dffe53d94fc76cf";
const EPIC_OAUTH_HOST: &str = "https://account-public-service-prod03.ol.epicgames.com";

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct EpicSession {
    pub access_token: String,
    pub refresh_token: String,
    #[serde(default)]
    pub account_id: String,
    #[serde(default)]
    pub display_name: String,
    #[serde(default)]
    pub expires_at_unix: u64,
}

#[derive(Debug, Deserialize)]
struct OAuthTokenResponse {
    access_token: Option<String>,
    refresh_token: Option<String>,
    account_id: Option<String>,
    #[serde(rename = "displayName")]
    display_name: Option<String>,
    expires_in: Option<u64>,
    #[serde(rename = "errorMessage")]
    error_message: Option<String>,
    error: Option<String>,
}

pub fn epic_auth_url() -> String {
    let redirect = format!(
        "https://www.epicgames.com/id/api/redirect?clientId={EPIC_CLIENT_ID}&responseType=code"
    );
    format!("https://www.epicgames.com/id/login?redirectUrl={redirect}")
}

pub fn default_config_dir() -> PathBuf {
    if let Ok(xdg) = std::env::var("XDG_CONFIG_HOME")
        && !xdg.trim().is_empty()
    {
        return PathBuf::from(xdg).join("gamectl");
    }
    if let Ok(home) = std::env::var("HOME")
        && !home.trim().is_empty()
    {
        return PathBuf::from(home).join(".config").join("gamectl");
    }
    PathBuf::from(".config").join("gamectl")
}

pub fn session_file_path() -> PathBuf {
    if let Ok(override_path) = std::env::var("GAMECTL_EPIC_AUTH_FILE")
        && !override_path.trim().is_empty()
    {
        return PathBuf::from(override_path);
    }
    default_config_dir().join("epic_auth.json")
}

pub fn legendary_user_file_path() -> PathBuf {
    if let Ok(lpath) = std::env::var("LEGENDARY_CONFIG_PATH")
        && !lpath.trim().is_empty()
    {
        return PathBuf::from(lpath).join("user.json");
    }
    if let Ok(xdg) = std::env::var("XDG_CONFIG_HOME")
        && !xdg.trim().is_empty()
    {
        return PathBuf::from(xdg).join("legendary").join("user.json");
    }
    if let Ok(home) = std::env::var("HOME")
        && !home.trim().is_empty()
    {
        return PathBuf::from(home)
            .join(".config")
            .join("legendary")
            .join("user.json");
    }
    PathBuf::from(".config").join("legendary").join("user.json")
}

fn now_unix() -> u64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|d| d.as_secs())
        .unwrap_or(0)
}

fn basic_auth_header() -> String {
    let raw = format!("{EPIC_CLIENT_ID}:{EPIC_CLIENT_SECRET}");
    let enc = base64::engine::general_purpose::STANDARD.encode(raw.as_bytes());
    format!("Basic {enc}")
}

pub fn load_session_from_disk() -> Option<EpicSession> {
    let candidates = [session_file_path(), legendary_user_file_path()];
    for path in candidates {
        if let Ok(raw) = std::fs::read_to_string(&path)
            && let Ok(sess) = serde_json::from_str::<EpicSession>(&raw)
            && !sess.access_token.trim().is_empty()
        {
            return Some(sess);
        }
    }
    None
}

pub fn save_session_to_path(path: &Path, session: &EpicSession) -> Result<()> {
    if let Some(parent) = path.parent() {
        std::fs::create_dir_all(parent)?;
    }
    let tmp = path.with_extension("json.tmp");
    let body = serde_json::to_string_pretty(session)?;
    std::fs::write(&tmp, format!("{body}\n"))?;
    #[cfg(unix)]
    {
        use std::os::unix::fs::PermissionsExt as _;
        let _ = std::fs::set_permissions(&tmp, std::fs::Permissions::from_mode(0o600));
    }
    std::fs::rename(&tmp, path)?;
    Ok(())
}

pub async fn exchange_authorization_code(http: &Client, code: &str) -> Result<EpicSession> {
    let clean_code = code.trim();
    if clean_code.is_empty() {
        return Err(CoreError::InvalidInput(
            "authorization code cannot be empty".to_string(),
        ));
    }

    let url = format!("{EPIC_OAUTH_HOST}/account/api/oauth/token");
    let resp = http
        .post(&url)
        .header("Authorization", basic_auth_header())
        .form(&[
            ("grant_type", "authorization_code"),
            ("code", clean_code),
            ("token_type", "eg1"),
        ])
        .send()
        .await?;

    let status = resp.status();
    let bytes = resp.bytes().await?;
    let payload: OAuthTokenResponse = serde_json::from_slice(&bytes)?;
    if !status.is_success() {
        let msg = payload
            .error_message
            .or(payload.error)
            .unwrap_or_else(|| format!("HTTP {status}"));
        return Err(CoreError::Auth(msg));
    }

    let access_token = payload
        .access_token
        .ok_or_else(|| CoreError::Auth("missing access_token in Epic response".to_string()))?;
    let refresh_token = payload
        .refresh_token
        .ok_or_else(|| CoreError::Auth("missing refresh_token in Epic response".to_string()))?;

    let session = EpicSession {
        access_token,
        refresh_token,
        account_id: payload.account_id.unwrap_or_default(),
        display_name: payload.display_name.unwrap_or_default(),
        expires_at_unix: now_unix().saturating_add(payload.expires_in.unwrap_or(7200)),
    };
    save_session_to_path(&session_file_path(), &session)?;
    Ok(session)
}

pub async fn refresh_session(http: &Client, existing: &EpicSession) -> Result<EpicSession> {
    if existing.refresh_token.trim().is_empty() {
        return Err(CoreError::Auth(
            "no refresh_token stored; run 'gamectl epic auth'".to_string(),
        ));
    }
    let url = format!("{EPIC_OAUTH_HOST}/account/api/oauth/token");
    let resp = http
        .post(&url)
        .header("Authorization", basic_auth_header())
        .form(&[
            ("grant_type", "refresh_token"),
            ("refresh_token", existing.refresh_token.as_str()),
            ("token_type", "eg1"),
        ])
        .send()
        .await?;

    let status = resp.status();
    let bytes = resp.bytes().await?;
    let payload: OAuthTokenResponse = serde_json::from_slice(&bytes)?;
    if !status.is_success() {
        let msg = payload
            .error_message
            .or(payload.error)
            .unwrap_or_else(|| format!("HTTP {status}"));
        return Err(CoreError::Auth(format!("token refresh failed: {msg}")));
    }

    let access_token = payload
        .access_token
        .ok_or_else(|| CoreError::Auth("missing access_token on refresh".to_string()))?;
    let refresh_token = payload
        .refresh_token
        .unwrap_or_else(|| existing.refresh_token.clone());

    let updated = EpicSession {
        access_token,
        refresh_token,
        account_id: payload
            .account_id
            .unwrap_or_else(|| existing.account_id.clone()),
        display_name: payload
            .display_name
            .unwrap_or_else(|| existing.display_name.clone()),
        expires_at_unix: now_unix().saturating_add(payload.expires_in.unwrap_or(7200)),
    };
    save_session_to_path(&session_file_path(), &updated)?;
    Ok(updated)
}

pub async fn ensure_valid_session(http: &Client) -> Result<EpicSession> {
    let sess = load_session_from_disk()
        .ok_or_else(|| CoreError::Auth("not authenticated; run 'gamectl epic auth'".to_string()))?;
    let now = now_unix();
    if sess.expires_at_unix > 0 && now.saturating_add(120) >= sess.expires_at_unix {
        return refresh_session(http, &sess).await;
    }
    Ok(sess)
}

pub fn safe_status_summary() -> String {
    match load_session_from_disk() {
        Some(sess) => {
            let user = if !sess.display_name.is_empty() {
                sess.display_name
            } else if !sess.account_id.is_empty() {
                sess.account_id
            } else {
                "authenticated".to_string()
            };
            let now = now_unix();
            if sess.expires_at_unix > 0 && now >= sess.expires_at_unix {
                format!("session present (refresh needed, account: {user})")
            } else {
                format!("session present (native engine, account: {user})")
            }
        }
        None => "unconfigured (run 'gamectl epic auth')".to_string(),
    }
}

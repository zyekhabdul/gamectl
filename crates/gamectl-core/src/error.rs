use thiserror::Error;

#[derive(Debug, Error)]
pub enum CoreError {
    #[error("I/O error: {0}")]
    Io(#[from] std::io::Error),

    #[error("HTTP request failed: {0}")]
    Http(#[from] reqwest::Error),

    #[error("JSON parse error: {0}")]
    Json(#[from] serde_json::Error),

    #[error("authentication required or expired: {0}")]
    Auth(String),

    #[error("API error: {0}")]
    Api(String),

    #[error("manifest parse error: {0}")]
    Manifest(String),

    #[error("integrity verification failed: {0}")]
    Integrity(String),

    #[error("invalid path or input: {0}")]
    InvalidInput(String),
}

pub type Result<T> = std::result::Result<T, CoreError>;

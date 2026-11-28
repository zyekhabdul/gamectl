//! MIT-licensed core runtime for `gamectl`.
//!
//! Provides native Epic Games Store authentication, catalog resolution,
//! binary/JSON manifest parsing, and parallel chunk downloading.

pub mod api;
pub mod auth;
pub mod download;
pub mod error;
pub mod manifest;

pub use error::{CoreError, Result};

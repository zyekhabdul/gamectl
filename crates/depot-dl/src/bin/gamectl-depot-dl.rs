use std::env;
use std::path::PathBuf;
use std::process;
use steam_depot_downloader_mod::{DepotDownloader, DownloadRequest, ProgressEvent};

const USAGE: &str = "Usage: gamectl-depot-dl --app <appid> --dir <dir> --depot <manifest>:<key> [--depot <manifest>:<key> ...] [--max-downloads <n>] [--verbose|-v] [--quiet|-q]";

#[derive(Debug, PartialEq, Eq)]
struct CliConfig {
    app_id: u32,
    dir: PathBuf,
    depots: Vec<(PathBuf, String)>,
    max_downloads: usize,
    verbose: bool,
    quiet: bool,
}

#[derive(Debug, PartialEq, Eq)]
enum CliError {
    HelpRequested,
    InvalidArg(String),
}

fn parse_cli_args<I, S>(args: I) -> Result<CliConfig, CliError>
where
    I: IntoIterator<Item = S>,
    S: Into<String>,
{
    let args: Vec<String> = args.into_iter().map(Into::into).collect();
    if args.is_empty() || args.iter().any(|a| a == "--help" || a == "-h") {
        return Err(CliError::HelpRequested);
    }

    let mut app_id: Option<u32> = None;
    let mut dir: Option<PathBuf> = None;
    let mut depots: Vec<(PathBuf, String)> = Vec::new();
    let mut max_downloads: usize = 8;
    let mut verbose: bool = false;
    let mut quiet: bool = false;

    let mut i = 0;
    while i < args.len() {
        match args[i].as_str() {
            "--app" => {
                if i + 1 >= args.len() {
                    return Err(CliError::InvalidArg("--app requires an appid".to_string()));
                }
                let parsed = args[i + 1].parse::<u32>().map_err(|_| {
                    CliError::InvalidArg(format!("Invalid --app value: {}", args[i + 1]))
                })?;
                app_id = Some(parsed);
                i += 2;
            }
            "--dir" => {
                if i + 1 >= args.len() {
                    return Err(CliError::InvalidArg(
                        "--dir requires a directory path".to_string(),
                    ));
                }
                if args[i + 1].is_empty() {
                    return Err(CliError::InvalidArg(
                        "--dir path cannot be empty".to_string(),
                    ));
                }
                dir = Some(PathBuf::from(&args[i + 1]));
                i += 2;
            }
            "--depot" => {
                if i + 1 >= args.len() {
                    return Err(CliError::InvalidArg(
                        "--depot requires an argument".to_string(),
                    ));
                }
                let pair = &args[i + 1];
                if let Some(pos) = pair.rfind(':') {
                    let manifest_str = &pair[..pos];
                    let key_str = &pair[pos + 1..];
                    if manifest_str.is_empty() || key_str.is_empty() {
                        return Err(CliError::InvalidArg(
                            "--depot requires non-empty <manifest_path>:<hex_key>".to_string(),
                        ));
                    }
                    depots.push((PathBuf::from(manifest_str), key_str.to_string()));
                } else {
                    return Err(CliError::InvalidArg(
                        "--depot requires format <manifest_path>:<hex_key>".to_string(),
                    ));
                }
                i += 2;
            }
            "--max-downloads" => {
                if i + 1 >= args.len() {
                    return Err(CliError::InvalidArg(
                        "--max-downloads requires a positive integer".to_string(),
                    ));
                }
                let parsed = args[i + 1].parse::<usize>().map_err(|_| {
                    CliError::InvalidArg(format!("Invalid --max-downloads value: {}", args[i + 1]))
                })?;
                if parsed == 0 {
                    return Err(CliError::InvalidArg(
                        "--max-downloads must be greater than 0".to_string(),
                    ));
                }
                max_downloads = parsed;
                i += 2;
            }
            "--verbose" | "-v" => {
                verbose = true;
                i += 1;
            }
            "--quiet" | "-q" => {
                quiet = true;
                i += 1;
            }
            other => {
                return Err(CliError::InvalidArg(format!("Unknown argument: {other}")));
            }
        }
    }

    let app_id =
        app_id.ok_or_else(|| CliError::InvalidArg("Missing required --app <appid>".to_string()))?;
    let dir =
        dir.ok_or_else(|| CliError::InvalidArg("Missing required --dir <output_dir>".to_string()))?;
    if depots.is_empty() {
        return Err(CliError::InvalidArg(
            "At least one --depot <manifest>:<key> is required".to_string(),
        ));
    }

    Ok(CliConfig {
        app_id,
        dir,
        depots,
        max_downloads,
        verbose,
        quiet,
    })
}

#[tokio::main]
async fn main() {
    let config = match parse_cli_args(env::args().skip(1)) {
        Ok(cfg) => cfg,
        Err(CliError::HelpRequested) => {
            eprintln!("{USAGE}");
            process::exit(1);
        }
        Err(CliError::InvalidArg(msg)) => {
            eprintln!("Error: {msg}");
            process::exit(1);
        }
    };

    let CliConfig {
        app_id,
        dir,
        depots,
        max_downloads,
        verbose,
        quiet,
    } = config;

    println!("[INFO] Standalone Steam Depot Downloader");
    println!("[INFO] App ID: {}", app_id);
    println!("[INFO] Output Dir: {}", dir.display());
    println!("[INFO] Total Depots: {}", depots.len());

    let mut builder = DownloadRequest::builder()
        .app_id(app_id)
        .output_dir(dir)
        .max_downloads(max_downloads);

    for (manifest, key) in depots {
        if !manifest.exists() {
            eprintln!(
                "Error: Manifest file does not exist: {}",
                manifest.display()
            );
            process::exit(1);
        }
        builder = builder.depots([(manifest, key)]);
    }

    let request = match builder.build() {
        Ok(req) => req,
        Err(e) => {
            eprintln!("Error building download request: {}", e);
            process::exit(1);
        }
    };

    let downloader = match DepotDownloader::new() {
        Ok(dl) => dl,
        Err(e) => {
            eprintln!("Error initializing DepotDownloader: {}", e);
            process::exit(1);
        }
    };

    let mut handle = downloader.download(request);
    let mut last_chunk_report: u64 = 0;

    while let Some(event) = handle.events().recv().await {
        match event {
            ProgressEvent::ServerListLoaded { servers } => {
                if !quiet {
                    println!("[INFO] Connected to Valve CDN. Edge servers: {}", servers);
                }
            }
            ProgressEvent::ManifestLoaded {
                depot_id,
                manifest_gid,
                ..
            } => {
                if !quiet {
                    println!(
                        "[INFO] Depot {} manifest loaded (GID: {})",
                        depot_id, manifest_gid
                    );
                }
            }
            ProgressEvent::DepotStarted {
                depot_id,
                files_total,
                bytes_total,
                ..
            } => {
                if !quiet {
                    let mb = bytes_total as f64 / (1024.0 * 1024.0);
                    println!(
                        "[DEPOT_START] Depot {}: {} files ({:.2} MB)",
                        depot_id, files_total, mb
                    );
                }
            }
            ProgressEvent::FileVerifying {
                depot_id: _,
                path: _,
            } => {}
            ProgressEvent::FileStarted {
                depot_id: _,
                path: _,
                size: _,
            } => {}
            ProgressEvent::ChunkCompleted {
                depot_id: _,
                path: _,
                file_bytes_completed: _,
                file_size: _,
                downloaded_increment: _,
                uncompressed_increment: _,
                total_downloaded,
                total_uncompressed,
            } => {
                let current_step = total_downloaded / (5 * 1024 * 1024);
                if current_step > last_chunk_report {
                    last_chunk_report = current_step;
                    if !quiet {
                        let dl_mb = total_downloaded as f64 / (1024.0 * 1024.0);
                        let un_mb = total_uncompressed as f64 / (1024.0 * 1024.0);
                        println!(
                            "[PROGRESS] Transferred: {:.2} MB | Uncompressed: {:.2} MB",
                            dl_mb, un_mb
                        );
                    }
                }
            }
            ProgressEvent::FileCompleted {
                depot_id,
                path,
                depot_bytes_completed,
                depot_bytes_total,
            } => {
                if verbose {
                    let pct = (depot_bytes_completed * 100)
                        .checked_div(depot_bytes_total)
                        .unwrap_or(100);
                    println!(
                        "[FILE] {} (Depot {} progress: {}%)",
                        path.display(),
                        depot_id,
                        pct
                    );
                }
            }
            ProgressEvent::DepotCompleted {
                depot_id,
                downloaded_bytes,
                ..
            } => {
                if !quiet {
                    let mb = downloaded_bytes as f64 / (1024.0 * 1024.0);
                    println!(
                        "[DEPOT_COMPLETE] Depot {} completed ({:.2} MB transferred)",
                        depot_id, mb
                    );
                }
            }
            ProgressEvent::DepotFailed { depot_id, error } => {
                eprintln!("[DEPOT_FAILED] Depot {:?} failed: {}", depot_id, error);
            }
            ProgressEvent::Finished { report } => {
                if report.is_ok() {
                    let dl_mb = report.downloaded_bytes as f64 / (1024.0 * 1024.0);
                    let un_mb = report.uncompressed_bytes as f64 / (1024.0 * 1024.0);
                    println!(
                        "[SUCCESS] Download finished in {:.1}s",
                        report.duration.as_secs_f64()
                    );
                    println!(
                        "[SUCCESS] Network payload: {:.2} MB, Extracted files: {:.2} MB",
                        dl_mb, un_mb
                    );
                } else {
                    eprintln!("[ERROR] Download finished with failures:");
                    for f in report.failed() {
                        eprintln!(
                            "  - Depot {:?}: {}",
                            f.depot_id,
                            f.error.as_deref().unwrap_or("unknown error")
                        );
                    }
                }
                break;
            }
        }
    }

    match handle.join().await {
        Ok(report) => {
            if report.is_ok() {
                process::exit(0);
            } else {
                process::exit(1);
            }
        }
        Err(e) => {
            eprintln!("[FATAL] Download failed: {}", e);
            process::exit(1);
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn valid_multi_depot_with_defaults() {
        let cfg = parse_cli_args([
            "--app",
            "48000",
            "--dir",
            "/tmp/limbo",
            "--depot",
            "/tmp/48001.manifest:deadbeef01",
            "--depot",
            "/tmp/48002.manifest:deadbeef02",
        ])
        .expect("valid args should parse");

        assert_eq!(cfg.app_id, 48000);
        assert_eq!(cfg.dir, PathBuf::from("/tmp/limbo"));
        assert_eq!(
            cfg.depots,
            vec![
                (
                    PathBuf::from("/tmp/48001.manifest"),
                    "deadbeef01".to_string()
                ),
                (
                    PathBuf::from("/tmp/48002.manifest"),
                    "deadbeef02".to_string()
                ),
            ]
        );
        assert_eq!(cfg.max_downloads, 8);
        assert!(!cfg.verbose);
        assert!(!cfg.quiet);
    }

    #[test]
    fn valid_flags_and_colon_in_manifest_path() {
        let cfg = parse_cli_args([
            "--app",
            "105600",
            "--dir",
            "/tmp/terraria",
            "--depot",
            "/tmp/dir:1/depot_105601.manifest:cafebabe",
            "--max-downloads",
            "16",
            "-v",
            "-q",
        ])
        .expect("flags and colon path should parse");

        assert_eq!(cfg.app_id, 105600);
        assert_eq!(cfg.max_downloads, 16);
        assert!(cfg.verbose);
        assert!(cfg.quiet);
        assert_eq!(
            cfg.depots,
            vec![(
                PathBuf::from("/tmp/dir:1/depot_105601.manifest"),
                "cafebabe".to_string()
            )]
        );

        let long_flags = parse_cli_args([
            "--app",
            "105600",
            "--dir",
            "/tmp/terraria",
            "--depot",
            "/tmp/m.manifest:0011",
            "--verbose",
            "--quiet",
        ])
        .expect("long flags should parse");
        assert!(long_flags.verbose);
        assert!(long_flags.quiet);
    }

    #[test]
    fn help_and_empty_args_return_help_requested() {
        assert_eq!(
            parse_cli_args(Vec::<String>::new()),
            Err(CliError::HelpRequested)
        );
        assert_eq!(parse_cli_args(["-h"]), Err(CliError::HelpRequested));
        assert_eq!(parse_cli_args(["--help"]), Err(CliError::HelpRequested));
        assert_eq!(
            parse_cli_args(["--app", "48000", "--help"]),
            Err(CliError::HelpRequested)
        );
    }

    #[test]
    fn missing_required_flags_and_values_fail() {
        assert!(matches!(
            parse_cli_args(["--dir", "/tmp/x", "--depot", "m:k"]),
            Err(CliError::InvalidArg(_))
        ));
        assert!(matches!(
            parse_cli_args(["--app", "48000", "--depot", "m:k"]),
            Err(CliError::InvalidArg(_))
        ));
        assert!(matches!(
            parse_cli_args(["--app", "48000", "--dir", "/tmp/x"]),
            Err(CliError::InvalidArg(_))
        ));
        for flag in ["--app", "--dir", "--depot", "--max-downloads"] {
            assert!(
                matches!(parse_cli_args([flag]), Err(CliError::InvalidArg(_))),
                "flag {flag} without value must fail"
            );
        }
        assert!(matches!(
            parse_cli_args(["--app", "48000", "--dir", "", "--depot", "m:k"]),
            Err(CliError::InvalidArg(_))
        ));
    }

    #[test]
    fn malformed_app_depot_and_max_downloads_fail() {
        assert!(matches!(
            parse_cli_args(["--app", "abc", "--dir", "/tmp/x", "--depot", "m:k"]),
            Err(CliError::InvalidArg(_))
        ));
        for bad_depot in ["nocolon", ":onlykey", "onlymanifest:"] {
            assert!(
                matches!(
                    parse_cli_args(["--app", "48000", "--dir", "/tmp/x", "--depot", bad_depot]),
                    Err(CliError::InvalidArg(_))
                ),
                "malformed depot {bad_depot} must fail"
            );
        }
        for bad_max in ["0", "-1", "abc"] {
            assert!(
                matches!(
                    parse_cli_args([
                        "--app",
                        "48000",
                        "--dir",
                        "/tmp/x",
                        "--depot",
                        "m:k",
                        "--max-downloads",
                        bad_max,
                    ]),
                    Err(CliError::InvalidArg(_))
                ),
                "invalid --max-downloads {bad_max} must fail"
            );
        }
    }

    #[test]
    fn unknown_flags_and_positional_args_fail() {
        assert!(matches!(
            parse_cli_args([
                "--app",
                "48000",
                "--dir",
                "/tmp/x",
                "--depot",
                "m:k",
                "--unknown",
            ]),
            Err(CliError::InvalidArg(_))
        ));
        assert!(matches!(
            parse_cli_args([
                "--app", "48000", "--dir", "/tmp/x", "--depot", "m:k", "extra"
            ]),
            Err(CliError::InvalidArg(_))
        ));
    }
}

use std::env;
use std::path::PathBuf;
use std::process;
use steam_depot_downloader_mod::{DepotDownloader, DownloadRequest, ProgressEvent};

#[tokio::main]
async fn main() {
    let args: Vec<String> = env::args().collect();
    if args.len() < 2 || args.contains(&"--help".to_string()) || args.contains(&"-h".to_string()) {
        eprintln!("Usage: gamectl-depot-dl --app <appid> --dir <dir> --depot <manifest>:<key> [--depot <manifest>:<key> ...] [--max-downloads <n>] [--verbose|-v] [--quiet|-q]");
        process::exit(1);
    }

    let mut app_id: Option<u32> = None;
    let mut dir: Option<PathBuf> = None;
    let mut depots: Vec<(PathBuf, String)> = Vec::new();
    let mut max_downloads: usize = 8;
    let mut verbose: bool = false;
    let mut quiet: bool = false;

    let mut i = 1;
    while i < args.len() {
        match args[i].as_str() {
            "--app" => {
                if i + 1 < args.len() {
                    app_id = args[i + 1].parse().ok();
                    i += 2;
                } else {
                    eprintln!("Error: --app requires an appid");
                    process::exit(1);
                }
            }
            "--dir" => {
                if i + 1 < args.len() {
                    dir = Some(PathBuf::from(&args[i + 1]));
                    i += 2;
                } else {
                    eprintln!("Error: --dir requires a directory path");
                    process::exit(1);
                }
            }
            "--depot" => {
                if i + 1 < args.len() {
                    let pair = &args[i + 1];
                    if let Some(pos) = pair.rfind(':') {
                        let manifest_path = PathBuf::from(&pair[..pos]);
                        let key = pair[pos + 1..].to_string();
                        depots.push((manifest_path, key));
                    } else {
                        eprintln!("Error: --depot requires format <manifest_path>:<hex_key>");
                        process::exit(1);
                    }
                    i += 2;
                } else {
                    eprintln!("Error: --depot requires an argument");
                    process::exit(1);
                }
            }
            "--max-downloads" => {
                if i + 1 < args.len() {
                    max_downloads = args[i + 1].parse().unwrap_or(8);
                    i += 2;
                } else {
                    i += 1;
                }
            }
            "--verbose" | "-v" => {
                verbose = true;
                i += 1;
            }
            "--quiet" | "-q" => {
                quiet = true;
                i += 1;
            }
            _ => {
                i += 1;
            }
        }
    }

    let app_id = match app_id {
        Some(id) => id,
        None => {
            eprintln!("Error: Missing required --app <appid>");
            process::exit(1);
        }
    };

    let dir = match dir {
        Some(d) => d,
        None => {
            eprintln!("Error: Missing required --dir <output_dir>");
            process::exit(1);
        }
    };

    if depots.is_empty() {
        eprintln!("Error: At least one --depot <manifest>:<key> is required");
        process::exit(1);
    }

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
            eprintln!("Error: Manifest file does not exist: {}", manifest.display());
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
            ProgressEvent::ManifestLoaded { depot_id, manifest_gid, .. } => {
                if !quiet {
                    println!("[INFO] Depot {} manifest loaded (GID: {})", depot_id, manifest_gid);
                }
            }
            ProgressEvent::DepotStarted { depot_id, files_total, bytes_total, .. } => {
                if !quiet {
                    let mb = bytes_total as f64 / (1024.0 * 1024.0);
                    println!("[DEPOT_START] Depot {}: {} files ({:.2} MB)", depot_id, files_total, mb);
                }
            }
            ProgressEvent::FileVerifying { depot_id: _, path: _ } => {}
            ProgressEvent::FileStarted { depot_id: _, path: _, size: _ } => {}
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
                        println!("[PROGRESS] Transferred: {:.2} MB | Uncompressed: {:.2} MB", dl_mb, un_mb);
                    }
                }
            }
            ProgressEvent::FileCompleted { depot_id, path, depot_bytes_completed, depot_bytes_total } => {
                if verbose {
                    let pct = if depot_bytes_total > 0 {
                        (depot_bytes_completed * 100) / depot_bytes_total
                    } else {
                        100
                    };
                    println!("[FILE] {} (Depot {} progress: {}%)", path.display(), depot_id, pct);
                }
            }
            ProgressEvent::DepotCompleted { depot_id, downloaded_bytes, .. } => {
                if !quiet {
                    let mb = downloaded_bytes as f64 / (1024.0 * 1024.0);
                    println!("[DEPOT_COMPLETE] Depot {} completed ({:.2} MB transferred)", depot_id, mb);
                }
            }
            ProgressEvent::DepotFailed { depot_id, error } => {
                eprintln!("[DEPOT_FAILED] Depot {:?} failed: {}", depot_id, error);
            }
            ProgressEvent::Finished { report } => {
                if report.is_ok() {
                    let dl_mb = report.downloaded_bytes as f64 / (1024.0 * 1024.0);
                    let un_mb = report.uncompressed_bytes as f64 / (1024.0 * 1024.0);
                    println!("[SUCCESS] Download finished in {:.1}s", report.duration.as_secs_f64());
                    println!("[SUCCESS] Network payload: {:.2} MB, Extracted files: {:.2} MB", dl_mb, un_mb);
                } else {
                    eprintln!("[ERROR] Download finished with failures:");
                    for f in report.failed() {
                        eprintln!("  - Depot {:?}: {}", f.depot_id, f.error.as_deref().unwrap_or("unknown error"));
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

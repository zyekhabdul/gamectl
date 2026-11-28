use std::io::BufRead as _;
use std::path::PathBuf;
use std::process::ExitCode;

use reqwest::Client;

use gamectl_core::api::{build_catalog_list, fetch_catalog_item_title, resolve_manifest_target};
use gamectl_core::auth::{
    EpicSession, ensure_valid_session, epic_auth_url, exchange_authorization_code,
    load_session_from_disk, safe_status_summary, save_session_to_path, session_file_path,
};
use gamectl_core::download::download_and_install;
use gamectl_core::manifest::parse_manifest_bytes;
use gamectl_core::{CoreError, Result};

#[tokio::main(flavor = "multi_thread")]
async fn main() -> ExitCode {
    let args: Vec<String> = std::env::args().skip(1).collect();
    if args.is_empty() || matches!(args[0].as_str(), "--help" | "-h" | "help") {
        print_usage();
        return ExitCode::SUCCESS;
    }

    let res = match args[0].as_str() {
        "epic" => handle_epic(&args[1..]).await,
        "--version" | "-v" => {
            println!("gamectl-core v{}", env!("CARGO_PKG_VERSION"));
            Ok(())
        }
        other => Err(CoreError::InvalidInput(format!(
            "unknown subcommand '{other}'"
        ))),
    };

    match res {
        Ok(()) => ExitCode::SUCCESS,
        Err(err) => {
            eprintln!("[ERROR] {err}");
            ExitCode::FAILURE
        }
    }
}

fn print_usage() {
    println!(
        "gamectl-core - MIT Native Engine for gamectl\n\n\
         Usage:\n  \
         gamectl-core epic auth-url\n  \
         gamectl-core epic auth [--code <code>] [--json <session_file>]\n  \
         gamectl-core epic status\n  \
         gamectl-core epic list [--json]\n  \
         gamectl-core epic info <app_name> [--json]\n  \
         gamectl-core epic install <app_name> --dir <target_dir> [--platform <Windows|Linux>] [--dry-run]\n  \
         gamectl-core epic manifest-inspect <path.manifest>"
    );
}

fn build_http() -> Result<Client> {
    Ok(Client::builder()
        .user_agent(
            "UELauncher/14.0.8-22004686+++Portal+Release-Live Windows/10.0.19044.1.256.64bit",
        )
        .connect_timeout(std::time::Duration::from_secs(15))
        .build()?)
}

async fn handle_epic(args: &[String]) -> Result<()> {
    let sub = args.first().map(String::as_str).unwrap_or("status");
    let rest = if args.is_empty() { &[] } else { &args[1..] };
    let http = build_http()?;

    match sub {
        "auth-url" => {
            println!("{}", epic_auth_url());
            Ok(())
        }
        "status" => {
            println!("{}", safe_status_summary());
            Ok(())
        }
        "auth" => cmd_epic_auth(&http, rest).await,
        "list" => cmd_epic_list(&http, rest).await,
        "info" => cmd_epic_info(&http, rest).await,
        "install" => cmd_epic_install(&http, rest).await,
        "manifest-inspect" => cmd_manifest_inspect(rest),
        "--help" | "-h" | "help" => {
            print_usage();
            Ok(())
        }
        other => Err(CoreError::InvalidInput(format!(
            "unknown epic command '{other}'"
        ))),
    }
}

async fn cmd_epic_auth(http: &Client, args: &[String]) -> Result<()> {
    let mut code = String::new();
    let mut json_file = String::new();
    let mut i = 0;
    while i < args.len() {
        match args[i].as_str() {
            "--code" if i + 1 < args.len() => {
                code = args[i + 1].clone();
                i += 2;
            }
            "--json" if i + 1 < args.len() => {
                json_file = args[i + 1].clone();
                i += 2;
            }
            arg if !arg.starts_with('-') && code.is_empty() => {
                code = arg.to_string();
                i += 1;
            }
            other => {
                return Err(CoreError::InvalidInput(format!(
                    "unexpected option '{other}' for epic auth"
                )));
            }
        }
    }

    if !json_file.is_empty() {
        let raw = std::fs::read_to_string(&json_file)?;
        let sess: EpicSession = serde_json::from_str(&raw)?;
        save_session_to_path(&session_file_path(), &sess)?;
        println!("[VERIFIED] Imported Epic session ({}).", sess.display_name);
        return Ok(());
    }

    if code.is_empty() {
        println!("Open this URL in your browser and copy the 'authorizationCode' value:");
        println!("  {}", epic_auth_url());
        eprint!("Authorization code: ");
        let stdin = std::io::stdin();
        let mut line = String::new();
        stdin.lock().read_line(&mut line)?;
        code = line.trim().to_string();
    }

    let sess = exchange_authorization_code(http, &code).await?;
    let acct = if !sess.display_name.is_empty() {
        sess.display_name
    } else {
        sess.account_id
    };
    println!("[VERIFIED] Authenticated Epic account: {acct}");
    Ok(())
}

async fn cmd_epic_list(http: &Client, args: &[String]) -> Result<()> {
    let as_json = args.iter().any(|a| a == "--json");
    let session = ensure_valid_session(http).await?;
    let rows = build_catalog_list(http, &session).await?;
    if as_json {
        println!("{}", serde_json::to_string(&rows)?);
    } else {
        for r in rows {
            println!("{}\t{}\t{}", r.app_name, r.app_title, r.build_version);
        }
    }
    Ok(())
}

async fn cmd_epic_info(http: &Client, args: &[String]) -> Result<()> {
    let app_name = args.iter().find(|a| !a.starts_with('-')).ok_or_else(|| {
        CoreError::InvalidInput("Usage: gamectl-core epic info <app_name> [--json]".to_string())
    })?;
    let session = ensure_valid_session(http).await?;
    let target = resolve_manifest_target(http, &session, app_name, "Windows").await?;
    let mf_bytes = http.get(&target.manifest_url).send().await?.bytes().await?;
    let parsed = parse_manifest_bytes(&mf_bytes)?;
    let (title, dev, dlc_count) =
        fetch_catalog_item_title(http, &session, &target.namespace, &target.catalog_item_id)
            .await
            .unwrap_or_else(|| (app_name.clone(), String::new(), 0));

    let dlcs: Vec<serde_json::Value> = (0..dlc_count).map(|_| serde_json::json!({})).collect();
    let payload = serde_json::json!({
        "app_name": target.app_name,
        "game": {
            "title": title,
            "developer": dev,
            "app_version": parsed.build_version,
            "dlc_list": dlcs,
        },
        "manifest": {
            "download_size": parsed.total_download_size(),
            "disk_size": parsed.total_disk_size(),
            "version": parsed.build_version,
            "launch_exe": parsed.launch_exe,
        }
    });
    println!("{}", serde_json::to_string(&payload)?);
    Ok(())
}

async fn cmd_epic_install(http: &Client, args: &[String]) -> Result<()> {
    let mut app_name = String::new();
    let mut target_dir = String::new();
    let mut platform = "Windows".to_string();
    let mut dry_run = false;

    let mut i = 0;
    while i < args.len() {
        match args[i].as_str() {
            "--dir" | "--game-folder" if i + 1 < args.len() => {
                target_dir = args[i + 1].clone();
                i += 2;
            }
            "--platform" if i + 1 < args.len() => {
                platform = args[i + 1].clone();
                i += 2;
            }
            "--dry-run" | "-n" => {
                dry_run = true;
                i += 1;
            }
            "-y" | "--yes" => {
                i += 1;
            }
            arg if !arg.starts_with('-') && app_name.is_empty() => {
                app_name = arg.to_string();
                i += 1;
            }
            other => {
                return Err(CoreError::InvalidInput(format!(
                    "unexpected option '{other}' for epic install"
                )));
            }
        }
    }

    if app_name.is_empty() || target_dir.is_empty() {
        return Err(CoreError::InvalidInput(
            "Usage: gamectl-core epic install <app_name> --dir <target_dir> [--platform Windows]"
                .to_string(),
        ));
    }

    if load_session_from_disk().is_none() {
        return Err(CoreError::Auth(
            "Epic session missing; run 'gamectl epic auth'".to_string(),
        ));
    }
    let session = ensure_valid_session(http).await?;
    let target = resolve_manifest_target(http, &session, &app_name, &platform).await?;
    let mf_bytes = http.get(&target.manifest_url).send().await?.bytes().await?;
    let parsed = parse_manifest_bytes(&mf_bytes)?;

    if dry_run {
        println!(
            "[DRY-RUN] Epic app={} version={} files={} dl_bytes={} disk_bytes={}",
            target.app_name,
            parsed.build_version,
            parsed.files.len(),
            parsed.total_download_size(),
            parsed.total_disk_size()
        );
        return Ok(());
    }

    let (title, _, _) =
        fetch_catalog_item_title(http, &session, &target.namespace, &target.catalog_item_id)
            .await
            .unwrap_or_else(|| (app_name.clone(), String::new(), 0));

    let dest = PathBuf::from(&target_dir);
    download_and_install(http, &target, &parsed, &dest, &title, &platform).await?;
    println!(
        "[VERIFIED] Epic install complete: {} ({}) -> {}",
        title,
        target.app_name,
        dest.display()
    );
    Ok(())
}

fn cmd_manifest_inspect(args: &[String]) -> Result<()> {
    let path = args.first().ok_or_else(|| {
        CoreError::InvalidInput("Usage: gamectl-core epic manifest-inspect <file>".to_string())
    })?;
    let raw = std::fs::read(path)?;
    let parsed = parse_manifest_bytes(&raw)?;
    let out = serde_json::json!({
        "app_name": parsed.app_name,
        "build_version": parsed.build_version,
        "feature_level": parsed.feature_level,
        "launch_exe": parsed.launch_exe,
        "files": parsed.files.len(),
        "chunks": parsed.chunks.len(),
        "download_bytes": parsed.total_download_size(),
        "disk_bytes": parsed.total_disk_size(),
    });
    println!("{}", serde_json::to_string_pretty(&out)?);
    Ok(())
}

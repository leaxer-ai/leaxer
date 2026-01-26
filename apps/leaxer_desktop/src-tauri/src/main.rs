// Prevents additional console window on Windows in release
#![cfg_attr(not(debug_assertions), windows_subsystem = "windows")]

use tauri::Manager;
use std::sync::Mutex;
use std::process::{Command, Child};
use std::path::PathBuf;
use std::fs;
use std::io::Write;

/// Log to file for debugging (since console is hidden in release)
fn log_to_file(msg: &str) {
    if let Some(dir) = get_leaxer_user_dir() {
        let _ = fs::create_dir_all(&dir);
        let log_path = dir.join("startup.log");
        if let Ok(mut file) = fs::OpenOptions::new()
            .create(true)
            .append(true)
            .open(&log_path)
        {
            let timestamp = std::time::SystemTime::now()
                .duration_since(std::time::UNIX_EPOCH)
                .map(|d| d.as_secs())
                .unwrap_or(0);
            let _ = writeln!(file, "[{}] {}", timestamp, msg);
        }
    }
}

#[cfg(target_os = "windows")]
use std::os::windows::process::CommandExt;

#[cfg(target_os = "windows")]
const CREATE_NO_WINDOW: u32 = 0x08000000;

struct BackendState {
    child: Option<Child>,
}

/// Get the Leaxer user data directory path
fn get_leaxer_user_dir() -> Option<PathBuf> {
    #[cfg(target_os = "windows")]
    {
        dirs::document_dir().map(|p| p.join("Leaxer"))
    }
    #[cfg(target_os = "macos")]
    {
        dirs::document_dir().map(|p| p.join("Leaxer"))
    }
    #[cfg(target_os = "linux")]
    {
        dirs::data_dir().map(|p| p.join("Leaxer"))
    }
}

/// Check if network exposure is enabled in config.json
fn is_network_exposure_enabled() -> bool {
    let config_path = match get_leaxer_user_dir() {
        Some(dir) => dir.join("config.json"),
        None => return false,
    };

    match fs::read_to_string(&config_path) {
        Ok(content) => {
            match serde_json::from_str::<serde_json::Value>(&content) {
                Ok(config) => {
                    config.get("network_exposure_enabled")
                        .and_then(|v| v.as_bool())
                        .unwrap_or(false)
                }
                Err(_) => false,
            }
        }
        Err(_) => false,
    }
}

fn main() {
    tauri::Builder::default()
        .plugin(tauri_plugin_shell::init())
        .plugin(tauri_plugin_dialog::init())
        .plugin(tauri_plugin_fs::init())
        .plugin(tauri_plugin_http::init())
        .manage(Mutex::new(BackendState { child: None }))
        .setup(|app| {
            // Try multiple locations for the backend:
            // 1. Bundled resources (for installer builds)
            // 2. Next to executable (for portable builds)
            let resource_path = app.path().resource_dir().ok();
            let exe_dir = std::env::current_exe()
                .ok()
                .and_then(|p| p.parent().map(|p| p.to_path_buf()));

            #[cfg(target_os = "windows")]
            let backend_filename = std::path::PathBuf::from("leaxer_core").join("bin").join("leaxer_core.bat");
            #[cfg(not(target_os = "windows"))]
            let backend_filename = std::path::PathBuf::from("leaxer_core").join("bin").join("leaxer_core");

            // Check bundled resources first, then portable location
            let backend_exe = resource_path
                .map(|p| p.join(&backend_filename))
                .filter(|p| p.exists())
                .or_else(|| exe_dir.clone().map(|p| p.join("resources").join(&backend_filename)).filter(|p| p.exists()))
                .or_else(|| exe_dir.map(|p| p.join(&backend_filename)).filter(|p| p.exists()));

            log_to_file("[Leaxer] Looking for backend...");

            if let Some(ref backend_exe) = backend_exe {
                log_to_file(&format!("[Leaxer] Found backend at: {:?}", backend_exe));

                // Get the release root directory (parent of bin/)
                let release_root = backend_exe.parent()
                    .and_then(|p| p.parent())
                    .map(|p| p.to_path_buf());

                // Spawn the backend process with required environment variables
                #[cfg(target_os = "windows")]
                let mut cmd = Command::new("cmd");
                #[cfg(target_os = "windows")]
                {
                    cmd.args(["/C", backend_exe.to_str().unwrap(), "start"]);
                    cmd.creation_flags(CREATE_NO_WINDOW); // Hide console window
                    if let Some(ref root) = release_root {
                        cmd.current_dir(root);
                    }
                }

                #[cfg(not(target_os = "windows"))]
                let mut cmd = Command::new(&backend_exe);
                #[cfg(not(target_os = "windows"))]
                {
                    cmd.arg("start");
                    if let Some(ref root) = release_root {
                        cmd.current_dir(root);
                    }
                }

                // Set required environment variables for Phoenix
                cmd.env("PHX_SERVER", "true");
                cmd.env("PHX_HOST", "localhost");
                cmd.env("SECRET_KEY_BASE", "leaxer_desktop_secret_key_base_that_is_at_least_64_bytes_long_for_security");
                cmd.env("SIGNING_SALT", "leaxer_desktop_signing_salt");
                cmd.env("CORS_ORIGINS", "http://localhost:4000,http://127.0.0.1:4000,https://tauri.localhost,tauri://localhost");

                // Check if network exposure is enabled and set env var
                let network_enabled = is_network_exposure_enabled();
                if network_enabled {
                    log_to_file("[Leaxer] Network exposure enabled, binding to all interfaces");
                    cmd.env("LEAXER_BIND_ALL_INTERFACES", "true");
                }

                log_to_file(&format!("[Leaxer] Spawning command..."));

                match cmd.spawn() {
                    Ok(process) => {
                        log_to_file(&format!("[Leaxer] Backend started with PID: {}", process.id()));
                        let state = app.state::<Mutex<BackendState>>();
                        state.lock().unwrap().child = Some(process);
                    }
                    Err(e) => {
                        log_to_file(&format!("[Leaxer] Failed to start backend: {}", e));
                    }
                }
            } else {
                log_to_file("[Leaxer] Backend not found, running in dev mode (connect to localhost:4000)");
            }

            Ok(())
        })
        .on_window_event(|window, event| {
            if let tauri::WindowEvent::CloseRequested { .. } = event {
                // Kill the backend when the window is closed
                let state = window.state::<Mutex<BackendState>>();
                let mut guard = state.lock().unwrap();
                if let Some(ref mut child) = guard.child {
                    println!("[Leaxer] Stopping backend...");
                    let _ = child.kill();
                }
                guard.child = None;

                // Kill epmd (Erlang Port Mapper Daemon) on Windows
                #[cfg(target_os = "windows")]
                {
                    let _ = Command::new("taskkill")
                        .args(["/F", "/IM", "epmd.exe"])
                        .creation_flags(CREATE_NO_WINDOW)
                        .spawn();
                }
            }
        })
        .run(tauri::generate_context!())
        .expect("error while running tauri application");
}

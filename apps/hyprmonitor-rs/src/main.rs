mod collect;
mod config;
mod context;
mod desktop;
mod details;
mod explorer;
mod ipc;
mod render;
mod session;
mod ui;
mod window;

use collect::Collector;
use config::Config;
use render::Renderer;
use std::{
    env,
    path::PathBuf,
    thread,
    time::{Duration, Instant},
};

const HELP: &str = "hyprmonitor — native Rust desktop system monitor

Usage: hyprmonitor [--config PATH] [COMMAND]

  --desktop                 Auto-select a desktop overlay or normal window (default)
  --window                  Normal native Wayland/X11 window
  --overlay                 Require a wlr-layer-shell desktop overlay
  --settings                Open the running app’s own settings menu
  --toggle-workspace        Optional Hyprland workspace-specific toggle
  --once                    Print one JSON sample; interval counters start unknown
  --watch                   Stream JSON samples at the configured interval
  --preview FILE.png        Render real readings to PNG without a desktop connection
  --benchmark SECONDS       Measure collection + rendering at the normal cadence
  --benchmark-collector N   Measure collection only (excludes desktop/rendering)
  --show / --hide / --toggle Control the running overlay; hiding pauses collection
  --quit                    Stop the running overlay
  --check-config            Validate configuration without changing it
  --print-config            Print defaults as TOML
  --help                    Show this help

Config: $XDG_CONFIG_HOME/hyprmonitor/config.toml (or ~/.config/hyprmonitor/config.toml)
Right-click anywhere inside the monitor for its own settings.
Overlay mode needs wlr-layer-shell; normal window mode works on Linux Wayland/X11.
";

enum Mode {
    Desktop,
    Window,
    Overlay,
    Once,
    Watch,
    Preview(PathBuf),
    Benchmark(u64, bool),
    Control(String),
    Check,
    Print,
    Help,
}

fn args() -> Result<(Option<PathBuf>, Mode), String> {
    let mut args = env::args().skip(1);
    let mut config = None;
    let mut mode = None;
    while let Some(arg) = args.next() {
        if arg == "--config" {
            if config.is_some() {
                return Err("--config specified twice".into());
            }
            config = Some(PathBuf::from(args.next().ok_or("--config needs a path")?));
            continue;
        }
        if mode.is_some() {
            return Err("Choose one command; use --help for usage".into());
        }
        mode = Some(match arg.as_str() {
            "--help" | "-h" => Mode::Help,
            "--desktop" => Mode::Desktop,
            "--window" => Mode::Window,
            "--overlay" => Mode::Overlay,
            "--once" => Mode::Once,
            "--watch" => Mode::Watch,
            "--preview" => Mode::Preview(args.next().ok_or("--preview needs a PNG path")?.into()),
            "--benchmark" | "--benchmark-collector" => {
                let seconds = args
                    .next()
                    .ok_or("benchmark needs seconds")?
                    .parse::<u64>()
                    .map_err(|_| "seconds must be an integer")?;
                if !(2..=3600).contains(&seconds) {
                    return Err("benchmark seconds must be 2–3600".into());
                }
                Mode::Benchmark(seconds, arg == "--benchmark")
            }
            "--show" | "--hide" | "--toggle" | "--quit" | "--settings" | "--toggle-workspace" => {
                Mode::Control(arg.trim_start_matches("--").into())
            }
            "--check-config" => Mode::Check,
            "--print-config" => Mode::Print,
            _ => return Err(format!("Unknown argument {arg}; use --help")),
        });
    }
    Ok((config, mode.unwrap_or(Mode::Desktop)))
}

fn run() -> Result<(), String> {
    let (path, mode) = args()?;
    match mode {
        Mode::Help => {
            print!("{HELP}");
            return Ok(());
        }
        Mode::Print => {
            print!(
                "{}",
                toml::to_string_pretty(&Config::default()).map_err(|e| e.to_string())?
            );
            return Ok(());
        }
        Mode::Control(command) => return control_or_start(path, &command),
        _ => {}
    }
    let config = Config::load(path)?;
    match mode {
        Mode::Desktop => {
            if config.mode == "window" {
                return window::run(config);
            }
            match desktop::run(config.clone()) {
                Ok(()) => Ok(()),
                Err(error)
                    if config.mode == "auto"
                        && (error.starts_with("Cannot connect to Wayland")
                            || error.starts_with("Compositor needs wlr-layer-shell")) =>
                {
                    eprintln!("Overlay unavailable; opening a normal window ({error})");
                    window::run(config)
                }
                Err(error) => Err(error),
            }
        }
        Mode::Window => window::run(config),
        Mode::Overlay => desktop::run(config),
        Mode::Check => {
            println!("Configuration is valid");
            Ok(())
        }
        Mode::Once => {
            println!(
                "{}",
                serde_json::to_string(&Collector::new(config).sample())
                    .map_err(|e| e.to_string())?
            );
            Ok(())
        }
        Mode::Watch => {
            let mut collector = Collector::new(config.clone());
            loop {
                let start = Instant::now();
                println!(
                    "{}",
                    serde_json::to_string(&collector.sample()).map_err(|e| e.to_string())?
                );
                thread::sleep(
                    Duration::from_millis(config.interval_ms).saturating_sub(start.elapsed()),
                );
            }
        }
        Mode::Preview(path) => {
            if path.extension().is_none_or(|e| e != "png") {
                return Err("Preview path must end with .png".into());
            }
            let mut collector = Collector::new(config.clone());
            collector.sample();
            thread::sleep(Duration::from_millis(500));
            let data = collector.sample();
            let mut renderer = Renderer::new(config.clone())?;
            let image = if config.mode == "window" {
                renderer.render_window(
                    &data,
                    config.width,
                    config.height,
                    0,
                    0,
                    &crate::explorer::Explorer::default(),
                )?
            } else {
                renderer.render(&data, config.width, config.height)?
            };
            image.save_png(&path).map_err(|e| e.to_string())?;
            println!("Preview: {}", path.display());
            Ok(())
        }
        Mode::Benchmark(seconds, render) => benchmark(config, seconds, render),
        Mode::Help | Mode::Print | Mode::Control(_) => unreachable!(),
    }
}

fn control_or_start(path: Option<PathBuf>, command: &str) -> Result<(), String> {
    let error = match desktop::control(command) {
        Ok(()) => return Ok(()),
        Err(error) => error,
    };
    if !error.starts_with("No running Hyprmonitor")
        || !["show", "toggle", "settings", "toggle-workspace"].contains(&command)
    {
        return Err(error);
    }
    let mut process = std::process::Command::new(env::current_exe().map_err(|e| e.to_string())?);
    if let Some(path) = path {
        process.arg("--config").arg(path);
    }
    process
        .arg("--desktop")
        .stdin(std::process::Stdio::null())
        .stdout(std::process::Stdio::null());
    let mut child = process.spawn().map_err(|e| e.to_string())?;
    for _ in 0..100 {
        if let Some(status) = child.try_wait().map_err(|e| e.to_string())? {
            return Err(format!("Hyprmonitor startup failed: {status}"));
        }
        if desktop::control(command).is_ok() {
            return Ok(());
        }
        thread::sleep(Duration::from_millis(50));
    }
    Err("Hyprmonitor did not become ready within five seconds".into())
}

fn cpu_ticks() -> u64 {
    let text = collect::read("/proc/self/stat");
    let Some((_, rest)) = text.rsplit_once(')') else {
        return 0;
    };
    rest.split_whitespace()
        .skip(11)
        .take(2)
        .filter_map(|s| s.parse::<u64>().ok())
        .sum()
}
fn status_kib(name: &str) -> Option<u64> {
    collect::read("/proc/self/status").lines().find_map(|l| {
        l.strip_prefix(name)
            .and_then(|s| s.split_whitespace().next())
            .and_then(|s| s.parse().ok())
    })
}
fn percentile(values: &[u64], p: f64) -> f64 {
    if values.is_empty() {
        return 0.0;
    }
    let mut values = values.to_vec();
    values.sort_unstable();
    values[((values.len() - 1) as f64 * p).ceil() as usize] as f64 / 1000.0
}

fn benchmark(config: Config, seconds: u64, draw: bool) -> Result<(), String> {
    let start = Instant::now();
    let before = cpu_ticks();
    let mut collector = Collector::new(config.clone());
    let mut renderer = if draw {
        Some(Renderer::new(config.clone())?)
    } else {
        None
    };
    let mut collection = vec![];
    let mut rendering = vec![];
    while start.elapsed() < Duration::from_secs(seconds) {
        let frame = Instant::now();
        let data = collector.sample();
        collection.push(data.collection_us);
        if let Some(renderer) = renderer.as_mut() {
            let render = Instant::now();
            let _ = renderer.render(&data, config.width, config.height)?;
            rendering.push(render.elapsed().as_micros() as u64);
        }
        let left = Duration::from_secs(seconds).saturating_sub(start.elapsed());
        thread::sleep(
            Duration::from_millis(config.interval_ms)
                .saturating_sub(frame.elapsed())
                .min(left),
        );
    }
    let wall = start.elapsed().as_secs_f64();
    let cpu =
        cpu_ticks().saturating_sub(before) as f64 / rustix::param::clock_ticks_per_second() as f64;
    let report = serde_json::json!({
        "mode":if draw {"collector+software-renderer"} else {"collector-only"},
        "wall_seconds":wall,"samples":collection.len(),"interval_ms":config.interval_ms,
        "cpu_percent_one_thread":cpu/wall*100.0,
        "rss_mib":status_kib("VmRSS:").map(|n|n as f64/1024.0),
        "peak_rss_mib":status_kib("VmHWM:").map(|n|n as f64/1024.0),
        "collection_ms_p50":percentile(&collection,0.5),"collection_ms_p95":percentile(&collection,0.95),
        "render_ms_p50":percentile(&rendering,0.5),"render_ms_p95":percentile(&rendering,0.95),
        "scope":"Includes startup/font/cache costs. Does not include Wayland buffers, compositor, GPU, or other desktop processes. /proc reflects this process namespace."
    });
    println!(
        "{}",
        serde_json::to_string_pretty(&report).map_err(|e| e.to_string())?
    );
    Ok(())
}

fn main() {
    if let Err(error) = run() {
        eprintln!("hyprmonitor: {error}");
        std::process::exit(1);
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn latency_percentiles_are_bounded() {
        assert_eq!(percentile(&[], 0.95), 0.0);
        assert_eq!(percentile(&[1000, 3000, 2000], 0.95), 3.0);
    }
}

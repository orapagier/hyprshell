mod config;
mod desktop;
mod ipc;
mod render;
mod wallpaper;
use config::Config;
use std::{fs::File, io::BufWriter, time::Instant};

const HELP: &str = "Hyprmatrix — wallpaper-aware desktop digital rain\n\n\
  hyprmatrix                    Start (or show the running instance)\n\
  --settings                    Open hidden settings (starts app if needed)\n\
  --fullscreen / --region        Start using this placement\n\
  --show / --hide / --toggle     Control running app; hide pauses animation\n\
  --toggle-workspace             Toggle rain on the active workspace only\n\
                                 (starts the app when it is not running)\n\
  --drag-begin / --drag-end      Region drag handshake for Super+left click\n\
  --quit                        Stop the running app\n\
  --refresh                     Refresh wallpaper color\n\
  --check-config                Validate ~/.config/hyprmatrix/config.toml\n\
  --print-config                Print default TOML\n\
  --preview FILE.png            Save a 1280x720 transparent rain preview\n\
  --preview-settings FILE.png   Save a preview with settings visible\n\
  --benchmark SECONDS           Measure 1920x1080 software rendering\n\n\
Right-click the invisible 44px upper-right corner, or the panel, to close settings.\n\
Drag the settings panel to move the rain region; Super+left click also drags it.\n\
Rain is opt-in per workspace; use the keybinding or --toggle-workspace.\n\
Runs beneath application windows; other desktop clicks pass through.\n\
Configuration: $XDG_CONFIG_HOME/hyprmatrix/config.toml\n";
fn main() {
    if let Err(e) = run() {
        eprintln!("hyprmatrix: {e}");
        std::process::exit(1);
    }
}
fn run() -> Result<(), String> {
    let args: Vec<String> = std::env::args().skip(1).collect();
    let command = args.first().map(String::as_str).unwrap_or("");
    if command == "--help" || command == "-h" {
        print!("{HELP}");
        return Ok(());
    }
    if command == "--print-config" {
        print!("{}", toml::to_string_pretty(&Config::default()).unwrap());
        return Ok(());
    }
    let mut c = Config::load()?;
    match command {
        "--check-config" => {
            println!("Configuration valid: {}", Config::path().display());
            Ok(())
        }
        "--preview" | "--preview-settings" | "--benchmark" => {
            if args.len() != 2 {
                return Err("Provide a filename or benchmark duration".into());
            }
            let mut r = render::Renderer::new(&c)?;
            let color = wallpaper::current_path(c.output.as_deref().unwrap_or(""))
                .and_then(|p| wallpaper::sample(&p))
                .unwrap_or(wallpaper::FALLBACK);
            r.color = c.color(color).map(|v| v as f32);
            if command != "--benchmark" {
                let (w, h) = (1280, 720);
                let mut pixels = vec![0u32; (w * h) as usize];
                r.render(
                    &mut pixels,
                    w,
                    h,
                    &c,
                    12.0,
                    1.0,
                    c.color(color),
                    command
                        .eq("--preview-settings")
                        .then(|| render::menu_rect(1280, 720)),
                    "",
                );
                let bytes: Vec<u8> = pixels
                    .iter()
                    .flat_map(|p| {
                        let a = p >> 24;
                        let channel = |shift: u32| {
                            ((p >> shift & 255) * 255)
                                .checked_div(a)
                                .unwrap_or(0)
                                .min(255) as u8
                        };
                        [channel(16), channel(8), channel(0), a as u8]
                    })
                    .collect();
                let f = BufWriter::new(File::create(&args[1]).map_err(|e| e.to_string())?);
                let mut encoder = png::Encoder::new(f, w, h);
                encoder.set_color(png::ColorType::Rgba);
                encoder.set_depth(png::BitDepth::Eight);
                encoder
                    .write_header()
                    .map_err(|e| e.to_string())?
                    .write_image_data(&bytes)
                    .map_err(|e| e.to_string())?;
                println!("Preview: {}", args[1]);
            } else {
                let seconds: f32 = args[1].parse().map_err(|_| "Invalid duration")?;
                if !seconds.is_finite() || !(0.1..=60.0).contains(&seconds) {
                    return Err("Duration must be 0.1..60 seconds".into());
                }
                let mut pixels = vec![0u32; 1920 * 1080];
                let start = Instant::now();
                let mut frames = 0u64;
                while start.elapsed().as_secs_f32() < seconds {
                    r.render(
                        &mut pixels,
                        1920,
                        1080,
                        &c,
                        frames as f32 / c.fps as f32,
                        1.0 / c.fps as f32,
                        c.color(color),
                        None,
                        "",
                    );
                    std::hint::black_box(&pixels);
                    frames += 1;
                }
                let ms = start.elapsed().as_secs_f64() * 1000.0 / frames as f64;
                println!("1920x1080: {frames} frames, {ms:.3} ms/frame; estimated rendering CPU at {} FPS: {:.1}% of one core (excludes compositor)",c.fps,ms*c.fps as f64/10.0);
            }
            Ok(())
        }
        "" | "--settings" | "--fullscreen" | "--region" => {
            let control = match command {
                "--settings" => "settings",
                "--fullscreen" => "fullscreen",
                "--region" => "region",
                _ => "show",
            };
            if desktop::control(control).is_ok() {
                return Ok(());
            }
            if command == "--fullscreen" {
                c.fullscreen = true;
            } else if command == "--region" {
                c.fullscreen = false;
            }
            desktop::run(c, command == "--settings")
        }
        "--show" | "--hide" | "--toggle" | "--quit" | "--refresh" | "--drag-begin"
        | "--drag-end" => desktop::control(&command[2..]),
        "--toggle-workspace" => {
            if desktop::control("toggle-workspace").is_err() {
                // Not running: fresh start enables rain on this workspace.
                desktop::run(c, false)?;
            }
            Ok(())
        }
        _ => Err(format!("Unknown option {command}; use --help")),
    }
}

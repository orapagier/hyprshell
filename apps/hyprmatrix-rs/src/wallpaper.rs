//! Query paths cheaply; decode a tiny thumbnail only when the image changes.
use std::{
    io::Read,
    process::{Command, Stdio},
    thread,
    time::{Duration, Instant},
};
pub const FALLBACK: [u8; 3] = [80, 210, 175];

pub fn bounded_output(mut command: Command, limit: usize) -> Result<Vec<u8>, String> {
    let mut child = command
        .stdout(Stdio::piped())
        .stderr(Stdio::null())
        .spawn()
        .map_err(|e| e.to_string())?;
    // Read concurrently so even unexpectedly large output cannot fill the pipe and block the child.
    let stdout = child.stdout.take().ok_or("No child stdout")?;
    let reader = thread::spawn(move || {
        let mut data = Vec::new();
        stdout
            .take(limit as u64)
            .read_to_end(&mut data)
            .map(|_| data)
    });
    let start = Instant::now();
    let result = loop {
        match child.try_wait() {
            Ok(Some(status)) => {
                break if status.success() {
                    Ok(())
                } else {
                    Err("Wallpaper helper failed".into())
                }
            }
            Ok(None) if start.elapsed() < Duration::from_secs(3) => {
                thread::sleep(Duration::from_millis(20))
            }
            _ => {
                let _ = child.kill();
                let _ = child.wait();
                break Err("Wallpaper helper timed out".into());
            }
        }
    };
    let bytes = reader
        .join()
        .map_err(|_| "Wallpaper reader failed")?
        .map_err(|e| e.to_string())?;
    result.map(|_| bytes)
}
pub fn current_path(output: &str) -> Result<String, String> {
    let mut cmd = Command::new("awww");
    cmd.arg("query").env("LC_ALL", "C");
    let bytes = bounded_output(cmd, 64 * 1024)?;
    parse_path(&String::from_utf8_lossy(&bytes), output)
        .ok_or_else(|| "Wallpaper path unavailable".into())
}
pub fn parse_path(text: &str, output: &str) -> Option<String> {
    text.lines().find_map(|line| {
        let (head, path) = line.split_once("currently displaying: image: ")?;
        // awww may prefix its namespace before the output name.
        let matches = output.is_empty()
            || head
                .split(": ")
                .any(|part| part.trim_end_matches(':') == output);
        (matches && !path.trim().is_empty()).then(|| path.trim().to_owned())
    })
}
pub fn sample(path: &str) -> Result<[u8; 3], String> {
    let mut cmd = Command::new("ffmpeg");
    cmd.args([
        "-v",
        "error",
        "-nostdin",
        "-threads",
        "1",
        "-i",
        path,
        "-vf",
        "scale=48:48",
        "-frames:v",
        "1",
        "-threads",
        "1",
        "-f",
        "rawvideo",
        "-pix_fmt",
        "rgb24",
        "pipe:1",
    ]);
    let bytes = bounded_output(cmd, 48 * 48 * 3 + 1)?;
    if bytes.len() != 48 * 48 * 3 {
        return Err("Wallpaper thumbnail unavailable".into());
    }
    Ok(palette(&bytes))
}
pub fn palette(bytes: &[u8]) -> [u8; 3] {
    // Find a common saturated hue rather than averaging complementary colors into grey.
    let mut sums = [[0u32; 4]; 12];
    let mut luminance = 0.0;
    for p in bytes.chunks_exact(3) {
        let (r, g, b) = (
            p[0] as f32 / 255.0,
            p[1] as f32 / 255.0,
            p[2] as f32 / 255.0,
        );
        luminance += 0.2126 * r + 0.7152 * g + 0.0722 * b;
        let max = r.max(g).max(b);
        let min = r.min(g).min(b);
        let d = max - min;
        if d < 0.10 || max < 0.10 {
            continue;
        }
        let hue = if max == r {
            ((g - b) / d).rem_euclid(6.0)
        } else if max == g {
            (b - r) / d + 2.0
        } else {
            (r - g) / d + 4.0
        };
        let bin = ((hue * 2.0) as usize).min(11);
        let weight = (d * 100.0) as u32;
        for i in 0..3 {
            sums[bin][i] += p[i] as u32 * weight;
        }
        sums[bin][3] += weight;
    }
    let bright = luminance / (bytes.len() / 3).max(1) as f32 > 0.60;
    let best = sums.iter().max_by_key(|s| s[3]).unwrap();
    if best[3] == 0 {
        return if bright { [38, 75, 85] } else { FALLBACK };
    }
    let color = [
        best[0] as f32 / best[3] as f32,
        best[1] as f32 / best[3] as f32,
        best[2] as f32 / best[3] as f32,
    ];
    let peak = color.iter().copied().fold(0.0, f32::max);
    // Bright rain on dark images; darker ink on bright images.
    let (ceiling, floor) = if bright { (105.0, 20.0) } else { (230.0, 48.0) };
    color.map(|c| (c / peak * ceiling).max(floor) as u8)
}
#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn output_specific_paths_with_spaces() {
        let s="eDP-1: 1920x1080, scale: 1, currently displaying: image: /a red wall.jpg\nwork: HDMI-A-1: 1280x720, currently displaying: image: /blue.png\n";
        assert_eq!(parse_path(s, "eDP-1").as_deref(), Some("/a red wall.jpg"));
        assert_eq!(parse_path(s, "HDMI-A-1").as_deref(), Some("/blue.png"));
        assert_eq!(parse_path(s, "missing"), None);
    }
    #[test]
    fn palette_handles_grey_and_dark_saturated_images() {
        assert_eq!(palette(&[20, 20, 20]), FALLBACK);
        assert!(palette(&[250, 250, 250]).iter().all(|c| *c < 110));
        let c = palette(&[10, 20, 70, 12, 22, 80]);
        assert!(c[2] > 200 && c[0] >= 48 && c[2] > c[1]);
    }
}

use crate::config::Config;
use fontdue::{Font, FontSettings};
use std::{collections::HashMap, fs, path::PathBuf};
const SYMBOLS: &[u8] = b"0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ<>[]{}/\\:;=+*#$%&!?";
pub const MENU_ROWS: usize = 17;
pub const ROW: u32 = 23;
pub const MENU_WIDTH: u32 = 360;
pub const MENU_HEIGHT: u32 = ROW * (MENU_ROWS as u32 + 2);
/// Movement in surface coordinates before a panel press becomes a drag.
pub const DRAG_THRESHOLD: f64 = 4.0;

struct Glyph {
    pixels: Vec<(i32, i32, u8)>,
}
pub struct Renderer {
    font: Font,
    glyphs: HashMap<(char, u32), Glyph>,
    table: Vec<u32>,
    last_color: [u8; 3],
    last_opacity: f32,
    last_background: f32,
    pub color: [f32; 3],
}
pub fn hash(mut n: u32) -> u32 {
    n ^= n >> 16;
    n = n.wrapping_mul(0x7feb352d);
    n ^= n >> 15;
    n = n.wrapping_mul(0x846ca68b);
    n ^ (n >> 16)
}
fn argb(color: [u8; 3], alpha: u32, background: u32) -> u32 {
    let a = alpha + background * (255 - alpha) / 255;
    (a << 24)
        | ((color[0] as u32 * alpha / 255) << 16)
        | ((color[1] as u32 * alpha / 255) << 8)
        | (color[2] as u32 * alpha / 255)
}
impl Renderer {
    pub fn new(config: &Config) -> Result<Self, String> {
        let paths = config.font.clone().map(|p| vec![p]).unwrap_or_else(|| {
            [
                "/usr/share/fonts/dejavu-sans-mono-fonts/DejaVuSansMono.ttf",
                "/usr/share/fonts/TTF/DejaVuSansMono.ttf",
                "/usr/share/fonts/truetype/dejavu/DejaVuSansMono.ttf",
                "/usr/share/fonts/dejavu-sans-fonts/DejaVuSans.ttf",
            ]
            .iter()
            .map(PathBuf::from)
            .collect()
        });
        let bytes = paths
            .iter()
            .find_map(|p| fs::read(p).ok())
            .ok_or("No readable font; set font in config.toml")?;
        let font = Font::from_bytes(bytes, FontSettings::default()).map_err(|e| e.to_string())?;
        let mut r = Self {
            font,
            glyphs: HashMap::new(),
            table: vec![0; 17 * 256],
            last_color: [0; 3],
            last_opacity: -1.0,
            last_background: -1.0,
            color: crate::wallpaper::FALLBACK.map(|v| v as f32),
        };
        r.prepare(config);
        Ok(r)
    }
    pub fn prepare(&mut self, c: &Config) {
        // Cache a fixed bitmap alphabet once per size. Text rendering never allocates per frame.
        for ch in SYMBOLS
            .iter()
            .map(|c| *c as char)
            .chain((32..127).map(|c| c as u8 as char))
        {
            self.cache(ch, c.font_size);
            self.cache(ch, 13);
        }
    }
    fn cache(&mut self, ch: char, size: u32) {
        self.glyphs.entry((ch, size)).or_insert_with(|| {
            let (m, bitmap) = self.font.rasterize(ch, size as f32);
            let mut pixels = Vec::new();
            for (i, a) in bitmap.iter().enumerate() {
                if *a > 0 {
                    pixels.push((
                        (i % m.width) as i32 + m.xmin,
                        (i / m.width) as i32 - m.ymin - m.height as i32,
                        *a,
                    ));
                }
            }
            Glyph { pixels }
        });
    }
    fn tables(&mut self, c: &Config, target: [u8; 3], dt: f32) {
        let blend = 1.0 - (-dt * 2.5).exp();
        for (current, target) in self.color.iter_mut().zip(target) {
            *current += (target as f32 - *current) * blend;
        }
        let color = self.color.map(|v| v.round() as u8);
        if color == self.last_color
            && c.opacity == self.last_opacity
            && c.background == self.last_background
        {
            return;
        }
        for level in 0..17 {
            let color = if level == 16 {
                if color.iter().all(|v| *v <= 110) && c.background < 0.2 {
                    color.map(|v| (v as f32 * 0.35) as u8)
                } else {
                    color.map(|v| (v as f32 * 0.25 + 255.0 * 0.75) as u8)
                }
            } else {
                color
            };
            let fade = if level == 16 {
                1.0
            } else {
                (level as f32 / 15.0).powf(1.5) * 0.85
            };
            for coverage in 0..256 {
                self.table[level * 256 + coverage] = argb(
                    color,
                    (coverage as f32 * c.opacity * fade) as u32,
                    (c.background * 255.0) as u32,
                );
            }
        }
        self.last_color = color;
        self.last_opacity = c.opacity;
        self.last_background = c.background;
    }
    // Explicit drawing parameters keep the hot path free of temporary scene objects.
    #[allow(clippy::too_many_arguments)]
    pub fn render(
        &mut self,
        pixels: &mut [u32],
        w: u32,
        h: u32,
        c: &Config,
        time: f32,
        dt: f32,
        target: [u8; 3],
        menu: Option<(u32, u32, u32, u32)>,
        status: &str,
    ) {
        self.tables(c, target, dt);
        pixels.fill(((c.background * 255.0) as u32) << 24);
        let cw = (c.font_size * 2 / 3).max(7);
        let ch = c.font_size + 5;
        let rows = h / ch + 1;
        for col in 0..w / cw {
            let seed = hash(col + 7919);
            if (seed % 1000) as f32 >= c.density * 1000.0 {
                continue;
            }
            let trail = 7 + seed % 22;
            let factor = 0.55 + (seed % 101) as f32 / 100.0;
            let period = (rows + trail + 12) as f32;
            let phase = (hash(seed) % 10000) as f32 / 10000.0 * period;
            let travel = time * c.speed * factor + phase;
            let head = (travel % period) as i32;
            let cycle = (travel / period) as u32;
            for age in 0..trail {
                let row = head - age as i32;
                if row < 0 || row >= rows as i32 {
                    continue;
                }
                let noise = hash(
                    seed.wrapping_add((row as u32).wrapping_mul(997))
                        .wrapping_add(cycle.wrapping_mul(293)),
                );
                // A sparse changing character adds life without making every glyph flicker.
                let glitch = if noise % 19 == 0 {
                    (time * 2.0) as u32
                } else {
                    0
                };
                let symbol =
                    SYMBOLS[hash(noise.wrapping_add(glitch)) as usize % SYMBOLS.len()] as char;
                let level = if age == 0 {
                    16
                } else {
                    ((trail - age) * 15 / trail).max(1) as usize
                };
                self.glyph(
                    pixels,
                    (w, h),
                    symbol,
                    c.font_size,
                    (col * cw) as i32,
                    row * ch as i32 + c.font_size as i32,
                    level,
                );
            }
        }
        if let Some(rect) = menu {
            self.menu(pixels, w, h, c, status, rect);
        }
    }
    #[allow(clippy::too_many_arguments)]
    fn glyph(
        &self,
        pixels: &mut [u32],
        size: (u32, u32),
        ch: char,
        font: u32,
        x: i32,
        y: i32,
        level: usize,
    ) {
        let Some(g) = self.glyphs.get(&(ch, font)) else {
            return;
        };
        for &(dx, dy, a) in &g.pixels {
            let (px, py) = (x + dx, y + dy);
            if px >= 0 && py >= 0 && px < size.0 as i32 && py < size.1 as i32 {
                pixels[py as usize * size.0 as usize + px as usize] =
                    self.table[level * 256 + a as usize];
            }
        }
    }
    #[allow(clippy::too_many_arguments)]
    fn text(&self, pixels: &mut [u32], w: u32, h: u32, text: &str, x: i32, y: i32, color: [u8; 3]) {
        let mut x = x;
        for ch in text.chars() {
            if let Some(g) = self.glyphs.get(&(ch, 13)) {
                for &(dx, dy, a) in &g.pixels {
                    let (px, py) = (x + dx, y + dy);
                    if px >= 0 && py >= 0 && px < w as i32 && py < h as i32 {
                        // Menu is opaque, independent of the rain opacity.
                        let bg = pixels[py as usize * w as usize + px as usize];
                        let mut result = 0xff000000;
                        for (i, shift) in [16, 8, 0].iter().enumerate() {
                            result |= ((color[i] as u32 * a as u32
                                + (bg >> shift & 255) * (255 - a as u32))
                                / 255)
                                << shift;
                        }
                        pixels[py as usize * w as usize + px as usize] = result;
                    }
                }
            }
            x += 8;
        }
    }
    fn menu(
        &self,
        pixels: &mut [u32],
        w: u32,
        h: u32,
        c: &Config,
        status: &str,
        (x, y, mw, mh): (u32, u32, u32, u32),
    ) {
        for py in y..y + mh {
            for px in x..x + mw {
                pixels[(py * w + px) as usize] =
                    if px == x || px == x + mw - 1 || py == y || py == y + mh - 1 {
                        0xff3a5960
                    } else {
                        0xff10181d
                    };
            }
        }
        self.text(
            pixels,
            w,
            h,
            "HYPRMATRIX",
            x as i32 + 12,
            y as i32 + 19,
            [135, 235, 210],
        );
        for (i, (name, value)) in labels(c).iter().enumerate() {
            let baseline = y as i32 + ROW as i32 * (i as i32 + 2) - 4;
            self.text(pixels, w, h, name, x as i32 + 12, baseline, [190, 200, 205]);
            let value = if value.is_empty() {
                String::new()
            } else {
                format!("< {value} >")
            };
            self.text(
                pixels,
                w,
                h,
                &value,
                x as i32 + mw as i32 - 12 - value.len() as i32 * 8,
                baseline,
                [135, 235, 210],
            );
        }
        let note = if status.is_empty() {
            "Adjust L/R · Drag · Right-click closes"
        } else {
            status
        };
        let note: String = note
            .chars()
            .take((mw as usize).saturating_sub(24) / 8)
            .collect();
        self.text(
            pixels,
            w,
            h,
            &note,
            x as i32 + 12,
            (y + mh - 9) as i32,
            [130, 145, 155],
        );
    }
}
pub fn menu_rect(w: u32, h: u32) -> (u32, u32, u32, u32) {
    let mw = MENU_WIDTH.min(w);
    let mh = MENU_HEIGHT.min(h);
    (
        w.saturating_sub(mw + 8),
        8.min(h.saturating_sub(mh)),
        mw,
        mh,
    )
}
/// Keep a panel top-left position inside the surface.
pub fn clamp_menu_pos(pos: (u32, u32), surface: (u32, u32)) -> (u32, u32) {
    (
        pos.0.min(surface.0.saturating_sub(MENU_WIDTH.min(surface.0))),
        pos.1
            .min(surface.1.saturating_sub(MENU_HEIGHT.min(surface.1))),
    )
}
/// Settings-row index (0..MENU_ROWS) for a press inside the panel body.
pub fn menu_row(rect: (u32, u32, u32, u32), x: f64, y: f64) -> Option<usize> {
    let (mx, my, mw, mh) = rect;
    if x < mx as f64
        || x >= (mx + mw) as f64
        || y < (my + ROW) as f64
        || y >= (my + mh).saturating_sub(ROW) as f64
    {
        return None;
    }
    Some(((y - my as f64) / ROW as f64) as usize - 1)
}
pub fn labels(c: &Config) -> Vec<(String, String)> {
    vec![
        (
            "Placement".into(),
            if c.fullscreen {
                "Full screen"
            } else {
                "Region"
            }
            .into(),
        ),
        (
            "Rain opacity".into(),
            format!("{}%", (c.opacity * 100.0).round()),
        ),
        (
            "Background".into(),
            format!("{}%", (c.background * 100.0).round()),
        ),
        ("Color".into(), c.theme.clone()),
        (
            "Density".into(),
            format!("{}%", (c.density * 100.0).round()),
        ),
        ("Speed".into(), format!("{:.0}", c.speed)),
        ("Character size".into(), c.font_size.to_string()),
        ("Frame limit".into(), format!("{} FPS", c.fps)),
        ("Region width".into(), c.width.to_string()),
        ("Region height".into(), c.height.to_string()),
        ("Horizontal".into(), format!("{}%", (c.x * 100.0).round())),
        ("Vertical".into(), format!("{}%", (c.y * 100.0).round())),
        ("Refresh wallpaper color".into(), String::new()),
        ("Reset appearance".into(), String::new()),
        ("Hide (resume via launcher)".into(), String::new()),
        ("Close settings".into(), String::new()),
        ("Quit Hyprmatrix".into(), String::new()),
    ]
}
/// Returns an action for desktop integration; configuration changes save immediately.
pub fn adjust(c: &mut Config, row: usize, increase: bool) -> &'static str {
    let d = if increase { 1.0 } else { -1.0 };
    match row {
        0 => {
            c.fullscreen = !c.fullscreen;
            return "resize";
        }
        1 => c.opacity = (c.opacity + d * 0.05).clamp(0.0, 1.0),
        2 => c.background = (c.background + d * 0.05).clamp(0.0, 1.0),
        3 => {
            let themes = ["wallpaper", "matrix", "cyan", "amber"];
            let i = themes.iter().position(|t| *t == c.theme).unwrap_or(0);
            c.theme = themes[((i as i32 + if increase { 1 } else { 3 }) % 4) as usize].into();
        }
        4 => c.density = (c.density + d * 0.05).clamp(0.0, 1.0),
        5 => c.speed = (c.speed + d).clamp(1.0, 30.0),
        6 => c.font_size = (c.font_size as i32 + d as i32).clamp(10, 32) as u32,
        7 => {
            let rates = [5, 10, 15, 20, 30, 60];
            c.fps = if increase {
                rates.into_iter().find(|r| *r > c.fps).unwrap_or(60)
            } else {
                rates.into_iter().rev().find(|r| *r < c.fps).unwrap_or(5)
            };
        }
        8 => {
            c.width = (c.width as i32 + d as i32 * 80).clamp(360, 7680) as u32;
            return "resize";
        }
        9 => {
            c.height = (c.height as i32 + d as i32 * 60).clamp(460, 4320) as u32;
            return "resize";
        }
        10 => {
            c.x = (c.x + d * 0.05).clamp(0.0, 1.0);
            return "resize";
        }
        11 => {
            c.y = (c.y + d * 0.05).clamp(0.0, 1.0);
            return "resize";
        }
        12 => return "refresh",
        13 => {
            let output = c.output.clone();
            *c = Config::default();
            c.output = output;
            return "resize";
        }
        14 => return "hide",
        15 => return "close",
        16 => return "quit",
        _ => {}
    }
    "draw"
}
#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn menu_adjustments_stay_valid() {
        for direction in [false, true] {
            let mut c = Config::default();
            for _ in 0..150 {
                for row in 0..12 {
                    adjust(&mut c, row, direction);
                    assert!(c.validate().is_ok());
                }
            }
        }
    }
    #[test]
    fn premultiplied_pixels_preserve_alpha() {
        let p = argb([100, 200, 250], 128, 64);
        assert_eq!(p >> 24, 159);
        for shift in [0, 8, 16] {
            assert!((p >> shift & 255) <= (p >> 24));
        }
        assert_eq!(argb([255; 3], 0, 0), 0);
    }
    #[test]
    fn menu_row_hit_test_matches_visible_rows() {
        let rect = menu_rect(1920, 1080);
        let (mx, my, _, _) = rect;
        // Header band and the footnote band never map to a row.
        assert_eq!(menu_row(rect, mx as f64 + 10.0, my as f64 + 4.0), None);
        assert_eq!(
            menu_row(rect, mx as f64 + 10.0, (my + MENU_HEIGHT - 4) as f64),
            None
        );
        // Row i occupies [my + (i+1)*ROW, my + (i+2)*ROW).
        assert_eq!(
            menu_row(rect, mx as f64 + 5.0, (my + ROW) as f64 + 1.0),
            Some(0)
        );
        assert_eq!(
            menu_row(rect, mx as f64 + 5.0, (my + 16 * ROW) as f64 + 1.0),
            Some(15)
        );
        assert_eq!(
            menu_row(rect, mx as f64 + 5.0, (my + 17 * ROW) as f64 + 1.0),
            Some(16)
        );
        assert_eq!(menu_row(rect, mx as f64 - 1.0, 50.0), None);
        // Close settings and Quit remain reachable.
        assert_eq!(labels(&Config::default())[15].0, "Close settings");
        assert_eq!(labels(&Config::default())[16].0, "Quit Hyprmatrix");
    }
    #[test]
    fn clamp_menu_pos_keeps_panel_inside_surface() {
        assert_eq!(clamp_menu_pos((0, 0), (1920, 1080)), (0, 0));
        assert_eq!(
            clamp_menu_pos((5000, 5000), (1920, 1080)),
            (1920 - MENU_WIDTH, 1080 - MENU_HEIGHT)
        );
        assert_eq!(clamp_menu_pos((5000, 5000), (300, 300)), (0, 300 - 300));
        assert_eq!(clamp_menu_pos((100, 100), (300, 300)), (0, 0));
    }
}

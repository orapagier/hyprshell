#![allow(clippy::too_many_arguments)] // Drawing primitives use explicit bounds and colors.

use crate::{collect::Snapshot, config::Config};
use fontdue::{Font, FontSettings, Metrics};
use std::{
    collections::{HashMap, VecDeque},
    fs,
    path::PathBuf,
};
use tiny_skia::{Color, FillRule, Paint, PathBuilder, Pixmap, Stroke, Transform};

type Rgb = [u8; 3];
const TEXT: Rgb = [232, 240, 248];
const MUTED: Rgb = [139, 157, 180];

struct Glyph {
    metrics: Metrics,
    bitmap: Vec<u8>,
}

pub struct Renderer {
    font: Font,
    glyphs: HashMap<(char, u16), Glyph>,
    background: Option<Pixmap>,
    pub accent: Rgb,
    config: Config,
    colors: Vec<Rgb>,
    background_key: Vec<u32>,
    scale: f32,
}

pub fn bytes(value: f64) -> String {
    let mut n = if value > 0.0 { value } else { 0.0 };
    let mut unit = 0;
    let units = ["B", "KiB", "MiB", "GiB", "TiB"];
    while n >= 1024.0 && unit < 4 {
        n /= 1024.0;
        unit += 1;
    }
    if unit == 0 {
        format!("{n:.0} {}", units[unit])
    } else {
        format!("{n:.1} {}", units[unit])
    }
}
pub fn metric(n: Option<f64>, suffix: &str) -> String {
    n.map(|v| format!("{v:.1}{suffix}"))
        .unwrap_or_else(|| "—".into())
}

fn rate(n: Option<f64>) -> String {
    n.map(bytes).unwrap_or_else(|| "—".into())
}

#[derive(Debug)]
pub struct Section {
    pub title: &'static str,
    pub rows: Vec<(String, String)>,
    pub history: VecDeque<f64>,
    pub maximum: f64,
}
fn b(n: u64) -> String {
    bytes(n as f64)
}
fn row(label: impl Into<String>, value: impl Into<String>) -> (String, String) {
    (label.into(), value.into())
}
pub fn sections(d: &Snapshot) -> Vec<Section> {
    let section = |title, rows, history, maximum| Section {
        title,
        rows,
        history,
        maximum,
    };
    let m = &d.memory;
    let percent = if m.total > 0 {
        m.used as f64 / m.total as f64 * 100.0
    } else {
        0.0
    };
    let mut system = vec![
        row("OS", &d.os),
        row("Model", &d.model),
        row("Kernel", &d.kernel),
        row("OS age", crate::details::age(d.extra.install_epoch)),
        row(
            "Uptime",
            format!(
                "{}d {}h {}m",
                d.uptime / 86400,
                d.uptime / 3600 % 24,
                d.uptime / 60 % 60
            ),
        ),
    ];
    for display in &d.context.displays {
        system.push(row(
            &display.name,
            format!(
                "{} × {} · {} · {}",
                display.width,
                display.height,
                metric(display.refresh_rate, " Hz"),
                metric(display.scale, "× scale")
            ),
        ));
    }
    if d.context.displays.is_empty() {
        system.push(row("Displays", "Unavailable outside desktop session"));
    }
    let temp = d
        .sensors
        .iter()
        .filter(|s| s.name.contains("Package") && s.unit == "°C")
        .map(|s| s.value)
        .reduce(f64::max);
    let mut cpu = vec![
        row("CPU", &d.cpu_model),
        row("Topology", &d.extra.topology),
        row("Usage", metric(d.cpu, "%")),
        row("CPU stall pressure (10s)", metric(d.cpu_pressure, "%")),
        row(
            "Frequency",
            metric(d.frequency_mhz.map(|n| n / 1000.0), " GHz avg"),
        ),
        row("Load / tasks", format!("{} · {} tasks", d.load, d.tasks)),
        row("Thermals", metric(temp, " °C CPU")),
        row(
            "Throttling",
            d.throttle_events
                .map(|n| {
                    format!(
                        "{} · {n} max counter since boot",
                        if d.new_throttle {
                            "New thermal events"
                        } else {
                            "No new thermal events"
                        }
                    )
                })
                .unwrap_or_else(|| "Not exposed by CPU".into()),
        ),
    ];
    for (i, core) in d.cores.iter().enumerate() {
        cpu.push(row(format!("CPU {i}"), metric(*core, "%")));
    }
    cpu.push(row("", ""));
    cpu.push(row("Top CPU processes", "100% = 1 CPU thread"));
    for p in &d.top_cpu {
        cpu.push(row(format!("{} ({})", p.name, p.pid), metric(p.cpu, "%")));
    }
    let mut graphics = vec![];
    for gpu in &d.gpus {
        graphics.extend([
            row("Graphics", format!("{} · {}", gpu.model, gpu.driver)),
            row(
                "GPU usage",
                gpu.busy
                    .map(|n| format!("{n:.1}%"))
                    .unwrap_or_else(|| "Requires GPU profiling / not exposed".into()),
            ),
            row(
                "GPU memory",
                if gpu.memory_total.unwrap_or(0) > 0 {
                    format!(
                        "{} / {}",
                        b(gpu.memory_used.unwrap_or(0)),
                        b(gpu.memory_total.unwrap_or(0))
                    )
                } else {
                    "Shared system RAM / not exposed".into()
                },
            ),
            row("GPU temperature", metric(gpu.temperature, " °C")),
            row("GPU clock", metric(gpu.clock_mhz, " MHz")),
        ]);
    }
    if d.gpus.is_empty() {
        graphics.push(row("Graphics", "Not exposed"));
    }
    for s in &d.sensors {
        graphics.push(row(&s.name, format!("{:.1} {}", s.value, s.unit)));
    }
    if !d.sensors.iter().any(|s| s.unit == "RPM") {
        graphics.push(row("Fans", "Not exposed by hardware"));
    }
    let mut memory = vec![
        row(
            "RAM",
            format!("{} / {} · {percent:.1}%", b(m.used), b(m.total)),
        ),
        row("Available", b(m.available)),
        row("Cache", b(m.cache)),
        row("Swap", format!("{} / {}", b(m.swap_used), b(m.swap_total))),
        row(
            "Memory stalls",
            format!(
                "{} some · {} full (10 s avg)",
                metric(d.pressure_some, "%"),
                metric(d.pressure_full, "%")
            ),
        ),
        row("", ""),
        row("Top RAM processes", "Resident memory"),
    ];
    for p in &d.top_memory {
        memory.push(row(format!("{} ({})", p.name, p.pid), b(p.memory)));
    }
    let mut storage = vec![row("I/O stall pressure (10s)", metric(d.io_pressure, "%"))];
    for (i, disk) in d
        .disks
        .iter()
        .filter(|s| s.name.starts_with('/'))
        .enumerate()
    {
        let name = if i == 0 { "Root" } else { "Home" };
        storage.push(row(
            name,
            format!(
                "{} / {}",
                disk.used.map(b).unwrap_or_else(|| "—".into()),
                disk.total.map(b).unwrap_or_else(|| "—".into())
            ),
        ));
        storage.push(row(
            format!("{name} free"),
            disk.free.map(b).unwrap_or_else(|| "—".into()),
        ));
    }
    for drive in &d.extra.drives {
        storage.push(row(
            format!("{} temperature", drive.name),
            metric(drive.temperature, " °C"),
        ));
        storage.push(row(format!("{} SMART", drive.name), &drive.health));
    }
    for disk in d.disks.iter().filter(|s| !s.name.starts_with('/')) {
        storage.push(row(
            format!("{} read / write", disk.name),
            format!("{}/s · {}/s", rate(disk.read), rate(disk.write)),
        ));
        storage.push(row(
            format!("{} activity", disk.name),
            metric(disk.busy, "%"),
        ));
    }
    let physical: Vec<_> = d.networks.iter().filter(|n| n.physical).collect();
    let rx = physical.iter().filter_map(|n| n.rx).reduce(|a, b| a + b);
    let tx = physical.iter().filter_map(|n| n.tx).reduce(|a, b| a + b);
    let mut network = vec![
        row(
            "Connection",
            d.context.connection.lines().next().unwrap_or("Unavailable"),
        ),
        row("Wi-Fi signal", metric(d.context.wifi_signal, "%")),
        row("Traffic", format!("↓ {}/s  ↑ {}/s", rate(rx), rate(tx))),
        row(
            "Link totals",
            format!(
                "↓ {}  ↑ {}",
                b(physical.iter().map(|n| n.rx_total).sum()),
                b(physical.iter().map(|n| n.tx_total).sum())
            ),
        ),
        row(
            "Bluetooth",
            d.context.bluetooth.lines().next().unwrap_or("Unavailable"),
        ),
    ];
    for n in &d.networks {
        let wifi = d.extra.wifi.get(&n.name);
        network.push(row(
            &n.name,
            format!(
                "{} · {}",
                n.state,
                if n.physical { "physical" } else { "virtual" }
            ),
        ));
        network.push(row(
            format!("{} IP", n.name),
            d.extra
                .addresses
                .get(&n.name)
                .map(|a| a.join(" · "))
                .filter(|a| !a.is_empty())
                .unwrap_or_else(|| "No address / unavailable".into()),
        ));
        network.push(row(
            format!("{} traffic", n.name),
            format!("↓ {}/s  ↑ {}/s", rate(n.rx), rate(n.tx)),
        ));
        network.push(row(
            format!("{} link", n.name),
            format!(
                "{} · {}",
                metric(wifi.and_then(|w| w.speed).or(n.speed_mbps), " Mb/s"),
                metric(wifi.and_then(|w| w.signal).or(n.signal_dbm), " dBm")
            ),
        ));
    }
    if d.networks.is_empty() {
        network.push(row("Interfaces / IP", "None visible / unavailable"));
    }
    let mut power = vec![];
    for battery in &d.batteries {
        power.extend([
            row(
                &battery.name,
                format!("{} · {}", metric(battery.percent, "%"), battery.status),
            ),
            row(
                "Battery time",
                battery
                    .hours
                    .map(|h| {
                        format!(
                            "{}h {}m {}",
                            h as u64,
                            (h * 60.0) as u64 % 60,
                            if battery.status == "Charging" {
                                "until full"
                            } else {
                                "remaining"
                            }
                        )
                    })
                    .unwrap_or_else(|| battery.status.clone()),
            ),
            row("Draw", metric(battery.watts, " W")),
            row("Health", metric(battery.health, "%")),
            row(
                format!("{} cycles", battery.name),
                battery
                    .cycles
                    .map(|n| format!("{n}{}", if n == 0 { " (reported)" } else { "" }))
                    .unwrap_or_else(|| "Unavailable".into()),
            ),
        ]);
    }
    for capacity in &d.extra.batteries {
        power.push(row(
            format!("{} charge now", capacity.name),
            metric(capacity.energy_wh, " Wh"),
        ));
        power.push(row(
            format!("{} full capacity", capacity.name),
            metric(capacity.full, &format!(" {}", capacity.unit)),
        ));
        power.push(row(
            format!("{} design capacity", capacity.name),
            metric(capacity.design, &format!(" {}", capacity.unit)),
        ));
    }
    if power.is_empty() {
        power.push(row("Power", "AC / battery unavailable"));
    }
    let maxnet = d.network_history.iter().copied().fold(1024.0, f64::max);
    vec![
        section("SYSTEM", system, VecDeque::new(), 1.0),
        section("PROCESSOR", cpu, d.cpu_history.clone(), 100.0),
        section("GRAPHICS & COOLING", graphics, VecDeque::new(), 1.0),
        section("MEMORY", memory, d.memory_history.clone(), 100.0),
        section("STORAGE", storage, VecDeque::new(), 1.0),
        section("NETWORK", network, d.network_history.clone(), maxnet),
        section("POWER", power, VecDeque::new(), 1.0),
    ]
}

impl Renderer {
    pub fn new(config: Config) -> Result<Self, String> {
        let candidates = config.font.clone().map(|p| vec![p]).unwrap_or_else(|| {
            vec![
                PathBuf::from("/usr/share/fonts/dejavu-sans-fonts/DejaVuSans.ttf"),
                PathBuf::from("/usr/share/fonts/TTF/DejaVuSans.ttf"),
                PathBuf::from("/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf"),
            ]
        });
        let font = candidates
            .into_iter()
            .find_map(|p| fs::read(p).ok())
            .ok_or("No readable font; set font in config.toml")?;
        let font = Font::from_bytes(font, FontSettings::default()).map_err(|e| e.to_string())?;
        let value = u32::from_str_radix(&config.accent[1..], 16).map_err(|e| e.to_string())?;
        Ok(Self {
            font,
            glyphs: HashMap::new(),
            background: None,
            accent: [(value >> 16) as u8, (value >> 8) as u8, value as u8],
            config,
            colors: vec![],
            background_key: vec![],
            scale: 1.0,
        })
    }

    fn rect(
        &self,
        pix: &mut Pixmap,
        x: f32,
        y: f32,
        w: f32,
        h: f32,
        r: f32,
        color: Rgb,
        alpha: f32,
    ) {
        if w <= 0.0 || h <= 0.0 {
            return;
        }
        let r = r.min(w / 2.0).min(h / 2.0);
        let k = 0.552_284_8;
        let mut p = PathBuilder::new();
        p.move_to(x + r, y);
        p.line_to(x + w - r, y);
        p.cubic_to(x + w - r + r * k, y, x + w, y + r - r * k, x + w, y + r);
        p.line_to(x + w, y + h - r);
        p.cubic_to(
            x + w,
            y + h - r + r * k,
            x + w - r + r * k,
            y + h,
            x + w - r,
            y + h,
        );
        p.line_to(x + r, y + h);
        p.cubic_to(x + r - r * k, y + h, x, y + h - r + r * k, x, y + h - r);
        p.line_to(x, y + r);
        p.cubic_to(x, y + r - r * k, x + r - r * k, y, x + r, y);
        p.close();
        let mut paint = Paint::default();
        paint.set_color(Color::from_rgba8(
            color[0],
            color[1],
            color[2],
            (alpha * 255.0) as u8,
        ));
        if let Some(path) = p.finish() {
            pix.fill_path(
                &path,
                &paint,
                FillRule::Winding,
                Transform::from_scale(self.scale, self.scale),
                None,
            );
        }
    }

    fn glyph(&mut self, c: char, size: f32) -> &Glyph {
        let pixels = (size * self.scale).round().max(1.0) as u16;
        self.glyphs.entry((c, pixels)).or_insert_with(|| {
            let (metrics, bitmap) = self.font.rasterize(c, pixels as f32);
            Glyph { metrics, bitmap }
        })
    }

    fn text(
        &mut self,
        pix: &mut Pixmap,
        text: &str,
        x: f32,
        y: f32,
        size: f32,
        color: Rgb,
        max_width: f32,
    ) {
        let scale = self.scale;
        let mut cursor = x * scale;
        let right = (x + max_width) * scale;
        let baseline = (y + size) * scale;
        let width = pix.width() as i32;
        let height = pix.height() as i32;
        let data = pix.data_mut();
        for c in text.chars().filter(|c| !c.is_control()).take(256) {
            let glyph = self.glyph(c, size);
            if cursor + glyph.metrics.advance_width > right {
                break;
            }
            let left = cursor.round() as i32 + glyph.metrics.xmin;
            let top = baseline.round() as i32 - glyph.metrics.ymin - glyph.metrics.height as i32;
            for gy in 0..glyph.metrics.height {
                let py = top + gy as i32;
                if py < 0 || py >= height {
                    continue;
                }
                for gx in 0..glyph.metrics.width {
                    let px = left + gx as i32;
                    if px < 0 || px >= width {
                        continue;
                    }
                    let a = glyph.bitmap[gy * glyph.metrics.width + gx] as u32;
                    if a == 0 {
                        continue;
                    }
                    let i = ((py * width + px) * 4) as usize;
                    // tiny-skia stores premultiplied RGBA; source-over retains translucency.
                    for channel in 0..3 {
                        data[i + channel] = ((color[channel] as u32 * a
                            + data[i + channel] as u32 * (255 - a)
                            + 127)
                            / 255) as u8;
                    }
                    data[i + 3] = (a + (data[i + 3] as u32 * (255 - a) + 127) / 255).min(255) as u8;
                }
            }
            cursor += glyph.metrics.advance_width;
        }
    }

    fn graph(
        &self,
        pix: &mut Pixmap,
        values: &VecDeque<f64>,
        x: f32,
        y: f32,
        w: f32,
        h: f32,
        max: f64,
        color: Rgb,
    ) {
        for part in [0.0, 0.5, 1.0] {
            self.rect(pix, x, y + h * part, w, 0.6, 0.0, [100, 125, 155], 0.13);
        }
        if values.len() < 2 {
            return;
        }
        let max = max.max(1.0);
        let mut path = PathBuilder::new();
        for (i, value) in values.iter().enumerate() {
            let px = x + w * i as f32 / (values.len() - 1) as f32;
            let py = y + h - h * (value / max).clamp(0.0, 1.0) as f32;
            if i == 0 {
                path.move_to(px, py);
            } else {
                path.line_to(px, py);
            }
        }
        if let Some(line) = path.finish() {
            let mut paint = Paint::default();
            paint.set_color_rgba8(color[0], color[1], color[2], 235);
            pix.stroke_path(
                &line,
                &paint,
                &Stroke {
                    width: 1.8,
                    ..Stroke::default()
                },
                Transform::from_scale(self.scale, self.scale),
                None,
            );
        }
    }

    pub fn configure(&mut self, config: &Config) {
        self.config = config.clone();
        self.background = None;
        if let Ok(v) = u32::from_str_radix(&config.accent[1..], 16) {
            self.accent = [(v >> 16) as u8, (v >> 8) as u8, v as u8];
        }
    }
    pub fn draw_settings(
        &mut self,
        pix: &mut Pixmap,
        menu: &crate::ui::SettingsMenu,
        config: &Config,
    ) {
        if !menu.open {
            return;
        }
        self.scale = 1.0;
        let w = menu.width(pix.width());
        let h = menu.height(pix.height());
        let x = menu.x;
        let y = menu.y;
        self.rect(pix, x, y, w, h, 12.0, [103, 130, 162], 0.95);
        self.rect(
            pix,
            x + 1.0,
            y + 1.0,
            w - 2.0,
            h - 2.0,
            11.0,
            [14, 23, 36],
            0.99,
        );
        self.text(
            pix,
            "HYPRMONITOR SETTINGS",
            x + 14.0,
            y + 12.0,
            13.0,
            TEXT,
            w - 28.0,
        );
        let rows = crate::ui::SettingsMenu::rows(config);
        for (i, (label, value)) in rows
            .iter()
            .skip(menu.scroll)
            .take(menu.visible_rows(pix.height()))
            .enumerate()
        {
            let ry = y + 47.0 + i as f32 * crate::ui::ROW_HEIGHT;
            self.text(pix, label, x + 14.0, ry, 11.0, TEXT, w * 0.58);
            self.text(pix, value, x + w * 0.64, ry, 11.0, self.accent, w * 0.33);
        }
        self.text(
            pix,
            &menu.status,
            x + 14.0,
            y + h - 34.0,
            10.0,
            self.accent,
            w - 28.0,
        );
        self.text(
            pix,
            "Scroll for more · Right-click to close",
            x + 14.0,
            y + h - 19.0,
            9.0,
            MUTED,
            w - 28.0,
        );
    }

    fn wrap(&self, text: &str, size: f32, width: f32) -> Vec<String> {
        if text.is_empty() {
            return vec![String::new()];
        }
        let mut lines = vec![];
        let mut current = String::new();
        let mut measured = 0.0;
        for word in text.split_whitespace() {
            let word_width: f32 = word
                .chars()
                .map(|c| self.font.metrics(c, size).advance_width)
                .sum();
            let space = self.font.metrics(' ', size).advance_width;
            if !current.is_empty() && measured + space + word_width > width {
                lines.push(std::mem::take(&mut current));
                measured = 0.0;
            }
            if !current.is_empty() {
                current.push(' ');
                measured += space;
            }
            for c in word.chars() {
                let advance = self.font.metrics(c, size).advance_width;
                if !current.is_empty() && measured + advance > width {
                    lines.push(std::mem::take(&mut current));
                    measured = 0.0;
                }
                current.push(c);
                measured += advance;
            }
        }
        if !current.is_empty() {
            lines.push(current);
        }
        lines
    }

    fn process_table(
        &mut self,
        pix: &mut Pixmap,
        data: &Snapshot,
        view: &crate::explorer::Explorer,
        scroll: usize,
        x: f32,
        width: f32,
        height: f32,
    ) {
        let rows = view.rows(data);
        let accent = self.accent;
        self.rect(pix, x, 104.0, width - 90.0, 34.0, 6.0, [34, 47, 65], 1.0);
        self.text(
            pix,
            &format!(
                "{}{}",
                if view.searching {
                    "Search: "
                } else {
                    "Search name / PID: "
                },
                view.query
            ),
            x + 10.0,
            113.0,
            12.0,
            TEXT,
            width - 115.0,
        );
        self.text(
            pix,
            if view.paused { "Resume" } else { "Pause" },
            x + width - 78.0,
            113.0,
            12.0,
            accent,
            78.0,
        );
        for (i, label) in crate::explorer::SORTS.iter().enumerate() {
            let bx = x + i as f32 * width / 7.0;
            self.text(
                pix,
                &format!(
                    "{}{}",
                    label,
                    if i == view.sort {
                        if view.ascending {
                            " ↑"
                        } else {
                            " ↓"
                        }
                    } else {
                        ""
                    }
                ),
                bx + 3.0,
                157.0,
                11.0,
                if i == view.sort { accent } else { MUTED },
                width / 7.0 - 4.0,
            );
        }
        self.text(
            pix,
            &format!(
                "{} / {} processes · CPU 100% = one logical CPU · RSS includes shared pages",
                rows.len(),
                data.processes.len()
            ),
            x,
            188.0,
            10.0,
            MUTED,
            width,
        );
        let visible = ((height - 244.0) / 68.0).max(1.0) as usize;
        let start = scroll.min(rows.len().saturating_sub(visible));
        for (i, p) in rows.iter().skip(start).take(visible).enumerate() {
            let y = 214.0 + i as f32 * 68.0;
            self.rect(pix, x, y, width, 62.0, 6.0, [24, 35, 51], 1.0);
            self.text(
                pix,
                &format!("{}  /  {}", p.name, p.pid),
                x + 10.0,
                y + 8.0,
                12.0,
                TEXT,
                width * 0.55,
            );
            self.text(
                pix,
                &format!("{} CPU · {}", metric(p.cpu, "%"), b(p.memory)),
                x + width * 0.56,
                y + 8.0,
                11.0,
                accent,
                width * 0.42,
            );
            self.text(
                pix,
                &format!(
                    "{} · parent {} · {} threads · read {}/s · write {}/s",
                    p.state,
                    p.parent,
                    p.threads,
                    rate(p.read_rate),
                    rate(p.write_rate)
                ),
                x + 10.0,
                y + 35.0,
                10.0,
                MUTED,
                width - 20.0,
            );
        }
        if rows.is_empty() {
            self.text(
                pix,
                "No matching processes",
                x + 10.0,
                230.0,
                14.0,
                MUTED,
                width,
            );
        }
        self.text(
            pix,
            &format!(
                "Rows {}–{} of {} · Click a sort label to reverse · Esc clears search",
                if rows.is_empty() { 0 } else { start + 1 },
                (start + visible).min(rows.len()),
                rows.len()
            ),
            x,
            height - 22.0,
            10.0,
            MUTED,
            width,
        );
    }

    pub fn render_window(
        &mut self,
        data: &Snapshot,
        width: u32,
        height: u32,
        page: usize,
        scroll: usize,
        explorer: &crate::explorer::Explorer,
    ) -> Result<Pixmap, String> {
        self.scale = 1.0;
        let mut pix = Pixmap::new(width, height).ok_or("Invalid window size")?;
        pix.fill(Color::from_rgba8(12, 18, 29, 255));
        let w = width as f32;
        let h = height as f32;
        let accent = self.accent;
        self.rect(&mut pix, 0.0, 0.0, 196.0, h, 0.0, [19, 28, 43], 1.0);
        self.text(&mut pix, "HYPRMONITOR", 22.0, 26.0, 17.0, TEXT, 170.0);
        self.text(
            &mut pix,
            "System intelligence",
            22.0,
            54.0,
            11.0,
            MUTED,
            170.0,
        );
        let labels = crate::explorer::PAGES;
        for (i, label) in labels.iter().enumerate() {
            let y = 104.0 + i as f32 * 44.0;
            if i == page {
                self.rect(&mut pix, 12.0, y, 172.0, 36.0, 9.0, accent, 0.13);
                self.rect(&mut pix, 12.0, y + 9.0, 3.0, 18.0, 1.0, accent, 1.0);
            }
            self.text(
                &mut pix,
                label,
                28.0,
                y + 9.0,
                12.0,
                if i == page { accent } else { MUTED },
                151.0,
            );
        }
        self.rect(
            &mut pix,
            12.0,
            h - 56.0,
            172.0,
            36.0,
            9.0,
            [34, 47, 65],
            1.0,
        );
        self.text(&mut pix, "Settings", 28.0, h - 47.0, 12.0, TEXT, 150.0);
        let x = 222.0;
        let cw = (w - x - 26.0).max(100.0);
        self.text(
            &mut pix,
            labels[page.min(labels.len() - 1)],
            x,
            26.0,
            26.0,
            TEXT,
            cw,
        );
        self.text(
            &mut pix,
            if explorer.paused {
                "PAUSED  /  Frozen snapshot"
            } else {
                "LIVE  /  Resource activity"
            },
            x,
            66.0,
            11.0,
            accent,
            cw,
        );
        if page == 0 {
            let ram = if data.memory.total > 0 {
                data.memory.used as f64 / data.memory.total as f64 * 100.0
            } else {
                0.0
            };
            let cards = [
                ("PROCESSOR", metric(data.cpu, "%")),
                (
                    "MEMORY",
                    if data.memory.total > 0 {
                        format!("{ram:.1}%")
                    } else {
                        "—".into()
                    },
                ),
                ("PROCESSES", data.processes.len().to_string()),
                (
                    "NETWORK RX + TX",
                    format!(
                        "{}/s",
                        rate(
                            data.networks
                                .iter()
                                .filter(|n| n.physical)
                                .filter_map(|n| Some(n.rx? + n.tx?))
                                .reduce(|a, b| a + b)
                        )
                    ),
                ),
                (
                    "DISK READ + WRITE",
                    format!(
                        "{}/s",
                        rate(
                            data.disks
                                .iter()
                                .filter_map(|d| Some(d.read? + d.write?))
                                .reduce(|a, b| a + b)
                        )
                    ),
                ),
                (
                    "BATTERY DRAW",
                    metric(
                        data.batteries
                            .iter()
                            .filter_map(|b| b.watts)
                            .reduce(|a, b| a + b),
                        " W",
                    ),
                ),
            ];
            let card_w = (cw - 24.0) / 3.0;
            for (i, (label, value)) in cards.iter().enumerate() {
                let cx = x + (i % 3) as f32 * (card_w + 12.0);
                let cy = (i / 3) as f32 * 120.0;
                self.rect(
                    &mut pix,
                    cx,
                    108.0 + cy,
                    card_w,
                    108.0,
                    12.0,
                    [24, 35, 51],
                    1.0,
                );
                self.text(
                    &mut pix,
                    label,
                    cx + 16.0,
                    124.0 + cy,
                    10.0,
                    MUTED,
                    card_w - 32.0,
                );
                self.text(
                    &mut pix,
                    value,
                    cx + 16.0,
                    153.0 + cy,
                    22.0,
                    accent,
                    card_w - 32.0,
                );
            }
            self.text(
                &mut pix,
                "Processes · highest CPU activity",
                x,
                364.0,
                17.0,
                TEXT,
                cw,
            );
            self.text(
                &mut pix,
                "100% CPU = one thread · sampled process leaders",
                x,
                394.0,
                11.0,
                MUTED,
                cw,
            );
            self.text(
                &mut pix,
                "NAME / PID",
                x + 16.0,
                430.0,
                10.0,
                MUTED,
                cw * 0.55,
            );
            self.text(&mut pix, "CPU", x + cw * 0.6, 430.0, 10.0, MUTED, 80.0);
            self.text(&mut pix, "MEMORY", x + cw * 0.8, 430.0, 10.0, MUTED, 100.0);
            for (i, p) in data.top_cpu.iter().skip(scroll).enumerate() {
                let y = 458.0 + i as f32 * 42.0;
                if y + 42.0 > h - 24.0 {
                    break;
                }
                self.rect(
                    &mut pix,
                    x,
                    y,
                    cw,
                    38.0,
                    6.0,
                    [24, 35, 51],
                    if i % 2 == 0 { 0.8 } else { 0.3 },
                );
                self.text(
                    &mut pix,
                    &format!("{}  /  {}", p.name, p.pid),
                    x + 16.0,
                    y + 10.0,
                    12.0,
                    TEXT,
                    cw * 0.55,
                );
                self.text(
                    &mut pix,
                    &metric(p.cpu, "%"),
                    x + cw * 0.6,
                    y + 10.0,
                    12.0,
                    accent,
                    cw * 0.18,
                );
                self.text(
                    &mut pix,
                    &b(p.memory),
                    x + cw * 0.8,
                    y + 10.0,
                    12.0,
                    TEXT,
                    cw * 0.19,
                );
            }
        } else if page == 1 {
            self.process_table(&mut pix, data, explorer, scroll, x, cw, h);
        } else {
            let section = explorer.section(data, page);
            let offset = if page == 2 { 48.0 } else { 0.0 };
            if page == 2 {
                for (i, label) in crate::explorer::PERFORMANCE.iter().enumerate() {
                    let bx = x + i as f32 * cw / 4.0;
                    self.rect(
                        &mut pix,
                        bx,
                        104.0,
                        cw / 4.0 - 6.0,
                        34.0,
                        6.0,
                        accent,
                        if i == explorer.performance {
                            0.22
                        } else {
                            0.06
                        },
                    );
                    self.text(
                        &mut pix,
                        label,
                        bx + 8.0,
                        113.0,
                        11.0,
                        if i == explorer.performance {
                            accent
                        } else {
                            TEXT
                        },
                        cw / 4.0 - 20.0,
                    );
                }
            }
            let graph_height = if self.config.graphs && !section.history.is_empty() {
                138.0
            } else {
                0.0
            };
            if graph_height > 0.0 {
                self.rect(
                    &mut pix,
                    x,
                    108.0 + offset,
                    cw,
                    graph_height,
                    12.0,
                    [24, 35, 51],
                    1.0,
                );
                self.graph(
                    &mut pix,
                    &section.history,
                    x + 18.0,
                    126.0 + offset,
                    cw - 36.0,
                    100.0,
                    section.maximum,
                    accent,
                );
            }
            let start = 120.0 + graph_height + offset;
            for (i, (label, value)) in section.rows.iter().skip(scroll).enumerate() {
                let y = start + i as f32 * 38.0;
                if y + 38.0 > h - 28.0 {
                    break;
                }
                self.rect(
                    &mut pix,
                    x,
                    y,
                    cw,
                    34.0,
                    6.0,
                    [24, 35, 51],
                    if i % 2 == 0 { 0.8 } else { 0.3 },
                );
                self.text(
                    &mut pix,
                    label,
                    x + 14.0,
                    y + 8.0,
                    self.config.font_size,
                    MUTED,
                    cw * 0.35,
                );
                self.text(
                    &mut pix,
                    value,
                    x + cw * 0.39,
                    y + 8.0,
                    self.config.font_size,
                    TEXT,
                    cw * 0.59,
                );
            }
            self.text(
                &mut pix,
                "Scroll to explore all readings",
                x,
                h - 22.0,
                10.0,
                MUTED,
                cw,
            );
        }
        Ok(pix)
    }

    pub fn render(&mut self, data: &Snapshot, width: u32, height: u32) -> Result<Pixmap, String> {
        // Fit once using font metrics. No asynchronous positioners, timers, or wallpaper pixel scans.
        self.scale = 1.0;
        let mut sections: Vec<_> = sections(data)
            .into_iter()
            .filter(|s| self.config.sections.iter().any(|title| title == s.title))
            .collect();
        if !self.config.graphs {
            for section in &mut sections {
                section.history.clear();
            }
        }
        let gap = 8.0 * (width as f32 / 1000.0).min(2.0);
        let card_width = (width as f32 - gap) / 2.0;
        let padding = (card_width * 0.025).max(3.0);
        let label_width = (card_width - 2.0 * padding) * 0.38;
        let reading_width = (card_width - 2.0 * padding) * 0.60;
        let mut weights = [0usize; 2];
        let mut columns = vec![];
        let mut card_counts = [0usize; 2];
        for section in &sections {
            let column = usize::from(weights[1] < weights[0]);
            weights[column] += section.rows.len() + 2;
            card_counts[column] += 1;
            columns.push(column);
        }
        let mut font = (self.config.font_size * width as f32 / 1000.0).min(24.0);
        let (wrapped, heights, totals) = loop {
            let mut heights = Vec::new();
            let mut totals = [0.0f32; 2];
            let mut counts = [0usize; 2];
            let mut wrapped = Vec::new();
            for (i, section) in sections.iter().enumerate() {
                let rows: Vec<_> = section
                    .rows
                    .iter()
                    .map(|(a, b)| {
                        (
                            self.wrap(a, font, label_width),
                            self.wrap(b, font, reading_width),
                        )
                    })
                    .collect();
                let rows_height: f32 = rows
                    .iter()
                    .map(|(a, b)| a.len().max(b.len()) as f32 * font * 1.24)
                    .sum();
                let graph = if section.history.is_empty() {
                    0.0
                } else {
                    font * 2.7
                };
                let h = padding * 2.0 + font * 1.8 + rows_height + graph;
                heights.push(h);
                totals[columns[i]] += h;
                counts[columns[i]] += 1;
                wrapped.push(rows);
            }
            for i in 0..2 {
                totals[i] += counts[i].saturating_sub(1) as f32 * gap;
            }
            if totals.iter().all(|h| *h <= height as f32) || font <= 1.5 {
                break (wrapped, heights, totals);
            }
            let ratio = height as f32 / totals[0].max(totals[1]);
            font = (font * (ratio * 0.99)).min(font - 0.1).max(1.5);
        };
        let mut positions = Vec::new();
        let mut offsets = [0.0f32; 2];
        for (i, h) in heights.iter().enumerate() {
            let column = columns[i];
            let extra = (height as f32 - totals[column]).max(0.0) * h
                / (totals[column] - card_counts[column].saturating_sub(1) as f32 * gap).max(1.0);
            positions.push((
                column as f32 * (card_width + gap),
                offsets[column],
                h + extra,
            ));
            offsets[column] += h + extra + gap;
        }
        let fallback = [
            self.accent,
            [134, 166, 255],
            [84, 227, 218],
            [255, 107, 157],
            [226, 127, 255],
            [184, 138, 255],
            [94, 232, 165],
        ];
        let colors: Vec<_> = (0..sections.len())
            .map(|i| {
                if self.colors.is_empty() {
                    fallback[i]
                } else {
                    self.colors[i * 3 % self.colors.len()]
                }
            })
            .collect();
        let mut key = vec![width, height, self.config.opacity.to_bits()];
        for (i, (x, y, h)) in positions.iter().enumerate() {
            key.extend([
                x.to_bits(),
                y.to_bits(),
                h.to_bits(),
                u32::from_be_bytes([0, colors[i][0], colors[i][1], colors[i][2]]),
            ]);
        }
        if self.background.is_none() || self.background_key != key {
            let mut background =
                Pixmap::new(width, height).ok_or("Cannot allocate render buffer")?;
            for (i, (x, y, h)) in positions.iter().enumerate() {
                let color = colors[i];
                let tint = [10 + color[0] / 12, 15 + color[1] / 12, 23 + color[2] / 12];
                self.rect(
                    &mut background,
                    *x,
                    *y,
                    card_width,
                    *h,
                    12.0,
                    color,
                    self.config.opacity * 0.32,
                );
                self.rect(
                    &mut background,
                    *x + 1.0,
                    *y + 1.0,
                    card_width - 2.0,
                    *h - 2.0,
                    11.0,
                    tint,
                    self.config.opacity,
                );
                self.rect(
                    &mut background,
                    *x + 12.0,
                    *y + 1.0,
                    card_width - 24.0,
                    0.7,
                    0.0,
                    [255, 255, 255],
                    self.config.opacity * 0.28,
                );
            }
            self.background = Some(background);
            self.background_key = key;
        }
        let mut pix = self.background.as_ref().unwrap().clone();
        if self.glyphs.len() > 4096 {
            self.glyphs.clear();
        }
        for (i, section) in sections.iter().enumerate() {
            let (x, y, _) = positions[i];
            let color = colors[i];
            let foreground = [150 + color[0] / 3, 150 + color[1] / 3, 150 + color[2] / 3];
            self.text(
                &mut pix,
                section.title,
                x + padding,
                y + padding,
                font * 1.04,
                color,
                card_width - 2.0 * padding,
            );
            let mut ry = y + padding + font * 1.8;
            for (labels, readings) in &wrapped[i] {
                for (line, label) in labels.iter().enumerate() {
                    self.text(
                        &mut pix,
                        label,
                        x + padding,
                        ry + line as f32 * font * 1.24,
                        font,
                        foreground,
                        label_width,
                    );
                }
                for (line, reading) in readings.iter().enumerate() {
                    let measured: f32 = reading
                        .chars()
                        .map(|c| self.font.metrics(c, font.round().max(1.0)).advance_width)
                        .sum();
                    self.text(
                        &mut pix,
                        reading,
                        x + card_width - padding - measured.min(reading_width),
                        ry + line as f32 * font * 1.24,
                        font,
                        foreground,
                        reading_width + 1.0,
                    );
                }
                ry += labels.len().max(readings.len()) as f32 * font * 1.24;
            }
            if !section.history.is_empty() {
                self.graph(
                    &mut pix,
                    &section.history,
                    x + padding,
                    ry + font * 0.6,
                    card_width - padding * 2.0,
                    font * 1.7,
                    section.maximum,
                    color,
                );
            }
        }
        Ok(pix)
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn all_original_sections_and_memory_details_are_present() {
        let sections = sections(&Snapshot::default());
        assert_eq!(sections.len(), 7);
        let rows = &sections.iter().find(|s| s.title == "MEMORY").unwrap().rows;
        for key in [
            "RAM",
            "Available",
            "Cache",
            "Swap",
            "Memory stalls",
            "Top RAM processes",
        ] {
            assert!(rows.iter().any(|(label, _)| label == key));
        }
    }
    #[test]
    fn window_pages_render_at_minimum_and_default_sizes() {
        let mut renderer = Renderer::new(Config::default()).unwrap();
        for (w, h) in [(720, 540), (1000, 720)] {
            for page in 0..crate::explorer::PAGES.len() {
                let image = renderer
                    .render_window(
                        &Snapshot::default(),
                        w,
                        h,
                        page,
                        0,
                        &crate::explorer::Explorer::default(),
                    )
                    .unwrap();
                assert!(image.pixels().iter().all(|p| p.alpha() == 255));
            }
        }
    }
    #[test]
    fn process_explorer_and_performance_render_populated_snapshots() {
        let config = Config::default();
        let mut collector = crate::collect::Collector::new(config.clone());
        let data = collector.sample();
        let mut renderer = Renderer::new(config).unwrap();
        let mut view = crate::explorer::Explorer::default();
        for (w, h) in [(720, 540), (1000, 720)] {
            for page in 0..crate::explorer::PAGES.len() {
                for part in 0..4 {
                    view.performance = part;
                    let image = renderer
                        .render_window(&data, w, h, page, usize::MAX, &view)
                        .unwrap();
                    assert!(image.pixels().iter().all(|p| p.alpha() == 255));
                    if w == 1000 && part == 0 {
                        if let Ok(dir) = std::env::var("HYPRMONITOR_PREVIEW_DIR") {
                            image
                                .save_png(
                                    std::path::Path::new(&dir).join(format!("page-{page}.png")),
                                )
                                .unwrap();
                        }
                    }
                }
            }
        }
    }

    #[test]
    fn missing_rates_are_not_zero() {
        assert_eq!(rate(None), "—");
        assert_eq!(bytes(-0.0), "0 B");
    }
    #[test]
    fn renderer_keeps_background_translucent_and_pixels_premultiplied() {
        let mut renderer = Renderer::new(Config::default()).expect("Test needs an installed font");
        let pix = renderer.render(&Snapshot::default(), 1000, 1000).unwrap();
        assert!(pix
            .pixels()
            .iter()
            .any(|p| p.alpha() > 0 && p.alpha() < 255));
        assert!(pix
            .pixels()
            .iter()
            .all(|p| p.red() <= p.alpha() && p.green() <= p.alpha() && p.blue() <= p.alpha()));
        let count = renderer.glyphs.len();
        renderer.render(&Snapshot::default(), 1000, 1000).unwrap();
        assert_eq!(renderer.glyphs.len(), count);
    }
}

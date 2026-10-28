//! Opaque task-manager workspace, independent of the legacy desktop overlay.
use super::*;
use crate::explorer::{visible_rows, Explorer, COLUMNS, CONTENT, PAGES, RAIL, ROW, TABLE_TOP};
const PANEL: Rgb = [17, 24, 29];
const LINE: Rgb = [43, 57, 65];
const GREEN: Rgb = [104, 235, 171];
const BLUE: Rgb = [100, 192, 245];
const AMBER: Rgb = [241, 195, 97];
const PURPLE: Rgb = [189, 151, 248];

impl Renderer {
    fn workspace_text(
        &mut self,
        p: &mut Pixmap,
        text: &str,
        x: f32,
        y: f32,
        size: f32,
        color: Rgb,
        width: f32,
    ) {
        self.text(
            p,
            text,
            x,
            y,
            size * self.config.font_size / 13.0,
            color,
            width,
        );
    }
    fn instrument(
        &mut self,
        p: &mut Pixmap,
        label: &str,
        value: &str,
        note: &str,
        history: &VecDeque<f64>,
        maximum: f64,
        color: Rgb,
        x: f32,
        y: f32,
        w: f32,
        h: f32,
    ) {
        self.rect(p, x, y, w, h, 3.0, LINE, 1.0);
        self.rect(p, x + 1.0, y + 1.0, w - 2.0, h - 2.0, 3.0, PANEL, 1.0);
        self.rect(p, x + 1.0, y + 1.0, 3.0, h - 2.0, 0.0, color, 0.8);
        self.workspace_text(p, label, x + 14.0, y + 12.0, 11.0, color, w - 28.0);
        self.workspace_text(p, value, x + 14.0, y + 34.0, 27.0, color, w - 28.0);
        self.workspace_text(p, note, x + 14.0, y + h - 22.0, 10.0, MUTED, w - 28.0);
        if self.config.graphs && !history.is_empty() {
            self.graph(
                p,
                history,
                x + 14.0,
                y + 72.0,
                w - 28.0,
                (h - 110.0).max(12.0),
                maximum,
                color,
            );
        } else {
            // Segmented current-value meter; no invented history.
            let value = history.back().copied();
            for i in 0..24 {
                let active = value.is_some_and(|v| v / maximum.max(1.0) > i as f64 / 24.0);
                self.rect(
                    p,
                    x + 14.0 + i as f32 * (w - 28.0) / 24.0,
                    y + 79.0,
                    ((w - 28.0) / 24.0 - 2.0).max(1.0),
                    12.0,
                    0.0,
                    color,
                    if active { 0.85 } else { 0.09 },
                );
            }
        }
    }

    pub fn render_window(
        &mut self,
        data: &Snapshot,
        width: u32,
        height: u32,
        page: usize,
        scroll: usize,
        view: &Explorer,
    ) -> Result<Pixmap, String> {
        self.scale = 1.0;
        let mut p = Pixmap::new(width, height).ok_or("Invalid window size")?;
        p.fill(Color::from_rgba8(10, 15, 19, 255));
        let (w, h) = (width as f32, height as f32);
        let page = page.min(PAGES.len() - 1);
        let x = CONTENT;
        let cw = (w - x - 20.0).max(100.0);
        let accent = self.accent;
        self.rect(&mut p, 0.0, 0.0, RAIL, h, 0.0, [20, 27, 32], 1.0);
        self.rect(&mut p, RAIL - 1.0, 0.0, 1.0, h, 0.0, LINE, 1.0);
        self.workspace_text(&mut p, "HYPRMONITOR", 14.0, 21.0, 15.0, TEXT, 145.0);
        self.workspace_text(&mut p, "TASK MANAGER", 14.0, 45.0, 10.0, accent, 145.0);
        for (i, label) in PAGES.iter().enumerate() {
            let y = 82.0 + i as f32 * 38.0;
            if i == page {
                self.rect(&mut p, 7.0, y, RAIL - 14.0, 34.0, 3.0, accent, 0.11);
                self.rect(&mut p, 7.0, y + 5.0, 3.0, 24.0, 0.0, accent, 1.0);
            }
            self.workspace_text(
                &mut p,
                &format!("{:02}", i + 1),
                18.0,
                y + 11.0,
                10.0,
                if i == page { accent } else { MUTED },
                22.0,
            );
            self.workspace_text(
                &mut p,
                label,
                45.0,
                y + 10.0,
                11.0,
                if i == page { TEXT } else { MUTED },
                116.0,
            );
        }
        self.workspace_text(&mut p, "Settings", 20.0, h - 35.0, 12.0, TEXT, 120.0);
        self.workspace_text(&mut p, PAGES[page], x, 20.0, 23.0, TEXT, cw - 190.0);
        self.workspace_text(
            &mut p,
            if view.paused { "PAUSED" } else { "LIVE" },
            w - 180.0,
            21.0,
            10.0,
            if view.paused { AMBER } else { GREEN },
            64.0,
        );
        self.rect(&mut p, w - 104.0, 14.0, 84.0, 30.0, 3.0, LINE, 1.0);
        self.workspace_text(
            &mut p,
            if view.paused { "Resume" } else { "Pause" },
            w - 91.0,
            23.0,
            11.0,
            TEXT,
            70.0,
        );
        self.workspace_text(
            &mut p,
            &format!(
                "{}  ·  {} processes  ·  up {}h {}m",
                data.os,
                data.processes.len(),
                data.uptime / 3600,
                data.uptime / 60 % 60
            ),
            x,
            53.0,
            10.0,
            MUTED,
            cw,
        );
        self.rect(&mut p, x, 75.0, cw, 1.0, 0.0, LINE, 1.0);
        match page {
            0 => self.summary(&mut p, data, x, cw, h),
            1 => self.process_grid(&mut p, data, view, scroll, x, cw, h),
            _ => self.resource(&mut p, data, view, page, scroll, x, cw, h),
        }
        Ok(p)
    }

    fn summary(&mut self, p: &mut Pixmap, d: &Snapshot, x: f32, w: f32, h: f32) {
        let memory =
            (d.memory.total > 0).then(|| d.memory.used as f64 / d.memory.total as f64 * 100.0);
        let disk = d
            .disks
            .iter()
            .filter_map(|v| Some(v.read? + v.write?))
            .reduce(|a, b| a + b);
        let net = d
            .networks
            .iter()
            .filter(|n| n.physical)
            .filter_map(|n| Some(n.rx? + n.tx?))
            .reduce(|a, b| a + b);
        let power = d
            .batteries
            .iter()
            .filter_map(|b| b.watts)
            .reduce(|a, b| a + b);
        let gpu = d.gpus.iter().filter_map(|g| g.busy).reduce(f64::max);
        let items = [
            (
                "CPU",
                metric(d.cpu, "%"),
                format!(
                    "{} logical CPUs · {}",
                    d.cores.len(),
                    metric(d.frequency_mhz.map(|v| v / 1000.0), " GHz")
                ),
                d.cpu_history.clone(),
                100.0,
                GREEN,
            ),
            (
                "MEMORY",
                metric(memory, "%"),
                format!("{} / {}", b(d.memory.used), b(d.memory.total)),
                d.memory_history.clone(),
                100.0,
                PURPLE,
            ),
            (
                "GPU",
                metric(gpu, "%"),
                d.gpus
                    .first()
                    .map(|g| g.model.clone())
                    .unwrap_or("No exposed GPU sensor".into()),
                d.gpu_history.clone(),
                100.0,
                BLUE,
            ),
            (
                "DISKS",
                format!("{}/s", rate(disk)),
                format!("I/O pressure {}", metric(d.io_pressure, "%")),
                d.disk_history.clone(),
                d.disk_history.iter().copied().fold(1.0, f64::max),
                AMBER,
            ),
            (
                "NETWORK",
                format!("{}/s", rate(net)),
                "Physical interfaces · receive + send".into(),
                d.network_history.clone(),
                d.network_history.iter().copied().fold(1.0, f64::max),
                BLUE,
            ),
            (
                "POWER",
                metric(power, " W"),
                d.batteries
                    .first()
                    .map(|b| format!("{} · {}", metric(b.percent, "%"), b.status))
                    .unwrap_or("Battery power not exposed".into()),
                d.power_history.clone(),
                d.power_history.iter().copied().fold(1.0, f64::max),
                GREEN,
            ),
        ];
        let ch = ((h - 250.0) / 2.0).clamp(132.0, 215.0);
        let cell = (w - 20.0) / 3.0;
        for (i, (label, value, note, history, max, color)) in items.iter().enumerate() {
            self.instrument(
                p,
                label,
                value,
                note,
                history,
                *max,
                *color,
                x + (i % 3) as f32 * (cell + 10.0),
                90.0 + (i / 3) as f32 * (ch + 10.0),
                cell,
                ch,
            );
        }
        let top = 90.0 + 2.0 * (ch + 10.0);
        self.workspace_text(p, "TOP PROCESSES", x, top + 2.0, 11.0, TEXT, w);
        self.workspace_text(
            p,
            "CPU / MEMORY",
            x + w - 170.0,
            top + 2.0,
            10.0,
            MUTED,
            170.0,
        );
        for (i, proc) in d.top_cpu.iter().enumerate() {
            let y = top + 26.0 + i as f32 * 26.0;
            if y + 24.0 > h - 30.0 {
                break;
            }
            self.rect(
                p,
                x,
                y,
                w,
                25.0,
                0.0,
                PANEL,
                if i % 2 == 0 { 1.0 } else { 0.3 },
            );
            self.workspace_text(p, &proc.name, x + 9.0, y + 6.0, 11.0, TEXT, w - 180.0);
            self.workspace_text(
                p,
                &format!("{}  /  {}", metric(proc.cpu, "%"), b(proc.memory)),
                x + w - 170.0,
                y + 6.0,
                11.0,
                GREEN,
                166.0,
            );
        }
        self.workspace_text(
            p,
            "Select a resource to inspect it  ·  Processes to find or end a task",
            x,
            h - 20.0,
            10.0,
            MUTED,
            w,
        );
    }

    fn process_grid(
        &mut self,
        p: &mut Pixmap,
        d: &Snapshot,
        v: &Explorer,
        scroll: usize,
        x: f32,
        w: f32,
        h: f32,
    ) {
        self.rect(
            p,
            x,
            90.0,
            w,
            32.0,
            3.0,
            if v.searching { LINE } else { PANEL },
            1.0,
        );
        self.workspace_text(
            p,
            &format!(
                "{}{}",
                if v.query.is_empty() && !v.searching {
                    "Search by name or PID"
                } else {
                    "Filter: "
                },
                v.query
            ),
            x + 10.0,
            100.0,
            12.0,
            TEXT,
            w - 20.0,
        );
        self.rect(p, x, 130.0, w, 28.0, 0.0, LINE, 0.65);
        for (i, (label, fraction, sort)) in COLUMNS.iter().enumerate() {
            let end = COLUMNS.get(i + 1).map(|c| c.1).unwrap_or(1.0);
            self.workspace_text(
                p,
                &format!(
                    "{}{}",
                    label,
                    if *sort == v.sort {
                        if v.ascending {
                            " ↑"
                        } else {
                            " ↓"
                        }
                    } else {
                        ""
                    }
                ),
                x + w * fraction + 7.0,
                139.0,
                10.0,
                if *sort == v.sort { self.accent } else { TEXT },
                w * (end - fraction) - 9.0,
            );
        }
        let rows = v.rows(d);
        let count = visible_rows(h);
        let start = scroll.min(rows.len().saturating_sub(count));
        for (i, proc) in rows.iter().skip(start).take(count).enumerate() {
            let y = TABLE_TOP + i as f32 * ROW;
            let selected = v.selected == Some((proc.pid, proc.start_ticks));
            self.rect(
                p,
                x,
                y,
                w,
                ROW - 1.0,
                0.0,
                if selected { self.accent } else { PANEL },
                if selected {
                    0.22
                } else if i % 2 == 0 {
                    1.0
                } else {
                    0.35
                },
            );
            let cells = [
                proc.name.clone(),
                proc.pid.to_string(),
                metric(proc.cpu, "%"),
                b(proc.memory),
                proc.threads.to_string(),
                rate(proc.read_rate),
                rate(proc.write_rate),
            ];
            for (j, (_, fraction, _)) in COLUMNS.iter().enumerate() {
                let end = COLUMNS.get(j + 1).map(|c| c.1).unwrap_or(1.0);
                if j == 2 || j == 3 {
                    let load = if j == 2 {
                        proc.cpu.unwrap_or(0.0) / 100.0
                    } else {
                        proc.memory as f64 / d.memory.total.max(1) as f64
                    };
                    self.rect(
                        p,
                        x + w * fraction,
                        y,
                        w * (end - fraction),
                        ROW - 1.0,
                        0.0,
                        if j == 2 { GREEN } else { PURPLE },
                        (load as f32 * 0.25).clamp(0.02, 0.25),
                    );
                }
                self.workspace_text(
                    p,
                    &cells[j],
                    x + w * fraction + 7.0,
                    y + 9.0,
                    11.0,
                    if j == 2 { GREEN } else { TEXT },
                    w * (end - fraction) - 10.0,
                );
            }
        }
        if rows.is_empty() {
            self.workspace_text(
                p,
                "No matching processes",
                x + 12.0,
                TABLE_TOP + 20.0,
                13.0,
                MUTED,
                w - 24.0,
            );
        }
        let selected = v
            .selected
            .and_then(|id| d.processes.iter().find(|p| (p.pid, p.start_ticks) == id));
        let info = selected
            .map(|p| {
                format!(
                    "{} · PID {} · parent {} · state {}",
                    p.name, p.pid, p.parent, p.state
                )
            })
            .unwrap_or("Select a process to inspect or end it".into());
        self.rect(p, x, h - 79.0, w, 1.0, 0.0, LINE, 1.0);
        self.workspace_text(
            p,
            if v.status.is_empty() {
                &info
            } else {
                &v.status
            },
            x,
            h - 66.0,
            11.0,
            if v.status.is_empty() { TEXT } else { AMBER },
            w - 130.0,
        );
        self.rect(
            p,
            x + w - 118.0,
            h - 70.0,
            118.0,
            30.0,
            3.0,
            if v.confirming { [137, 55, 49] } else { LINE },
            1.0,
        );
        self.workspace_text(
            p,
            if v.confirming {
                "Confirm end"
            } else {
                "End task"
            },
            x + w - 107.0,
            h - 61.0,
            11.0,
            if selected.is_some() { TEXT } else { MUTED },
            105.0,
        );
        self.workspace_text(
            p,
            if v.confirming {
                "Send SIGTERM? Unsaved work may be lost. Esc cancels."
            } else {
                "CPU: 100% = one logical CPU · Memory: RSS (includes shared pages)"
            },
            x,
            h - 39.0,
            10.0,
            if v.confirming { AMBER } else { MUTED },
            w,
        );
        self.workspace_text(
            p,
            &format!(
                "{} processes · rows {}–{} · process interval {}s",
                rows.len(),
                if rows.is_empty() { 0 } else { start + 1 },
                (start + count).min(rows.len()),
                self.config.process_interval_secs
            ),
            x,
            h - 20.0,
            10.0,
            MUTED,
            w,
        );
        if rows.len() > count {
            let track = count as f32 * ROW;
            self.rect(
                p,
                x + w - 3.0,
                TABLE_TOP + track * start as f32 / rows.len() as f32,
                3.0,
                track * count as f32 / rows.len() as f32,
                0.0,
                self.accent,
                0.65,
            );
        }
    }

    fn resource(
        &mut self,
        p: &mut Pixmap,
        d: &Snapshot,
        v: &Explorer,
        page: usize,
        scroll: usize,
        x: f32,
        w: f32,
        h: f32,
    ) {
        let mut section = v.section(d, page);
        match page {
            4 => {
                section.history = d.disk_history.clone();
                section.maximum = section.history.iter().copied().fold(1.0, f64::max);
            }
            6 => {
                section.history = d.gpu_history.clone();
                section.maximum = 100.0;
            }
            7 => {
                section.history = d.power_history.clone();
                section.maximum = section.history.iter().copied().fold(1.0, f64::max);
            }
            _ => {}
        }
        let color = match page {
            3 => PURPLE,
            4 => AMBER,
            5 | 6 => BLUE,
            _ => GREEN,
        };
        let heading = match page {
            2 => d.cpu_model.clone(),
            3 => format!("{} installed memory", b(d.memory.total)),
            4 => "Storage devices & filesystems".into(),
            5 => "Physical traffic & interface details".into(),
            6 => "Graphics, temperature & fan sensors".into(),
            7 => "Battery state & energy".into(),
            _ => d.model.clone(),
        };
        self.workspace_text(p, &heading, x, 91.0, 13.0, TEXT, w);
        let has_graph = self.config.graphs && matches!(page, 2..=7);
        let mut top = 124.0;
        if has_graph {
            let gh = ((h - 330.0) * 0.48).clamp(80.0, 180.0);
            self.rect(p, x, top, w, gh + 30.0, 2.0, LINE, 1.0);
            self.rect(p, x + 1.0, top + 1.0, w - 2.0, gh + 28.0, 2.0, PANEL, 1.0);
            self.workspace_text(
                p,
                &format!(
                    "{} samples  ·  {} ms / sample",
                    section.history.len(),
                    self.config.interval_ms
                ),
                x + 12.0,
                top + 9.0,
                10.0,
                color,
                w - 24.0,
            );
            self.graph(
                p,
                &section.history,
                x + 12.0,
                top + 28.0,
                w - 24.0,
                gh - 10.0,
                section.maximum,
                color,
            );
            if section.history.iter().filter(|v| v.is_finite()).count() < 2 {
                self.workspace_text(
                    p,
                    "Waiting for measurements / sensor unavailable",
                    x + 18.0,
                    top + 51.0,
                    12.0,
                    MUTED,
                    w - 36.0,
                );
            }
            top += gh + 43.0;
        }
        if page == 2 && !d.cores.is_empty() {
            let cols = ((w / 115.0) as usize).max(1);
            let cell = w / cols as f32;
            let shown = d.cores.len().min(cols * 2);
            for (i, load) in d.cores.iter().take(shown).enumerate() {
                let bx = x + (i % cols) as f32 * cell;
                let by = top + (i / cols) as f32 * 53.0;
                self.workspace_text(
                    p,
                    &format!("CPU {i}  {}", metric(*load, "%")),
                    bx,
                    by,
                    10.0,
                    color,
                    cell - 5.0,
                );
                if self.config.graphs {
                    if let Some(history) = d.core_history.get(i) {
                        self.graph(p, history, bx, by + 19.0, cell - 10.0, 24.0, 100.0, color);
                    }
                } else {
                    self.rect(p, bx, by + 20.0, cell - 10.0, 5.0, 0.0, LINE, 1.0);
                    if let Some(load) = load {
                        self.rect(
                            p,
                            bx,
                            by + 20.0,
                            (cell - 10.0) * (*load as f32 / 100.0).clamp(0.0, 1.0),
                            5.0,
                            0.0,
                            color,
                            1.0,
                        );
                    }
                }
            }
            top += shown.div_ceil(cols) as f32 * 53.0;
        }
        let count = ((h - top - 33.0) / 29.0).max(1.0) as usize;
        let start = scroll.min(section.rows.len().saturating_sub(count));
        for (i, (key, value)) in section.rows.iter().skip(start).take(count).enumerate() {
            let y = top + i as f32 * 29.0;
            self.rect(
                p,
                x,
                y,
                w,
                28.0,
                0.0,
                PANEL,
                if i % 2 == 0 { 1.0 } else { 0.3 },
            );
            self.workspace_text(p, key, x + 9.0, y + 8.0, 11.0, MUTED, w * 0.34 - 14.0);
            self.workspace_text(p, value, x + w * 0.34, y + 8.0, 11.0, TEXT, w * 0.66 - 10.0);
        }
        self.workspace_text(
            p,
            &format!(
                "Readings {}–{} of {} · Scroll to explore · — unavailable",
                start + 1,
                (start + count).min(section.rows.len()),
                section.rows.len()
            ),
            x,
            h - 20.0,
            10.0,
            MUTED,
            w,
        );
    }
}

//! Native settings UI shared by layer-shell and ordinary-window backends.
use crate::config::Config;

pub const TITLES: [&str; 7] = [
    "SYSTEM",
    "PROCESSOR",
    "GRAPHICS & COOLING",
    "MEMORY",
    "STORAGE",
    "NETWORK",
    "POWER",
];
pub const ROW_HEIGHT: f32 = 25.0;
#[derive(Default)]
pub struct SettingsMenu {
    pub open: bool,
    pub x: f32,
    pub y: f32,
    pub scroll: usize,
    pub status: String,
}
#[derive(Clone, Copy, PartialEq)]
pub enum Effect {
    Changed,
    Resize,
    Visibility,
    Restart,
    Quit,
    Close,
}
impl SettingsMenu {
    pub fn show(&mut self, x: f32, y: f32, width: u32, height: u32) {
        self.open = !self.open;
        self.scroll = 0;
        self.x = x.min((width as f32 - self.width(width)).max(0.0));
        self.y = y.min((height as f32 - self.height(height)).max(0.0));
    }
    pub fn width(&self, width: u32) -> f32 {
        (width as f32 - 12.0).clamp(200.0, 380.0)
    }
    pub fn height(&self, height: u32) -> f32 {
        (height as f32 - 12.0).clamp(180.0, 650.0)
    }
    pub fn visible_rows(&self, height: u32) -> usize {
        ((self.height(height) - 90.0) / ROW_HEIGHT).floor() as usize
    }
    pub fn rows(config: &Config) -> Vec<(String, String)> {
        let mut rows: Vec<_> = TITLES
            .iter()
            .map(|title| {
                (
                    title.to_string(),
                    if config.sections.iter().any(|s| s == title) {
                        "On".into()
                    } else {
                        "Off".into()
                    },
                )
            })
            .collect();
        rows.extend([
            (
                "History graphs".into(),
                if config.graphs {
                    "On".into()
                } else {
                    "Off".into()
                },
            ),
            (
                "Background opacity".into(),
                format!("−  {:.0}%  +", config.opacity * 100.0),
            ),
            ("Text size".into(), format!("−  {:.0}  +", config.font_size)),
            (
                "Update interval".into(),
                format!("−  {} ms  +", config.interval_ms),
            ),
            (
                "Process interval".into(),
                format!("−  {} s  +", config.process_interval_secs),
            ),
            (
                "Sensor interval".into(),
                format!("−  {} s  +", config.slow_interval_secs),
            ),
            ("History length".into(), format!("−  {}  +", config.history)),
            ("Accent color".into(), config.accent.clone()),
            ("Display mode".into(), config.mode.clone()),
            ("Show on all workspaces".into(), "Apply".into()),
            ("Hide on all workspaces".into(), "Apply".into()),
            ("Reset size and position".into(), "Apply".into()),
            ("Close settings".into(), "Close".into()),
            ("Quit Hyprmonitor".into(), "Quit".into()),
        ]);
        rows
    }
    pub fn wheel(&mut self, delta: f32, config: &Config, height: u32) {
        if delta < 0.0 {
            self.scroll = (self.scroll + 2).min(
                Self::rows(config)
                    .len()
                    .saturating_sub(self.visible_rows(height)),
            );
        } else {
            self.scroll = self.scroll.saturating_sub(2);
        }
    }
    pub fn click(
        &mut self,
        x: f32,
        y: f32,
        width: u32,
        height: u32,
        config: &mut Config,
    ) -> Option<Effect> {
        if !self.open {
            return None;
        }
        if x < self.x
            || x > self.x + self.width(width)
            || y < self.y
            || y > self.y + self.height(height)
        {
            self.open = false;
            return Some(Effect::Close);
        }
        if y < self.y + 47.0 || y >= self.y + 47.0 + self.visible_rows(height) as f32 * ROW_HEIGHT {
            return Some(Effect::Close);
        }
        let index = ((y - self.y - 47.0) / ROW_HEIGHT).floor() as usize + self.scroll;
        let plus = x > self.x + self.width(width) - 42.0;
        let previous = config.clone();
        let effect = match index {
            0..=6 => {
                let title = TITLES[index];
                if config.sections.iter().any(|s| s == title) {
                    if config.sections.len() == 1 {
                        self.status = "Keep at least one section visible".into();
                        return Some(Effect::Changed);
                    }
                    config.sections.retain(|s| s != title);
                } else {
                    config.sections.push(title.into());
                }
                Effect::Changed
            }
            7 => {
                config.graphs = !config.graphs;
                Effect::Changed
            }
            8 => {
                config.opacity = (config.opacity + if plus { 0.05 } else { -0.05 }).clamp(0.0, 1.0);
                Effect::Changed
            }
            9 => {
                config.font_size =
                    (config.font_size + if plus { 1.0 } else { -1.0 }).clamp(10.0, 17.0);
                Effect::Changed
            }
            10 => {
                config.interval_ms = if plus {
                    (config.interval_ms + 500).min(60000)
                } else {
                    config.interval_ms.saturating_sub(500).max(500)
                };
                Effect::Changed
            }
            11 => {
                config.process_interval_secs = if plus {
                    (config.process_interval_secs + 1).min(3600)
                } else {
                    config.process_interval_secs.saturating_sub(1).max(1)
                };
                Effect::Changed
            }
            12 => {
                config.slow_interval_secs = if plus {
                    (config.slow_interval_secs + 5).min(3600)
                } else {
                    config.slow_interval_secs.saturating_sub(5).max(5)
                };
                Effect::Changed
            }
            13 => {
                config.history = if plus {
                    (config.history + 10).min(300)
                } else {
                    config.history.saturating_sub(10).max(10)
                };
                Effect::Changed
            }
            14 => {
                let colors = [
                    "#67e8c1", "#86a6ff", "#ff6b9d", "#ffd45c", "#e27fff", "#54e3da",
                ];
                let index = colors.iter().position(|s| *s == config.accent).unwrap_or(0);
                config.accent = colors[(index + 1) % colors.len()].into();
                Effect::Changed
            }
            15 => {
                config.mode = match config.mode.as_str() {
                    "auto" => "window",
                    "window" => "overlay",
                    _ => "auto",
                }
                .into();
                Effect::Restart
            }
            16 => {
                config.enabled = true;
                config.workspace_overrides.clear();
                config.workspaces.clear();
                Effect::Visibility
            }
            17 => {
                config.enabled = false;
                config.workspace_overrides.clear();
                Effect::Visibility
            }
            18 => {
                let defaults = Config::default();
                config.width = defaults.width;
                config.height = defaults.height;
                config.x = defaults.x;
                config.y = defaults.y;
                Effect::Resize
            }
            19 => {
                self.open = false;
                return Some(Effect::Close);
            }
            20 => return Some(Effect::Quit),
            _ => return Some(Effect::Close),
        };
        match config.save() {
            Ok(()) => {
                self.status = if effect == Effect::Restart {
                    "Saved. Restart to change display mode."
                } else {
                    "Saved"
                }
                .into()
            }
            Err(error) => {
                *config = previous;
                self.status = format!("Save failed: {error}");
                return Some(Effect::Changed);
            }
        }
        Some(effect)
    }
}

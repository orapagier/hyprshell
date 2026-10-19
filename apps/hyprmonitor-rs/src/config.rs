use serde::{Deserialize, Serialize};
use std::{collections::BTreeMap, fs, io::Write, os::unix::fs::OpenOptionsExt, path::PathBuf};

#[derive(Clone, Debug, Deserialize, Serialize)]
#[serde(default, deny_unknown_fields)]
pub struct Config {
    pub mode: String,
    pub enabled: bool,
    pub workspace_overrides: BTreeMap<String, bool>,
    pub x: f64,
    pub y: f64,
    pub sections: Vec<String>,
    pub graphs: bool,
    #[serde(skip)]
    pub source_path: Option<PathBuf>,
    pub interval_ms: u64,
    pub slow_interval_secs: u64,
    pub process_interval_secs: u64,
    pub history: usize,
    pub width: u32,
    pub height: u32,
    pub margin_x: i32,
    pub margin_y: i32,
    pub anchor: String,
    pub opacity: f32,
    pub accent: String,
    pub click_through: bool,
    pub font_size: f32,
    pub font: Option<PathBuf>,
    pub output: Option<String>,
    pub interfaces: Vec<String>,
    pub workspaces: Vec<String>,
}

impl Default for Config {
    fn default() -> Self {
        Self {
            mode: "auto".into(),
            enabled: true,
            workspace_overrides: BTreeMap::new(),
            x: 1.0,
            y: 0.08,
            sections: vec![
                "SYSTEM".into(),
                "PROCESSOR".into(),
                "GRAPHICS & COOLING".into(),
                "MEMORY".into(),
                "STORAGE".into(),
                "NETWORK".into(),
                "POWER".into(),
            ],
            graphs: true,
            source_path: None,
            interval_ms: 2000,
            slow_interval_secs: 30,
            process_interval_secs: 6,
            history: 60,
            width: 1000,
            height: 1000,
            margin_x: 24,
            margin_y: 56,
            anchor: "top-right".into(),
            opacity: 0.72,
            accent: "#67e8c1".into(),
            click_through: false,
            font_size: 13.0,
            font: None,
            output: None,
            interfaces: vec![],
            workspaces: vec![],
        }
    }
}

impl Config {
    pub fn load(path: Option<PathBuf>) -> Result<Self, String> {
        let explicit = path.is_some();
        let path = path.unwrap_or_else(Self::path);
        let mut config: Self = match fs::read_to_string(&path) {
            Ok(text) => toml::from_str(&text).map_err(|e| format!("{}: {e}", path.display()))?,
            Err(e) if !explicit && e.kind() == std::io::ErrorKind::NotFound => {
                Self::import_legacy()
            }
            Err(e) => return Err(format!("{}: {e}", path.display())),
        };
        config.validate()?;
        config.source_path = Some(path);
        Ok(config)
    }

    pub fn path() -> PathBuf {
        std::env::var_os("XDG_CONFIG_HOME")
            .map(PathBuf::from)
            .unwrap_or_else(|| {
                PathBuf::from(std::env::var_os("HOME").unwrap_or_default()).join(".config")
            })
            .join("hyprmonitor/config.toml")
    }

    pub fn validate(&self) -> Result<(), String> {
        if !["auto", "overlay", "window"].contains(&self.mode.as_str()) {
            return Err("mode must be auto, overlay, or window".into());
        }
        if !self.x.is_finite()
            || !self.y.is_finite()
            || !(0.0..=1.0).contains(&self.x)
            || !(0.0..=1.0).contains(&self.y)
        {
            return Err("position must be within 0–1".into());
        }
        if self.workspace_overrides.iter().any(|(key, _)| {
            key.parse::<u32>()
                .map_or(true, |n| !(1..=99).contains(&n) || n.to_string() != *key)
        }) {
            return Err("workspace overrides must use numbers 1–99".into());
        }
        let allowed = [
            "SYSTEM",
            "PROCESSOR",
            "GRAPHICS & COOLING",
            "MEMORY",
            "STORAGE",
            "NETWORK",
            "POWER",
        ];
        if self.sections.is_empty()
            || self.sections.len() > 7
            || self.sections.iter().any(|s| !allowed.contains(&s.as_str()))
            || self
                .sections
                .iter()
                .collect::<std::collections::BTreeSet<_>>()
                .len()
                != self.sections.len()
        {
            return Err("Choose one or more distinct monitor sections".into());
        }
        if !(500..=60000).contains(&self.interval_ms) {
            return Err("interval_ms must be 500–60000".into());
        }
        if !(5..=3600).contains(&self.slow_interval_secs) {
            return Err("slow_interval_secs must be 5–3600".into());
        }
        if !(1..=3600).contains(&self.process_interval_secs) {
            return Err("process_interval_secs must be 1–3600".into());
        }
        if !(10..=300).contains(&self.history) {
            return Err("history must be 10–300".into());
        }
        if !(240..=3840).contains(&self.width) || !(420..=2160).contains(&self.height) {
            return Err("width must be 240–3840; height 420–2160".into());
        }
        if !["top-left", "top-right", "bottom-left", "bottom-right"].contains(&self.anchor.as_str())
        {
            return Err("invalid anchor".into());
        }
        if !self.opacity.is_finite() || !(0.0..=1.0).contains(&self.opacity) {
            return Err("opacity must be 0–1".into());
        }
        if !self.font_size.is_finite() || !(10.0..=17.0).contains(&self.font_size) {
            return Err("font_size must be 10–17".into());
        }
        if self.margin_x < 0 || self.margin_y < 0 || self.margin_x > 4096 || self.margin_y > 4096 {
            return Err("margins must be 0–4096".into());
        }
        if self.accent.len() != 7
            || !self.accent.starts_with('#')
            || u32::from_str_radix(&self.accent[1..], 16).is_err()
        {
            return Err("accent must be #RRGGBB".into());
        }
        Ok(())
    }

    pub fn visible_on(&self, workspace: Option<&str>) -> bool {
        let default = workspace
            .and_then(|w| self.workspace_overrides.get(w))
            .copied()
            .unwrap_or(self.enabled);
        default
            && (self.workspaces.is_empty()
                || workspace.is_none_or(|w| self.workspaces.iter().any(|s| s == w)))
    }

    pub fn save(&self) -> Result<(), String> {
        self.validate()?;
        let path = self.source_path.clone().unwrap_or_else(Self::path);
        let parent = path
            .parent()
            .ok_or("Configuration needs a parent directory")?;
        fs::create_dir_all(parent).map_err(|e| e.to_string())?;
        let name = format!(
            ".hyprmonitor-{}-{}.tmp",
            std::process::id(),
            std::time::SystemTime::now()
                .duration_since(std::time::UNIX_EPOCH)
                .unwrap_or_default()
                .as_nanos()
        );
        let temp = parent.join(name);
        let result = (|| {
            let mut file = fs::OpenOptions::new()
                .write(true)
                .create_new(true)
                .mode(0o600)
                .open(&temp)
                .map_err(|e| e.to_string())?;
            file.write_all(
                toml::to_string_pretty(self)
                    .map_err(|e| e.to_string())?
                    .as_bytes(),
            )
            .map_err(|e| e.to_string())?;
            file.sync_all().map_err(|e| e.to_string())?;
            fs::rename(&temp, &path).map_err(|e| e.to_string())?;
            fs::File::open(parent)
                .and_then(|f| f.sync_all())
                .map_err(|e| e.to_string())
        })();
        if result.is_err() {
            let _ = fs::remove_file(temp);
        }
        result
    }

    fn import_legacy() -> Self {
        let mut config = Self::default();
        let path = Self::path()
            .parent()
            .unwrap()
            .parent()
            .unwrap()
            .join("hyprshell/settings.json");
        let old: serde_json::Value =
            serde_json::from_str(&fs::read_to_string(path).unwrap_or_default()).unwrap_or_default();
        let monitor = &old["systemMonitor"];
        if let Some(enabled) = monitor["enabled"].as_bool() {
            config.enabled = enabled;
        }
        if let Some(v) = monitor["x"].as_f64() {
            config.x = v;
        }
        if let Some(v) = monitor["y"].as_f64() {
            config.y = v;
        }
        if let Some(v) = monitor["width"].as_u64() {
            config.width = v.min(u32::MAX as u64) as u32;
        }
        if let Some(v) = monitor["height"].as_u64() {
            config.height = v.min(u32::MAX as u64) as u32;
        }
        if let Some(v) = monitor["transparency"].as_f64() {
            config.opacity = 0.72 * (1.0 - v as f32 / 100.0);
        }
        if let Some(overrides) = monitor["workspaceOverrides"].as_object() {
            for (w, v) in overrides {
                if let Some(b) = v.as_bool() {
                    config.workspace_overrides.insert(w.clone(), b);
                }
            }
        }
        if config.validate().is_err() {
            Self::default()
        } else {
            config
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn defaults_are_valid() {
        Config::default().validate().unwrap();
    }
    #[test]
    fn rejects_unbounded_work() {
        for text in [
            "interval_ms = 0",
            "history = 999999",
            "width = 99999",
            "opacity = nan",
            "accent = '🦀🦀'",
            "anchor = 'center'",
            "unknown = 1",
        ] {
            assert!(
                toml::from_str::<Config>(text)
                    .and_then(|c| c.validate().map_err(serde::de::Error::custom))
                    .is_err(),
                "{text}"
            );
        }
    }
    #[test]
    fn example_is_valid() {
        toml::from_str::<Config>(include_str!("../hyprmonitor.example.toml"))
            .unwrap()
            .validate()
            .unwrap();
    }
    #[test]
    fn own_settings_save_atomically_and_keep_source_path() {
        let directory = std::env::temp_dir().join(format!(
            "hyprmonitor-settings-{}-{}",
            std::process::id(),
            std::time::SystemTime::now()
                .duration_since(std::time::UNIX_EPOCH)
                .unwrap()
                .as_nanos()
        ));
        let path = directory.join("config.toml");
        let mut config = Config {
            source_path: Some(path.clone()),
            opacity: 0.35,
            graphs: false,
            ..Config::default()
        };
        config.workspace_overrides.insert("2".into(), false);
        config.save().unwrap();
        let saved = Config::load(Some(path.clone())).unwrap();
        assert!(!saved.graphs);
        assert_eq!(saved.opacity, 0.35);
        assert_eq!(saved.source_path, Some(path.clone()));
        assert!(!saved.visible_on(Some("2")));
        let before = fs::read(&path).unwrap();
        config.sections.clear();
        assert!(config.save().is_err());
        assert_eq!(fs::read(&path).unwrap(), before);
        fs::remove_dir_all(directory).unwrap();
    }
}

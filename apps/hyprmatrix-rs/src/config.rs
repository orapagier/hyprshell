use serde::{Deserialize, Serialize};
use std::{collections::BTreeMap, fs, path::PathBuf};

#[derive(Clone, Debug, Serialize, Deserialize)]
#[serde(default, deny_unknown_fields)]
pub struct Config {
    pub fullscreen: bool,
    pub width: u32,
    pub height: u32,
    /// Position within the available desktop space, 0..1.
    pub x: f32,
    pub y: f32,
    pub output: Option<String>,
    pub opacity: f32,
    pub background: f32,
    pub density: f32,
    pub speed: f32,
    pub font_size: u32,
    pub fps: u32,
    pub theme: String,
    pub font: Option<PathBuf>,
    /// Per-workspace visibility; absent workspaces stay hidden.
    pub workspace_overrides: BTreeMap<String, bool>,
}
impl Default for Config {
    fn default() -> Self {
        Self {
            fullscreen: true,
            width: 640,
            height: 520,
            x: 1.0,
            y: 0.5,
            output: None,
            opacity: 0.70,
            background: 0.0,
            density: 0.55,
            speed: 9.0,
            font_size: 16,
            fps: 20,
            theme: "wallpaper".into(),
            font: None,
            workspace_overrides: BTreeMap::new(),
        }
    }
}
impl Config {
    pub fn path() -> PathBuf {
        std::env::var_os("XDG_CONFIG_HOME")
            .map(PathBuf::from)
            .unwrap_or_else(|| {
                PathBuf::from(std::env::var_os("HOME").unwrap_or_default()).join(".config")
            })
            .join("hyprmatrix/config.toml")
    }
    pub fn load() -> Result<Self, String> {
        let config = match fs::read_to_string(Self::path()) {
            Ok(text) => toml::from_str(&text).map_err(|e| format!("Invalid config: {e}"))?,
            Err(e) if e.kind() == std::io::ErrorKind::NotFound => Self::default(),
            Err(e) => return Err(e.to_string()),
        };
        Self::validate(&config)?;
        Ok(config)
    }
    pub fn validate(&self) -> Result<(), String> {
        if !(360..=7680).contains(&self.width)
            || !(460..=4320).contains(&self.height)
            || !(5..=60).contains(&self.fps)
            || !(10..=32).contains(&self.font_size)
            || ![self.x, self.y, self.opacity, self.background, self.density]
                .iter()
                .all(|v| v.is_finite() && (0.0..=1.0).contains(v))
            || !self.speed.is_finite()
            || !(1.0..=30.0).contains(&self.speed)
            || !["wallpaper", "matrix", "cyan", "amber"].contains(&self.theme.as_str())
        {
            return Err("Settings outside supported bounds; see docs/hyprmatrix.md".into());
        }
        if self
            .workspace_overrides
            .keys()
            .any(|key| {
                key.parse::<u64>()
                    .map(|n| !(1..=99).contains(&n))
                    .unwrap_or(true)
            })
        {
            return Err("workspace overrides must use numbers 1–99".into());
        }
        Ok(())
    }
    pub fn save(&self) -> Result<(), String> {
        self.validate()?;
        let path = Self::path();
        fs::create_dir_all(path.parent().unwrap()).map_err(|e| e.to_string())?;
        let tmp = path.with_extension(format!("toml.{}.tmp", std::process::id()));
        fs::write(
            &tmp,
            toml::to_string_pretty(self).map_err(|e| e.to_string())?,
        )
        .map_err(|e| e.to_string())?;
        fs::rename(&tmp, &path).map_err(|e| e.to_string())
    }
    pub fn color(&self, wallpaper: [u8; 3]) -> [u8; 3] {
        match self.theme.as_str() {
            "matrix" => [65, 240, 115],
            "cyan" => [55, 220, 245],
            "amber" => [250, 180, 65],
            _ => wallpaper,
        }
    }
    /// Rain is opt-in per workspace; unknown or None workspaces stay hidden.
    pub fn visible_on(&self, workspace: Option<&str>) -> bool {
        workspace
            .and_then(|w| self.workspace_overrides.get(w))
            .copied()
            .unwrap_or(false)
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn reject_bad_config_before_allocating() {
        let mut c = Config {
            width: u32::MAX,
            ..Config::default()
        };
        assert!(c.validate().is_err());
        c = Config {
            opacity: f32::NAN,
            ..Config::default()
        };
        assert!(c.validate().is_err());
        assert!(toml::from_str::<Config>("opactiy = 0.5").is_err());
        assert!(Config::default().validate().is_ok());
    }
    #[test]
    fn workspace_visibility_is_opt_in_and_bounded() {
        let mut c = Config::default();
        assert!(!c.visible_on(None));
        assert!(!c.visible_on(Some("1")));
        c.workspace_overrides.insert("1".into(), true);
        assert!(c.visible_on(Some("1")));
        assert!(!c.visible_on(Some("2")));
        assert!(c.validate().is_ok());
        c.workspace_overrides.insert("named".into(), true);
        assert!(c.validate().is_err());
        c.workspace_overrides.clear();
        c.workspace_overrides.insert("0".into(), true);
        assert!(c.validate().is_err());
        c.workspace_overrides.clear();
        c.workspace_overrides.insert("100".into(), true);
        assert!(c.validate().is_err());
    }
    #[test]
    fn legacy_configs_without_overrides_parse() {
        let c: Config = toml::from_str("fullscreen = false\nfps = 15\n").unwrap();
        assert!(!c.fullscreen);
        assert_eq!(c.fps, 15);
        assert!(c.workspace_overrides.is_empty());
        assert!(c.validate().is_ok());
    }
}

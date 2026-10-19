//! Desktop information owned by the Rust application. No shell/controller protocol.
use serde::Serialize;
#[derive(Clone, Debug, Default, Serialize)]
pub struct Display {
    pub name: String,
    pub width: u32,
    pub height: u32,
    pub refresh_rate: Option<f64>,
    pub scale: Option<f64>,
}
#[derive(Clone, Debug, Serialize)]
pub struct DesktopContext {
    pub x: f64,
    pub y: f64,
    pub width: u32,
    pub height: u32,
    pub screen_width: u32,
    pub screen_height: u32,
    pub output: String,
    pub colors: Vec<String>,
    pub transparency: f32,
    pub displays: Vec<Display>,
    pub connection: String,
    pub bluetooth: String,
    pub wifi_signal: Option<f64>,
}
impl Default for DesktopContext {
    fn default() -> Self {
        Self {
            x: 1.0,
            y: 0.08,
            width: 1000,
            height: 1000,
            screen_width: 1920,
            screen_height: 1080,
            output: String::new(),
            colors: vec![],
            transparency: 0.0,
            displays: vec![],
            connection: "Unavailable".into(),
            bluetooth: "Unavailable".into(),
            wifi_signal: None,
        }
    }
}

use serde::{Deserialize, Serialize};
use serde_json::{json, Value};
use std::{
    env, fs,
    io::{self, Write},
    path::{Path, PathBuf},
    process::Command,
    time::{SystemTime, UNIX_EPOCH},
};

const TTL: u64 = 900;

#[derive(Clone, Debug, Deserialize, Serialize, PartialEq)]
struct Location {
    name: String,
    latitude: f64,
    longitude: f64,
}

impl Location {
    fn validate(&self) -> Result<(), String> {
        if self.name.trim().is_empty()
            || self.name.len() > 240
            || !self.latitude.is_finite()
            || !self.longitude.is_finite()
            || !(-90.0..=90.0).contains(&self.latitude)
            || !(-180.0..=180.0).contains(&self.longitude)
        {
            return Err("Enter a location name and valid latitude/longitude".into());
        }
        Ok(())
    }
}

fn root(variable: &str, fallback: &str) -> PathBuf {
    env::var_os(variable)
        .filter(|v| !v.is_empty())
        .map(PathBuf::from)
        .unwrap_or_else(|| PathBuf::from(env::var_os("HOME").unwrap_or_default()).join(fallback))
}
fn config_path() -> PathBuf {
    root("XDG_CONFIG_HOME", ".config").join("hyprshell/weather.json")
}
fn state_path() -> PathBuf {
    root("XDG_STATE_HOME", ".local/state").join("hyprshell/weather")
}
fn now() -> u64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap_or_default()
        .as_secs()
}
fn emit(value: &Value) {
    println!("{value}");
    let _ = io::stdout().flush();
}
fn atomic_write(path: &Path, value: &Value) -> Result<(), String> {
    fs::create_dir_all(path.parent().ok_or("Invalid data path")?).map_err(|e| e.to_string())?;
    let temp = path.with_extension(format!("{}.tmp", std::process::id()));
    fs::write(&temp, value.to_string()).map_err(|e| e.to_string())?;
    fs::rename(&temp, path).map_err(|e| e.to_string())
}
fn read_location() -> Result<Option<Location>, String> {
    let path = config_path();
    if !path.exists() {
        return Ok(None);
    }
    let config: Value = serde_json::from_slice(&fs::read(path).map_err(|e| e.to_string())?)
        .map_err(|e| e.to_string())?;
    if config["version"] != 1 {
        return Err("Unsupported weather settings version".into());
    }
    if config["location"].is_null() {
        return Ok(None);
    }
    let location: Location =
        serde_json::from_value(config["location"].clone()).map_err(|e| e.to_string())?;
    location.validate()?;
    Ok(Some(location))
}
fn encode(input: &str) -> String {
    input
        .bytes()
        .map(|b| {
            if b.is_ascii_alphanumeric() || b"-._~".contains(&b) {
                (b as char).to_string()
            } else {
                format!("%{b:02X}")
            }
        })
        .collect()
}
fn request(url: &str) -> Result<Value, String> {
    // curl supplies the system TLS/certificate stack; there is no resident HTTP runtime.
    // Arguments never pass through a shell. Size and time are bounded.
    let output = Command::new("curl")
        .args([
            "--disable",
            "--fail",
            "--silent",
            "--show-error",
            "--proto",
            "=https",
            "--connect-timeout",
            "4",
            "--max-time",
            "10",
            "--max-filesize",
            "524288",
            url,
        ])
        .output()
        .map_err(|_| "Weather requires curl".to_string())?;
    if !output.status.success() {
        return Err("Could not reach weather service. Check your connection.".into());
    }
    let value: Value = serde_json::from_slice(&output.stdout)
        .map_err(|_| "Invalid response from weather service".to_string())?;
    if value["error"] == true {
        return Err("Weather service could not process this request".into());
    }
    Ok(value)
}
fn place_name(row: &Value) -> String {
    let name = row["name"].as_str().unwrap_or_default();
    if row["country_code"] != "PH" {
        return name.into();
    }
    let bare_name = |text: &str| {
        let text = text.trim().to_lowercase();
        text.strip_prefix("city of ")
            .or_else(|| text.strip_prefix("municipality of "))
            .or_else(|| text.strip_suffix(" city"))
            .unwrap_or(&text)
            .to_string()
    };
    // GeoNames' populated-place codes also cover municipal seats. Use the
    // matching administrative name instead of treating every seat as a city.
    for field in ["name", "admin3", "admin2"] {
        if let Some(admin) = row[field].as_str() {
            let lower = admin.to_lowercase();
            if (lower.starts_with("city of ") || lower.ends_with(" city"))
                && bare_name(admin) == bare_name(name)
            {
                let name = name.strip_prefix("City of ").unwrap_or(name);
                return if name.to_lowercase().ends_with(" city") {
                    name.into()
                } else {
                    format!("{name} City")
                };
            }
        }
    }
    name.strip_prefix("Municipality of ").unwrap_or(name).into()
}
fn search(query: &str, country: &str) -> Result<Value, String> {
    if query.trim().chars().count() < 2 {
        return Err("Enter at least two characters".into());
    }
    if !country.is_empty()
        && (country.len() != 2 || !country.bytes().all(|b| b.is_ascii_alphabetic()))
    {
        return Err("Use a two-letter country code or leave it empty".into());
    }
    let url = format!("https://geocoding-api.open-meteo.com/v1/search?name={}&count=20&language=en&format=json&countryCode={}", encode(query.trim()), encode(country));
    let response = request(&url)?;
    let locations: Vec<Value> = response["results"]
        .as_array()
        .into_iter()
        .flatten()
        .filter_map(|row| {
            let mut names = vec![place_name(row)];
            for field in ["admin2", "admin1", "country"] {
                if let Some(text) = row[field].as_str().filter(|s| !s.is_empty()) {
                    if !names.iter().any(|name| name == text) {
                        names.push(text.to_string());
                    }
                }
            }
            let location = Location {
                name: names.join(", "),
                latitude: row["latitude"].as_f64()?,
                longitude: row["longitude"].as_f64()?,
            };
            location.validate().ok()?;
            serde_json::to_value(location).ok()
        })
        .collect();
    Ok(json!({"results": locations}))
}
fn fresh(timestamp: u64, current: u64) -> bool {
    timestamp <= current && current - timestamp < TTL
}
fn cache_path(location: &Location) -> PathBuf {
    state_path().join(format!(
        "{:016x}-{:016x}.json",
        location.latitude.to_bits(),
        location.longitude.to_bits()
    ))
}
fn snapshot(location: &Location, fetched: u64, weather: Value, stale: bool) -> Value {
    json!({"location":location,"fetchedAt":fetched,"stale":stale,"weather":weather})
}
fn forecast(location: &Location) -> Result<Value, String> {
    let url = format!("https://api.open-meteo.com/v1/forecast?latitude={}&longitude={}&current=temperature_2m,relative_humidity_2m,apparent_temperature,precipitation,weather_code,wind_speed_10m,wind_direction_10m,wind_gusts_10m&daily=temperature_2m_max,temperature_2m_min,precipitation_probability_max,sunrise,sunset&hourly=temperature_2m,precipitation_probability&timezone=auto&forecast_days=2", location.latitude, location.longitude);
    let result = request(&url)?;
    if !result["current"]["temperature_2m"].is_number() || !result["daily"].is_object() {
        return Err("Weather service returned incomplete data".into());
    }
    Ok(result)
}
fn weather() -> Result<(), String> {
    let Some(location) = read_location()? else {
        emit(&json!({"needsLocation":true}));
        return Ok(());
    };
    let path = cache_path(&location);
    let cache = fs::read(&path)
        .ok()
        .and_then(|bytes| serde_json::from_slice::<Value>(&bytes).ok())
        .filter(|v| {
            v["location"]["latitude"] == location.latitude
                && v["location"]["longitude"] == location.longitude
                && v["weather"]["current"]["temperature_2m"].is_number()
        });
    let mut cached_snapshot = None;
    if let Some(cache) = cache {
        if let Some(timestamp) = cache["fetchedAt"].as_u64() {
            let is_fresh = fresh(timestamp, now()) && cache["weather"]["hourly"].is_object();
            let value = snapshot(&location, timestamp, cache["weather"].clone(), !is_fresh);
            emit(&value);
            if is_fresh {
                return Ok(());
            }
            cached_snapshot = Some(value);
        }
    }
    match forecast(&location) {
        Ok(data) => {
            let value = snapshot(&location, now(), data, false);
            let mut displayed = value.clone();
            if atomic_write(&path, &value).is_err() {
                displayed["warning"] = json!("Weather loaded; cache could not be saved");
            }
            emit(&displayed);
        }
        Err(error) => {
            let mut value = cached_snapshot.unwrap_or_else(|| json!({"location":location}));
            value["error"] = json!(error);
            emit(&value);
        }
    }
    Ok(())
}
fn run() -> Result<(), String> {
    let args: Vec<String> = env::args().skip(1).collect();
    match args.first().map(String::as_str).unwrap_or("weather") {
        "weather" => weather(),
        "search" => {
            emit(&search(
                args.get(1).ok_or("Enter a city")?,
                args.get(2).map(String::as_str).unwrap_or("PH"),
            )?);
            Ok(())
        }
        "select" => {
            let location: Location = serde_json::from_str(args.get(1).ok_or("Choose a location")?)
                .map_err(|_| "Invalid location".to_string())?;
            location.validate()?;
            atomic_write(&config_path(), &json!({"version":1,"location":location}))?;
            emit(&json!({"saved":true,"location":location}));
            Ok(())
        }
        _ => Err("Unknown weather command".into()),
    }
}
fn main() {
    if let Err(error) = run() {
        emit(&json!({"error":error}));
        std::process::exit(1);
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn cache_expiry_and_clock_changes() {
        assert!(fresh(100, 999));
        assert!(!fresh(100, 1000));
        assert!(!fresh(1001, 1000));
    }
    #[test]
    fn coordinates_and_names_are_validated() {
        let mut location = Location {
            name: "Miagao, Iloilo, Philippines".into(),
            latitude: 10.64,
            longitude: 122.23,
        };
        assert!(location.validate().is_ok());
        location.latitude = 91.;
        assert!(location.validate().is_err());
        location.latitude = f64::NAN;
        assert!(location.validate().is_err());
    }
    #[test]
    fn search_is_url_encoded() {
        assert_eq!(encode("Santo Niño &"), "Santo%20Ni%C3%B1o%20%26");
    }
    #[test]
    fn philippine_city_names_use_matching_administrative_names() {
        for admin in ["Butuan City", "City of Butuan"] {
            assert_eq!(
                place_name(&json!({"name":"Butuan", "country_code":"PH",
                "admin3":admin})),
                "Butuan City"
            );
        }
        for name in ["Butuan City", "City of Butuan"] {
            assert_eq!(
                place_name(&json!({"name":name, "country_code":"PH"})),
                "Butuan City"
            );
        }
        assert_eq!(
            place_name(&json!({"name":"Buenavista", "country_code":"PH",
            "admin3":"Municipality of Buenavista", "feature_code":"PPLA3"})),
            "Buenavista"
        );
        assert_eq!(
            place_name(&json!({"name":"San Fernando", "country_code":"PH",
            "admin3":"Municipality of San Fernando"})),
            "San Fernando"
        );
        assert_eq!(
            place_name(&json!({"name":"Ampayon", "country_code":"PH",
            "admin3":"Butuan City"})),
            "Ampayon"
        );
        assert_eq!(
            place_name(&json!({"name":"New York", "country_code":"US",
            "admin3":"New York City"})),
            "New York"
        );
    }
}

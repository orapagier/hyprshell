//! Slow, read-only metadata. Optional probes have a deadline and never use a shell.
use crate::collect::{read, Snapshot};
use serde::Serialize;
use std::{
    collections::{BTreeMap, BTreeSet},
    fs,
    io::Read,
    path::{Path, PathBuf},
    process::{Command, Stdio},
    thread,
    time::{Duration, Instant, SystemTime, UNIX_EPOCH},
};

#[derive(Clone, Debug, Default, Serialize)]
pub struct Extra {
    pub install_epoch: Option<u64>,
    pub topology: String,
    pub addresses: BTreeMap<String, Vec<String>>,
    pub drives: Vec<Drive>,
    pub batteries: Vec<Capacity>,
    pub wifi: BTreeMap<String, Wifi>,
}
#[derive(Clone, Debug, Default, Serialize)]
pub struct Drive {
    pub name: String,
    pub temperature: Option<f64>,
    pub health: String,
}
#[derive(Clone, Debug, Default, Serialize)]
pub struct Capacity {
    pub name: String,
    pub energy_wh: Option<f64>,
    pub full: Option<f64>,
    pub design: Option<f64>,
    pub unit: String,
}
#[derive(Clone, Debug, Default, Serialize)]
pub struct Wifi {
    pub ssid: String,
    pub speed: Option<f64>,
    pub signal: Option<f64>,
}

fn entries(path: impl AsRef<Path>) -> Vec<PathBuf> {
    let mut p: Vec<_> = fs::read_dir(path)
        .into_iter()
        .flatten()
        .filter_map(Result::ok)
        .map(|e| e.path())
        .collect();
    p.sort();
    p
}
fn n(path: impl AsRef<Path>) -> Option<f64> {
    read(path).parse().ok().filter(|n: &f64| n.is_finite())
}
fn exists(command: &str) -> bool {
    std::env::var_os("PATH")
        .is_some_and(|paths| std::env::split_paths(&paths).any(|p| p.join(command).is_file()))
}

fn probe(command: &str, args: &[&str], timeout: Duration) -> Result<(bool, String), String> {
    let mut child = Command::new(command)
        .args(args)
        .stdin(Stdio::null())
        .stdout(Stdio::piped())
        .stderr(Stdio::null())
        .spawn()
        .map_err(|e| e.to_string())?;
    let stdout = child.stdout.take().ok_or("Probe output unavailable")?;
    let output = thread::spawn(move || {
        let mut bytes = Vec::new();
        let _ = stdout.take(65536).read_to_end(&mut bytes);
        String::from_utf8_lossy(&bytes).into_owned()
    });
    let start = Instant::now();
    let result = loop {
        match child.try_wait() {
            Ok(Some(status)) => break Ok(status.success()),
            Ok(None) if start.elapsed() < timeout => thread::sleep(Duration::from_millis(10)),
            Ok(None) => {
                let _ = child.kill();
                let _ = child.wait();
                break Err("Timed out".into());
            }
            Err(e) => {
                let _ = child.kill();
                let _ = child.wait();
                break Err(e.to_string());
            }
        }
    };
    let text = output.join().unwrap_or_default();
    result.map(|success| (success, text))
}

pub fn addresses() -> BTreeMap<String, Vec<String>> {
    let mut result: BTreeMap<String, Vec<String>> = BTreeMap::new();
    let mut list = std::ptr::null_mut();
    // SAFETY: getifaddrs initializes an owned linked list; it is read only until freeifaddrs below.
    unsafe {
        if libc::getifaddrs(&mut list) != 0 {
            return result;
        }
        let mut entry = list;
        while !entry.is_null() {
            let item = &*entry;
            if !item.ifa_addr.is_null() && !item.ifa_name.is_null() {
                let name = std::ffi::CStr::from_ptr(item.ifa_name)
                    .to_string_lossy()
                    .into_owned();
                let family = (*item.ifa_addr).sa_family as i32;
                let address = if family == libc::AF_INET {
                    let addr = &*(item.ifa_addr as *const libc::sockaddr_in);
                    Some(std::net::Ipv4Addr::from(addr.sin_addr.s_addr.to_ne_bytes()).to_string())
                } else if family == libc::AF_INET6 {
                    let addr = &*(item.ifa_addr as *const libc::sockaddr_in6);
                    Some(std::net::Ipv6Addr::from(addr.sin6_addr.s6_addr).to_string())
                } else {
                    None
                };
                if let Some(addr) = address {
                    result.entry(name).or_default().push(addr);
                }
            }
            entry = item.ifa_next;
        }
        libc::freeifaddrs(list);
    }
    result
}

pub fn enrich(data: &mut Snapshot, previous: &Extra, refresh_health: bool) {
    if let Some(status) = crate::session::query() {
        if let Some(connection) = status.connection {
            data.context.connection = connection;
        }
        if let Some(bluetooth) = status.bluetooth {
            data.context.bluetooth = bluetooth;
        }
        data.context.wifi_signal = status.strength;
    }
    data.extra.install_epoch = fs::metadata("/")
        .ok()
        .and_then(|m| m.created().ok())
        .and_then(|t| t.duration_since(UNIX_EPOCH).ok())
        .map(|d| d.as_secs());
    let mut cores = BTreeSet::new();
    for block in read("/proc/cpuinfo").split("\n\n") {
        let fields: BTreeMap<_, _> = block
            .lines()
            .filter_map(|l| l.split_once(':').map(|(a, b)| (a.trim(), b.trim())))
            .collect();
        if let Some(core) = fields.get("core id") {
            cores.insert((
                fields
                    .get("physical id")
                    .copied()
                    .unwrap_or("0")
                    .to_string(),
                core.to_string(),
            ));
        }
    }
    data.extra.topology = if cores.is_empty() {
        format!("{} logical CPUs", data.cores.len())
    } else {
        format!("{} cores · {} threads", cores.len(), data.cores.len())
    };
    data.extra.addresses = addresses();
    data.extra.drives.clear();
    let budget = Instant::now();
    let smart = exists("smartctl");
    for disk in entries("/sys/block")
        .into_iter()
        .filter(|p| p.join("device").exists())
    {
        let name = disk
            .file_name()
            .unwrap_or_default()
            .to_string_lossy()
            .into_owned();
        let mut drive = previous
            .drives
            .iter()
            .find(|d| d.name == name)
            .cloned()
            .unwrap_or(Drive {
                name: name.clone(),
                temperature: None,
                health: if smart {
                    "Waiting for health refresh".into()
                } else {
                    "Tool not installed: smartctl".into()
                },
            });
        for hw in entries(disk.join("device/hwmon")) {
            if let Some(t) = n(hw.join("temp1_input")) {
                drive.temperature = Some(t / 1000.0);
                break;
            }
        }
        if smart && refresh_health && budget.elapsed() < Duration::from_secs(2) {
            let dev = format!("/dev/{name}");
            drive.health = match probe(
                "smartctl",
                &["-j", "-n", "standby", "-H", "-A", &dev],
                Duration::from_millis(700),
            ) {
                Ok((success, text)) => {
                    let json: serde_json::Value = serde_json::from_str(&text).unwrap_or_default();
                    if let Some(temp) = json["temperature"]["current"].as_f64() {
                        drive.temperature = Some(temp);
                    }
                    if let Some(passed) = json["smart_status"]["passed"].as_bool() {
                        if passed {
                            "PASSED".into()
                        } else {
                            "FAILED — check drive".into()
                        }
                    } else if success {
                        "Health not exposed / standby".into()
                    } else {
                        "Unavailable / insufficient device access".into()
                    }
                }
                Err(error) => format!("Unavailable: {error}"),
            };
        }
        data.extra.drives.push(drive);
    }
    data.extra.batteries.clear();
    for battery in entries("/sys/class/power_supply") {
        if read(battery.join("type")) != "Battery" {
            continue;
        }
        let energy = n(battery.join("energy_full")).zip(n(battery.join("energy_full_design")));
        let charge = n(battery.join("charge_full")).zip(n(battery.join("charge_full_design")));
        let (full, design, unit) = if let Some((full, design)) = energy {
            (Some(full / 1e6), Some(design / 1e6), "Wh")
        } else if let Some((full, design)) = charge {
            (Some(full / 1000.0), Some(design / 1000.0), "mAh")
        } else {
            (None, None, "Wh")
        };
        data.extra.batteries.push(Capacity {
            name: battery
                .file_name()
                .unwrap_or_default()
                .to_string_lossy()
                .into_owned(),
            energy_wh: n(battery.join("energy_now")).map(|v| v / 1e6).or_else(|| {
                Some(n(battery.join("charge_now"))? * n(battery.join("voltage_now"))? / 1e12)
            }),
            full,
            design,
            unit: unit.into(),
        });
    }
    data.extra.wifi.clear();
    for iface in entries("/sys/class/net")
        .into_iter()
        .filter(|p| p.join("wireless").exists())
    {
        let name = iface
            .file_name()
            .unwrap_or_default()
            .to_string_lossy()
            .into_owned();
        if exists("iw") {
            if let Ok((true, text)) =
                probe("iw", &["dev", &name, "link"], Duration::from_millis(300))
            {
                data.extra.wifi.insert(name, parse_wifi(&text));
            }
        }
    }
    for gpu in &mut data.gpus {
        let card = gpu.name.split(" · ").last().unwrap_or("");
        let device = Path::new("/sys/class/drm").join(card).join("device");
        let vendor = read(device.join("vendor"));
        let id = read(device.join("device"));
        gpu.model = pci_name(vendor.trim_start_matches("0x"), id.trim_start_matches("0x"))
            .unwrap_or_else(|| gpu.name.clone());
        gpu.temperature = entries(device.join("hwmon"))
            .iter()
            .find_map(|p| n(p.join("temp1_input")))
            .map(|v| v / 1000.0);
    }
}

fn pci_name(vendor: &str, device: &str) -> Option<String> {
    let text = ["/usr/share/hwdata/pci.ids", "/usr/share/misc/pci.ids"]
        .iter()
        .find_map(|p| fs::read_to_string(p).ok())?;
    let mut found = false;
    for line in text.lines() {
        if !line.starts_with('\t') && !line.starts_with('#') && !line.trim().is_empty() {
            found = line.starts_with(&format!("{vendor}  "));
        }
        if found {
            if let Some(name) = line.strip_prefix(&format!("\t{device}  ")) {
                return Some(name.into());
            }
        }
    }
    None
}
fn parse_wifi(text: &str) -> Wifi {
    let mut wifi = Wifi::default();
    for line in text.lines().map(str::trim) {
        if let Some(ssid) = line.strip_prefix("SSID: ") {
            wifi.ssid = ssid.into();
        }
        if let Some(signal) = line.strip_prefix("signal: ") {
            wifi.signal = signal
                .split_whitespace()
                .next()
                .and_then(|s| s.parse().ok());
        }
        if let Some(speed) = line.strip_prefix("tx bitrate: ") {
            wifi.speed = speed.split_whitespace().next().and_then(|s| s.parse().ok());
        }
    }
    wifi
}
pub fn age(epoch: Option<u64>) -> String {
    epoch
        .and_then(|e| {
            SystemTime::now()
                .duration_since(UNIX_EPOCH)
                .ok()
                .map(|now| {
                    format!(
                        "~{} days (filesystem estimate)",
                        now.as_secs().saturating_sub(e) / 86400
                    )
                })
        })
        .unwrap_or_else(|| "Unknown".into())
}
#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn wifi_metadata_does_not_invent_a_rate() {
        let w = parse_wifi(
            "Connected\n\tSSID: Home network\n\tsignal: -41 dBm\n\ttx bitrate: 234.0 MBit/s",
        );
        assert_eq!(w.ssid, "Home network");
        assert_eq!(w.signal, Some(-41.0));
        assert_eq!(w.speed, Some(234.0));
        assert!(parse_wifi("Not connected").speed.is_none());
    }
}

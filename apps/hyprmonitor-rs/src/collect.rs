use crate::config::Config;
use serde::Serialize;
use std::{
    collections::{BTreeMap, HashMap, VecDeque},
    fs,
    path::{Path, PathBuf},
    time::Instant,
};

pub enum WorkerCommand {
    Visible(bool),
    Configure(Box<Config>),
}

#[derive(Clone, Default, Debug, Serialize)]
pub struct Snapshot {
    pub extra: crate::details::Extra,
    pub context: crate::context::DesktopContext,
    pub os: String,
    pub kernel: String,
    pub model: String,
    pub cpu_model: String,
    pub uptime: u64,
    pub cpu: Option<f64>,
    pub cores: Vec<Option<f64>>,
    pub frequency_mhz: Option<f64>,
    pub load: String,
    pub tasks: String,
    pub memory: Memory,
    pub cpu_pressure: Option<f64>,
    pub io_pressure: Option<f64>,
    pub pressure_some: Option<f64>,
    pub pressure_full: Option<f64>,
    pub networks: Vec<Network>,
    pub disks: Vec<Disk>,
    pub sensors: Vec<Sensor>,
    pub gpus: Vec<Gpu>,
    pub batteries: Vec<Battery>,
    pub processes: Vec<Process>,
    pub top_cpu: Vec<Process>,
    pub top_memory: Vec<Process>,
    pub cpu_history: VecDeque<f64>,
    pub memory_history: VecDeque<f64>,
    pub network_history: VecDeque<f64>,
    pub throttle_events: Option<u64>,
    pub new_throttle: bool,
    pub collection_us: u64,
    pub process_scan_us: u64,
}

#[derive(Clone, Default, Debug, Serialize)]
pub struct Memory {
    pub total: u64,
    pub used: u64,
    pub available: u64,
    pub cache: u64,
    pub swap_total: u64,
    pub swap_used: u64,
}
#[derive(Clone, Default, Debug, Serialize)]
pub struct Network {
    pub physical: bool,
    pub name: String,
    pub state: String,
    pub rx: Option<f64>,
    pub tx: Option<f64>,
    pub rx_total: u64,
    pub tx_total: u64,
    pub signal_dbm: Option<f64>,
    pub speed_mbps: Option<f64>,
}
#[derive(Clone, Default, Debug, Serialize)]
pub struct Disk {
    pub name: String,
    pub used: Option<u64>,
    pub total: Option<u64>,
    pub free: Option<u64>,
    pub read: Option<f64>,
    pub write: Option<f64>,
    pub busy: Option<f64>,
}
#[derive(Clone, Default, Debug, Serialize)]
pub struct Sensor {
    pub name: String,
    pub value: f64,
    pub unit: String,
}
#[derive(Clone, Default, Debug, Serialize)]
pub struct Gpu {
    pub model: String,
    pub temperature: Option<f64>,
    pub name: String,
    pub driver: String,
    pub busy: Option<f64>,
    pub clock_mhz: Option<f64>,
    pub memory_used: Option<u64>,
    pub memory_total: Option<u64>,
}
#[derive(Clone, Default, Debug, Serialize)]
pub struct Battery {
    pub name: String,
    pub status: String,
    pub percent: Option<f64>,
    pub watts: Option<f64>,
    pub health: Option<f64>,
    pub hours: Option<f64>,
    pub cycles: Option<u64>,
}
#[derive(Clone, Default, Debug, Serialize)]
pub struct Process {
    pub pid: u32,
    pub parent: u32,
    pub start_ticks: u64,
    pub state: String,
    pub threads: u32,
    pub read_rate: Option<f64>,
    pub write_rate: Option<f64>,
    pub name: String,
    pub cpu: Option<f64>,
    pub memory: u64,
}
#[derive(Clone, Copy, Default, Debug)]
struct Ticks {
    total: u64,
    idle: u64,
}
#[derive(Clone, Debug)]
struct ProcessStat {
    parent: u32,
    state: String,
    threads: u32,
    io: Option<(u64, u64)>,
    name: String,
    ticks: u64,
    start: u64,
    rss: u64,
}

pub struct Collector {
    config: Config,
    data: Snapshot,
    last: Instant,
    slow: Option<Instant>,
    health_at: Option<Instant>,
    processes_at: Option<Instant>,
    cpu: Vec<Ticks>,
    net: HashMap<String, (u64, u64)>,
    blocks: HashMap<String, (u64, u64, u64)>,
    processes: HashMap<u32, ProcessStat>,
    throttle: BTreeMap<String, u64>,
    ticks_per_second: f64,
    page_size: u64,
}

pub fn read(path: impl AsRef<Path>) -> String {
    fs::read_to_string(path)
        .unwrap_or_default()
        .trim()
        .to_owned()
}
fn number(path: impl AsRef<Path>) -> Option<f64> {
    read(path).parse().ok().filter(|n: &f64| n.is_finite())
}
fn dirs(path: impl AsRef<Path>) -> Vec<PathBuf> {
    let mut entries: Vec<_> = fs::read_dir(path)
        .into_iter()
        .flatten()
        .filter_map(Result::ok)
        .map(|e| e.path())
        .collect();
    entries.sort();
    entries
}
fn optional(s: String) -> String {
    if s.is_empty() {
        "Unavailable".into()
    } else {
        s
    }
}
fn os_name(text: &str) -> String {
    text.lines()
        .find_map(|line| line.strip_prefix("PRETTY_NAME="))
        .unwrap_or("Linux")
        .trim_matches('"')
        .into()
}
fn parse_memory(text: &str) -> Memory {
    let fields: HashMap<_, _> = text
        .lines()
        .filter_map(|l| {
            let (key, rest) = l.split_once(':')?;
            Some((
                key,
                rest.split_whitespace()
                    .next()?
                    .parse::<u64>()
                    .ok()?
                    .saturating_mul(1024),
            ))
        })
        .collect();
    let get = |name| fields.get(name).copied().unwrap_or(0);
    let total = get("MemTotal");
    let available = fields
        .get("MemAvailable")
        .copied()
        .unwrap_or_else(|| get("MemFree") + get("Buffers") + get("Cached"))
        .min(total);
    Memory {
        total,
        used: total.saturating_sub(available),
        available,
        cache: (get("Cached") + get("SReclaimable")).saturating_sub(get("Shmem")),
        swap_total: get("SwapTotal"),
        swap_used: get("SwapTotal").saturating_sub(get("SwapFree")),
    }
}
fn parse_cpu(text: &str) -> Vec<Ticks> {
    text.lines()
        .filter(|l| l.starts_with("cpu"))
        .filter_map(|line| {
            let values: Vec<u64> = line
                .split_whitespace()
                .skip(1)
                .take(8)
                .map(str::parse)
                .collect::<Result<_, _>>()
                .ok()?;
            if values.len() < 4 {
                return None;
            }
            Some(Ticks {
                total: values.iter().sum(),
                idle: values[3] + values.get(4).copied().unwrap_or(0),
            })
        })
        .collect()
}
fn cpu_percent(old: Ticks, new: Ticks) -> Option<f64> {
    let total = new.total.checked_sub(old.total)?;
    let idle = new.idle.checked_sub(old.idle)?;
    (total > 0).then(|| 100.0 * total.saturating_sub(idle) as f64 / total as f64)
}
fn delta(old: u64, new: u64, elapsed: f64) -> Option<f64> {
    if elapsed <= 0.0 {
        return None;
    }
    Some(new.checked_sub(old)? as f64 / elapsed)
}
fn process_io_rates(
    old: Option<&ProcessStat>,
    current: &ProcessStat,
    elapsed: Option<f64>,
) -> (Option<f64>, Option<f64>) {
    let rate = |write: bool| {
        let previous = old.filter(|old| old.start == current.start)?.io?;
        let current = current.io?;
        delta(
            if write { previous.1 } else { previous.0 },
            if write { current.1 } else { current.0 },
            elapsed?,
        )
    };
    (rate(false), rate(true))
}

fn parse_process_io(text: &str) -> Option<(u64, u64)> {
    let value = |key: &str| {
        text.lines()
            .find_map(|line| line.strip_prefix(key)?.trim().parse::<u64>().ok())
    };
    Some((value("read_bytes:")?, value("write_bytes:")?))
}

fn parse_process(text: &str) -> Option<ProcessStat> {
    let start = text.find('(')?;
    let end = text.rfind(')')?;
    let parts: Vec<_> = text.get(end + 1..)?.split_whitespace().collect();
    Some(ProcessStat {
        parent: parts.get(1)?.parse().ok()?,
        state: parts.first()?.to_string(),
        threads: parts.get(17)?.parse().ok()?,
        io: None,
        name: text
            .get(start + 1..end)?
            .chars()
            .filter(|c| !c.is_control())
            .take(64)
            .collect(),
        ticks: parts
            .get(11)?
            .parse::<u64>()
            .ok()?
            .saturating_add(parts.get(12)?.parse().ok()?),
        start: parts.get(19)?.parse().ok()?,
        rss: parts.get(21)?.parse::<i64>().ok()?.max(0) as u64,
    })
}
fn psi(text: &str, kind: &str) -> Option<f64> {
    text.lines()
        .find(|l| l.starts_with(kind))?
        .split_whitespace()
        .find_map(|s| s.strip_prefix("avg10="))?
        .parse()
        .ok()
}

impl Collector {
    pub fn new(config: Config) -> Self {
        let cpu_model = read("/proc/cpuinfo")
            .lines()
            .find_map(|l| {
                l.strip_prefix("model name")
                    .and_then(|s| s.split_once(':'))
                    .map(|(_, s)| s.trim().into())
            })
            .unwrap_or_else(|| "Processor".into());
        Self {
            config,
            data: Snapshot {
                os: os_name(&read("/etc/os-release")),
                kernel: read("/proc/sys/kernel/osrelease"),
                model: optional(read("/sys/class/dmi/id/product_name")),
                cpu_model,
                ..Snapshot::default()
            },
            last: Instant::now(),
            slow: None,
            health_at: None,
            processes_at: None,
            cpu: vec![],
            net: HashMap::new(),
            blocks: HashMap::new(),
            processes: HashMap::new(),
            throttle: BTreeMap::new(),
            ticks_per_second: rustix::param::clock_ticks_per_second() as f64,
            page_size: rustix::param::page_size() as u64,
        }
    }

    // Re-prime interval counters after hiding. Hidden time is not a CPU sample.
    pub fn configure(&mut self, config: Config) {
        self.config = config;
        for history in [
            &mut self.data.cpu_history,
            &mut self.data.memory_history,
            &mut self.data.network_history,
        ] {
            while history.len() > self.config.history {
                history.pop_front();
            }
        }
    }

    pub fn resume(&mut self) {
        self.cpu.clear();
        self.net.clear();
        self.blocks.clear();
        self.processes.clear();
        self.processes_at = None;
        self.slow = None;
        self.last = Instant::now();
    }

    pub fn sample(&mut self) -> Snapshot {
        let started = Instant::now();
        let elapsed = started.duration_since(self.last).as_secs_f64();
        let cpu = parse_cpu(&read("/proc/stat"));
        let percentages: Vec<_> = cpu
            .iter()
            .enumerate()
            .map(|(i, ticks)| self.cpu.get(i).and_then(|old| cpu_percent(*old, *ticks)))
            .collect();
        self.data.cpu = percentages.first().copied().flatten();
        self.data.cores = percentages.into_iter().skip(1).collect();
        self.cpu = cpu;
        self.data.uptime = read("/proc/uptime")
            .split_whitespace()
            .next()
            .and_then(|s| s.parse::<f64>().ok())
            .unwrap_or(0.0) as u64;
        self.data.memory = parse_memory(&read("/proc/meminfo"));
        self.data.cpu_pressure = psi(&read("/proc/pressure/cpu"), "some");
        self.data.io_pressure = psi(&read("/proc/pressure/io"), "some");
        self.data.pressure_some = psi(&read("/proc/pressure/memory"), "some");
        self.data.pressure_full = psi(&read("/proc/pressure/memory"), "full");
        let load = read("/proc/loadavg");
        let load: Vec<_> = load.split_whitespace().collect();
        self.data.load = load.iter().take(3).copied().collect::<Vec<_>>().join(" / ");
        self.data.tasks = load.get(3).unwrap_or(&"—").to_string();
        self.sample_network(elapsed);
        self.sample_disks(elapsed);
        if self
            .slow
            .is_none_or(|t| started.duration_since(t).as_secs() >= self.config.slow_interval_secs)
        {
            self.slow_metrics();
            let previous = self.data.extra.clone();
            let health = self
                .health_at
                .is_none_or(|t| started.duration_since(t).as_secs() >= 300);
            crate::details::enrich(&mut self.data, &previous, health);
            if health {
                self.health_at = Some(started);
            }
            self.slow = Some(started);
        }
        if self.processes_at.is_none_or(|t| {
            started.duration_since(t).as_secs() >= self.config.process_interval_secs
        }) {
            let scan = Instant::now();
            self.sample_processes(
                self.processes_at
                    .map(|t| started.duration_since(t).as_secs_f64()),
            );
            self.data.process_scan_us = scan.elapsed().as_micros() as u64;
            self.processes_at = Some(started);
        }
        let mut throttle = BTreeMap::new();
        for cpu in dirs("/sys/devices/system/cpu").into_iter().filter(|p| {
            p.file_name()
                .unwrap_or_default()
                .to_string_lossy()
                .strip_prefix("cpu")
                .is_some_and(|s| s.parse::<u32>().is_ok())
        }) {
            for name in ["core_throttle_count", "package_throttle_count"] {
                let path = cpu.join("thermal_throttle").join(name);
                if let Ok(n) = read(&path).parse::<u64>() {
                    throttle.insert(path.to_string_lossy().to_string(), n);
                }
            }
        }
        self.data.new_throttle = throttle
            .iter()
            .any(|(key, n)| self.throttle.get(key).is_some_and(|old| n > old));
        self.data.throttle_events = throttle.values().copied().max();
        self.throttle = throttle;
        let cpu = self.data.cpu;
        let memory = (self.data.memory.total > 0)
            .then(|| self.data.memory.used as f64 / self.data.memory.total as f64 * 100.0);
        let network = self
            .data
            .networks
            .iter()
            .filter(|n| n.physical || !self.config.interfaces.is_empty())
            .filter_map(|n| Some(n.rx? + n.tx?))
            .reduce(|a, b| a + b);
        for (history, value) in [
            (&mut self.data.cpu_history, cpu),
            (&mut self.data.memory_history, memory),
            (&mut self.data.network_history, network),
        ] {
            let Some(value) = value else {
                continue;
            };
            if history.len() >= self.config.history {
                history.pop_front();
            }
            history.push_back(value);
        }
        self.last = started;
        self.data.collection_us = started.elapsed().as_micros() as u64;
        self.data.clone()
    }

    fn sample_processes(&mut self, elapsed: Option<f64>) {
        let mut current = HashMap::new();
        let mut rows = vec![];
        for path in dirs("/proc") {
            let Some(pid) = path
                .file_name()
                .and_then(|s| s.to_str())
                .and_then(|s| s.parse::<u32>().ok())
            else {
                continue;
            };
            let Some(mut stat) = parse_process(&read(path.join("stat"))) else {
                continue;
            };
            stat.io = parse_process_io(&read(path.join("io")));
            let (read_rate, write_rate) =
                process_io_rates(self.processes.get(&pid), &stat, elapsed);
            let cpu = elapsed.and_then(|elapsed| {
                self.processes
                    .get(&pid)
                    .filter(|old| old.start == stat.start)
                    .and_then(|old| delta(old.ticks, stat.ticks, elapsed))
                    .map(|ticks| ticks * 100.0 / self.ticks_per_second)
            });
            rows.push(Process {
                pid,
                parent: stat.parent,
                start_ticks: stat.start,
                state: stat.state.clone(),
                threads: stat.threads,
                read_rate,
                write_rate,
                name: stat.name.clone(),
                cpu,
                memory: stat.rss.saturating_mul(self.page_size),
            });
            current.insert(pid, stat);
        }
        rows.sort_unstable_by(|a, b| b.memory.cmp(&a.memory).then(a.pid.cmp(&b.pid)));
        self.data.top_memory = rows.iter().take(5).cloned().collect();
        rows.sort_unstable_by(|a, b| {
            b.cpu
                .unwrap_or(0.0)
                .total_cmp(&a.cpu.unwrap_or(0.0))
                .then(a.pid.cmp(&b.pid))
        });
        self.data.top_cpu = rows.iter().take(5).cloned().collect();
        self.data.processes = rows;
        self.processes = current;
    }

    fn sample_network(&mut self, elapsed: f64) {
        let mut current = HashMap::new();
        let mut rows = vec![];
        let wireless = read("/proc/net/wireless");
        for line in read("/proc/net/dev").lines().skip(2) {
            let Some((name, values)) = line.split_once(':') else {
                continue;
            };
            let name = name.trim();
            if name == "lo" {
                continue;
            }
            if !self.config.interfaces.is_empty()
                && !self.config.interfaces.iter().any(|n| n == name)
            {
                continue;
            }
            let values: Vec<u64> = values
                .split_whitespace()
                .map(str::parse)
                .collect::<Result<_, _>>()
                .unwrap_or_default();
            if values.len() < 9 {
                continue;
            }
            let (rx, tx) = (values[0], values[8]);
            let old = self.net.get(name);
            let path = Path::new("/sys/class/net").join(name);
            let signal_dbm = wireless.lines().find_map(|l| {
                let (n, rest) = l.split_once(':')?;
                (n.trim() == name)
                    .then(|| {
                        rest.split_whitespace()
                            .nth(2)?
                            .trim_end_matches('.')
                            .parse()
                            .ok()
                    })
                    .flatten()
            });
            rows.push(Network {
                physical: path.join("device").exists(),
                name: name.into(),
                state: optional(read(path.join("operstate"))),
                rx_total: rx,
                tx_total: tx,
                rx: old.and_then(|o| delta(o.0, rx, elapsed)),
                tx: old.and_then(|o| delta(o.1, tx, elapsed)),
                signal_dbm,
                speed_mbps: number(path.join("speed")).filter(|n| *n > 0.0),
            });
            current.insert(name.into(), (rx, tx));
        }
        self.net = current;
        self.data.networks = rows;
    }

    fn sample_disks(&mut self, elapsed: f64) {
        let mut current = HashMap::new();
        self.data.disks.retain(|d| d.name.starts_with('/'));
        for line in read("/proc/diskstats").lines() {
            let parts: Vec<_> = line.split_whitespace().collect();
            if parts.len() < 14 {
                continue;
            }
            let name = parts[2];
            if !Path::new("/sys/block").join(name).join("device").exists() {
                continue;
            }
            let parse = |i: usize| parts[i].parse::<u64>().unwrap_or(0);
            let counters = (
                parse(5).saturating_mul(512),
                parse(9).saturating_mul(512),
                parse(12),
            );
            let old = self.blocks.get(name);
            self.data.disks.push(Disk {
                name: name.into(),
                read: old.and_then(|o| delta(o.0, counters.0, elapsed)),
                write: old.and_then(|o| delta(o.1, counters.1, elapsed)),
                busy: old
                    .and_then(|o| delta(o.2, counters.2, elapsed))
                    .map(|v| (v / 10.0).min(100.0)),
                ..Disk::default()
            });
            current.insert(name.into(), counters);
        }
        self.blocks = current;
    }

    fn slow_metrics(&mut self) {
        self.data.disks.retain(|d| !d.name.starts_with('/'));
        for path in [
            PathBuf::from("/"),
            std::env::var_os("HOME")
                .map(PathBuf::from)
                .unwrap_or_else(|| PathBuf::from("/home")),
        ] {
            let stat = rustix::fs::statvfs(&path).ok();
            self.data.disks.push(Disk {
                name: path.to_string_lossy().into(),
                total: stat.as_ref().map(|s| s.f_blocks.saturating_mul(s.f_frsize)),
                free: stat.as_ref().map(|s| s.f_bavail.saturating_mul(s.f_frsize)),
                used: stat.as_ref().map(|s| {
                    s.f_blocks
                        .saturating_sub(s.f_bfree)
                        .saturating_mul(s.f_frsize)
                }),
                ..Disk::default()
            });
        }
        self.data.sensors.clear();
        for hw in dirs("/sys/class/hwmon") {
            let chip = read(hw.join("name"));
            for path in dirs(&hw) {
                let filename = path.file_name().unwrap_or_default().to_string_lossy();
                if !filename.ends_with("_input") {
                    continue;
                }
                let (divisor, unit) = if filename.starts_with("temp") {
                    (1000.0, "°C")
                } else if filename.starts_with("fan") {
                    (1.0, "RPM")
                } else {
                    continue;
                };
                let Some(value) = number(&path) else {
                    continue;
                };
                let label = read(hw.join(filename.replace("_input", "_label")));
                self.data.sensors.push(Sensor {
                    name: format!(
                        "{} · {}",
                        chip,
                        if label.is_empty() {
                            filename.trim_end_matches("_input")
                        } else {
                            &label
                        }
                    ),
                    value: value / divisor,
                    unit: unit.into(),
                });
            }
        }
        let freq: Vec<_> = dirs("/sys/devices/system/cpu/cpufreq")
            .iter()
            .filter_map(|p| number(p.join("scaling_cur_freq")))
            .collect();
        self.data.frequency_mhz =
            (!freq.is_empty()).then(|| freq.iter().sum::<f64>() / freq.len() as f64 / 1000.0);
        self.data.gpus.clear();
        for card in dirs("/sys/class/drm").into_iter().filter(|p| {
            p.file_name()
                .unwrap_or_default()
                .to_string_lossy()
                .strip_prefix("card")
                .is_some_and(|s| s.parse::<u32>().is_ok())
        }) {
            let device = card.join("device");
            if !device.exists() {
                continue;
            }
            let driver = fs::read_link(device.join("driver"))
                .ok()
                .and_then(|p| p.file_name().map(|s| s.to_string_lossy().to_string()))
                .unwrap_or_else(|| "unknown".into());
            let vendor = match read(device.join("vendor")).as_str() {
                "0x8086" => "Intel",
                "0x1002" => "AMD",
                "0x10de" => "NVIDIA",
                _ => "GPU",
            };
            self.data.gpus.push(Gpu {
                model: String::new(),
                temperature: None,
                name: format!(
                    "{vendor} · {}",
                    card.file_name().unwrap_or_default().to_string_lossy()
                ),
                driver,
                busy: number(device.join("gpu_busy_percent")),
                clock_mhz: number(card.join("gt_cur_freq_mhz"))
                    .or_else(|| number(card.join("gt/gt0/rps_cur_freq_mhz"))),
                memory_used: number(device.join("mem_info_vram_used")).map(|n| n as u64),
                memory_total: number(device.join("mem_info_vram_total")).map(|n| n as u64),
            });
        }
        self.data.batteries.clear();
        for path in dirs("/sys/class/power_supply") {
            if read(path.join("type")) != "Battery" {
                continue;
            }
            let capacities = number(path.join("energy_full"))
                .zip(number(path.join("energy_full_design")))
                .or_else(|| {
                    number(path.join("charge_full")).zip(number(path.join("charge_full_design")))
                });
            let watts = number(path.join("power_now")).map(|n| n / 1e6).or_else(|| {
                Some(number(path.join("current_now"))? * number(path.join("voltage_now"))? / 1e12)
            });
            let status = optional(read(path.join("status")));
            let now = number(path.join("energy_now"));
            let hours = match status.as_str() {
                "Discharging" => now
                    .zip(watts)
                    .and_then(|(n, w)| (w > 0.1).then_some(n / 1e6 / w)),
                "Charging" => number(path.join("energy_full"))
                    .zip(now)
                    .zip(watts)
                    .and_then(|((f, n), w)| (w > 0.1).then_some((f - n).max(0.0) / 1e6 / w)),
                _ => None,
            };
            self.data.batteries.push(Battery {
                name: path
                    .file_name()
                    .unwrap_or_default()
                    .to_string_lossy()
                    .into(),
                status,
                percent: number(path.join("capacity")),
                watts,
                hours,
                health: capacities.and_then(|(f, d)| (d > 0.0).then_some(f / d * 100.0)),
                cycles: read(path.join("cycle_count")).parse().ok(),
            });
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn memory_counts_available_and_shared_cache() {
        let m = parse_memory("MemTotal: 1000 kB\nMemAvailable: 700 kB\nCached: 200 kB\nSReclaimable: 50 kB\nShmem: 60 kB\nSwapTotal: 100 kB\nSwapFree: 90 kB\n");
        assert_eq!(
            (m.used, m.cache, m.swap_used),
            (300 * 1024, 190 * 1024, 10 * 1024)
        );
        assert_eq!(parse_memory("").used, 0);
    }
    #[test]
    fn cpu_excludes_double_counted_guest_ticks() {
        let t = parse_cpu("cpu 10 0 10 80 0 0 0 0 10 0\ncpu0 10 0 10 80 0 0 0 0\n");
        assert_eq!(t[0].total, 100);
        assert_eq!(cpu_percent(Ticks::default(), t[0]), Some(20.0));
        assert_eq!(cpu_percent(t[0], t[0]), None);
    }
    #[test]
    fn counter_reset_is_unknown() {
        assert_eq!(delta(200, 100, 2.0), None);
        assert_eq!(delta(0, 100, 2.0), Some(50.0));
    }
    #[test]
    fn process_names_can_contain_spaces_and_parentheses() {
        let p = parse_process(
            "42 (a (strange) name) S 0 0 0 0 0 0 0 0 0 0 100 20 0 0 0 0 0 0 999 0 12",
        )
        .unwrap();
        assert_eq!(p.name, "a (strange) name");
        assert_eq!((p.ticks, p.start, p.rss), (120, 999, 12));
        assert!(parse_process("gone").is_none());
    }
    #[test]
    fn process_io_rates_reject_reused_pids_resets_and_missing_samples() {
        let mut old =
            parse_process("42 (worker) S 1 0 0 0 0 0 0 0 0 0 100 20 0 0 0 0 2 0 999 0 12").unwrap();
        old.io = Some((100, 200));
        let mut current = old.clone();
        current.io = Some((300, 600));
        assert_eq!(
            process_io_rates(Some(&old), &current, Some(2.0)),
            (Some(100.0), Some(200.0))
        );
        assert_eq!(process_io_rates(None, &current, Some(2.0)), (None, None));
        current.start += 1;
        assert_eq!(
            process_io_rates(Some(&old), &current, Some(2.0)),
            (None, None)
        );
        current.start = old.start;
        current.io = Some((0, 0));
        assert_eq!(
            process_io_rates(Some(&old), &current, Some(2.0)),
            (None, None)
        );
        current.io = None;
        assert_eq!(
            process_io_rates(Some(&old), &current, Some(2.0)),
            (None, None)
        );
        assert_eq!((old.parent, old.threads), (1, 2));
    }

    #[test]
    fn process_io_requires_actual_counters() {
        assert_eq!(parse_process_io(""), None);
        assert_eq!(
            parse_process_io("read_bytes: 0\nwrite_bytes: 0"),
            Some((0, 0))
        );
        assert_eq!(parse_process_io("read_bytes: 100"), None);
    }
    #[test]
    fn psi_is_not_memory_usage() {
        assert_eq!(psi("some avg10=1.23 avg60=0 total=100", "some"), Some(1.23));
    }
    #[test]
    fn history_is_bounded_and_first_cpu_sample_is_unknown() {
        let mut c = Collector::new(Config {
            history: 10,
            ..Config::default()
        });
        assert_eq!(c.sample().cpu, None);
        for _ in 0..12 {
            // The history limit must not depend on /proc/stat advancing between
            // rapid calls. Supply a known earlier aggregate counter each time.
            c.cpu = vec![Ticks::default()];
            assert!(c.sample().cpu.is_some());
        }
        assert_eq!(c.data.cpu_history.len(), 10);
        c.resume();
        assert_eq!(c.sample().cpu, None);
    }
}

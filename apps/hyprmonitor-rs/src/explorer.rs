//! Shared navigation and read-only process exploration, independent of window input.
use crate::collect::{Process, Snapshot};
use crate::render::{sections, Section};

pub const PAGES: [&str; 9] = [
    "Summary",
    "Processes",
    "CPU",
    "Memory",
    "Disks",
    "Network",
    "GPU & thermals",
    "Power",
    "System info",
];
// Column boundaries are shared by rendering and hit testing.
pub const COLUMNS: [(&str, f32, usize); 7] = [
    ("Name", 0.0, 3),
    ("PID", 0.30, 2),
    ("CPU", 0.40, 0),
    ("Memory", 0.51, 1),
    ("Threads", 0.65, 4),
    ("Read/s", 0.75, 5),
    ("Write/s", 0.875, 6),
];
pub const RAIL: f32 = 168.0;
pub const CONTENT: f32 = 188.0;
pub const TABLE_TOP: f32 = 158.0;
pub const ROW: f32 = 30.0;
pub fn visible_rows(height: f32) -> usize {
    ((height - TABLE_TOP - 84.0) / ROW).max(1.0) as usize
}
pub fn sort_at(fraction: f32) -> usize {
    COLUMNS
        .iter()
        .rev()
        .find(|(_, x, _)| fraction >= *x)
        .map(|c| c.2)
        .unwrap_or(3)
}
#[derive(Default)]
pub struct Explorer {
    pub selected: Option<(u32, u64)>,
    pub confirming: bool,
    pub status: String,
    pub sort: usize,
    pub ascending: bool,
    pub query: String,
    pub searching: bool,
    pub paused: bool,
}
impl Explorer {
    pub fn rows<'a>(&self, data: &'a Snapshot) -> Vec<&'a Process> {
        let query = self.query.to_lowercase();
        let mut rows: Vec<_> = data
            .processes
            .iter()
            .filter(|p| {
                query.is_empty()
                    || p.name.to_lowercase().contains(&query)
                    || p.pid.to_string().contains(&query)
            })
            .collect();
        rows.sort_by(|a, b| {
            // Unavailable samples remain last in either sort direction.
            let optional = |a: Option<f64>, b: Option<f64>| match (a, b) {
                (Some(a), Some(b)) => {
                    if self.ascending {
                        a.total_cmp(&b)
                    } else {
                        b.total_cmp(&a)
                    }
                }
                (Some(_), None) => std::cmp::Ordering::Less,
                (None, Some(_)) => std::cmp::Ordering::Greater,
                _ => std::cmp::Ordering::Equal,
            };
            let order = match self.sort {
                0 => return optional(a.cpu, b.cpu).then(a.pid.cmp(&b.pid)),
                1 => a.memory.cmp(&b.memory),
                2 => a.pid.cmp(&b.pid),
                3 => a.name.to_lowercase().cmp(&b.name.to_lowercase()),
                4 => a.threads.cmp(&b.threads),
                5 => return optional(a.read_rate, b.read_rate).then(a.pid.cmp(&b.pid)),
                _ => return optional(a.write_rate, b.write_rate).then(a.pid.cmp(&b.pid)),
            };
            (if self.ascending {
                order
            } else {
                order.reverse()
            })
            .then(a.pid.cmp(&b.pid))
        });
        rows
    }
    pub fn section(&self, data: &Snapshot, page: usize) -> Section {
        let index = match page {
            2 => 1,
            3 => 3,
            4 => 4,
            5 => 5,
            6 => 2,
            7 => 6,
            _ => 0,
        };
        sections(data).remove(index)
    }
}
#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn filters_and_sorts_all_processes_with_missing_last() {
        let data = Snapshot {
            processes: vec![
                Process {
                    pid: 12,
                    name: "Browser".into(),
                    cpu: None,
                    ..Default::default()
                },
                Process {
                    pid: 9,
                    name: "browser helper".into(),
                    cpu: Some(20.0),
                    ..Default::default()
                },
                Process {
                    pid: 4,
                    name: "shell".into(),
                    cpu: Some(0.0),
                    ..Default::default()
                },
            ],
            ..Default::default()
        };
        let mut view = Explorer::default();
        assert_eq!(
            view.rows(&data).iter().map(|p| p.pid).collect::<Vec<_>>(),
            [9, 4, 12]
        );
        view.ascending = true;
        assert_eq!(
            view.rows(&data).iter().map(|p| p.pid).collect::<Vec<_>>(),
            [4, 9, 12]
        );
        view.query = "BROWSER".into();
        assert_eq!(view.rows(&data).len(), 2);
        view.query = "12".into();
        assert_eq!(view.rows(&data)[0].pid, 12);
        view.query = "missing".into();
        assert!(view.rows(&data).is_empty());
    }
    #[test]
    fn grouped_navigation_retains_every_detail_section() {
        let data = Snapshot::default();
        let view = Explorer::default();
        let titles: Vec<_> = (2..9).map(|page| view.section(&data, page).title).collect();
        for section in sections(&data) {
            assert!(titles.contains(&section.title));
        }
    }
    #[test]
    fn columns_and_density_match_input() {
        assert_eq!(sort_at(0.2), 3);
        assert_eq!(sort_at(0.43), 0);
        assert_eq!(sort_at(0.99), 6);
        assert_eq!(visible_rows(720.0), 15);
    }
}

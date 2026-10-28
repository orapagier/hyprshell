//! Shared navigation and read-only process exploration, independent of window input.
use crate::collect::{Process, Snapshot};
use crate::render::{sections, Section};

pub const PAGES: [&str; 6] = [
    "Overview",
    "Processes",
    "Performance",
    "Storage",
    "Network",
    "System",
];
pub const PERFORMANCE: [&str; 4] = ["CPU", "Memory", "GPU / cooling", "Power"];
pub const SORTS: [&str; 7] = ["CPU", "Memory", "PID", "Name", "Threads", "Read", "Write"];
#[derive(Default)]
pub struct Explorer {
    pub performance: usize,
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
            2 => [1, 3, 2, 6][self.performance.min(3)],
            3 => 4,
            4 => 5,
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
        let mut view = Explorer::default();
        let mut titles = vec![];
        for part in 0..4 {
            view.performance = part;
            titles.push(view.section(&data, 2).title);
        }
        for page in 3..6 {
            titles.push(view.section(&data, page).title);
        }
        assert_eq!(titles.len(), 7);
        for section in sections(&data) {
            assert!(titles.contains(&section.title));
        }
    }
}

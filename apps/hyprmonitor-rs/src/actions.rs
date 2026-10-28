//! Bind actions to a kernel process handle and verify the sampled creation identity.
use std::{
    fs, io,
    os::fd::{AsRawFd, FromRawFd, OwnedFd},
};

fn start_time(stat: &str) -> Option<u64> {
    stat.rsplit_once(')')?
        .1
        .split_whitespace()
        .nth(19)?
        .parse()
        .ok()
}
pub fn end_task(pid: u32, expected_start: u64) -> Result<(), String> {
    if pid <= 1 || pid == std::process::id() || expected_start == 0 {
        return Err("This process cannot be ended here".into());
    }
    // Open before checking /proc: if the PID exits or is recycled after this
    // point, the pidfd still refers only to the original process.
    let fd = unsafe { libc::syscall(libc::SYS_pidfd_open, pid, 0u32) };
    if fd < 0 {
        return Err(format!(
            "Cannot open process: {}",
            io::Error::last_os_error()
        ));
    }
    let fd = unsafe { OwnedFd::from_raw_fd(fd as i32) };
    let stat = fs::read_to_string(format!("/proc/{pid}/stat"))
        .map_err(|e| format!("Process unavailable: {e}"))?;
    if start_time(&stat) != Some(expected_start) {
        return Err("Process changed or exited; select it again".into());
    }
    let result = unsafe {
        libc::syscall(
            libc::SYS_pidfd_send_signal,
            fd.as_raw_fd(),
            libc::SIGTERM,
            std::ptr::null::<libc::siginfo_t>(),
            0u32,
        )
    };
    if result < 0 {
        Err(format!("Cannot end task: {}", io::Error::last_os_error()))
    } else {
        Ok(())
    }
}
#[cfg(test)]
mod tests {
    use super::*;
    use std::process::{Command, Stdio};
    #[test]
    fn identity_checked_before_signalling_owned_child() {
        let mut child = Command::new("sleep")
            .arg("30")
            .stdout(Stdio::null())
            .spawn()
            .unwrap();
        let pid = child.id();
        let start = start_time(&fs::read_to_string(format!("/proc/{pid}/stat")).unwrap()).unwrap();
        assert!(end_task(pid, start + 1).is_err());
        assert!(child.try_wait().unwrap().is_none());
        let result = end_task(pid, start);
        if result.is_err() {
            let _ = child.kill();
        }
        let status = child.wait().unwrap();
        assert!(result.is_ok(), "{result:?}");
        assert!(!status.success());
    }
    #[test]
    fn protects_init_and_self() {
        assert!(end_task(1, 1).is_err());
        assert!(end_task(std::process::id(), 1).is_err());
        assert_eq!(start_time("bad stat"), None);
    }
}

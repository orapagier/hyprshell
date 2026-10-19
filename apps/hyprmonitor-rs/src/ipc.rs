//! Serialize startup and recover only sockets whose listener is gone.
use std::{
    fs::{self, File, OpenOptions},
    io,
    os::{
        fd::AsRawFd,
        unix::{
            fs::{FileTypeExt, MetadataExt, OpenOptionsExt, PermissionsExt},
            net::{UnixListener, UnixStream},
        },
    },
    path::PathBuf,
};

pub struct SocketLease {
    path: PathBuf,
    inode: u64,
    // Keep the lock file: unlinking it would allow competing inode locks.
    _lock: File,
}

impl Drop for SocketLease {
    fn drop(&mut self) {
        if fs::symlink_metadata(&self.path).is_ok_and(|m| m.ino() == self.inode) {
            let _ = fs::remove_file(&self.path);
        }
    }
}

fn lock(path: &std::path::Path) -> Result<File, String> {
    let file = OpenOptions::new()
        .read(true)
        .write(true)
        .create(true)
        .truncate(false)
        .mode(0o600)
        .custom_flags(libc::O_NOFOLLOW | libc::O_CLOEXEC)
        .open(path)
        .map_err(|e| format!("Cannot open instance lock: {e}"))?;
    let metadata = file.metadata().map_err(|e| e.to_string())?;
    // SAFETY: geteuid has no arguments or memory requirements.
    if !metadata.is_file() || metadata.uid() != unsafe { libc::geteuid() } {
        return Err("Instance lock is not a regular file owned by this user".into());
    }
    // SAFETY: the descriptor belongs to a live File; flock does not retain pointers.
    if unsafe { libc::flock(file.as_raw_fd(), libc::LOCK_EX | libc::LOCK_NB) } != 0 {
        return Err(format!(
            "Hyprmonitor instance lock is busy: {}",
            io::Error::last_os_error()
        ));
    }
    Ok(file)
}

pub fn bind(path: PathBuf) -> Result<(UnixListener, SocketLease), String> {
    let lock = lock(&path.with_extension("lock"))?;
    match fs::symlink_metadata(&path) {
        Ok(metadata) => {
            // SAFETY: geteuid has no arguments or memory requirements.
            if !metadata.file_type().is_socket() || metadata.uid() != unsafe { libc::geteuid() } {
                return Err(format!(
                    "Refusing to replace non-owned socket: {}",
                    path.display()
                ));
            }
            match UnixStream::connect(&path) {
                Ok(_) => return Err("Another Hyprmonitor instance is already running".into()),
                Err(e)
                    if matches!(
                        e.kind(),
                        io::ErrorKind::ConnectionRefused | io::ErrorKind::NotFound
                    ) => {}
                Err(e) => return Err(format!("Cannot establish whether socket is abandoned: {e}")),
            }
            match fs::symlink_metadata(&path) {
                Ok(current)
                    if current.ino() == metadata.ino() && current.dev() == metadata.dev() =>
                {
                    fs::remove_file(&path).map_err(|e| e.to_string())?;
                }
                Err(e) if e.kind() == io::ErrorKind::NotFound => {}
                _ => return Err("Socket changed during recovery; retry startup".into()),
            }
        }
        Err(e) if e.kind() == io::ErrorKind::NotFound => {}
        Err(e) => return Err(e.to_string()),
    }
    let listener = UnixListener::bind(&path).map_err(|e| format!("{}: {e}", path.display()))?;
    let lease = SocketLease {
        inode: fs::symlink_metadata(&path)
            .map_err(|e| e.to_string())?
            .ino(),
        path: path.clone(),
        _lock: lock,
    };
    fs::set_permissions(&path, fs::Permissions::from_mode(0o600)).map_err(|e| e.to_string())?;
    Ok((listener, lease))
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::os::unix::fs::symlink;

    fn test_path(name: &str) -> PathBuf {
        std::env::temp_dir().join(format!("hyprmonitor-{}-{name}.sock", std::process::id()))
    }

    #[test]
    fn lock_excludes_competing_startup_and_releases_on_drop() {
        let path = test_path("lock");
        let first = lock(&path).unwrap();
        assert!(lock(&path).is_err());
        drop(first);
        assert!(lock(&path).is_ok());
        fs::remove_file(path).unwrap();
    }

    #[test]
    fn never_replaces_files_or_symlinks() {
        let path = test_path("file");
        fs::write(&path, b"keep").unwrap();
        assert!(bind(path.clone()).is_err());
        assert_eq!(fs::read(&path).unwrap(), b"keep");
        let link = test_path("link");
        symlink(&path, &link).unwrap();
        assert!(bind(link.clone()).is_err());
        assert!(lock(&link).is_err());
        assert!(link.is_symlink());
        for p in [
            &path,
            &link,
            &path.with_extension("lock"),
            &link.with_extension("lock"),
        ] {
            fs::remove_file(p).unwrap();
        }
    }

    #[test]
    #[ignore = "requires permission to create Unix sockets; run in desktop terminal"]
    fn recovers_abandoned_socket_and_preserves_live_server() {
        let path = test_path("socket");
        let old = UnixListener::bind(&path).unwrap();
        assert!(bind(path.clone()).is_err());
        assert!(UnixStream::connect(&path).is_ok());
        drop(old);
        let (listener, lease) = bind(path.clone()).unwrap();
        assert!(UnixStream::connect(&path).is_ok());
        assert!(bind(path.clone()).is_err());
        drop(listener);
        drop(lease);
        assert!(!path.exists());
        fs::remove_file(path.with_extension("lock")).unwrap();
    }
}

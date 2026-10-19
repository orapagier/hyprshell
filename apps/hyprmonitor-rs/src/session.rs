//! Optional native system D-Bus metadata. No shell process, Qt, or desktop-specific controller.
use std::{
    collections::HashMap,
    sync::{
        atomic::{AtomicBool, Ordering},
        mpsc,
    },
    thread,
    time::Duration,
};
use zbus::{
    blocking::{Connection, Proxy},
    zvariant::{OwnedObjectPath, OwnedValue},
};
static QUERY_RUNNING: AtomicBool = AtomicBool::new(false);
#[derive(Default)]
pub struct Status {
    pub connection: Option<String>,
    pub strength: Option<f64>,
    pub bluetooth: Option<String>,
}
pub fn query() -> Option<Status> {
    // A slow/unavailable bus can leave at most one bounded query worker, never a thread per refresh.
    if QUERY_RUNNING.swap(true, Ordering::AcqRel) {
        return None;
    }
    let (sender, receiver) = mpsc::sync_channel(1);
    thread::spawn(move || {
        let result = read_bus();
        let _ = sender.send(result);
        QUERY_RUNNING.store(false, Ordering::Release);
    });
    receiver
        .recv_timeout(Duration::from_millis(250))
        .ok()
        .flatten()
}
fn read_bus() -> Option<Status> {
    let connection = Connection::system().ok()?;
    let mut status = Status::default();
    if let Ok(manager) = Proxy::new(
        &connection,
        "org.freedesktop.NetworkManager",
        "/org/freedesktop/NetworkManager",
        "org.freedesktop.NetworkManager",
    ) {
        if let Ok(path) = manager.get_property::<OwnedObjectPath>("PrimaryConnection") {
            if path.as_str() != "/" {
                if let Ok(active) = Proxy::new(
                    &connection,
                    "org.freedesktop.NetworkManager",
                    path.as_str(),
                    "org.freedesktop.NetworkManager.Connection.Active",
                ) {
                    status.connection = active.get_property::<String>("Id").ok();
                    if let Ok(ap) = active.get_property::<OwnedObjectPath>("SpecificObject") {
                        if let Ok(wifi) = Proxy::new(
                            &connection,
                            "org.freedesktop.NetworkManager",
                            ap.as_str(),
                            "org.freedesktop.NetworkManager.AccessPoint",
                        ) {
                            status.strength =
                                wifi.get_property::<u8>("Strength").ok().map(f64::from);
                            if let Ok(ssid) = wifi.get_property::<Vec<u8>>("Ssid") {
                                status.connection = String::from_utf8(ssid).ok();
                            }
                        }
                    }
                }
            } else {
                status.connection = Some("Offline".into());
            }
        }
    }
    type Objects = HashMap<OwnedObjectPath, HashMap<String, HashMap<String, OwnedValue>>>;
    if let Ok(manager) = Proxy::new(
        &connection,
        "org.bluez",
        "/",
        "org.freedesktop.DBus.ObjectManager",
    ) {
        if let Ok(objects) = manager.call::<_, _, Objects>("GetManagedObjects", &()) {
            let mut adapters = 0;
            let mut powered = false;
            let mut connected = 0;
            for interfaces in objects.values() {
                if let Some(adapter) = interfaces.get("org.bluez.Adapter1") {
                    adapters += 1;
                    powered |= adapter
                        .get("Powered")
                        .and_then(|v| bool::try_from(v).ok())
                        .unwrap_or(false);
                }
                if let Some(device) = interfaces.get("org.bluez.Device1") {
                    connected += usize::from(
                        device
                            .get("Connected")
                            .and_then(|v| bool::try_from(v).ok())
                            .unwrap_or(false),
                    );
                }
            }
            status.bluetooth = Some(if adapters == 0 {
                "No Bluetooth adapter".into()
            } else if !powered {
                "off".into()
            } else if connected > 0 {
                format!("on · {connected} connected")
            } else {
                "on".into()
            });
        }
    }
    Some(status)
}

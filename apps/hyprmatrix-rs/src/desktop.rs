use crate::{
    config::Config,
    render::{self, Renderer},
    wallpaper,
};
use calloop::{
    channel::{self, Event as ChannelEvent},
    EventLoop,
};
use calloop_wayland_source::WaylandSource;
use smithay_client_toolkit::{
    compositor::{CompositorHandler, CompositorState, Region},
    delegate_compositor, delegate_layer, delegate_output, delegate_pointer, delegate_registry,
    delegate_seat, delegate_shm,
    output::{OutputHandler, OutputState},
    registry::{ProvidesRegistryState, RegistryState},
    registry_handlers,
    seat::{
        pointer::{PointerEvent, PointerEventKind, PointerHandler},
        Capability, SeatHandler, SeatState,
    },
    shell::{
        wlr_layer::{
            Anchor, KeyboardInteractivity, Layer, LayerShell, LayerShellHandler, LayerSurface,
            LayerSurfaceConfigure,
        },
        WaylandSurface,
    },
    shm::{
        slot::{Buffer, SlotPool},
        Shm, ShmHandler,
    },
};
use std::{
    io::{BufRead, BufReader, Read, Write},
    os::unix::net::UnixStream,
    path::PathBuf,
    sync::{
        atomic::{AtomicBool, Ordering},
        mpsc as std_mpsc, Arc,
    },
    thread,
    time::{Duration, Instant},
};
use wayland_client::{
    globals::registry_queue_init,
    protocol::{wl_output, wl_pointer, wl_seat, wl_shm, wl_surface},
    Connection, QueueHandle,
};

enum Event {
    Command(String, Option<std_mpsc::Sender<Result<(), String>>>),
    Palette([u8; 3]),
    Workspace(String),
    WorkspaceError(String),
}
/// Diagnostics gated by HYPRIX_DEBUG for troubleshooting the frame loop.
fn dbg_event(what: &str) {
    if std::env::var_os("HYPRIX_DEBUG").is_some() {
        eprintln!("hyprmatrix[dbg]: {what}");
    }
}
/// HYPRIX_DUMP=path captures the first rendered frame for inspection.
fn dump_frame(pixels: &[u32], w: u32, h: u32, path: &str) -> Result<(), String> {
    let bytes: Vec<u8> = pixels
        .iter()
        .flat_map(|p| {
            let a = p >> 24;
            let channel = |shift: u32| {
                ((p >> shift & 255) * 255)
                    .checked_div(a)
                    .unwrap_or(0)
                    .min(255) as u8
            };
            [channel(16), channel(8), channel(0), a as u8]
        })
        .collect();
    let f = std::io::BufWriter::new(std::fs::File::create(path).map_err(|e| e.to_string())?);
    let mut encoder = png::Encoder::new(f, w, h);
    encoder.set_color(png::ColorType::Rgba);
    encoder.set_depth(png::BitDepth::Eight);
    encoder
        .write_header()
        .map_err(|e| e.to_string())?
        .write_image_data(&bytes)
        .map_err(|e| e.to_string())?;
    Ok(())
}
fn socket_path() -> Result<PathBuf, String> {
    Ok(
        PathBuf::from(std::env::var_os("XDG_RUNTIME_DIR").ok_or("XDG_RUNTIME_DIR missing")?)
            .join("hyprmatrix.sock"),
    )
}
fn hypr_path(name: &str) -> Result<PathBuf, String> {
    let signature = std::env::var_os("HYPRLAND_INSTANCE_SIGNATURE")
        .ok_or("Workspace tracking requires a Hyprland session")?;
    let runtime = std::env::var_os("XDG_RUNTIME_DIR").ok_or("XDG_RUNTIME_DIR missing")?;
    Ok(PathBuf::from(runtime)
        .join("hypr")
        .join(signature)
        .join(name))
}
fn hypr_query(command: &str, limit: u64) -> Result<String, String> {
    let mut stream = UnixStream::connect(hypr_path(".socket.sock")?).map_err(|e| e.to_string())?;
    stream
        .set_read_timeout(Some(Duration::from_secs(1)))
        .map_err(|e| e.to_string())?;
    stream
        .set_write_timeout(Some(Duration::from_secs(1)))
        .map_err(|e| e.to_string())?;
    stream
        .write_all(command.as_bytes())
        .map_err(|e| e.to_string())?;
    let mut text = String::new();
    stream
        .take(limit)
        .read_to_string(&mut text)
        .map_err(|e| e.to_string())?;
    Ok(text)
}
fn focused_workspace() -> Result<String, String> {
    let text = hypr_query("j/activeworkspace", 65536)?;
    let value: serde_json::Value = serde_json::from_str(&text).map_err(|e| e.to_string())?;
    let id = value["id"]
        .as_u64()
        .filter(|n| (1..=99).contains(n))
        .ok_or("Choose a numbered workspace (1–99)")?;
    Ok(id.to_string())
}
fn workspace_name(output: &str) -> Result<String, String> {
    let text = hypr_query("j/monitors", 256 * 1024)?;
    let monitors: serde_json::Value = serde_json::from_str(&text).map_err(|e| e.to_string())?;
    let monitor = monitors
        .as_array()
        .and_then(|list| {
            list.iter()
                .find(|m| m["name"].as_str() == Some(output))
        })
        .ok_or("Target output is unavailable")?;
    monitor["activeWorkspace"]["name"]
        .as_str()
        .map(String::from)
        .ok_or_else(|| "Workspace name unavailable".into())
}
fn cursor_position() -> Result<(i32, i32), String> {
    let text = hypr_query("j/cursorpos", 4096)?;
    let value: serde_json::Value = serde_json::from_str(&text).map_err(|e| e.to_string())?;
    Ok((
        value["x"].as_i64().unwrap_or(0) as i32,
        value["y"].as_i64().unwrap_or(0) as i32,
    ))
}
/// Client windows report `at`/`size` arrays; point hit-test in global coordinates.
fn client_contains(obj: &serde_json::Value, x: i32, y: i32) -> bool {
    let (ax, ay) = (
        obj["at"][0].as_i64().unwrap_or(0) as i32,
        obj["at"][1].as_i64().unwrap_or(0) as i32,
    );
    let (w, h) = (
        obj["size"][0].as_i64().unwrap_or(0) as i32,
        obj["size"][1].as_i64().unwrap_or(0) as i32,
    );
    x >= ax && x < ax + w && y >= ay && y < ay + h
}
/// Layer surfaces report flat `x`/`y`/`w`/`h` fields.
fn layer_contains(obj: &serde_json::Value, x: i32, y: i32) -> bool {
    let (ax, ay) = (
        obj["x"].as_i64().unwrap_or(0) as i32,
        obj["y"].as_i64().unwrap_or(0) as i32,
    );
    let (w, h) = (
        obj["w"].as_i64().unwrap_or(0) as i32,
        obj["h"].as_i64().unwrap_or(0) as i32,
    );
    x >= ax && x < ax + w && y >= ay && y < ay + h
}
fn start_workspaces(output: String, sender: channel::Sender<Event>) {
    thread::spawn(move || {
        let result = (|| -> Result<(), String> {
            let stream =
                UnixStream::connect(hypr_path(".socket2.sock")?).map_err(|e| e.to_string())?;
            sender
                .send(Event::Workspace(workspace_name(&output)?))
                .map_err(|e| e.to_string())?;
            for line in BufReader::new(stream).lines() {
                let line = line.map_err(|e| e.to_string())?;
                if [
                    "workspacev2>>",
                    "focusedmon>>",
                    "moveworkspacev2>>",
                    "monitoraddedv2>>",
                    "monitorremoved>>",
                ]
                .iter()
                .any(|prefix| line.starts_with(prefix))
                {
                    sender
                        .send(Event::Workspace(workspace_name(&output)?))
                        .map_err(|e| e.to_string())?;
                }
            }
            Err("Hyprland event socket closed".into())
        })();
        if let Err(e) = result {
            let _ = sender.send(Event::WorkspaceError(e));
        }
    });
}
pub fn control(command: &str) -> Result<(), String> {
    let mut stream =
        UnixStream::connect(socket_path()?).map_err(|e| format!("No running Hyprmatrix: {e}"))?;
    stream
        .set_read_timeout(Some(Duration::from_secs(2)))
        .map_err(|e| e.to_string())?;
    stream
        .set_write_timeout(Some(Duration::from_secs(2)))
        .map_err(|e| e.to_string())?;
    stream
        .write_all(command.as_bytes())
        .map_err(|e| e.to_string())?;
    stream
        .shutdown(std::net::Shutdown::Write)
        .map_err(|e| e.to_string())?;
    let mut reply = String::new();
    stream
        .take(128)
        .read_to_string(&mut reply)
        .map_err(|e| e.to_string())?;
    if reply.trim() == "ok" {
        Ok(())
    } else {
        Err(reply)
    }
}
pub fn run(config: Config, menu: bool) -> Result<(), String> {
    let (listener, _lease) = crate::ipc::bind(socket_path()?)?;
    let connection =
        Connection::connect_to_env().map_err(|e| format!("Cannot connect to Wayland: {e}"))?;
    let (globals, mut queue) = registry_queue_init(&connection).map_err(|e| e.to_string())?;
    let qh = queue.handle();
    let compositor = CompositorState::bind(&globals, &qh).map_err(|e| e.to_string())?;
    let shell = LayerShell::bind(&globals, &qh)
        .map_err(|e| format!("Wayland layer-shell required: {e}"))?;
    let shm = Shm::bind(&globals, &qh).map_err(|e| e.to_string())?;
    let pool = SlotPool::new(4096, &shm).map_err(|e| e.to_string())?;
    let renderer = Renderer::new(&config)?;
    let active = Arc::new(AtomicBool::new(true));
    let refresh = Arc::new(AtomicBool::new(false));
    let mut state = Desktop {
        registry: RegistryState::new(&globals),
        seats: SeatState::new(&globals, &qh),
        outputs: OutputState::new(&globals, &qh),
        compositor,
        pointer: None,
        shm,
        pool,
        buffers: Vec::new(),
        layer: None,
        target: None,
        renderer,
        config,
        width: 640,
        height: 520,
        screen: (1920, 1080),
        configured: false,
        ready: true,
        visible: true,
        user_visible: true,
        workspace_allowed: true,
        current_workspace: None,
        seeding: true,
        menu,
        menu_pos: None,
        menu_drag: None,
        region_drag: None,
        status: String::new(),
        exit: false,
        error: None,
        last: Instant::now() - Duration::from_secs(1),
        time: 0.0,
        palette: wallpaper::FALLBACK,
        active: active.clone(),
        refresh: refresh.clone(),
    };
    queue.roundtrip(&mut state).map_err(|e| e.to_string())?;
    let target = state.outputs.outputs().find(|o| {
        state.config.output.as_ref().is_none_or(|name| {
            state
                .outputs
                .info(o)
                .is_some_and(|i| i.name.as_ref() == Some(name))
        })
    });
    if state.config.output.is_some() && target.is_none() {
        return Err("Requested output is unavailable".into());
    }
    let output = target
        .as_ref()
        .and_then(|o| state.outputs.info(o))
        .and_then(|i| i.name)
        .unwrap_or_default();
    state.target = target;
    state.update_screen();
    let surface = state.compositor.create_surface(&qh);
    let layer = shell.create_layer_surface(
        &qh,
        surface,
        Layer::Bottom,
        Some("hyprmatrix"),
        state.target.as_ref(),
    );
    layer.set_keyboard_interactivity(KeyboardInteractivity::None);
    layer.set_exclusive_zone(-1);
    state.layer = Some(layer);
    state.place()?;
    let (sender, events) = channel::channel();
    let control_sender = sender.clone();
    thread::spawn(move || {
        for stream in listener.incoming() {
            let Ok(mut stream) = stream else {
                break;
            };
            let _ = stream.set_read_timeout(Some(Duration::from_secs(1)));
            let _ = stream.set_write_timeout(Some(Duration::from_secs(2)));
            let mut command = String::new();
            if (&mut stream).take(64).read_to_string(&mut command).is_err() {
                continue;
            }
            let command = command.trim().to_string();
            if ![
                "show",
                "hide",
                "toggle",
                "quit",
                "settings",
                "refresh",
                "fullscreen",
                "region",
                "toggle-workspace",
                "drag-begin",
                "drag-end",
            ]
            .contains(&command.as_str())
            {
                let _ = stream.write_all(b"invalid command\n");
                continue;
            }
            let (tx, rx) = std_mpsc::channel();
            if control_sender
                .send(Event::Command(command, Some(tx)))
                .is_err()
            {
                break;
            }
            let reply = match rx.recv_timeout(Duration::from_secs(2)) {
                Ok(Ok(())) => "ok\n".to_string(),
                Ok(Err(error)) => format!("{error}\n"),
                Err(_) => "Control timed out\n".to_string(),
            };
            let _ = stream.write_all(reply.as_bytes());
        }
    });
    if std::env::var_os("HYPRLAND_INSTANCE_SIGNATURE").is_some_and(|s| !s.is_empty()) {
        start_workspaces(output.clone(), sender.clone());
    }
    thread::spawn(move || {
        let mut last = String::new();
        let mut fingerprint = None;
        loop {
            if active.load(Ordering::Relaxed) {
                if let Ok(path) = wallpaper::current_path(&output) {
                    let modified = std::fs::metadata(&path).and_then(|m| m.modified()).ok();
                    if path != last
                        || modified != fingerprint
                        || refresh.swap(false, Ordering::Relaxed)
                    {
                        match wallpaper::sample(&path) {
                            Ok(color) => {
                                if sender.send(Event::Palette(color)).is_err() {
                                    break;
                                }
                                last = path;
                                fingerprint = modified;
                            }
                            Err(error) => {
                                eprintln!("hyprmatrix: {error}; keeping previous color");
                                last = path;
                                fingerprint = modified;
                            }
                        }
                    }
                }
            }
            thread::sleep(Duration::from_secs(5));
        }
    });
    let mut event_loop = EventLoop::<Desktop>::try_new().map_err(|e| e.to_string())?;
    WaylandSource::new(connection, queue)
        .insert(event_loop.handle())
        .map_err(|e| e.to_string())?;
    event_loop
        .handle()
        .insert_source(events, |event, _, state| {
            if let ChannelEvent::Msg(event) = event {
                match event {
                    Event::Palette(color) => state.palette = color,
                    Event::Workspace(workspace) => state.on_workspace(workspace),
                    Event::WorkspaceError(error) => {
                        eprintln!("hyprmatrix: workspace tracking stopped: {error}");
                        // Without events the surface falls back to legacy always-on
                        // behavior only when no per-workspace choice was saved.
                        state.workspace_allowed = state.config.workspace_overrides.is_empty();
                        if let Err(error) = state.update_visibility() {
                            state.error = Some(error);
                            state.exit = true;
                        }
                    }
                    Event::Command(command, reply) => {
                        dbg_event(&format!("cmd {command}"));
                        let result = state.command(&command);
                        if let Some(tx) = reply {
                            let _ = tx.send(result.clone());
                        }
                        if let Err(error) = result {
                            // Refusals from interactive commands stay recoverable.
                            let fatal = !matches!(
                                command.as_str(),
                                "drag-begin" | "drag-end" | "toggle-workspace" | "settings"
                            );
                            if fatal {
                                state.error = Some(error);
                                state.exit = true;
                            } else {
                                eprintln!("hyprmatrix: {error}");
                                state.status = error;
                                state.wake_draw();
                            }
                        }
                    }
                }
            }
        })
        .map_err(|e| e.to_string())?;
    while !state.exit {
        let timeout = if state.region_drag.is_some() {
            Some(Duration::from_millis(16))
        } else if state.visible && state.configured && state.ready {
            Some(
                Duration::from_secs_f64(1.0 / state.config.fps as f64)
                    .saturating_sub(state.last.elapsed()),
            )
        } else {
            None
        };
        event_loop
            .dispatch(timeout, &mut state)
            .map_err(|e| e.to_string())?;
        state.poll_region_drag();
        if !state.exit {
            state.draw(&qh)?;
        }
    }
    if let Some(error) = state.error {
        Err(error)
    } else {
        Ok(())
    }
}
struct MenuDrag {
    grab: (f64, f64),
    origin: (u32, u32),
    start: (f32, f32),
    moved: bool,
}
struct RegionDrag {
    offset: (i32, i32),
    started: Instant,
}
struct Desktop {
    registry: RegistryState,
    seats: SeatState,
    outputs: OutputState,
    compositor: CompositorState,
    pointer: Option<wl_pointer::WlPointer>,
    shm: Shm,
    pool: SlotPool,
    buffers: Vec<Buffer>,
    layer: Option<LayerSurface>,
    target: Option<wl_output::WlOutput>,
    renderer: Renderer,
    config: Config,
    width: u32,
    height: u32,
    screen: (u32, u32),
    configured: bool,
    ready: bool,
    visible: bool,
    user_visible: bool,
    workspace_allowed: bool,
    current_workspace: Option<String>,
    seeding: bool,
    menu: bool,
    menu_pos: Option<(u32, u32)>,
    menu_drag: Option<MenuDrag>,
    region_drag: Option<RegionDrag>,
    status: String,
    exit: bool,
    error: Option<String>,
    last: Instant,
    time: f32,
    palette: [u8; 3],
    active: Arc<AtomicBool>,
    refresh: Arc<AtomicBool>,
}
impl Desktop {
    fn layer(&self) -> &LayerSurface {
        self.layer.as_ref().expect("layer initialized")
    }
    fn update_screen(&mut self) {
        if let Some(info) = self.target.as_ref().and_then(|o| self.outputs.info(o)) {
            let size = info.logical_size.or_else(|| {
                info.modes.iter().find(|m| m.current).map(|m| {
                    (
                        m.dimensions.0 / info.scale_factor.max(1),
                        m.dimensions.1 / info.scale_factor.max(1),
                    )
                })
            });
            if let Some((w, h)) = size {
                self.screen = (w.max(1) as u32, h.max(1) as u32);
            }
        }
    }
    fn place(&mut self) -> Result<(), String> {
        let width = if self.config.fullscreen {
            self.screen.0
        } else {
            self.config.width.min(self.screen.0)
        };
        let height = if self.config.fullscreen {
            self.screen.1
        } else {
            self.config.height.min(self.screen.1)
        };
        let resized = width != self.width || height != self.height;
        self.width = width;
        self.height = height;
        let x = ((self.screen.0 - self.width) as f32 * self.config.x) as i32;
        let y = ((self.screen.1 - self.height) as f32 * self.config.y) as i32;
        self.layer().set_anchor(Anchor::TOP | Anchor::LEFT);
        self.layer().set_size(self.width, self.height);
        self.layer().set_margin(y, 0, 0, x);
        if resized {
            self.buffers.clear();
        }
        self.input_region()?;
        self.layer().commit();
        Ok(())
    }
    /// Move the surface without reallocating buffers.
    fn reposition(&mut self) {
        let x = ((self.screen.0 - self.width) as f32 * self.config.x) as i32;
        let y = ((self.screen.1 - self.height) as f32 * self.config.y) as i32;
        self.layer().set_margin(y, 0, 0, x);
        self.layer().commit();
    }
    fn menu_rect_at(&self) -> (u32, u32, u32, u32) {
        let (dx, dy) = render::clamp_menu_pos(
            self.menu_pos.unwrap_or_else(|| {
                let (x, y, _, _) = render::menu_rect(self.width, self.height);
                (x, y)
            }),
            (self.width, self.height),
        );
        let mw = render::MENU_WIDTH.min(self.width);
        let mh = render::MENU_HEIGHT.min(self.height);
        (dx, dy, mw, mh)
    }
    /// Request the next frame as soon as the frame budget allows.
    fn wake_draw(&mut self) {
        self.ready = true;
        self.last = Instant::now()
            - Duration::from_secs_f64((1.0 / self.config.fps as f64).min(0.25));
    }
    fn input_region(&self) -> Result<(), String> {
        let region = Region::new(&self.compositor).map_err(|e| e.to_string())?;
        region.add(self.width.saturating_sub(44) as i32, 0, 44, 44);
        if self.menu {
            let (x, y, w, h) = self.menu_rect_at();
            region.add(x as i32, y as i32, w as i32, h as i32);
        }
        self.layer()
            .wl_surface()
            .set_input_region(Some(region.wl_region()));
        Ok(())
    }
    fn visibility(&mut self, show: bool) -> Result<(), String> {
        dbg_event(&format!(
            "visibility show={show} (was {}) user={} allowed={}",
            self.visible, self.user_visible, self.workspace_allowed
        ));
        if self.visible == show {
            return Ok(());
        }
        self.visible = show;
        self.active.store(show, Ordering::Relaxed);
        self.last = Instant::now();
        if show {
            self.ready = true;
            self.place()?;
        } else {
            self.region_drag = None;
            self.layer().wl_surface().attach(None, 0, 0);
            self.layer().commit();
            self.configured = false;
            self.menu = false;
        }
        Ok(())
    }
    fn update_visibility(&mut self) -> Result<(), String> {
        self.visibility(self.user_visible && self.workspace_allowed)
    }
    fn on_workspace(&mut self, workspace: String) {
        dbg_event(&format!("workspace {workspace} seeding={}", self.seeding));
        if self.seeding {
            // A fresh start enables rain on the launch workspace once.
            self.seeding = false;
            if !self.config.workspace_overrides.contains_key(&workspace) {
                self.config.workspace_overrides.insert(workspace.clone(), true);
                if let Err(error) = self.config.save() {
                    eprintln!("hyprmatrix: {error}");
                }
            }
        }
        self.current_workspace = Some(workspace.clone());
        self.workspace_allowed = self.config.visible_on(Some(&workspace));
        if let Err(error) = self.update_visibility() {
            self.error = Some(error);
            self.exit = true;
        }
    }
    fn output_position(&self) -> (i32, i32) {
        self.target
            .as_ref()
            .and_then(|o| self.outputs.info(o))
            .map(|i| i.location)
            .unwrap_or((0, 0))
    }
    fn region_rect(&self) -> (i32, i32, u32, u32) {
        let out = self.output_position();
        let lx = ((self.screen.0.saturating_sub(self.width)) as f32 * self.config.x) as i32;
        let ly = ((self.screen.1.saturating_sub(self.height)) as f32 * self.config.y) as i32;
        (out.0 + lx, out.1 + ly, self.width, self.height)
    }
    fn cursor_over_foreign_surface(&self, cursor: (i32, i32)) -> Result<bool, String> {
        let text = hypr_query("j/clients", 2 * 1024 * 1024)?;
        let clients: serde_json::Value = serde_json::from_str(&text).map_err(|e| e.to_string())?;
        for client in clients.as_array().into_iter().flatten() {
            if client["mapped"].as_bool() != Some(true)
                || client["hidden"].as_bool() == Some(true)
            {
                continue;
            }
            if client_contains(client, cursor.0, cursor.1) {
                return Ok(true);
            }
        }
        let text = hypr_query("j/layers", 2 * 1024 * 1024)?;
        let layers: serde_json::Value = serde_json::from_str(&text).map_err(|e| e.to_string())?;
        if let Some(monitors) = layers.as_object() {
            for data in monitors.values() {
                if let Some(levels) = data["levels"].as_object() {
                    for items in levels.values() {
                        for item in items.as_array().into_iter().flatten() {
                            if item["namespace"].as_str() == Some("hyprmatrix") {
                                continue;
                            }
                            if layer_contains(item, cursor.0, cursor.1) {
                                return Ok(true);
                            }
                        }
                    }
                }
            }
        }
        Ok(false)
    }
    fn drag_begin(&mut self) -> Result<(), String> {
        if self.config.fullscreen {
            return Err("Switch Placement to Region before dragging".into());
        }
        if !self.visible {
            return Err("Hyprmatrix is hidden on this workspace".into());
        }
        let cursor = cursor_position()?;
        let (rx, ry, rw, rh) = self.region_rect();
        if cursor.0 < rx
            || cursor.0 >= rx + rw as i32
            || cursor.1 < ry
            || cursor.1 >= ry + rh as i32
        {
            return Err("Cursor is not over the rain region".into());
        }
        if self.cursor_over_foreign_surface(cursor)? {
            return Err("Another surface is under the cursor".into());
        }
        self.region_drag = Some(RegionDrag {
            offset: (cursor.0 - rx, cursor.1 - ry),
            started: Instant::now(),
        });
        Ok(())
    }
    fn end_region_drag(&mut self, save: bool) -> Result<(), String> {
        if self.region_drag.take().is_none() || !save {
            return Ok(());
        }
        self.config.save()?;
        self.wake_draw();
        Ok(())
    }
    fn poll_region_drag(&mut self) {
        // The surface release normally ends the drag; expire defensively if it is lost.
        if self
            .region_drag
            .as_ref()
            .is_some_and(|d| d.started.elapsed() > Duration::from_secs(20))
        {
            if let Err(error) = self.end_region_drag(true) {
                eprintln!("hyprmatrix: {error}");
            }
            return;
        }
        if self.region_drag.is_none() {
            return;
        }
        let cursor = match cursor_position() {
            Ok(cursor) => cursor,
            Err(error) => {
                self.region_drag = None;
                eprintln!("hyprmatrix: drag stopped: {error}");
                return;
            }
        };
        let out = self.output_position();
        let avail_w = self.screen.0.saturating_sub(self.width) as f64;
        let avail_h = self.screen.1.saturating_sub(self.height) as f64;
        let local_x = (cursor.0 - out.0 - self.region_drag.as_ref().unwrap().offset.0) as f64;
        let local_y = (cursor.1 - out.1 - self.region_drag.as_ref().unwrap().offset.1) as f64;
        self.config.x = (local_x / avail_w.max(1.0)).clamp(0.0, 1.0) as f32;
        self.config.y = (local_y / avail_h.max(1.0)).clamp(0.0, 1.0) as f32;
        self.reposition();
        self.wake_draw();
    }
    fn command(&mut self, command: &str) -> Result<(), String> {
        match command {
            "quit" => self.exit = true,
            "show" => {
                self.user_visible = true;
                self.update_visibility()?;
            }
            "hide" => {
                self.user_visible = false;
                self.update_visibility()?;
            }
            "toggle" => {
                self.user_visible = !self.user_visible;
                self.update_visibility()?;
            }
            "settings" => {
                self.user_visible = true;
                self.workspace_allowed = true;
                self.visibility(true)?;
                self.menu = true;
                self.input_region()?;
                self.layer().commit();
                self.wake_draw();
            }
            "refresh" => self.refresh.store(true, Ordering::Relaxed),
            "fullscreen" | "region" => {
                self.config.fullscreen = command == "fullscreen";
                self.config.save()?;
                self.user_visible = true;
                self.update_visibility()?;
                self.place()?;
            }
            "toggle-workspace" => {
                // socket1 is authoritative even if the event stream lags.
                let workspace = focused_workspace()?;
                self.user_visible = true;
                let old = self
                    .config
                    .workspace_overrides
                    .get(&workspace)
                    .copied()
                    .unwrap_or(false);
                self.config
                    .workspace_overrides
                    .insert(workspace.clone(), !old);
                self.config.save()?;
                self.current_workspace = Some(workspace.clone());
                self.workspace_allowed = self.config.visible_on(Some(&workspace));
                self.update_visibility()?;
                self.wake_draw();
            }
            "drag-begin" => self.drag_begin()?,
            "drag-end" => self.end_region_drag(true)?,
            _ => {}
        }
        Ok(())
    }
    fn draw(&mut self, qh: &QueueHandle<Self>) -> Result<(), String> {
        if !self.visible || !self.configured || !self.ready {
            dbg_event(&format!(
                "skip visible={} configured={} ready={}",
                self.visible, self.configured, self.ready
            ));
            return Ok(());
        }
        if self.last.elapsed() < Duration::from_secs_f64(1.0 / self.config.fps as f64) {
            return Ok(());
        }
        dbg_event("render");
        let (w, h) = (self.width, self.height);
        if w as u64 * h as u64 > 16_000_000 {
            return Err("Surface exceeds the 16 megapixel resource limit".into());
        }
        if self.buffers.is_empty() {
            // Replace the pool on resize so its high-water mark does not grow indefinitely.
            self.pool =
                SlotPool::new(w as usize * h as usize * 8, &self.shm).map_err(|e| e.to_string())?;
            for _ in 0..2 {
                let (buffer, _) = self
                    .pool
                    .create_buffer(w as i32, h as i32, w as i32 * 4, wl_shm::Format::Argb8888)
                    .map_err(|e| e.to_string())?;
                self.buffers.push(buffer);
            }
        }
        let Some(index) = self
            .buffers
            .iter()
            .position(|b| self.pool.canvas(b).is_some())
        else {
            self.last = Instant::now(); // Wait one frame interval if both buffers are still held.
            return Ok(());
        };
        let dt = self.last.elapsed().as_secs_f32().min(0.25);
        self.time += dt;
        let menu_rect = self.menu.then(|| self.menu_rect_at());
        let canvas = self
            .pool
            .canvas(&self.buffers[index])
            .ok_or("Busy buffer")?;
        let pixels = bytemuck::try_cast_slice_mut::<u8, u32>(canvas).map_err(|e| e.to_string())?;
        self.renderer.render(
            pixels,
            w,
            h,
            &self.config,
            self.time,
            dt,
            self.config.color(self.palette),
            menu_rect,
            &self.status,
        );
        if let Ok(path) = std::env::var("HYPRIX_DUMP") {
            static DUMPED: AtomicBool = AtomicBool::new(false);
            if !DUMPED.swap(true, Ordering::Relaxed) {
                if let Err(error) = dump_frame(pixels, w, h, &path) {
                    eprintln!("hyprmatrix: dump failed: {error}");
                }
            }
        }
        self.layer().wl_surface().set_buffer_scale(1);
        self.buffers[index]
            .attach_to(self.layer().wl_surface())
            .map_err(|e| e.to_string())?;
        self.layer()
            .wl_surface()
            .damage_buffer(0, 0, w as i32, h as i32);
        self.layer()
            .wl_surface()
            .frame(qh, self.layer().wl_surface().clone());
        self.layer().commit();
        self.ready = false;
        self.last = Instant::now();
        Ok(())
    }
    fn close_menu(&mut self) -> Result<(), String> {
        self.menu = false;
        self.menu_drag = None;
        self.workspace_allowed = self.config.visible_on(self.current_workspace.as_deref());
        self.input_region()?;
        self.layer().commit();
        self.update_visibility()?;
        self.wake_draw();
        Ok(())
    }
    fn click_row(&mut self, x: f64, y: f64) -> Result<(), String> {
        if !self.menu {
            return Ok(());
        }
        let rect = self.menu_rect_at();
        let Some(row) = render::menu_row(rect, x, y) else {
            return Ok(());
        };
        let old = self.config.clone();
        let action = render::adjust(&mut self.config, row, x >= (rect.0 + rect.2 / 2) as f64);
        if !["hide", "close", "quit", "refresh"].contains(&action) {
            if let Err(error) = self.config.save() {
                self.config = old;
                self.status = format!("Save failed: {error}");
                self.wake_draw();
                return Ok(());
            }
            self.status.clear();
            self.renderer.prepare(&self.config);
        }
        match action {
            "resize" => self.place()?,
            "refresh" => self.refresh.store(true, Ordering::Relaxed),
            "hide" => self.visibility(false)?,
            "close" => self.close_menu()?,
            "quit" => self.exit = true,
            _ => {}
        }
        self.wake_draw();
        Ok(())
    }
}
impl CompositorHandler for Desktop {
    fn scale_factor_changed(
        &mut self,
        _: &Connection,
        _: &QueueHandle<Self>,
        _: &wl_surface::WlSurface,
        _: i32,
    ) {
    }
    fn transform_changed(
        &mut self,
        _: &Connection,
        _: &QueueHandle<Self>,
        _: &wl_surface::WlSurface,
        _: wl_output::Transform,
    ) {
    }
    fn frame(&mut self, _: &Connection, _: &QueueHandle<Self>, _: &wl_surface::WlSurface, _: u32) {
        dbg_event("frame");
        self.ready = true;
    }
    fn surface_enter(
        &mut self,
        _: &Connection,
        _: &QueueHandle<Self>,
        _: &wl_surface::WlSurface,
        _: &wl_output::WlOutput,
    ) {
    }
    fn surface_leave(
        &mut self,
        _: &Connection,
        _: &QueueHandle<Self>,
        _: &wl_surface::WlSurface,
        _: &wl_output::WlOutput,
    ) {
    }
}
impl LayerShellHandler for Desktop {
    fn closed(&mut self, _: &Connection, _: &QueueHandle<Self>, _: &LayerSurface) {
        self.exit = true;
    }
    fn configure(
        &mut self,
        _: &Connection,
        _: &QueueHandle<Self>,
        _: &LayerSurface,
        c: LayerSurfaceConfigure,
        _: u32,
    ) {
        let (w, h) = c.new_size;
        dbg_event(&format!("configure {w}x{h}"));
        if w > 0 {
            self.width = w;
        }
        if h > 0 {
            self.height = h;
        }
        self.buffers.clear();
        self.configured = true;
        self.ready = true;
        if let Err(e) = self.input_region() {
            self.error = Some(e);
            self.exit = true;
        }
    }
}
impl ShmHandler for Desktop {
    fn shm_state(&mut self) -> &mut Shm {
        &mut self.shm
    }
}
impl OutputHandler for Desktop {
    fn output_state(&mut self) -> &mut OutputState {
        &mut self.outputs
    }
    fn new_output(&mut self, _: &Connection, _: &QueueHandle<Self>, _: wl_output::WlOutput) {}
    fn update_output(&mut self, _: &Connection, _: &QueueHandle<Self>, o: wl_output::WlOutput) {
        if self.target.as_ref() == Some(&o) && self.layer.is_some() {
            self.update_screen();
            if let Err(e) = self.place() {
                self.error = Some(e);
                self.exit = true;
            }
        }
    }
    fn output_destroyed(&mut self, _: &Connection, _: &QueueHandle<Self>, o: wl_output::WlOutput) {
        if self.target.as_ref() == Some(&o) {
            self.exit = true;
        }
    }
}
impl ProvidesRegistryState for Desktop {
    fn registry(&mut self) -> &mut RegistryState {
        &mut self.registry
    }
    registry_handlers![OutputState, SeatState];
}
impl SeatHandler for Desktop {
    fn seat_state(&mut self) -> &mut SeatState {
        &mut self.seats
    }
    fn new_seat(&mut self, _: &Connection, _: &QueueHandle<Self>, _: wl_seat::WlSeat) {}
    fn new_capability(
        &mut self,
        _: &Connection,
        qh: &QueueHandle<Self>,
        seat: wl_seat::WlSeat,
        cap: Capability,
    ) {
        if cap == Capability::Pointer && self.pointer.is_none() {
            self.pointer = self.seats.get_pointer(qh, &seat).ok();
        }
    }
    fn remove_capability(
        &mut self,
        _: &Connection,
        _: &QueueHandle<Self>,
        _: wl_seat::WlSeat,
        cap: Capability,
    ) {
        if cap == Capability::Pointer {
            if let Some(p) = self.pointer.take() {
                p.release();
            }
        }
    }
    fn remove_seat(&mut self, _: &Connection, _: &QueueHandle<Self>, _: wl_seat::WlSeat) {}
}
impl PointerHandler for Desktop {
    fn pointer_frame(
        &mut self,
        _: &Connection,
        _: &QueueHandle<Self>,
        _: &wl_pointer::WlPointer,
        events: &[PointerEvent],
    ) {
        for event in events {
            if &event.surface != self.layer().wl_surface() {
                continue;
            }
            let (x, y) = event.position;
            let over_menu = |desktop: &Self| {
                let (mx, my, mw, mh) = desktop.menu_rect_at();
                x >= mx as f64
                    && x < (mx + mw) as f64
                    && y >= my as f64
                    && y < (my + mh) as f64
            };
            let result = match &event.kind {
                PointerEventKind::Press { button: 0x111, .. } => {
                    if x >= self.width.saturating_sub(44) as f64 && y < 44.0 {
                        if self.menu {
                            self.close_menu()
                        } else {
                            self.menu = true;
                            self.menu_drag = None;
                            let out = self.input_region();
                            if out.is_ok() {
                                self.layer().commit();
                                self.wake_draw();
                            }
                            out
                        }
                    } else if self.menu && over_menu(self) {
                        self.close_menu()
                    } else {
                        Ok(())
                    }
                }
                PointerEventKind::Press { button: 0x110, .. } => {
                    if self.menu && over_menu(self) {
                        let (mx, my, _, _) = self.menu_rect_at();
                        self.menu_drag = Some(MenuDrag {
                            grab: (x, y),
                            origin: (mx, my),
                            start: (self.config.x, self.config.y),
                            moved: false,
                        });
                    }
                    Ok(())
                }
                PointerEventKind::Motion { .. } => {
                    let mut out: Result<(), String> = Ok(());
                    if let Some(drag) = &mut self.menu_drag {
                        let (dx, dy) = (x - drag.grab.0, y - drag.grab.1);
                        if !drag.moved
                            && (dx.abs() >= render::DRAG_THRESHOLD
                                || dy.abs() >= render::DRAG_THRESHOLD)
                        {
                            drag.moved = true;
                        }
                        if drag.moved {
                            if self.config.fullscreen {
                                let (nx, ny) = render::clamp_menu_pos(
                                    (
                                        (drag.origin.0 as f64 + dx).max(0.0) as u32,
                                        (drag.origin.1 as f64 + dy).max(0.0) as u32,
                                    ),
                                    (self.width, self.height),
                                );
                                self.menu_pos = Some((nx, ny));
                                out = self.input_region();
                                if out.is_ok() {
                                    self.layer().commit();
                                }
                            } else {
                                let avail_w =
                                    self.screen.0.saturating_sub(self.width).max(1) as f64;
                                let avail_h =
                                    self.screen.1.saturating_sub(self.height).max(1) as f64;
                                self.config.x =
                                    (drag.start.0 as f64 + dx / avail_w).clamp(0.0, 1.0) as f32;
                                self.config.y =
                                    (drag.start.1 as f64 + dy / avail_h).clamp(0.0, 1.0) as f32;
                                self.reposition();
                            }
                            self.wake_draw();
                        }
                    }
                    out
                }
                PointerEventKind::Release { button: 0x110, .. } => {
                    let mut out: Result<(), String> = Ok(());
                    if let Some(drag) = self.menu_drag.take() {
                        out = if !drag.moved {
                            self.click_row(drag.grab.0, drag.grab.1)
                        } else {
                            if !self.config.fullscreen {
                                if let Err(error) = self.config.save() {
                                    self.status = format!("Save failed: {error}");
                                }
                            }
                            self.wake_draw();
                            Ok(())
                        };
                    }
                    if out.is_ok() && self.region_drag.is_some() {
                        out = self.end_region_drag(true);
                    }
                    out
                }
                _ => Ok(()),
            };
            if let Err(error) = result {
                self.error = Some(error);
                self.exit = true;
            }
        }
    }
}
delegate_compositor!(Desktop);
delegate_layer!(Desktop);
delegate_output!(Desktop);
delegate_registry!(Desktop);
delegate_shm!(Desktop);
delegate_seat!(Desktop);
delegate_pointer!(Desktop);

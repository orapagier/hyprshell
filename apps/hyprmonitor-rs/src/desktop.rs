use crate::{
    collect::{Collector, Snapshot, WorkerCommand},
    config::Config,
    render::Renderer,
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
    os::unix::net::{UnixListener, UnixStream},
    path::PathBuf,
    sync::{
        atomic::{AtomicBool, Ordering},
        mpsc, Arc, Mutex,
    },
    thread,
    time::Duration,
};
use wayland_client::{
    globals::registry_queue_init,
    protocol::{wl_output, wl_pointer, wl_seat, wl_shm, wl_surface},
    Connection, QueueHandle,
};

enum Event {
    Sample,
    Command(String),
    Workspace(String),
    WorkspaceError(String),
}

pub fn socket_path() -> Result<PathBuf, String> {
    let dir = std::env::var_os("XDG_RUNTIME_DIR").ok_or("XDG_RUNTIME_DIR is not set")?;
    Ok(PathBuf::from(dir).join("hyprmonitor.sock"))
}

pub fn control(command: &str) -> Result<(), String> {
    let mut stream =
        UnixStream::connect(socket_path()?).map_err(|e| format!("No running Hyprmonitor: {e}"))?;
    stream
        .set_read_timeout(Some(Duration::from_secs(2)))
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
        Err(format!("Control failed: {reply}"))
    }
}

pub fn run(config: Config) -> Result<(), String> {
    let connection =
        Connection::connect_to_env().map_err(|e| format!("Cannot connect to Wayland: {e}"))?;
    let (globals, queue) = registry_queue_init(&connection).map_err(|e| e.to_string())?;
    let qh = queue.handle();
    let compositor = CompositorState::bind(&globals, &qh).map_err(|e| e.to_string())?;
    let shell = LayerShell::bind(&globals, &qh)
        .map_err(|e| format!("Compositor needs wlr-layer-shell: {e}"))?;
    let shm = Shm::bind(&globals, &qh).map_err(|e| e.to_string())?;
    let pool = SlotPool::new(config.width as usize * config.height as usize * 8, &shm)
        .map_err(|e| e.to_string())?;
    let renderer = Renderer::new(config.clone())?;
    let (collector_tx, collector_rx) = mpsc::channel();
    let initially_visible = config.visible_on(None);
    let mut state = Desktop {
        registry: RegistryState::new(&globals),
        seats: SeatState::new(&globals, &qh),
        pointer: None,
        shell_state: Some(crate::context::DesktopContext {
            x: config.x,
            y: config.y,
            width: config.width,
            height: config.height,
            ..crate::context::DesktopContext::default()
        }),
        drag: None,
        outputs: OutputState::new(&globals, &qh),
        shm,
        pool,
        layer: None,
        buffers: vec![],
        renderer,
        width: config.width,
        height: config.height,
        scale: 1,
        configured: false,
        dirty: true,
        exit: false,
        error: None,
        user_visible: true,
        workspace_allowed: initially_visible,
        visible: initially_visible,
        data: Snapshot::default(),
        collector_tx,
        config: config.clone(),
        menu: crate::ui::SettingsMenu::default(),
        current_workspace: None,
    };
    let mut queue = queue;
    queue.roundtrip(&mut state).map_err(|e| e.to_string())?;
    let target = state.outputs.outputs().find(|o| {
        config.output.as_ref().is_none_or(|name| {
            state
                .outputs
                .info(o)
                .is_some_and(|i| i.name.as_ref() == Some(name))
        })
    });
    if config.output.is_some() && target.is_none() {
        return Err(format!("Output {:?} is not connected", config.output));
    }
    let target_name = target
        .as_ref()
        .and_then(|o| state.outputs.info(o))
        .and_then(|i| i.name)
        .unwrap_or_default();
    let displays: Vec<_> = state
        .outputs
        .outputs()
        .filter_map(|o| state.outputs.info(&o))
        .map(|info| {
            let mode = info.modes.iter().find(|m| m.current);
            crate::context::Display {
                name: info.name.unwrap_or_default(),
                width: mode.map(|m| m.dimensions.0.max(0) as u32).unwrap_or(0),
                height: mode.map(|m| m.dimensions.1.max(0) as u32).unwrap_or(0),
                refresh_rate: mode.map(|m| m.refresh_rate as f64 / 1000.0),
                scale: Some(info.scale_factor as f64),
            }
        })
        .collect();
    if let Some(info) = target.as_ref().and_then(|o| state.outputs.info(o)) {
        let mode = info.modes.iter().find(|m| m.current);
        let factor = info.scale_factor.max(1);
        let size = info
            .logical_size
            .or_else(|| mode.map(|m| (m.dimensions.0 / factor, m.dimensions.1 / factor)));
        if let (Some(context), Some((w, h))) = (&mut state.shell_state, size) {
            context.screen_width = w.max(1) as u32;
            context.screen_height = h.max(1) as u32;
            context.output = target_name.clone();
            context.displays = displays;
            state.width = state.width.min(context.screen_width);
            state.height = state.height.min(context.screen_height);
            state.data.context = context.clone();
        }
    }
    let surface = compositor.create_surface(&qh);
    if config.click_through {
        let region = Region::new(&compositor).map_err(|e| e.to_string())?;
        surface.set_input_region(Some(region.wl_region()));
    }
    let layer = shell.create_layer_surface(
        &qh,
        surface,
        Layer::Bottom,
        Some("hyprmonitor"),
        target.as_ref(),
    );
    layer.set_anchor(Anchor::TOP | Anchor::LEFT);
    layer.set_keyboard_interactivity(KeyboardInteractivity::None);
    layer.set_exclusive_zone(-1);
    layer.set_size(state.width, state.height);
    state.layer = Some(layer);
    state.place();
    let (listener, _socket_guard) = crate::ipc::bind(socket_path()?)?;
    let (sender, events) = channel::channel();
    let latest = Arc::new(Mutex::new(None));
    let queued = Arc::new(AtomicBool::new(false));
    let worker = start_collector(
        config.clone(),
        initially_visible,
        collector_rx,
        sender.clone(),
        latest.clone(),
        queued.clone(),
    );
    start_control(listener, sender.clone());
    if std::env::var_os("HYPRLAND_INSTANCE_SIGNATURE").is_some_and(|s| !s.is_empty()) {
        start_workspaces(config.clone(), target_name, sender.clone());
    }
    let mut event_loop = EventLoop::<Desktop>::try_new().map_err(|e| e.to_string())?;
    WaylandSource::new(connection, queue)
        .insert(event_loop.handle())
        .map_err(|e| e.to_string())?;
    event_loop
        .handle()
        .insert_source(events, move |event, _, state| {
            if let ChannelEvent::Msg(event) = event {
                match event {
                    Event::Sample => {
                        let mut latest = latest.lock().unwrap();
                        if let Some(data) = latest.take() {
                            let mut context = state.data.context.clone();
                            context.connection = data.context.connection.clone();
                            context.bluetooth = data.context.bluetooth.clone();
                            context.wifi_signal = data.context.wifi_signal;
                            state.data = data;
                            state.data.context = context;
                            state.dirty = true;
                        }
                        queued.store(false, Ordering::Release);
                    }
                    Event::Command(command) => match command.as_str() {
                        "settings" => {
                            state.menu.open = false;
                            state.menu.show(
                                20.0,
                                20.0,
                                state.width * state.scale as u32,
                                state.height * state.scale as u32,
                            );
                            state.user_visible = true;
                            state.workspace_allowed = true;
                            state.update_visibility();
                            state.dirty = true;
                        }
                        "toggle-workspace" => match focused_workspace() {
                            Ok(workspace) => {
                                state.user_visible = true;
                                let old = state
                                    .config
                                    .workspace_overrides
                                    .get(&workspace)
                                    .copied()
                                    .unwrap_or(state.config.enabled);
                                state.config.workspace_overrides.insert(workspace, !old);
                                if let Err(error) = state.config.save() {
                                    eprintln!("{error}");
                                }
                                state.workspace_allowed =
                                    state.config.visible_on(state.current_workspace.as_deref());
                                state.update_visibility();
                            }
                            Err(error) => eprintln!("{error}"),
                        },
                        "quit" => state.exit = true,
                        "show" => {
                            state.user_visible = true;
                            state.update_visibility();
                        }
                        "hide" => {
                            state.user_visible = false;
                            state.update_visibility();
                        }
                        "toggle" => {
                            state.user_visible = !state.user_visible;
                            state.update_visibility();
                        }
                        _ => {}
                    },
                    Event::Workspace(workspace) => {
                        state.workspace_allowed = state.config.visible_on(Some(&workspace));
                        state.current_workspace = Some(workspace);
                        state.update_visibility();
                    }
                    Event::WorkspaceError(error) => {
                        eprintln!("Workspace tracking stopped: {error}");
                        state.workspace_allowed = state.config.workspaces.is_empty()
                            && state.config.workspace_overrides.is_empty()
                            && state.config.enabled;
                        state.update_visibility();
                    }
                }
            }
        })
        .map_err(|e| e.to_string())?;
    if state.visible {
        state.layer().commit();
    }
    let result = (|| {
        while !state.exit {
            event_loop
                .dispatch(None, &mut state)
                .map_err(|e| e.to_string())?;
            state.draw()?;
        }
        if let Some(error) = state.error.take() {
            return Err(error);
        }
        Ok(())
    })();
    drop(state.collector_tx);
    let _ = worker.join();
    result
}

fn anchor(name: &str) -> Anchor {
    (if name.starts_with("bottom") {
        Anchor::BOTTOM
    } else {
        Anchor::TOP
    }) | (if name.ends_with("left") {
        Anchor::LEFT
    } else {
        Anchor::RIGHT
    })
}

fn start_collector(
    mut config: Config,
    mut visible: bool,
    rx: mpsc::Receiver<WorkerCommand>,
    sender: channel::Sender<Event>,
    latest: Arc<Mutex<Option<Snapshot>>>,
    queued: Arc<AtomicBool>,
) -> thread::JoinHandle<()> {
    thread::spawn(move || {
        let mut collector = Collector::new(config.clone());
        loop {
            if visible {
                let sample = collector.sample();
                let mut slot = latest.lock().unwrap();
                *slot = Some(sample);
                if !queued.swap(true, Ordering::AcqRel) && sender.send(Event::Sample).is_err() {
                    break;
                }
                drop(slot);
            }
            let command = if visible {
                rx.recv_timeout(Duration::from_millis(config.interval_ms))
            } else {
                rx.recv().map_err(|_| mpsc::RecvTimeoutError::Disconnected)
            };
            match command {
                Ok(WorkerCommand::Configure(next)) => {
                    config = *next;
                    collector.configure(config.clone());
                }
                Ok(WorkerCommand::Visible(value)) => {
                    if value && !visible {
                        collector.resume();
                    }
                    visible = value;
                }
                Err(mpsc::RecvTimeoutError::Timeout) => {}
                Err(mpsc::RecvTimeoutError::Disconnected) => break,
            }
        }
    })
}

fn start_control(listener: UnixListener, sender: channel::Sender<Event>) {
    thread::spawn(move || {
        for stream in listener.incoming() {
            let Ok(mut stream) = stream else {
                break;
            };
            let _ = stream.set_read_timeout(Some(Duration::from_secs(1)));
            let _ = stream.set_write_timeout(Some(Duration::from_secs(1)));
            let mut command = String::new();
            if (&mut stream).take(32).read_to_string(&mut command).is_err() {
                continue;
            }
            if ![
                "show",
                "hide",
                "toggle",
                "quit",
                "settings",
                "toggle-workspace",
            ]
            .contains(&command.trim())
            {
                let _ = stream.write_all(b"invalid command\n");
                continue;
            }
            if sender.send(Event::Command(command.trim().into())).is_err() {
                break;
            }
            let _ = stream.write_all(b"ok\n");
        }
    });
}

fn hypr_path(name: &str) -> Result<PathBuf, String> {
    let signature = std::env::var_os("HYPRLAND_INSTANCE_SIGNATURE")
        .ok_or("workspaces requires a Hyprland session")?;
    let runtime = std::env::var_os("XDG_RUNTIME_DIR").ok_or("XDG_RUNTIME_DIR missing")?;
    Ok(PathBuf::from(runtime)
        .join("hypr")
        .join(signature)
        .join(name))
}

fn workspace_name(output: &str) -> Result<String, String> {
    let mut stream = UnixStream::connect(hypr_path(".socket.sock")?).map_err(|e| e.to_string())?;
    stream
        .set_read_timeout(Some(Duration::from_secs(1)))
        .map_err(|e| e.to_string())?;
    stream.write_all(b"j/monitors").map_err(|e| e.to_string())?;
    let mut data = String::new();
    stream
        .take(256 * 1024)
        .read_to_string(&mut data)
        .map_err(|e| e.to_string())?;
    let monitors: Vec<serde_json::Value> =
        serde_json::from_str(&data).map_err(|e| e.to_string())?;
    let monitor = monitors
        .iter()
        .find(|m| m["name"].as_str() == Some(output))
        .ok_or("Target output is unavailable")?;
    let workspace = monitor["activeWorkspace"]["name"]
        .as_str()
        .ok_or("Workspace name unavailable")?;
    Ok(workspace.to_owned())
}

pub fn focused_workspace() -> Result<String, String> {
    let mut stream = UnixStream::connect(hypr_path(".socket.sock")?).map_err(|e| e.to_string())?;
    stream
        .set_read_timeout(Some(Duration::from_secs(1)))
        .map_err(|e| e.to_string())?;
    stream
        .write_all(b"j/activeworkspace")
        .map_err(|e| e.to_string())?;
    let mut text = String::new();
    stream
        .take(65536)
        .read_to_string(&mut text)
        .map_err(|e| e.to_string())?;
    let value: serde_json::Value = serde_json::from_str(&text).map_err(|e| e.to_string())?;
    let id = value["id"]
        .as_u64()
        .filter(|n| (1..=99).contains(n))
        .ok_or("Choose a numbered workspace (1–99)")?;
    Ok(id.to_string())
}

fn start_workspaces(_config: Config, output: String, sender: channel::Sender<Event>) {
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

struct Desktop {
    seats: SeatState,
    pointer: Option<wl_pointer::WlPointer>,
    shell_state: Option<crate::context::DesktopContext>,
    drag: Option<Drag>,
    registry: RegistryState,
    outputs: OutputState,
    shm: Shm,
    pool: SlotPool,
    layer: Option<LayerSurface>,
    buffers: Vec<Buffer>,
    renderer: Renderer,
    width: u32,
    height: u32,
    scale: i32,
    configured: bool,
    dirty: bool,
    exit: bool,
    error: Option<String>,
    user_visible: bool,
    workspace_allowed: bool,
    visible: bool,
    data: Snapshot,
    collector_tx: mpsc::Sender<WorkerCommand>,
    config: Config,
    menu: crate::ui::SettingsMenu,
    current_workspace: Option<String>,
}

impl Desktop {
    fn apply_settings(&mut self, effect: crate::ui::Effect) {
        if effect == crate::ui::Effect::Quit {
            self.exit = true;
            return;
        }
        self.renderer.configure(&self.config);
        let _ = self
            .collector_tx
            .send(WorkerCommand::Configure(Box::new(self.config.clone())));
        if effect == crate::ui::Effect::Resize {
            if let Some(context) = &mut self.shell_state {
                context.x = self.config.x;
                context.y = self.config.y;
                context.width = self.config.width;
                context.height = self.config.height;
                self.width = self.config.width.min(context.screen_width);
                self.height = self.config.height.min(context.screen_height);
                self.buffers.clear();
                self.place();
            }
        }
        if effect == crate::ui::Effect::Visibility {
            self.user_visible = true;
            self.workspace_allowed = self.config.visible_on(self.current_workspace.as_deref());
            self.update_visibility();
        }
        self.dirty = true;
    }
    fn place(&self) {
        if let Some(s) = &self.shell_state {
            let x = (s.x * s.screen_width.saturating_sub(self.width) as f64).round() as i32;
            let y = (s.y * s.screen_height.saturating_sub(self.height) as f64).round() as i32;
            self.layer().set_anchor(Anchor::TOP | Anchor::LEFT);
            self.layer().set_size(self.width, self.height);
            self.layer().set_margin(y, 0, 0, x);
        } else {
            self.layer().set_anchor(anchor(&self.config.anchor));
            self.layer().set_size(self.width, self.height);
            self.layer().set_margin(
                self.config.margin_y,
                self.config.margin_x,
                self.config.margin_y,
                self.config.margin_x,
            );
        }
        if self.configured {
            self.layer().commit();
        }
    }
    fn layer(&self) -> &LayerSurface {
        self.layer
            .as_ref()
            .expect("layer initialized before dispatch")
    }
    fn update_visibility(&mut self) {
        let visible = self.user_visible && self.workspace_allowed;
        if visible == self.visible {
            return;
        }
        self.visible = visible;
        let _ = self.collector_tx.send(WorkerCommand::Visible(visible));
        if visible {
            self.place();
            self.layer().set_exclusive_zone(-1);
            self.layer()
                .set_keyboard_interactivity(KeyboardInteractivity::None);
            self.layer().commit();
            self.dirty = true;
        } else {
            self.layer().wl_surface().attach(None, 0, 0);
            self.layer().commit();
            self.configured = false;
        }
    }

    fn draw(&mut self) -> Result<(), String> {
        if !self.visible || !self.configured || !self.dirty {
            return Ok(());
        }
        let w = self.width * self.scale as u32;
        let h = self.height * self.scale as u32;
        if w as u64 * h as u64 > 16_000_000 {
            return Err("Monitor buffer exceeds the 16 megapixel resource limit".into());
        }
        if self.buffers.is_empty() {
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
            return Ok(());
        };
        let mut pix = self.renderer.render(&self.data, w, h)?;
        self.renderer
            .draw_settings(&mut pix, &self.menu, &self.config);
        let canvas = self
            .pool
            .canvas(&self.buffers[index])
            .ok_or("SHM buffer is busy")?;
        for (src, dst) in pix.data().chunks_exact(4).zip(canvas.chunks_exact_mut(4)) {
            // Native-endian ARGB8888, premultiplied; tiny-skia is RGBA.
            dst.copy_from_slice(
                &u32::from_be_bytes([src[3], src[0], src[1], src[2]]).to_ne_bytes(),
            );
        }
        self.layer().wl_surface().set_buffer_scale(self.scale);
        self.buffers[index]
            .attach_to(self.layer().wl_surface())
            .map_err(|e| e.to_string())?;
        self.layer()
            .wl_surface()
            .damage_buffer(0, 0, w as i32, h as i32);
        self.layer().commit();
        self.dirty = false;
        Ok(())
    }
}

impl CompositorHandler for Desktop {
    fn scale_factor_changed(
        &mut self,
        _: &Connection,
        _: &QueueHandle<Self>,
        _: &wl_surface::WlSurface,
        factor: i32,
    ) {
        self.scale = factor.clamp(1, 4);
        self.buffers.clear();
        self.dirty = true;
    }
    fn transform_changed(
        &mut self,
        _: &Connection,
        _: &QueueHandle<Self>,
        _: &wl_surface::WlSurface,
        _: wl_output::Transform,
    ) {
    }
    fn frame(&mut self, _: &Connection, _: &QueueHandle<Self>, _: &wl_surface::WlSurface, _: u32) {}
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
        let changed = (w > 0 && w != self.width) || (h > 0 && h != self.height);
        if w > 3840 || h > 2160 {
            self.error = Some(format!("Compositor requested unsupported size {w}×{h}"));
            self.exit = true;
            return;
        }
        if w > 0 {
            self.width = w;
        }
        if h > 0 {
            self.height = h;
        }
        if changed || !self.configured {
            self.buffers.clear();
            self.dirty = true;
        }
        self.configured = true;
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
    fn update_output(&mut self, _: &Connection, _: &QueueHandle<Self>, _: wl_output::WlOutput) {}
    fn output_destroyed(&mut self, _: &Connection, _: &QueueHandle<Self>, _: wl_output::WlOutput) {}
}
impl ProvidesRegistryState for Desktop {
    fn registry(&mut self) -> &mut RegistryState {
        &mut self.registry
    }
    registry_handlers![OutputState, SeatState];
}
delegate_compositor!(Desktop);
delegate_layer!(Desktop);
delegate_output!(Desktop);
delegate_registry!(Desktop);
delegate_shm!(Desktop);
delegate_seat!(Desktop);
delegate_pointer!(Desktop);

struct Drag {
    origin: (f64, f64),
    size: (u32, u32),
    resize: bool,
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
        capability: Capability,
    ) {
        if capability == Capability::Pointer && self.pointer.is_none() {
            self.pointer = self.seats.get_pointer(qh, &seat).ok();
        }
    }
    fn remove_capability(
        &mut self,
        _: &Connection,
        _: &QueueHandle<Self>,
        _: wl_seat::WlSeat,
        capability: Capability,
    ) {
        if capability == Capability::Pointer {
            if let Some(pointer) = self.pointer.take() {
                pointer.release();
            }
            self.drag = None;
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
            if let PointerEventKind::Press { button: 0x111, .. } = event.kind {
                self.drag = None;
                self.menu.show(
                    event.position.0 as f32 * self.scale as f32,
                    event.position.1 as f32 * self.scale as f32,
                    self.width * self.scale as u32,
                    self.height * self.scale as u32,
                );
                self.dirty = true;
                continue;
            }
            if self.menu.open {
                if let PointerEventKind::Press { button: 0x110, .. } = event.kind {
                    if let Some(effect) = self.menu.click(
                        event.position.0 as f32 * self.scale as f32,
                        event.position.1 as f32 * self.scale as f32,
                        self.width * self.scale as u32,
                        self.height * self.scale as u32,
                        &mut self.config,
                    ) {
                        self.apply_settings(effect);
                    }
                }
                if let PointerEventKind::Axis { vertical, .. } = event.kind {
                    self.menu.wheel(
                        -vertical.absolute as f32,
                        &self.config,
                        self.height * self.scale as u32,
                    );
                    self.dirty = true;
                }
                continue;
            }
            match event.kind {
                PointerEventKind::Press { button: 0x110, .. } => {
                    self.drag = Some(Drag {
                        origin: event.position,
                        size: (self.width, self.height),
                        resize: event.position.0 > self.width as f64 - 32.0
                            && event.position.1 > self.height as f64 - 32.0,
                    })
                }
                PointerEventKind::Motion { .. } => {
                    let (Some(drag), Some(shell)) = (&self.drag, &mut self.shell_state) else {
                        continue;
                    };
                    let x = shell.x * shell.screen_width.saturating_sub(self.width) as f64;
                    let y = shell.y * shell.screen_height.saturating_sub(self.height) as f64;
                    if drag.resize {
                        self.width = ((drag.size.0 as f64 + event.position.0 - drag.origin.0)
                            .clamp(240.0, 3840.0) as u32)
                            .min(shell.screen_width.saturating_sub(x as u32).max(1));
                        self.height = ((drag.size.1 as f64 + event.position.1 - drag.origin.1)
                            .clamp(420.0, 2160.0) as u32)
                            .min(shell.screen_height.saturating_sub(y as u32).max(1));
                        shell.width = self.width;
                        shell.height = self.height;
                        shell.x = x / (shell.screen_width.saturating_sub(self.width).max(1)) as f64;
                        shell.y =
                            y / (shell.screen_height.saturating_sub(self.height).max(1)) as f64;
                        self.buffers.clear();
                        self.dirty = true;
                    } else {
                        shell.x = ((x + event.position.0 - drag.origin.0)
                            / shell.screen_width.saturating_sub(self.width).max(1) as f64)
                            .clamp(0.0, 1.0);
                        shell.y = ((y + event.position.1 - drag.origin.1)
                            / shell.screen_height.saturating_sub(self.height).max(1) as f64)
                            .clamp(0.0, 1.0);
                    }
                    self.place();
                }
                PointerEventKind::Release { button: 0x110, .. } if self.drag.take().is_some() => {
                    if let Some(shell) = &self.shell_state {
                        self.config.x = shell.x;
                        self.config.y = shell.y;
                        self.config.width = shell.width;
                        self.config.height = shell.height;
                        if let Err(error) = self.config.save() {
                            self.menu.status = error;
                            self.menu.open = true;
                            self.dirty = true;
                        }
                    }
                }
                _ => {}
            }
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn edge_anchors_are_exclusive() {
        for name in ["top-left", "top-right", "bottom-left", "bottom-right"] {
            let a = anchor(name);
            assert_ne!(a.contains(Anchor::LEFT), a.contains(Anchor::RIGHT));
            assert_ne!(a.contains(Anchor::TOP), a.contains(Anchor::BOTTOM));
        }
    }
}

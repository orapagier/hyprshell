//! Ordinary Wayland/X11 window fallback. The same Rust renderer and settings menu
//! run here; no layer-shell, Hyprland, Quickshell or GPU dependency is required.
use crate::{
    collect::{Collector, Snapshot, WorkerCommand},
    config::Config,
    render::Renderer,
    ui::{Effect, SettingsMenu},
};
use std::{
    io::{Read, Write},
    num::NonZeroU32,
    sync::{
        atomic::{AtomicBool, Ordering},
        mpsc, Arc, Mutex,
    },
    thread,
    time::{Duration, Instant},
};
use winit::{
    application::ApplicationHandler,
    dpi::LogicalSize,
    event::{ElementState, MouseButton, MouseScrollDelta, WindowEvent},
    event_loop::{ActiveEventLoop, ControlFlow, EventLoop},
    keyboard::{Key, NamedKey},
    window::{Window, WindowId},
};

enum Event {
    Sample,
    Command(String),
}
pub fn run(config: Config) -> Result<(), String> {
    let event_loop = EventLoop::<Event>::with_user_event()
        .build()
        .map_err(|e| format!("Cannot create a desktop window: {e}"))?;
    let proxy = event_loop.create_proxy();
    let renderer = Renderer::new(config.clone())?;
    let (listener, _lease) = crate::ipc::bind(crate::desktop::socket_path()?)?;
    let control = proxy.clone();
    thread::spawn(move || {
        for stream in listener.incoming() {
            let Ok(mut stream) = stream else {
                break;
            };
            let _ = stream.set_read_timeout(Some(Duration::from_secs(1)));
            let _ = stream.set_write_timeout(Some(Duration::from_secs(1)));
            let mut command = String::new();
            if (&mut stream).take(64).read_to_string(&mut command).is_err() {
                continue;
            }
            if ![
                "quit",
                "show",
                "hide",
                "toggle",
                "settings",
                "toggle-workspace",
            ]
            .contains(&command.trim())
            {
                let _ = stream.write_all(b"invalid command\n");
                continue;
            }
            if control
                .send_event(Event::Command(command.trim().into()))
                .is_err()
            {
                break;
            }
            let _ = stream.write_all(b"ok\n");
        }
    });
    let latest = Arc::new(Mutex::new(None));
    let pending = Arc::new(AtomicBool::new(false));
    let (worker_tx, worker_rx) = mpsc::channel();
    let worker_latest = latest.clone();
    let worker_pending = pending.clone();
    let mut worker_config = config.clone();
    let worker = thread::spawn(move || {
        let mut collector = Collector::new(worker_config.clone());
        let mut visible = worker_config.enabled;
        loop {
            if visible {
                let sample = collector.sample();
                let mut latest = worker_latest.lock().unwrap();
                *latest = Some(sample);
                if !worker_pending.swap(true, Ordering::AcqRel)
                    && proxy.send_event(Event::Sample).is_err()
                {
                    break;
                }
                drop(latest);
            }
            let command = if visible {
                worker_rx.recv_timeout(Duration::from_millis(worker_config.interval_ms))
            } else {
                worker_rx
                    .recv()
                    .map_err(|_| mpsc::RecvTimeoutError::Disconnected)
            };
            match command {
                Ok(WorkerCommand::Visible(next)) => {
                    if next && !visible {
                        collector.resume();
                    }
                    visible = next;
                }
                Ok(WorkerCommand::Configure(next)) => {
                    worker_config = *next;
                    collector.configure(worker_config.clone());
                }
                Err(mpsc::RecvTimeoutError::Timeout) => {}
                Err(mpsc::RecvTimeoutError::Disconnected) => break,
            }
        }
    });
    let mut app = App {
        visible: config.enabled,
        config,
        renderer,
        window: None,
        surface: None,
        context: None,
        data: Snapshot::default(),
        menu: SettingsMenu::default(),
        cursor: (0.0, 0.0),
        explorer: crate::explorer::Explorer::default(),
        page: 0,
        scroll: 0,
        latest,
        pending,
        worker: Some(worker_tx),
        error: None,
        occluded: false,
        save_at: None,
    };
    let result = event_loop.run_app(&mut app).map_err(|e| e.to_string());
    let error = app.error.take();
    drop(app);
    let _ = worker.join();
    result?;
    if let Some(error) = error {
        Err(error)
    } else {
        Ok(())
    }
}

struct App {
    config: Config,
    renderer: Renderer,
    window: Option<Arc<Window>>,
    surface: Option<softbuffer::Surface<Arc<Window>, Arc<Window>>>,
    context: Option<softbuffer::Context<Arc<Window>>>,
    data: Snapshot,
    menu: SettingsMenu,
    cursor: (f32, f32),
    explorer: crate::explorer::Explorer,
    page: usize,
    scroll: usize,
    latest: Arc<Mutex<Option<Snapshot>>>,
    pending: Arc<AtomicBool>,
    worker: Option<mpsc::Sender<WorkerCommand>>,
    visible: bool,
    occluded: bool,
    save_at: Option<Instant>,
    error: Option<String>,
}
impl App {
    fn fail(&mut self, event_loop: &ActiveEventLoop, error: String) {
        self.error = Some(error);
        event_loop.exit();
    }
    fn visibility(&mut self) {
        if let Some(window) = &self.window {
            window.set_visible(self.visible);
            if self.visible {
                window.request_redraw();
            }
        }
        if let Some(worker) = &self.worker {
            let _ = worker.send(WorkerCommand::Visible(self.visible && !self.occluded));
        }
    }
    fn apply(&mut self, effect: Effect, event_loop: &ActiveEventLoop) {
        if effect == Effect::Quit {
            event_loop.exit();
            return;
        }
        self.renderer.configure(&self.config);
        if let Some(worker) = &self.worker {
            let _ = worker.send(WorkerCommand::Configure(Box::new(self.config.clone())));
        }
        if effect == Effect::Visibility {
            self.visible = self.config.enabled;
            self.visibility();
        }
        if let Some(window) = &self.window {
            if effect == Effect::Resize {
                let _ = window
                    .request_inner_size(LogicalSize::new(self.config.width, self.config.height));
            }
            window.request_redraw();
        }
    }
    fn draw(&mut self) -> Result<(), String> {
        let Some(window) = &self.window else {
            return Ok(());
        };
        let size = window.inner_size();
        if size.width == 0 || size.height == 0 {
            return Ok(());
        }
        if size.width as u64 * size.height as u64 > 16_000_000 {
            return Err("Window exceeds the 16 megapixel rendering limit".into());
        }
        self.data.context.displays = window
            .available_monitors()
            .map(|m| crate::context::Display {
                name: m.name().unwrap_or_else(|| "Display".into()),
                width: m.size().width,
                height: m.size().height,
                refresh_rate: m.refresh_rate_millihertz().map(|n| n as f64 / 1000.0),
                scale: Some(m.scale_factor()),
            })
            .collect();
        let mut pix = self.renderer.render_window(
            &self.data,
            size.width,
            size.height,
            self.page,
            self.scroll,
            &self.explorer,
        )?;
        self.renderer
            .draw_settings(&mut pix, &self.menu, &self.config);
        let surface = self
            .surface
            .as_mut()
            .ok_or("Window surface is unavailable")?;
        surface
            .resize(
                NonZeroU32::new(size.width).unwrap(),
                NonZeroU32::new(size.height).unwrap(),
            )
            .map_err(|e| e.to_string())?;
        let mut buffer = surface.buffer_mut().map_err(|e| e.to_string())?;
        // The portable RGB surface has no alpha contract. Composite the same
        // glass-styled cards onto midnight rather than promise unsupported blur.
        for (destination, pixel) in buffer.iter_mut().zip(pix.data().chunks_exact(4)) {
            let inverse = 255 - pixel[3] as u32;
            let r = pixel[0] as u32 + 8 * inverse / 255;
            let g = pixel[1] as u32 + 14 * inverse / 255;
            let b = pixel[2] as u32 + 24 * inverse / 255;
            *destination = (r.min(255) << 16) | (g.min(255) << 8) | b.min(255);
        }
        buffer.present().map_err(|e| e.to_string())
    }
}
impl ApplicationHandler<Event> for App {
    fn resumed(&mut self, event_loop: &ActiveEventLoop) {
        if self.window.is_some() {
            return;
        }
        let attributes = Window::default_attributes()
            .with_title("Hyprmonitor")
            .with_inner_size(LogicalSize::new(self.config.width, self.config.height))
            .with_min_inner_size(LogicalSize::new(720, 540))
            .with_visible(self.visible);
        let result = (|| -> Result<(), String> {
            let window = Arc::new(
                event_loop
                    .create_window(attributes)
                    .map_err(|e| e.to_string())?,
            );
            let context = softbuffer::Context::new(window.clone()).map_err(|e| e.to_string())?;
            let surface =
                softbuffer::Surface::new(&context, window.clone()).map_err(|e| e.to_string())?;
            self.context = Some(context);
            self.surface = Some(surface);
            window.request_redraw();
            self.window = Some(window);
            Ok(())
        })();
        if let Err(error) = result {
            self.fail(event_loop, error);
        }
    }
    fn user_event(&mut self, event_loop: &ActiveEventLoop, event: Event) {
        match event {
            Event::Sample => {
                {
                    let mut latest = self.latest.lock().unwrap();
                    if let Some(data) = latest.take() {
                        if !self.explorer.paused {
                            self.data = data;
                        }
                    }
                    self.pending.store(false, Ordering::Release);
                }
                if let Some(window) = &self.window {
                    if self.visible {
                        window.request_redraw();
                    }
                }
            }
            Event::Command(command) => match command.as_str() {
                "quit" => event_loop.exit(),
                "show" => {
                    self.visible = true;
                    self.visibility();
                }
                "hide" => {
                    self.visible = false;
                    self.visibility();
                }
                "toggle" => {
                    self.visible = !self.visible;
                    self.visibility();
                }
                "settings" => {
                    self.menu.open = false;
                    self.visible = true;
                    self.visibility();
                    if let Some(window) = &self.window {
                        let size = window.inner_size();
                        self.menu.show(20.0, 20.0, size.width, size.height);
                        window.request_redraw();
                    }
                }
                "toggle-workspace" => match crate::desktop::focused_workspace() {
                    Ok(workspace) => {
                        let old = self
                            .config
                            .workspace_overrides
                            .get(&workspace)
                            .copied()
                            .unwrap_or(self.config.enabled);
                        self.config
                            .workspace_overrides
                            .insert(workspace.clone(), !old);
                        match self.config.save() {
                            Ok(()) => {
                                self.visible = self.config.visible_on(Some(&workspace));
                                self.visibility();
                            }
                            Err(error) => self.menu.status = error,
                        }
                    }
                    Err(error) => {
                        self.menu.status = error;
                        if let Some(window) = &self.window {
                            window.request_redraw();
                        }
                    }
                },
                _ => {}
            },
        }
    }
    fn window_event(&mut self, event_loop: &ActiveEventLoop, id: WindowId, event: WindowEvent) {
        let Some(window) = self.window.clone() else {
            return;
        };
        if window.id() != id {
            return;
        }
        match event {
            WindowEvent::CloseRequested => event_loop.exit(),
            WindowEvent::RedrawRequested => {
                if let Err(error) = self.draw() {
                    self.fail(event_loop, error);
                }
            }
            WindowEvent::Resized(size) => {
                if size.width > 0 && size.height > 0 {
                    let scale = window.scale_factor();
                    self.config.width = ((size.width as f64 / scale) as u32).clamp(240, 3840);
                    self.config.height = ((size.height as f64 / scale) as u32).clamp(420, 2160);
                    self.save_at = Some(Instant::now() + Duration::from_millis(300));
                    window.request_redraw();
                }
            }
            WindowEvent::ScaleFactorChanged { .. } => window.request_redraw(),
            WindowEvent::Occluded(value) => {
                self.occluded = value;
                self.visibility();
            }
            WindowEvent::CursorMoved { position, .. } => {
                self.cursor = (position.x as f32, position.y as f32)
            }
            WindowEvent::MouseInput {
                state: ElementState::Pressed,
                button: MouseButton::Right,
                ..
            } => {
                let size = window.inner_size();
                self.menu
                    .show(self.cursor.0, self.cursor.1, size.width, size.height);
                window.request_redraw();
            }
            WindowEvent::MouseInput {
                state: ElementState::Pressed,
                button: MouseButton::Left,
                ..
            } if self.menu.open => {
                let size = window.inner_size();
                if let Some(effect) = self.menu.click(
                    self.cursor.0,
                    self.cursor.1,
                    size.width,
                    size.height,
                    &mut self.config,
                ) {
                    self.apply(effect, event_loop);
                }
            }
            WindowEvent::MouseInput {
                state: ElementState::Pressed,
                button: MouseButton::Left,
                ..
            } => {
                let size = window.inner_size();
                use crate::explorer::{sort_at, visible_rows, CONTENT, RAIL, ROW, TABLE_TOP};
                let (x, y) = self.cursor;
                let width = size.width as f32;
                let height = size.height as f32;
                let content_width = width - CONTENT - 20.0;
                if x < RAIL {
                    if y >= height - 56.0 {
                        self.menu.show(CONTENT, 82.0, size.width, size.height);
                    } else if (82.0..82.0 + crate::explorer::PAGES.len() as f32 * 38.0).contains(&y)
                    {
                        self.page = ((y - 82.0) / 38.0) as usize;
                        self.scroll = 0;
                        self.explorer.searching = false;
                        self.explorer.confirming = false;
                    }
                } else if x >= width - 104.0 && (14.0..44.0).contains(&y) {
                    self.explorer.paused = !self.explorer.paused;
                } else if self.page == 1 && x >= CONTENT && x < width - 20.0 {
                    if (90.0..122.0).contains(&y) {
                        self.explorer.searching = true;
                    } else if (130.0..TABLE_TOP).contains(&y) {
                        let sort = sort_at((x - CONTENT) / content_width);
                        if sort == self.explorer.sort {
                            self.explorer.ascending = !self.explorer.ascending;
                        } else {
                            self.explorer.sort = sort;
                            self.explorer.ascending = sort == 2 || sort == 3;
                        }
                        self.scroll = 0;
                    } else if x >= width - 138.0 && (height - 70.0..height - 40.0).contains(&y) {
                        self.explorer.searching = false;
                        if let Some((pid, start)) = self.explorer.selected {
                            if self.explorer.confirming {
                                self.explorer.status = match crate::actions::end_task(pid, start) {
                                    Ok(()) => format!("Termination requested for PID {pid}"),
                                    Err(e) => e,
                                };
                                self.explorer.confirming = false;
                            } else {
                                self.explorer.confirming = true;
                                self.explorer.status.clear();
                            }
                        }
                    } else {
                        self.explorer.searching = false;
                        self.explorer.confirming = false;
                        let count = visible_rows(height);
                        if (TABLE_TOP..TABLE_TOP + count as f32 * ROW).contains(&y) {
                            let rows = self.explorer.rows(&self.data);
                            let start = self.scroll.min(rows.len().saturating_sub(count));
                            let index = start + ((y - TABLE_TOP) / ROW) as usize;
                            self.explorer.selected =
                                rows.get(index).map(|p| (p.pid, p.start_ticks));
                            self.explorer.status.clear();
                        }
                    }
                }
                window.request_redraw();
            }

            WindowEvent::MouseWheel { delta, .. } if !self.menu.open => {
                let y = match delta {
                    MouseScrollDelta::LineDelta(_, y) => y,
                    MouseScrollDelta::PixelDelta(p) => p.y as f32,
                };
                let count = if self.page == 0 {
                    self.data.top_cpu.len()
                } else if self.page == 1 {
                    self.explorer.rows(&self.data).len()
                } else {
                    self.explorer.section(&self.data, self.page).rows.len()
                };
                self.scroll = if y < 0.0 {
                    (self.scroll + 2).min(count.saturating_sub(if self.page == 1 {
                        crate::explorer::visible_rows(window.inner_size().height as f32)
                    } else {
                        1
                    }))
                } else {
                    self.scroll.saturating_sub(2)
                };
                window.request_redraw();
            }
            WindowEvent::MouseWheel { delta, .. } if self.menu.open => {
                let delta = match delta {
                    MouseScrollDelta::LineDelta(_, y) => y,
                    MouseScrollDelta::PixelDelta(p) => p.y as f32,
                };
                self.menu
                    .wheel(delta, &self.config, window.inner_size().height);
                window.request_redraw();
            }
            WindowEvent::KeyboardInput { event, .. }
                if event.state == ElementState::Pressed
                    && !self.menu.open
                    && self.page == 1
                    && self.explorer.searching =>
            {
                match event.logical_key {
                    Key::Named(NamedKey::Escape) => {
                        self.explorer.query.clear();
                        self.explorer.searching = false;
                    }
                    Key::Named(NamedKey::Enter) => self.explorer.searching = false,
                    Key::Named(NamedKey::Backspace) => {
                        self.explorer.query.pop();
                    }
                    Key::Character(text) => {
                        for ch in text.chars().filter(|c| !c.is_control()) {
                            if self.explorer.query.len() < 128 {
                                self.explorer.query.push(ch);
                            }
                        }
                    }
                    _ => {}
                }
                self.scroll = 0;
                window.request_redraw();
            }
            WindowEvent::KeyboardInput { event, .. }
                if event.state == ElementState::Pressed
                    && !self.menu.open
                    && !self.explorer.searching
                    && matches!(
                        event.logical_key,
                        Key::Named(
                            NamedKey::ArrowDown
                                | NamedKey::ArrowUp
                                | NamedKey::PageDown
                                | NamedKey::PageUp
                                | NamedKey::Home
                                | NamedKey::End
                                | NamedKey::Space
                        )
                    ) =>
            {
                let down = matches!(
                    event.logical_key,
                    Key::Named(NamedKey::ArrowDown | NamedKey::PageDown)
                );
                if event.logical_key == Key::Named(NamedKey::Space) {
                    self.explorer.paused = !self.explorer.paused;
                } else if self.page == 1 {
                    let rows = self.explorer.rows(&self.data);
                    let count = crate::explorer::visible_rows(window.inner_size().height as f32);
                    let current = rows
                        .iter()
                        .position(|p| self.explorer.selected == Some((p.pid, p.start_ticks)));
                    let step = if matches!(
                        event.logical_key,
                        Key::Named(NamedKey::PageDown | NamedKey::PageUp)
                    ) {
                        count
                    } else {
                        1
                    };
                    let index = match event.logical_key {
                        Key::Named(NamedKey::Home) => 0,
                        Key::Named(NamedKey::End) => rows.len().saturating_sub(1),
                        _ => current
                            .map(|i| {
                                if down {
                                    i.saturating_add(step)
                                } else {
                                    i.saturating_sub(step)
                                }
                            })
                            .unwrap_or(0)
                            .min(rows.len().saturating_sub(1)),
                    };
                    self.explorer.selected = rows.get(index).map(|p| (p.pid, p.start_ticks));
                    if index < self.scroll {
                        self.scroll = index;
                    } else if index >= self.scroll + count {
                        self.scroll = index + 1 - count;
                    }
                    self.explorer.confirming = false;
                    self.explorer.status.clear();
                } else if self.page >= 2 {
                    self.scroll = if down {
                        self.scroll.saturating_add(1).min(
                            self.explorer
                                .section(&self.data, self.page)
                                .rows
                                .len()
                                .saturating_sub(1),
                        )
                    } else {
                        self.scroll.saturating_sub(1)
                    };
                }
                window.request_redraw();
            }
            WindowEvent::KeyboardInput { event, .. }
                if event.state == ElementState::Pressed
                    && event.logical_key == Key::Named(NamedKey::Escape) =>
            {
                if self.explorer.confirming {
                    self.explorer.confirming = false;
                    window.request_redraw();
                } else if self.menu.open {
                    self.menu.open = false;
                    window.request_redraw();
                } else {
                    event_loop.exit();
                }
            }
            _ => {}
        }
    }
    fn about_to_wait(&mut self, event_loop: &ActiveEventLoop) {
        if let Some(deadline) = self.save_at {
            if Instant::now() >= deadline {
                self.save_at = None;
                if let Err(error) = self.config.save() {
                    self.menu.status = error;
                }
                event_loop.set_control_flow(ControlFlow::Wait);
            } else {
                event_loop.set_control_flow(ControlFlow::WaitUntil(deadline));
            }
        } else {
            event_loop.set_control_flow(ControlFlow::Wait);
        }
    }
}

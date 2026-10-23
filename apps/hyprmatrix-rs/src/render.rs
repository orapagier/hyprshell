use crate::{config::{Config, Effect}, effects::{self, Particle}};
use fontdue::{Font, FontSettings};
use std::{collections::HashMap, fs};
const SYMBOLS: &[u8] = b"0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ<>[]{}/\\:;=+*#$%&!?";
pub const MENU_ROWS: usize = 19;
pub const ROW: u32 = 26;
pub const MENU_WIDTH: u32 = 400;
pub const MENU_HEADER: u32 = 54;
pub const MENU_HEIGHT: u32 = MENU_HEADER + ROW * 14 + 28;
fn page_rows(_page: usize) -> &'static [usize] {
    &[18, 1, 2, 3, 4, 5, 6, 7, 17, 12, 13, 14, 15, 16]
}
/// Movement in surface coordinates before a panel press becomes a drag.
pub const DRAG_THRESHOLD: f64 = 4.0;

struct Glyph {
    pixels: Vec<(i16, i16, u8)>,
    bounds: (i32, i32, u32, u32),
}
pub struct Renderer {
    font: Option<Font>,
    glyph_size: u32,
    ui_glyphs: HashMap<(char, u32), (Glyph, f32)>,
    glyphs: HashMap<(char, u32), Glyph>,
    table: Vec<u32>,
    last_color: [u8; 3],
    last_opacity: f32,
    last_background: f32,
    pub color: [f32; 3],
    cells: Vec<Cell>,
    next: Vec<Cell>,
    draw_order: Vec<usize>,
    scene: (u32, u32, u32, u32),
    dirty: Vec<bool>,
    damage: Vec<(u32, u32, u32, u32)>,
    menu_cache: Option<MenuCache>,
    effect: Effect,
    particles: Vec<Particle>,
    next_particles: Vec<Particle>,
}
const TILE_W: u32 = 64;
const TILE_H: u32 = 32;
#[derive(Clone, Copy, Default, PartialEq, Eq)]
struct Cell { symbol: u8, level: u8 }
struct MenuCache {
    rect: (u32,u32,u32,u32),
    config: Config,
    page: usize,
    status: String,
    pixels: Vec<u32>,
}
fn mark_rect(dirty: &mut [bool], width: u32, height: u32, (x,y,w,h): (i32,i32,u32,u32)) {
    let left = x.max(0) as u32;
    let top = y.max(0) as u32;
    let right = (x as i64+w as i64).clamp(0,width as i64) as u32;
    let bottom = (y as i64+h as i64).clamp(0,height as i64) as u32;
    if right <= left || bottom <= top { return; }
    let cols = width.div_ceil(TILE_W);
    for row in top/TILE_H..=(bottom-1)/TILE_H {
        for col in left/TILE_W..=(right-1)/TILE_W {
            dirty[(row*cols+col) as usize] = true;
        }
    }
}
/// Frozen ASCII bitmaps have the same coverage as the original DejaVu rasterizer.
/// Only the chosen rain size and the small UI alphabet are materialized.
fn atlas(kind: u8, size: u32) -> HashMap<char, (Glyph, f32)> {
    let bytes = include_bytes!("font-atlas.bin");
    let count = u32::from_le_bytes(bytes[..4].try_into().unwrap()) as usize;
    let bitmap_start = 4+count*20;
    let mut result = HashMap::new();
    for entry in bytes[4..bitmap_start].chunks_exact(20) {
        if entry[0] != kind || entry[1] as u32 != size { continue; }
        let u16_at = |i| u16::from_le_bytes(entry[i..i+2].try_into().unwrap());
        let i16_at = |i| i16::from_le_bytes(entry[i..i+2].try_into().unwrap());
        let (w,h) = (u16_at(4) as usize,u16_at(6) as usize);
        let (xmin,ymin) = (i16_at(8),i16_at(10));
        let advance = f32::from_le_bytes(entry[12..16].try_into().unwrap());
        let offset = u32::from_le_bytes(entry[16..20].try_into().unwrap()) as usize+bitmap_start;
        let mut pixels = Vec::new();
        if w > 0 {
            for (i,a) in bytes[offset..offset+w*h].iter().enumerate() {
                if *a > 0 { pixels.push(((i%w) as i16+xmin,(i/w) as i16-ymin-h as i16,*a)); }
            }
        }
        result.insert(entry[2] as char, (Glyph { pixels, bounds: (xmin as i32,-ymin as i32-h as i32,w as u32,h as u32) }, advance));
    }
    result
}
pub fn hash(mut n: u32) -> u32 {
    n ^= n >> 16;
    n = n.wrapping_mul(0x7feb352d);
    n ^= n >> 15;
    n = n.wrapping_mul(0x846ca68b);
    n ^ (n >> 16)
}
fn argb(color: [u8; 3], alpha: u32, background: u32) -> u32 {
    let a = alpha + background * (255 - alpha) / 255;
    (a << 24)
        | ((color[0] as u32 * alpha / 255) << 16)
        | ((color[1] as u32 * alpha / 255) << 8)
        | (color[2] as u32 * alpha / 255)
}
impl Renderer {
    pub fn new(config: &Config) -> Result<Self, String> {
        // Keep runtime parsing only for explicitly selected custom TTFs.
        let font = config.font.as_ref().map(|path| {
            let bytes = fs::read(path).map_err(|e| e.to_string())?;
            Font::from_bytes(bytes, FontSettings::default()).map_err(|e| e.to_string())
        }).transpose()?;
        let mut r = Self {
            glyph_size: 0,
            ui_glyphs: HashMap::new(),
            font,
            glyphs: HashMap::new(),
            table: vec![0; 18 * 256],
            last_color: [0; 3],
            last_opacity: -1.0,
            last_background: -1.0,
            color: crate::wallpaper::FALLBACK.map(|v| v as f32),
            cells: Vec::new(), next: Vec::new(), draw_order: Vec::new(), scene: (0,0,0,0),
            dirty: Vec::new(), damage: Vec::new(), menu_cache: None,
            effect: config.effect, particles: Vec::new(), next_particles: Vec::new(),
        };
        r.prepare(config);
        Ok(r)
    }
    pub fn prepare(&mut self, c: &Config) {
        if self.glyph_size == c.font_size { return; }
        self.glyphs.clear(); // Changing size never retains all previous glyph caches.
        self.glyph_size = c.font_size;
        if let Some(font) = &self.font {
            for ch in 32u8..127 {
                let (m, bitmap) = font.rasterize(ch as char,c.font_size as f32);
                let mut pixels = Vec::new();
                if m.width > 0 {
                    for (i,a) in bitmap.iter().enumerate() {
                        if *a > 0 { pixels.push(((i%m.width) as i16+m.xmin as i16,
                            (i/m.width) as i16-m.ymin as i16-m.height as i16,*a)); }
                    }
                }
                self.glyphs.insert((ch as char,c.font_size),Glyph {pixels,
                    bounds:(m.xmin,-m.ymin-m.height as i32,m.width as u32,m.height as u32)});
            }
        } else {
            for (ch,(glyph,_)) in atlas(0,c.font_size) { self.glyphs.insert((ch,c.font_size),glyph); }
        }
    }
    pub fn invalidate(&mut self) { self.scene = (0,0,0,0); }
    pub fn damage(&self) -> &[(u32,u32,u32,u32)] { &self.damage }
    fn tables(&mut self, c: &Config, target: [u8; 3], dt: f32) -> bool {
        let blend = 1.0 - (-dt * 2.5).exp();
        for (current, target) in self.color.iter_mut().zip(target) {
            *current += (target as f32 - *current) * blend;
        }
        let color = self.color.map(|v| v.round() as u8);
        if color == self.last_color
            && c.opacity == self.last_opacity
            && c.background == self.last_background
            && self.effect == c.effect
        {
            return false;
        }
        for level in 0..18 {
            let color = if level == 17 {
                [210,225,245]
            } else if c.effect == Effect::Asteroids {
                let light = 0.18 + level as f32/16.0*0.72;
                color.map(|v| ((v as f32*0.35+100.0)*light) as u8)
            } else if level == 16 {
                if color.iter().all(|v| *v <= 110) && c.background < 0.2 {
                    color.map(|v| (v as f32 * 0.35) as u8)
                } else {
                    color.map(|v| (v as f32 * 0.25 + 255.0 * 0.75) as u8)
                }
            } else {
                color
            };
            let fade = if c.effect == Effect::Asteroids || level >= 16 {
                1.0
            } else {
                (level as f32 / 15.0).powf(1.5) * 0.85
            };
            for coverage in 0..256 {
                self.table[level * 256 + coverage] = argb(
                    color,
                    (coverage as f32 * c.opacity * fade) as u32,
                    (c.background * 255.0) as u32,
                );
            }
        }
        self.last_color = color;
        self.last_opacity = c.opacity;
        self.last_background = c.background;
        true
    }
    // Explicit drawing parameters keep the hot path free of temporary scene objects.
    #[allow(clippy::too_many_arguments)]
    pub fn render(
        &mut self,
        pixels: &mut [u32],
        w: u32,
        h: u32,
        c: &Config,
        time: f32,
        dt: f32,
        target: [u8; 3],
        menu: Option<(u32, u32, u32, u32)>,
        status: &str,
        page: usize,
    ) {
        if menu.is_some() { self.prepare_menu(); }
        let palette_changed = self.tables(c, target, dt);
        // Density controls one constant column pitch instead of random omissions.
        let base_cw = (c.font_size * 2 / 3).max(7) + 4;
        let cw = if c.density > 0.0 {
            (base_cw as f32 / c.density).round() as u32
        } else { w.max(1) + 1 };
        let full = palette_changed || self.effect != c.effect || self.scene != (w,h,c.font_size,cw);
        self.effect = c.effect;
        self.scene = (w,h,c.font_size,cw);
        let tiles = (w.div_ceil(TILE_W)*h.div_ceil(TILE_H)) as usize;
        self.dirty.resize(tiles,false);
        self.dirty.fill(full);
        let ch = c.font_size + 5;
        let rows = h / ch + 1;
        let cols = if c.effect == Effect::Matrix && c.density > 0.0 { w/cw } else { 0 };
        let cell_count = (cols*rows) as usize;
        self.cells.resize(cell_count,Cell::default());
        self.next.resize(cell_count,Cell::default());
        self.next.fill(Cell::default());
        self.draw_order.clear();
        for col in 0..cols {
            let seed = hash(col + 7919);
            let trail = (7 + seed % 22).min(rows);
            let factor = 0.55 + (seed % 101) as f32 / 100.0;
            let period = rows as f32;
            let phase = (hash(seed) % 10000) as f32 / 10000.0 * period;
            let travel = time * c.speed * factor + phase;
            let head = (travel % period) as i32;
            let cycle = (travel / period) as u32;
            for age in 0..trail {
                // Continue each lane across the edge without a blank interval between passes.
                let row = (head - age as i32).rem_euclid(rows as i32);
                let noise = hash(
                    seed.wrapping_add((row as u32).wrapping_mul(997))
                        .wrapping_add(cycle.wrapping_mul(293)),
                );
                // A sparse changing character adds life without making every glyph flicker.
                let glitch = if noise % 19 == 0 {
                    (time * 2.0) as u32
                } else {
                    0
                };
                let symbol =
                    SYMBOLS[hash(noise.wrapping_add(glitch)) as usize % SYMBOLS.len()] as char;
                let level = if age == 0 {
                    16
                } else {
                    ((trail - age) * 15 / trail).max(1) as usize
                };
                let index=(row as u32*cols+col) as usize;
                self.next[index] = Cell { symbol: symbol as u8, level: level as u8 };
                self.draw_order.push(index);
            }
        }
        for (i,(old,new)) in self.cells.iter().zip(&self.next).enumerate() {
            if !full && old != new {
                let x = (i as u32%cols*cw) as i32;
                let y = (i as u32/cols*ch+c.font_size) as i32;
                for cell in [old,new] {
                    if let Some(g) = self.glyphs.get(&(cell.symbol as char,c.font_size)) {
                        let (gx,gy,gw,gh) = g.bounds;
                        mark_rect(&mut self.dirty,w,h,(x+gx,y+gy,gw,gh));
                    }
                }
            }
        }
        effects::generate(&mut self.next_particles, (w,h), c, time);
        if !full && self.particles != self.next_particles {
            for particle in self.particles.iter().chain(&self.next_particles) {
                mark_rect(&mut self.dirty, w, h, particle.bounds());
            }
        }
        let menu_changed = match (&self.menu_cache,menu) {
            (Some(cache),Some(rect)) => cache.rect != rect || cache.config != *c || cache.page != page || cache.status != status,
            (None,None) => false,
            _ => true,
        };
        if menu_changed {
            if let Some(cache) = &self.menu_cache {
                let (x,y,mw,mh)=cache.rect;
                mark_rect(&mut self.dirty,w,h,(x as i32,y as i32,mw,mh));
            }
            self.menu_cache = if let Some(rect) = menu {
                let (x,y,mw,mh)=rect;
                mark_rect(&mut self.dirty,w,h,(x as i32,y as i32,mw,mh));
                let mut cache_pixels=vec![0; (mw*mh) as usize];
                self.menu(&mut cache_pixels,mw,mh,c,status,(0,0,mw,mh),page);
                Some(MenuCache { rect,config:c.clone(),page,status:status.into(),pixels:cache_pixels })
            } else { None };
        }
        self.damage.clear();
        let tile_cols=w.div_ceil(TILE_W);
        for ty in 0..h.div_ceil(TILE_H) {
            let mut tx=0;
            while tx<tile_cols {
                if !self.dirty[(ty*tile_cols+tx) as usize] { tx+=1; continue; }
                let start=tx;
                while tx<tile_cols && self.dirty[(ty*tile_cols+tx) as usize] { tx+=1; }
                let x=start*TILE_W;
                let y=ty*TILE_H;
                let dw=(tx*TILE_W).min(w)-x;
                let dh=TILE_H.min(h-y);
                self.damage.push((x,y,dw,dh));
                let bg=((c.background*255.0) as u32)<<24;
                for py in y..y+dh { pixels[(py*w+x) as usize..(py*w+x+dw) as usize].fill(bg); }
            }
        }
        for &i in &self.draw_order {
            let cell=self.next[i];
            self.glyph(pixels,(w,h),cell.symbol as char,c.font_size,
                (i as u32%cols*cw) as i32,(i as u32/cols*ch+c.font_size) as i32,cell.level as usize);
        }
        let tile_cols = w.div_ceil(TILE_W);
        for particle in &self.next_particles {
            effects::rasterize(particle, |x,y,coverage,level| {
                if x < 0 || y < 0 || x >= w as i32 || y >= h as i32 { return; }
                if !self.dirty[(y as u32/TILE_H*tile_cols+x as u32/TILE_W) as usize] { return; }
                let source = self.table[level*256+coverage as usize];
                let pixel = &mut pixels[(y as u32*w+x as u32) as usize];
                // Max coverage keeps overlapping parts of one tapered trail smooth.
                let mut result = 0;
                for shift in [0,8,16,24] {
                    result |= ((source>>shift & 255).max(*pixel>>shift & 255))<<shift;
                }
                *pixel = result;
            });
        }
        if let Some(cache)=&self.menu_cache {
            let (mx,my,mw,mh)=cache.rect;
            for &(x,y,dw,dh) in &self.damage {
                for py in y.max(my)..(y+dh).min(my+mh) {
                    for px in x.max(mx)..(x+dw).min(mx+mw) {
                        let color=cache.pixels[((py-my)*mw+px-mx) as usize];
                        if color != 0 {
                            let pixel = &mut pixels[(py*w+px) as usize];
                            *pixel = over(color, *pixel);
                        }
                    }
                }
            }
        }
        std::mem::swap(&mut self.cells,&mut self.next);
        std::mem::swap(&mut self.particles,&mut self.next_particles);
    }
    #[allow(clippy::too_many_arguments)]
    fn glyph(
        &self,
        pixels: &mut [u32],
        size: (u32, u32),
        ch: char,
        font: u32,
        x: i32,
        y: i32,
        level: usize,
    ) {
        let Some(g) = self.glyphs.get(&(ch, font)) else {
            return;
        };
        let (gx,gy,gw,gh)=g.bounds;
        let left=(x+gx).max(0) as u32;
        let top=(y+gy).max(0) as u32;
        let right=(x+gx+gw as i32).clamp(0,size.0 as i32) as u32;
        let bottom=(y+gy+gh as i32).clamp(0,size.1 as i32) as u32;
        if right<=left || bottom<=top { return; }
        let tile_cols=size.0.div_ceil(TILE_W);
        let has_damage=(top/TILE_H..=(bottom-1)/TILE_H).any(|ty|
            (left/TILE_W..=(right-1)/TILE_W).any(|tx| self.dirty[(ty*tile_cols+tx) as usize]));
        if !has_damage { return; }
        for &(dx, dy, a) in &g.pixels {
            let (px, py) = (x + dx as i32, y + dy as i32);
            if px >= 0 && py >= 0 && px < size.0 as i32 && py < size.1 as i32 {
                if self.dirty[(py as u32/TILE_H*tile_cols+px as u32/TILE_W) as usize] {
                    pixels[py as usize * size.0 as usize + px as usize] = self.table[level * 256 + a as usize];
                }
            }
        }
    }
    #[allow(clippy::too_many_arguments)]
    fn text(&self, pixels: &mut [u32], size: (u32, u32), text: &str, pos: (i32, i32), font: u32, color: [u8; 3]) {
        let (w, h) = size;
        let (mut x, y) = (pos.0 as f32, pos.1);
        for ch in text.chars() {
            if let Some((g, advance)) = self.ui_glyphs.get(&(ch, font)) {
                for &(dx, dy, a) in &g.pixels {
                    let (px, py) = (x.round() as i32 + dx as i32, y + dy as i32);
                    if px >= 0 && py >= 0 && px < w as i32 && py < h as i32 {
                        let bg = pixels[py as usize * w as usize + px as usize];
                        let mut source = (a as u32) << 24;
                        for (i, shift) in [16, 8, 0].iter().enumerate() {
                            source |= (color[i] as u32 * a as u32 / 255) << shift;
                        }
                        pixels[py as usize * w as usize + px as usize] = over(source, bg);
                    }
                }
                x += advance;
            }
        }
    }
    fn prepare_menu(&mut self) {
        if self.ui_glyphs.is_empty() {
            for size in [12,13,20] {
                for (ch,glyph) in atlas(1,size) { self.ui_glyphs.insert((ch,size),glyph); }
            }
        }
    }
    pub fn release_menu(&mut self) {
        self.ui_glyphs = HashMap::new();
        self.menu_cache = None;
    }
    /// Paint only the popup, leaving its rounded corners transparent for compositor blur.
    pub fn render_menu(&mut self, pixels: &mut [u32], w: u32, h: u32, c: &Config, status: &str) {
        self.prepare_menu();
        pixels.fill(0);
        self.menu(pixels, w, h, c, status, (0,0,w,h), 0);
    }
    #[allow(clippy::too_many_arguments)]
    fn menu(&self, pixels: &mut [u32], w: u32, h: u32, c: &Config, status: &str,
        (x, y, mw, mh): (u32, u32, u32, u32), page: usize) {
        let draw = |pixels: &mut [u32], rect, radius, color| rounded(pixels, (w, h), rect, radius, color);
        // Match the shell's 94% dark glass, light top gradient and tinted rim.
        draw(pixels, (x, y, mw, mh), 22, argb([142,193,255], 140, 0));
        draw(pixels, (x+1, y+1, mw.saturating_sub(2), mh.saturating_sub(2)), 21, argb([32;3], 240, 0));
        for py in y+1..(y+mh).saturating_sub(1) {
            let lift = 15 * (y+mh-py) / mh.max(1);
            for px in x+1..(x+mw).saturating_sub(1) {
                let pixel = &mut pixels[(py*w+px) as usize];
                if *pixel >> 24 >= 240 {
                    *pixel = argb([(32+lift) as u8;3], 240, 0);
                }
            }
        }
        self.text(pixels, (w,h), "Hyprmatrix", (x as i32+16, y as i32+30), 20, [245;3]);
        self.text(pixels, (w,h), "Drag to reposition", (x as i32+mw as i32-126, y as i32+28), 12, [184;3]);
        let labels = labels(c);
        debug_assert_eq!(labels.len(), MENU_ROWS);
        for (slot, &i) in page_rows(page).iter().enumerate() {
            let ry = y+MENU_HEADER+slot as u32*ROW;
            if ry+ROW > y+mh.saturating_sub(24) { break; }
            let (name, value) = &labels[i];
            let action = value.is_empty();
            draw(pixels, (x+12, ry, mw.saturating_sub(24), ROW-2), 6,
                argb([255;3], if action { 16 } else { 8 }, 0));
            self.text(pixels, (w,h), name, (x as i32+22, ry as i32+17), 13,
                if i == 16 { [255,156,165] } else { [245;3] });
            if !action {
                let vx = x+mw.saturating_sub(170);
                draw(pixels, (vx, ry+2, 148, ROW-6), 5, argb([0;3], 24, 0));
                self.text(pixels, (w,h), "<", (vx as i32+8, ry as i32+17), 13, [142,193,255]);
                let length: f32 = value.chars().filter_map(|ch| self.ui_glyphs.get(&(ch,13)).map(|g| g.1)).sum();
                self.text(pixels, (w,h), value, (vx as i32+74-(length/2.0) as i32, ry as i32+17), 13, [142,193,255]);
                self.text(pixels, (w,h), ">", (vx as i32+130, ry as i32+17), 13, [142,193,255]);
            }
        }
        let note = if status.is_empty() { "Auto-saved  /  Left: decrease  /  Right: increase" } else { status };
        let note: String = note.chars().take((mw as usize).saturating_sub(32)/7).collect();
        self.text(pixels, (w,h), &note, (x as i32+16, (y+mh.saturating_sub(10)) as i32), 12,
            if status.is_empty() { [184;3] } else { [255,156,165] });
    }
}
/// Premultiplied source-over keeps antialiased text and nested glass translucent.
fn over(source: u32, destination: u32) -> u32 {
    let inverse = 255 - (source >> 24);
    let mut result = 0;
    for shift in [0,8,16,24] {
        result |= (((source >> shift & 255) + (destination >> shift & 255) * inverse / 255).min(255)) << shift;
    }
    result
}
/// Rounded UI surfaces leave each corner transparent.
fn rounded(pixels: &mut [u32], size: (u32,u32), (x,y,w,h): (u32,u32,u32,u32), radius: u32, color: u32) {
    let r = radius.min(w/2).min(h/2) as i32;
    for py in y..(y+h).min(size.1) {
        for px in x..(x+w).min(size.0) {
            let lx = (px-x) as i32;
            let ly = (py-y) as i32;
            let dx = (r-lx-1).max(lx-(w as i32-r)).max(0);
            let dy = (r-ly-1).max(ly-(h as i32-r)).max(0);
            if dx*dx+dy*dy <= r*r {
                let pixel = &mut pixels[(py*size.0+px) as usize];
                *pixel = over(color, *pixel);
            }
        }
    }
}

pub fn menu_rect(w: u32, h: u32) -> (u32, u32, u32, u32) {
    let mw = MENU_WIDTH.min(w);
    let mh = MENU_HEIGHT.min(h);
    (
        w.saturating_sub(mw) / 2,
        h.saturating_sub(mh) / 2,
        mw,
        mh,
    )
}
/// Keep a panel top-left position inside the surface.
pub fn clamp_menu_pos(pos: (u32, u32), surface: (u32, u32)) -> (u32, u32) {
    (
        pos.0.min(surface.0.saturating_sub(MENU_WIDTH.min(surface.0))),
        pos.1
            .min(surface.1.saturating_sub(MENU_HEIGHT.min(surface.1))),
    )
}
/// Settings-row index (0..MENU_ROWS) for a press inside the panel body.
pub fn menu_row(rect: (u32, u32, u32, u32), page: usize, x: f64, y: f64) -> Option<usize> {
    let (mx,my,mw,mh) = rect;
    if x < mx as f64 || x >= (mx+mw) as f64 || y < my as f64 || y >= (my+mh) as f64 { return None; }
    let local_y = y-my as f64;
    if local_y < MENU_HEADER as f64 || local_y >= mh.saturating_sub(28) as f64 { return None; }
    page_rows(page).get(((local_y-MENU_HEADER as f64)/ROW as f64) as usize).copied()
}

/// The decrease/increase targets follow the visible value control, not the row midpoint.
pub fn menu_increase(rect: (u32, u32, u32, u32), x: f64) -> bool {
    x >= (rect.0 + rect.2.saturating_sub(96)) as f64
}
pub fn labels(c: &Config) -> Vec<(String, String)> {
    vec![
        // Retired row IDs stay reserved so existing control IDs remain stable.
        (String::new(), String::new()),
        (
            "Rain opacity".into(),
            format!("{}%", (c.opacity * 100.0).round()),
        ),
        (
            "Background".into(),
            format!("{}%", (c.background * 100.0).round()),
        ),
        ("Color".into(), c.theme.clone()),
        (
            "Density".into(),
            format!("{}%", (c.density * 100.0).round()),
        ),
        ("Speed".into(), format!("{:.0}", c.speed)),
        (if c.effect == Effect::Matrix { "Character size" } else { "Particle size" }.into(), c.font_size.to_string()),
        ("Frame limit".into(), format!("{} FPS", c.fps)),
        (String::new(), String::new()),
        (String::new(), String::new()),
        (String::new(), String::new()),
        (String::new(), String::new()),
        ("Refresh wallpaper color".into(), String::new()),
        ("Reset appearance".into(), String::new()),
        ("Hide rain".into(), String::new()),
        ("Close settings".into(), String::new()),
        ("Quit Hyprmatrix".into(), String::new()),
        ("Window layer".into(), if c.in_front { "In front" } else { "Behind" }.into()),
        ("Effect".into(), c.effect.label().into()),
    ]
}
/// Returns an action for desktop integration; configuration changes save immediately.
pub fn adjust(c: &mut Config, row: usize, increase: bool) -> &'static str {
    let d = if increase { 1.0 } else { -1.0 };
    match row {
        1 => c.opacity = (c.opacity + d * 0.05).clamp(0.0, 1.0),
        2 => c.background = (c.background + d * 0.05).clamp(0.0, 1.0),
        3 => {
            let themes = ["wallpaper", "matrix", "cyan", "amber"];
            let i = themes.iter().position(|t| *t == c.theme).unwrap_or(0);
            c.theme = themes[((i as i32 + if increase { 1 } else { 3 }) % 4) as usize].into();
        }
        4 => c.density = (c.density + d * 0.05).clamp(0.0, 1.0),
        5 => c.speed = (c.speed + d).clamp(1.0, 30.0),
        6 => c.font_size = (c.font_size as i32 + d as i32).clamp(10, 32) as u32,
        7 => {
            let rates = [5, 10, 15, 20, 30, 60];
            c.fps = if increase {
                rates.into_iter().find(|r| *r > c.fps).unwrap_or(60)
            } else {
                rates.into_iter().rev().find(|r| *r < c.fps).unwrap_or(5)
            };
        }
        12 => return "refresh",
        13 => {
            let output = c.output.clone();
            *c = Config::default();
            c.output = output;
            return "resize";
        }
        14 => return "hide",
        15 => return "close",
        16 => return "quit",
        17 => { c.in_front = !c.in_front; return "layer"; }
        18 => {
            let i = Effect::ALL.iter().position(|effect| *effect == c.effect).unwrap_or(0);
            c.effect = Effect::ALL[(i + if increase { 1 } else { Effect::ALL.len()-1 }) % Effect::ALL.len()];
        }
        _ => {}
    }
    "draw"
}
#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn stationary_stars_keep_a_neutral_palette_in_every_space_effect() {
        let mut c=Config { theme: "amber".into(),..Config::default() };
        let mut r=Renderer::new(&c).unwrap();
        for effect in [Effect::ShootingStars,Effect::Meteors,Effect::Asteroids] {
            c.effect=effect;
            r.tables(&c,c.color([0;3]),1.0);
            assert_eq!(r.table[17*256+255],argb([210,225,245],(c.opacity*255.0) as u32,0));
            r.effect=effect;
        }
    }
    #[test]
    fn effect_switches_and_particle_damage_match_full_repaints() {
        let mut c = Config { theme: "amber".into(), ..Config::default() };
        let mut incremental = Renderer::new(&c).unwrap();
        let mut reference = Renderer::new(&c).unwrap();
        let (w,h) = (640,520);
        let mut actual = vec![0;(w*h) as usize];
        let mut expected = actual.clone();
        for frame in 0..120 {
            c.effect = Effect::ALL[(frame/20)%4];
            if frame == 12 { c.density=1.0; }
            if frame == 25 { c.font_size=32; }
            if frame == 45 { c.opacity=0.4; c.background=0.2; }
            if frame == 70 { c.density=0.0; }
            if frame == 75 { c.density=0.7; }
            if frame == 90 { c.background=1.0; }
            let menu = if (10..35).contains(&frame) { Some(menu_rect(w,h)) } else { None };
            incremental.prepare(&c);
            reference.prepare(&c);
            let before = actual.clone();
            incremental.render(&mut actual,w,h,&c,frame as f32/5.0,0.2,c.color([0;3]),menu,"",0);
            reference.invalidate();
            reference.render(&mut expected,w,h,&c,frame as f32/5.0,0.2,c.color([0;3]),menu,"",0);
            assert_eq!(actual,expected,"frame {frame}, {:?}",c.effect);
            for (i,(old,new)) in before.iter().zip(&actual).enumerate() {
                if old==new { continue; }
                let (x,y)=(i as u32%w,i as u32/w);
                assert!(incremental.damage().iter().any(|&(dx,dy,dw,dh)| x>=dx && x<dx+dw && y>=dy && y<dy+dh));
            }
            assert!(actual.iter().all(|p| [0,8,16].iter().all(|shift| (p>>shift & 255) <= p>>24)));
        }
    }
    #[test]
    fn effect_selector_cycles_in_both_directions_and_reset_restores_matrix() {
        let mut c = Config::default();
        for effect in Effect::ALL.into_iter().cycle().skip(1).take(8) {
            adjust(&mut c,18,true);
            assert_eq!(c.effect,effect);
        }
        adjust(&mut c,18,false);
        assert_eq!(c.effect,Effect::Asteroids);
        assert_eq!(labels(&c)[6].0,"Particle size");
        adjust(&mut c,13,true);
        assert_eq!(c.effect,Effect::Matrix);
        assert_eq!(labels(&c)[6].0,"Character size");
    }
    #[test]
    fn rain_uses_every_evenly_spaced_column_and_zero_density_clears_it() {
        let mut c = Config { theme: "matrix".into(), density: 0.5, font_size: 14, ..Config::default() };
        let mut r = Renderer::new(&c).unwrap();
        let mut pixels = vec![0; 640 * 520];
        // A 9px character cell plus 4px breathing room gives a 26px half-density pitch.
        let cols = 640 / 26;
        let mut seen = vec![false; cols];
        for frame in 0..120 {
            r.render(&mut pixels, 640, 520, &c, frame as f32, 1.0, c.color([0;3]), None, "", 0);
            assert_eq!(r.scene.3, 26);
            let mut active = vec![false; cols];
            for &index in &r.draw_order { active[index % cols] = true; }
            assert!(active.iter().all(|visible| *visible), "missing lane at frame {frame}");
            for &index in &r.draw_order { seen[index % cols] = true; }
        }
        assert!(seen.iter().all(|active| *active));
        c.density = 0.0;
        r.render(&mut pixels, 640, 520, &c, 120.0, 1.0, c.color([0;3]), None, "", 0);
        assert!(pixels.iter().all(|pixel| *pixel == 0));
        c.density = 1.0;
        r.render(&mut pixels, 640, 520, &c, 121.0, 1.0, c.color([0;3]), None, "", 0);
        assert_eq!(r.scene.3, 13);
        assert!(!r.draw_order.is_empty());
    }
    #[test]
    fn incremental_frames_match_full_repaints_across_settings_changes() {
        let mut c=Config { theme:"matrix".into(), density:1.0, font_size:14, ..Config::default() };
        let mut incremental=Renderer::new(&c).unwrap();
        let mut reference=Renderer::new(&c).unwrap();
        let (w,h)=(640,520);
        let mut actual=vec![0;(w*h) as usize];
        let mut expected=actual.clone();
        for frame in 0..90 {
            if frame==15 { c.opacity=0.35; }
            if frame==30 { c.density=0.4; }
            if frame==45 { c.font_size=20; }
            if frame==60 { c.background=0.3; c.theme="amber".into(); }
            incremental.prepare(&c);
            reference.prepare(&c);
            let menu=if (10..35).contains(&frame) { Some(menu_rect(w,h)) }
                else if (55..70).contains(&frame) { Some((0,0,MENU_WIDTH,MENU_HEIGHT)) } else { None };
            let page=usize::from(frame>=25);
            let before=actual.clone();
            incremental.render(&mut actual,w,h,&c,frame as f32/15.0,1.0/15.0,c.color([80,210,175]),menu,"",page);
            reference.invalidate();
            reference.render(&mut expected,w,h,&c,frame as f32/15.0,1.0/15.0,c.color([80,210,175]),menu,"",page);
            assert_eq!(actual,expected,"frame {frame}");
            for (i,(old,new)) in before.iter().zip(&actual).enumerate() {
                if old==new { continue; }
                let (x,y)=(i as u32%w,i as u32/w);
                assert!(incremental.damage().iter().any(|&(dx,dy,dw,dh)| x>=dx && x<dx+dw && y>=dy && y<dy+dh));
            }
        }
    }
    #[test]
    fn unchanged_frames_need_no_damage() {
        let c=Config {theme:"matrix".into(), ..Config::default()};
        let mut r=Renderer::new(&c).unwrap();
        let mut pixels=vec![0;640*520];
        for _ in 0..2 { r.render(&mut pixels,640,520,&c,12.0,1.0,c.color([0;3]),Some(menu_rect(640,520)),"",0); }
        // Color interpolation can take multiple frames to settle, so initialize to the target.
        r.color=c.color([0;3]).map(|v|v as f32);
        r.render(&mut pixels,640,520,&c,12.0,1.0,c.color([0;3]),Some(menu_rect(640,520)),"",0);
        r.render(&mut pixels,640,520,&c,12.0,1.0,c.color([0;3]),Some(menu_rect(640,520)),"",0);
        assert!(r.damage().is_empty());
    }
    #[test]
    fn builtin_atlas_has_every_supported_size_and_ui_character() {
        for size in 10..=32 { assert_eq!(atlas(0,size).len(),95); }
        for size in [12,13,20] { assert_eq!(atlas(1,size).len(),95); }
    }
    #[test]
    fn value_arrows_adjust_in_the_displayed_direction() {
        for width in [360, MENU_WIDTH] {
            let rect = (12, 8, width, MENU_HEIGHT);
            let left_arrow = (rect.0 + width - 162) as f64;
            let right_arrow = (rect.0 + width - 40) as f64;
            let mut c = Config::default();
            let before = c.opacity;
            adjust(&mut c, 1, menu_increase(rect, left_arrow));
            assert!(c.opacity < before);
            adjust(&mut c, 1, menu_increase(rect, right_arrow));
            assert!((c.opacity - before).abs() < 0.001);
            adjust(&mut c, 17, true);
            assert!(c.in_front);
            adjust(&mut c, 17, false);
            assert!(!c.in_front);
        }
    }
    #[test]
    fn menu_adjustments_stay_valid() {
        for direction in [false, true] {
            let mut c = Config::default();
            for _ in 0..150 {
                for row in 0..12 {
                    adjust(&mut c, row, direction);
                    assert!(c.validate().is_ok());
                }
            }
        }
    }
    #[test]
    fn premultiplied_pixels_preserve_alpha() {
        let p = argb([100, 200, 250], 128, 64);
        assert_eq!(p >> 24, 159);
        for shift in [0, 8, 16] {
            assert!((p >> shift & 255) <= (p >> 24));
        }
        assert_eq!(argb([255; 3], 0, 0), 0);
    }
    #[test]
    fn menu_row_hit_test_matches_visible_rows() {
        let rect = menu_rect(1920, 1080);
        let (mx, my, _, _) = rect;
        assert_eq!(menu_row(rect, 0, mx as f64+10.0, my as f64+4.0), None);
        assert_eq!(menu_row(rect, 0, mx as f64+10.0, (my+MENU_HEIGHT-4) as f64), None);
        for page in 0..2 {
            for (slot, &row) in page_rows(page).iter().enumerate() {
                assert_eq!(menu_row(rect, page, mx as f64+25.0,
                    (my+MENU_HEADER+slot as u32*ROW+4) as f64), Some(row));
            }
        }
        assert_eq!(menu_row(rect, 0, mx as f64+20.0, (my+50) as f64), None);
        assert_eq!(menu_row(rect, 0, (mx+MENU_WIDTH-20) as f64, (my+50) as f64), None);
        assert_eq!(labels(&Config::default())[15].0, "Close settings");
        assert_eq!(labels(&Config::default())[16].0, "Quit Hyprmatrix");
    }

    #[test]
    fn fullscreen_settings_keep_all_remaining_controls_reachable() {
        let rect = menu_rect(360, 460);
        let mut reachable = std::collections::BTreeSet::new();
        for page in 0..1 {
            for (slot, row) in page_rows(page).iter().enumerate() {
                let y = rect.1+MENU_HEADER+slot as u32*ROW+ROW/2;
                assert!(y < rect.1+rect.3-28);
                assert_eq!(menu_row(rect, page, (rect.0+25) as f64, y as f64), Some(*row));
                reachable.insert(*row);
            }
        }
        assert_eq!(reachable, (0..MENU_ROWS).filter(|row| ![0,8,9,10,11].contains(row)).collect());
        let mut c = Config::default();
        for row in [0,8,9,10,11] {
            let before = c.clone();
            adjust(&mut c, row, true);
            assert_eq!(c, before);
        }
    }
    #[test]
    fn clamp_menu_pos_keeps_panel_inside_surface() {
        assert_eq!(clamp_menu_pos((0, 0), (1920, 1080)), (0, 0));
        assert_eq!(
            clamp_menu_pos((5000, 5000), (1920, 1080)),
            (1920 - MENU_WIDTH, 1080 - MENU_HEIGHT)
        );
        assert_eq!(clamp_menu_pos((5000, 5000), (300, 300)), (0, 300 - 300));
        assert_eq!(clamp_menu_pos((100, 100), (300, 300)), (0, 0));
    }
    #[test]
    fn popup_is_centered_and_glass_is_premultiplied_with_clear_corners() {
        assert_eq!(menu_rect(1920,1080), (760,317,400,446));
        assert_eq!(menu_rect(300,300), (0,0,300,300));
        let c = Config::default();
        let mut renderer = Renderer::new(&c).unwrap();
        let (w,h) = (MENU_WIDTH,MENU_HEIGHT);
        let mut pixels = vec![0;(w*h) as usize];
        renderer.render_menu(&mut pixels,w,h,&c,"");
        assert_eq!(pixels[0],0);
        assert_eq!(pixels[(w-1) as usize],0);
        assert_eq!(pixels[((h-1)*w) as usize],0);
        let center = pixels[(h/2*w+w/2) as usize];
        assert!((240..255).contains(&(center>>24)));
        for pixel in pixels {
            for shift in [0,8,16] { assert!((pixel>>shift&255) <= pixel>>24); }
        }
        renderer.release_menu();
        assert!(renderer.ui_glyphs.is_empty());
    }
}

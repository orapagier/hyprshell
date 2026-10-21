//! Small procedural space particles, using the rain renderer's palette and damage tiles.
use crate::{config::{Config, Effect}, render::hash};

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct Particle {
    x: i32,
    y: i32,
    radius: i32,
    tail: i32,
    direction: (i16,i16),
    opacity: u8,
    angle: u32,
    seed: u32,
    effect: Effect,
    pub stationary: bool,
}
impl Particle {
    pub fn bounds(&self) -> (i32,i32,u32,u32) {
        let margin = self.radius + 4;
        let tx = self.x-(self.tail as f32*self.direction.0 as f32/10000.0).round() as i32;
        let ty = self.y-(self.tail as f32*self.direction.1 as f32/10000.0).round() as i32;
        (self.x.min(tx)-margin, self.y.min(ty)-margin,
            ((self.x-tx).abs()+2*margin+1) as u32,
            ((self.y-ty).abs()+2*margin+1) as u32)
    }
}

fn unit(seed: u32) -> f32 { (hash(seed)%65536) as f32/65536.0 }

/// Usually within 6% of the selected size, with occasional 20% variations.
fn size_variation(seed: u32) -> f32 {
    match hash(seed.wrapping_add(101))%20 {
        0 => 0.8,
        1 => 1.2,
        _ => 0.94+unit(seed.wrapping_add(211))*0.12,
    }
}

/// Most passes share a downward-right heading; rare ones use another downward angle.
fn sky_direction(seed: u32) -> (i16,i16) {
    let degrees = if hash(seed.wrapping_add(307))%10 == 0 {
        20.0+unit(seed.wrapping_add(401))*140.0
    } else { 57.0+(unit(seed.wrapping_add(409))-0.5)*12.0 };
    let (dy,dx)=degrees.to_radians().sin_cos();
    ((dx*10000.0).round() as i16,(dy*10000.0).round() as i16)
}

fn speed_variation(seed: u32) -> f32 {
    match hash(seed.wrapping_add(503))%20 {
        0 => 0.75,
        1 => 1.25,
        _ => 0.96+unit(seed.wrapping_add(601))*0.08,
    }
}

/// Trace backward to a top/side entry, then forward to the bottom/side exit.
fn sky_path((x,y): (f32,f32), (dx,dy): (f32,f32), (w,h): (u32,u32), margin: f32)
    -> ((f32,f32),f32) {
    let back_x = if dx>=0.0 { x } else { w as f32-x }/dx.abs().max(0.0001);
    let back_y = y/dy;
    let front_x = if dx>=0.0 { w as f32-x } else { x }/dx.abs().max(0.0001);
    let front_y = (h as f32-y)/dy;
    let entry = back_x.min(back_y)+margin;
    let distance = entry+front_x.min(front_y)+margin;
    ((x-dx*entry,y-dy*entry),distance)
}

/// Fit a straight streak from the upper sky to well past the midpoint.
fn streak_path(seed: u32, (w,h): (u32,u32), direction: (i16,i16))
    -> ((f32,f32),f32,(i16,i16)) {
    let start_y = h as f32*(0.08+unit(seed.wrapping_add(701))*0.20);
    let end_y = h as f32*(0.65+unit(seed.wrapping_add(709))*0.20);
    let vertical = end_y-start_y;
    // On narrow/portrait regions, steepen the angle so the full pass fits on screen.
    let slope = (direction.0 as f32/direction.1 as f32)
        .clamp(-(w as f32)*0.79/vertical,w as f32*0.79/vertical);
    let dy = 1.0/(1.0+slope*slope).sqrt();
    let direction = ((slope*dy*10000.0).round() as i16,(dy*10000.0).round() as i16);
    let (dx,dy)=(direction.0 as f32/10000.0,direction.1 as f32/10000.0);
    let horizontal = vertical*dx/dy;
    let padding = w as f32*0.05;
    let room = (w as f32-2.0*padding-horizontal.abs()).max(0.0);
    let x = padding+(-horizontal).max(0.0)+unit(seed.wrapping_add(719))*room;
    ((x,start_y),vertical/dy,direction)
}

fn starfield(out: &mut Vec<Particle>, (w,h): (u32,u32), c: &Config, time: f32) {
    let count = ((w as f32*h as f32/16000.0*c.density).ceil() as u32).clamp(1,220);
    let columns = ((count as f32*w as f32/h as f32).sqrt().ceil() as u32).max(1);
    let rows = count.div_ceil(columns);
    for slot in 0..count {
        let base = hash(slot+894791);
        let interval = 18.0+unit(base)*22.0;
        let cursor = time+unit(base.wrapping_add(1))*interval;
        let age = cursor.rem_euclid(interval);
        let seed = hash(base.wrapping_add(((cursor/interval).floor() as u32).wrapping_mul(65537)));
        let fade = (age/2.5).min((interval-age)/2.5).clamp(0.0,1.0);
        let fade = fade*fade*(3.0-2.0*fade);
        out.push(Particle {
            x: (((slot%columns) as f32+unit(seed.wrapping_add(2)))*w as f32/columns as f32)
                .round().clamp(0.0,w.saturating_sub(1) as f32) as i32,
            y: (((slot/columns) as f32+unit(seed.wrapping_add(3)))*h as f32/rows as f32)
                .round().clamp(0.0,h.saturating_sub(1) as f32) as i32,
            radius: ((0.65+unit(seed.wrapping_add(4))*1.2)*(c.font_size as f32/16.0).max(0.9))
                .round().clamp(1.0,3.0) as i32,
            opacity: (fade*(40.0+unit(seed.wrapping_add(5))*110.0)).round() as u8,
            tail: 0, direction: (0,0), angle: 0, seed, effect: c.effect, stationary: true,
        });
    }
}

pub fn generate(out: &mut Vec<Particle>, (w,h): (u32,u32), c: &Config, time: f32) {
    out.clear();
    if c.effect == Effect::Matrix || c.density <= 0.0 || w == 0 || h == 0 { return; }
    starfield(out,(w,h),c,time);
    let size = c.font_size as f32 / 16.0;
    let slots = ((w as f32*h as f32/50000.0*c.density/size).ceil() as u32).clamp(1,220);
    let columns = ((slots as f32*w as f32/h as f32).sqrt().ceil() as u32).max(1);
    let rows = slots.div_ceil(columns);
    let clock = time*c.speed/9.0;
    for slot in 0..slots {
        let base = hash(slot+7919);
        let margin = 40.0*size;
        let interval = if c.effect == Effect::Asteroids {
            ((w as f32).hypot(h as f32)+margin*2.0)/(28.0*size)+5.0
        } else {
            (w as f32*0.8).hypot(h as f32*0.82)/(210.0*size)+1.0+unit(base)*4.0
        };
        let cursor = clock+unit(base.wrapping_add(1))*interval;
        let cycle = (cursor/interval).floor() as u32;
        let age = cursor.rem_euclid(interval);
        let seed = hash(base.wrapping_add(cycle.wrapping_mul(104729)));
        let scale = size*size_variation(seed);
        let mut direction = sky_direction(seed);
        let (dx,dy) = (direction.0 as f32/10000.0,direction.1 as f32/10000.0);
        // Stratify birth positions, with fresh jitter on every event.
        let x = (slot%columns) as f32+unit(seed.wrapping_add(3));
        let y = (slot/columns) as f32+unit(seed.wrapping_add(4));
        let anchor = (x*w as f32/columns as f32,y*h as f32/rows as f32);
        let ((x,y),distance) = if c.effect == Effect::Asteroids {
            sky_path(anchor,(dx,dy),(w,h),margin)
        } else {
            let (start,distance,adjusted) = streak_path(seed,(w,h),direction);
            direction=adjusted;
            (start,distance)
        };
        let (dx,dy)=(direction.0 as f32/10000.0,direction.1 as f32/10000.0);
        // Speed variation is independent of the subtle size variation.
        let speed = if c.effect == Effect::Asteroids { 47.0 } else { 280.0 }
            *size*speed_variation(seed);
        let duration = distance/speed+if c.effect == Effect::Asteroids { 0.0 } else { 0.25 };
        if age>=duration { continue; }
        let fade_time = if c.effect == Effect::Asteroids { 0.6 } else { 0.16 };
        let envelope = (age/fade_time).min((duration-age)/fade_time).clamp(0.0,1.0);
        let envelope = envelope*envelope*(3.0-2.0*envelope);
        let radius = match c.effect {
            Effect::ShootingStars => 1.5*scale,
            Effect::Meteors => 3.0*scale,
            Effect::Asteroids => 8.0*scale,
            Effect::Matrix => unreachable!(),
        }.round().max(1.0) as i32;
        let tail = match c.effect {
            Effect::ShootingStars => 72.0*scale,
            Effect::Meteors => 135.0*scale,
            _ => 0.0,
        }.min(age*speed).round() as i32;
        let spin = (8.0+unit(seed.wrapping_add(7))*18.0)
            *if seed%2 == 0 { 1.0 } else { -1.0 };
        out.push(Particle {
            x: (x+dx*speed*age).round() as i32,
            y: (y+dy*speed*age).round() as i32,
            radius, tail, direction, seed, effect: c.effect, stationary: false,
            opacity: (envelope*(0.9+unit(seed.wrapping_add(8))*0.1)*255.0).round() as u8,
            angle: (unit(seed.wrapping_add(9))*360.0+age*spin).rem_euclid(360.0).round() as u32,
        });
    }
}

/// Emit covered pixels and palette levels; clipping and damage stay in the renderer.
pub fn rasterize(p: &Particle, mut output: impl FnMut(i32,i32,u8,usize)) {
    let mut plot = |x,y,coverage:u8,level| {
        output(x,y,(coverage as u32*p.opacity as u32/255) as u8,level);
    };
    if p.stationary {
        disc(p.x,p.y,p.radius as f32,255,17,&mut plot);
        return;
    }
    if p.effect == Effect::Asteroids {
        let angle = (p.angle as f32).to_radians();
        let (sin,cos) = angle.sin_cos();
        let radius = p.radius as f32;
        for dy in -p.radius-1..=p.radius+1 {
            for dx in -p.radius-1..=p.radius+1 {
                let (rx,ry) = (dx as f32*cos+dy as f32*sin, -dx as f32*sin+dy as f32*cos);
                let theta = ry.atan2(rx);
                let edge = radius*(0.87+0.08*(theta*5.0+(p.seed%7) as f32).sin()
                    +0.05*(theta*3.0).cos());
                let distance = (rx*rx+ry*ry).sqrt();
                let coverage = ((edge+0.6-distance).clamp(0.0,1.0)*255.0) as u8;
                if coverage == 0 { continue; }
                // Rotating craters and a fixed upper-left light make a faceted rock.
                let crater = ((rx-radius*0.2).powi(2)+(ry+radius*0.2).powi(2)).sqrt();
                let shade = if crater < radius*0.27 { 6 } else {
                    (11.0-(dx+dy) as f32/radius*3.0).clamp(5.0,15.0) as usize
                };
                plot(p.x+dx,p.y+dy,coverage,shade);
            }
        }
        return;
    }
    // Draw back-to-front with a smooth, tapered tail opposite this particle's velocity.
    for step in (1..=p.tail).rev() {
        let fade = 1.0-step as f32/p.tail as f32;
        let radius = if p.effect == Effect::Meteors {
            (p.radius as f32*fade*0.8).max(0.5)
        } else { 0.55 };
        disc(p.x-(step as f32*p.direction.0 as f32/10000.0).round() as i32,
            p.y-(step as f32*p.direction.1 as f32/10000.0).round() as i32,
            radius, (fade.powf(1.5)*220.0) as u8, 15, &mut plot);
    }
    disc(p.x,p.y,p.radius as f32+1.5,55,15,&mut plot);
    disc(p.x,p.y,p.radius as f32,255,16,&mut plot);
    if p.effect == Effect::ShootingStars {
        for offset in -3i32..=3 {
            let coverage = (160/(offset.abs()+1)) as u8;
            plot(p.x+offset,p.y,coverage,16);
            plot(p.x,p.y+offset,coverage,16);
        }
    }
}

fn disc(x: i32,y: i32,radius: f32,alpha: u8,level: usize,plot: &mut impl FnMut(i32,i32,u8,usize)) {
    let reach = radius.ceil() as i32;
    for dy in -reach..=reach {
        for dx in -reach..=reach {
            let coverage = (radius+0.5-((dx*dx+dy*dy) as f32).sqrt()).clamp(0.0,1.0);
            if coverage > 0.0 { plot(x+dx,y+dy,(coverage*alpha as f32) as u8,level); }
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn higher_event_density_adds_visible_moving_particles_in_all_space_modes() {
        for effect in [Effect::ShootingStars,Effect::Meteors,Effect::Asteroids] {
            for dimensions in [(640,520),(1920,1080)] {
                let mut particles=Vec::new();
                let mut totals=[0usize;2];
                for (index,density) in [50000.0/85000.0,1.0].into_iter().enumerate() {
                    let c=Config { effect,density,font_size:14,..Config::default() };
                    for frame in 0..600 {
                        generate(&mut particles,dimensions,&c,frame as f32/5.0);
                        totals[index]+=particles.iter().filter(|p| !p.stationary && p.opacity>0
                            && p.x>=0 && p.y>=0 && p.x<dimensions.0 as i32
                            && p.y<dimensions.1 as i32).count();
                    }
                }
                assert!(totals[1] as f32>totals[0] as f32*1.4,"{effect:?} {dimensions:?}: {totals:?}");
            }
        }
    }
    #[test]
    fn streak_paths_reach_lower_half_without_leaving_narrow_or_wide_screens() {
        for (w,h) in [(640,520),(1920,1080),(360,4320),(7680,460)] {
            for seed in 0..1000 {
                let ((x,y),distance,dir)=streak_path(seed,(w,h),sky_direction(seed));
                let (dx,dy)=(dir.0 as f32/10000.0,dir.1 as f32/10000.0);
                let (end_x,end_y)=(x+dx*distance,y+dy*distance);
                assert!((0.079..=0.281).contains(&(y/h as f32)));
                assert!((0.649..=0.851).contains(&(end_y/h as f32)));
                assert!(x>=0.0 && x<w as f32 && end_x>=0.0 && end_x<w as f32);
                assert!(dy>0.0);
                // Even the slowest pass completes before the next scheduled event.
                assert!(distance<=(w as f32*0.8).hypot(h as f32*0.82));
            }
        }
        for effect in [Effect::ShootingStars,Effect::Meteors] {
            let c=Config { effect,density:1.0,..Config::default() };
            let mut particles=Vec::new();
            let mut lower_passes=std::collections::HashSet::new();
            for frame in 0..1000 {
                generate(&mut particles,(1280,720),&c,frame as f32/10.0);
                for p in particles.iter().filter(|p| !p.stationary && p.y>360 && p.opacity>100) {
                    lower_passes.insert(p.seed);
                }
            }
            assert!(lower_passes.len()>20,"{effect:?}");
        }
    }
    #[test]
    fn stationary_stars_hold_then_renew_in_every_space_mode_independent_of_speed() {
        let mut reference=Vec::new();
        for effect in [Effect::ShootingStars,Effect::Meteors,Effect::Asteroids] {
            let mut c=Config { effect,..Config::default() };
            let mut first=Vec::new();
            let mut next=Vec::new();
            starfield(&mut first,(1280,720),&c,12.0);
            starfield(&mut next,(1280,720),&c,12.1);
            assert!(first.len()>20);
            for (a,b) in first.iter().zip(&next) {
                assert!(a.stationary && b.stationary);
                if a.seed==b.seed { assert_eq!((a.x,a.y,a.radius),(b.x,b.y,b.radius)); }
                assert_eq!(a.direction,(0,0));
            }
            next.clear();
            c.speed=30.0;
            starfield(&mut next,(1280,720),&c,12.0);
            assert_eq!(first,next);
            let signature: Vec<_>=first.iter().map(|p| (p.x,p.y,p.radius,p.opacity)).collect();
            if reference.is_empty() { reference=signature; } else { assert_eq!(reference,signature); }
            next.clear();
            starfield(&mut next,(1280,720),&c,65.0);
            assert!(first.iter().zip(&next).all(|(a,b)| a.seed!=b.seed));
            assert!(first.iter().zip(&next).filter(|(a,b)| (a.x,a.y)!=(b.x,b.y)).count()>20);
            assert!(first.iter().zip(&next).any(|(a,b)| a.radius!=b.radius));
            assert!(first.iter().zip(&next).any(|(a,b)| a.opacity!=b.opacity));
        }
    }
    #[test]
    fn size_variation_is_usually_subtle_with_rare_larger_and_smaller_particles() {
        let mut typical=0;
        let mut smaller=0;
        let mut larger=0;
        for seed in 0..10000 {
            let scale=size_variation(seed);
            if (0.94..=1.06).contains(&scale) { typical+=1; }
            else if scale==0.8 { smaller+=1; }
            else if scale==1.2 { larger+=1; }
            else { panic!("unexpected scale {scale}"); }
        }
        assert!((8800..=9200).contains(&typical));
        assert!((350..=650).contains(&smaller));
        assert!((350..=650).contains(&larger));
    }
    #[test]
    fn sky_events_keep_size_heading_and_speed_and_always_move_downward() {
        for effect in [Effect::ShootingStars,Effect::Meteors,Effect::Asteroids] {
            let c=Config { effect,density:1.0,..Config::default() };
            let mut previous=std::collections::HashMap::<u32,Particle>::new();
            let mut particles=Vec::new();

            let mut tracked=0;
            for frame in 0..2400 {
                generate(&mut particles,(1280,720),&c,frame as f32/10.0);
                let mut current=std::collections::HashMap::new();
                for p in particles.iter().filter(|p| !p.stationary) {
                    assert!(p.direction.1>0);
                    if let Some(old)=previous.get(&p.seed) {
                        assert_eq!(old.radius,p.radius);
                        assert_eq!(old.direction,p.direction);
                        let expected_speed = (if effect == Effect::Asteroids { 47.0 } else { 280.0 })
                            *c.font_size as f32/16.0*speed_variation(p.seed);
                        let distance=((p.x-old.x) as f32).hypot((p.y-old.y) as f32);
                        assert!((distance-expected_speed/10.0).abs()<1.5);
                        let (dx,dy)=(p.x-old.x,p.y-old.y);
                        assert!(dx*p.direction.0 as i32+dy*p.direction.1 as i32>=0);
                        // Rounded positions stay within one pixel of a straight trajectory.
                        assert!((dx*p.direction.1 as i32-dy*p.direction.0 as i32).abs()<=20000);
                        tracked+=1;
                    }
                    current.insert(p.seed,p.clone());
                }
                previous=current;
            }
            assert!(tracked>100);
        }
    }
    #[test]
    fn main_direction_and_speed_dominate_with_rare_outliers_and_no_bottom_entry() {
        let mut main=0;
        let mut ordinary_speed=0;
        let mut slower=0;
        let mut faster=0;
        let mut right_edge=0;
        for seed in 0..10000 {
            let dir=sky_direction(seed);
            let (dx,dy)=(dir.0 as f32/10000.0,dir.1 as f32/10000.0);
            assert!(dy>0.0);
            let degrees=dy.atan2(dx).to_degrees();
            if (50.9..=63.1).contains(&degrees) { main+=1; }
            let speed=speed_variation(seed);
            if (0.96..=1.04).contains(&speed) { ordinary_speed+=1; }
            else if speed==0.75 { slower+=1; }
            else if speed==1.25 { faster+=1; }
            else { panic!("unexpected speed {speed}"); }
            let anchor=(unit(seed.wrapping_add(3))*1280.0,unit(seed.wrapping_add(4))*720.0);
            let ((x,y),distance)=sky_path(anchor,(dx,dy),(1280,720),40.0);
            assert!(distance>0.0);
            assert!(y<720.0);
            assert!(x<0.0 || x>1280.0 || y<0.0);
            if x>1280.0 { right_edge+=1; }
            assert!(y+dy*distance>720.0 || x+dx*distance<0.0 || x+dx*distance>1280.0);
        }
        assert!((8800..=9400).contains(&main));
        assert!((8800..=9200).contains(&ordinary_speed));
        assert!((350..=650).contains(&slower));
        assert!((350..=650).contains(&faster));
        assert!(right_edge>0);
    }
    #[test]
    fn varied_trajectories_keep_every_drawn_pixel_inside_damage() {
        for effect in [Effect::ShootingStars,Effect::Meteors,Effect::Asteroids] {
            for font_size in [10,16,32] {
                let mut c = Config { effect,font_size,..Config::default() };
                let mut particles = Vec::new();
                for time in [0.0,12.0,99.0] {
                    generate(&mut particles,(640,520),&c,time);
                    for p in &particles {
                        let (x,y,w,h) = p.bounds();
                        rasterize(p, |px,py,_,level| {
                            assert!(px>=x && py>=y && px<x+w as i32 && py<y+h as i32);
                            assert!(level<=17);
                        });
                    }
                }
                c.density=0.0;
                generate(&mut particles,(640,520),&c,0.0);
                assert!(particles.is_empty());
            }
        }
    }
}

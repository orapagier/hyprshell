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
    comet: bool,
    pub stationary: bool,
}
impl Particle {
    pub fn bounds(&self) -> (i32,i32,u32,u32) {
        let margin = if self.comet { self.radius*4+4 } else { self.radius+4 };
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

/// Sporadic meteors ignite anywhere in the upper/middle sky and burn out in view.
fn streak_path(seed: u32, region: u32, (w,h): (u32,u32))
    -> ((f32,f32),f32,(i16,i16)) {
    // Equal-width birth regions get the same opportunities, with fresh jitter.
    let x = w as f32*(region as f32+0.03+unit(seed.wrapping_add(701))*0.94)/3.0;
    let vertical = region==1 && unit(seed.wrapping_add(711))<0.65;
    let y = h as f32*if vertical {
        0.02+unit(seed.wrapping_add(709))*0.12
    } else { 0.04+unit(seed.wrapping_add(709)).powf(1.4)*0.51 };
    // Mirrored side distributions remove a preferred diagonal; central events
    // mostly fall straight down, while the rest have symmetric angle variation.
    let tilt = unit(seed.wrapping_add(713));
    let degrees = if vertical { 90.0 } else { match region {
        0 => 28.0+tilt*70.0,
        2 => 152.0-tilt*70.0,
        _ => 35.0+tilt*110.0,
    }};
    let (dy,dx) = degrees.to_radians().sin_cos();
    let direction = ((dx*10000.0).round() as i16,(dy*10000.0).round() as i16);
    let (dx,dy)=(direction.0 as f32/10000.0,direction.1 as f32/10000.0);
    let available_x = if dx>0.0 { w as f32-x } else { x }/dx.abs().max(0.0001);
    let available_y = (h as f32-y)/dy;
    let length = (w as f32).hypot(h as f32)*(0.12+unit(seed.wrapping_add(719))*0.24);
    ((x,y),length.min(available_x.min(available_y)*0.88),direction)
}

/// Stateless random time windows allow quiet gaps and overlapping events without
/// frame-rate-dependent spawning or an identical repeating stream per particle.
fn streaks(out: &mut Vec<Particle>, (w,h): (u32,u32), c: &Config, time: f32) {
    let clock = time*c.speed/9.0;
    let window = (clock/8.0).floor() as i32;
    let area = w as f32*h as f32/(1920.0*1080.0);
    let lanes = area.ceil().clamp(1.0,16.0) as u32;
    // Keep sparse settings quiet, with a much busier sky toward 100%.
    let activity = c.density*(0.12+0.88*c.density*c.density);
    let chance = (activity*area.max(0.35)/lanes as f32).min(1.0);
    let size = c.font_size as f32/16.0;
    for period in (window-1).max(0)..=window {
        for slot in 0..lanes*72 {
            let group = slot/3;
            let group_seed = hash((period as u32).wrapping_mul(104729).wrapping_add(group*7919+971));
            // Accept a left/center/right triplet together, but randomize each
            // birth time independently across the window (no visible rotation).
            if unit(group_seed)>chance { continue; }
            let seed = hash(group_seed.wrapping_add((slot%3)*65537+179));
            let region = slot%3;
            let birth = period as f32*8.0+unit(seed.wrapping_add(1))*8.0;
            let cluster = if unit(seed.wrapping_add(2))<0.09 { 2+seed%2 } else { 1 };
            for member in 0..cluster {
                let event = if member==0 { seed } else { hash(seed.wrapping_add(member*65537)) };
                let age = clock-birth-member as f32*(0.12+unit(event)*0.36);
                let ((x,y),distance,direction) = streak_path(event,region,(w,h));
                let comet = unit(event.wrapping_add(43))<0.08;
                let speed = (650.0+unit(event.wrapping_add(31))*650.0)*size
                    *if comet { 0.38 } else { 1.0 };
                let distance = distance.min(speed*if comet { 3.8 } else { 1.35 });
                let duration = distance/speed;
                if age<0.0 || age>=duration { continue; }
                let phase = age/duration;
                let fade = (phase/0.12).min((1.0-phase)/0.32).clamp(0.0,1.0);
                let envelope = fade*fade*(3.0-2.0*fade);
                let bright = c.effect==Effect::Meteors || unit(event.wrapping_add(37))<0.20;
                let effect = if bright || comet { Effect::Meteors } else { Effect::ShootingStars };
                let scale = size*size_variation(event);
                let tail = (if comet { 280.0 } else if bright { 125.0 } else { 65.0 })*scale;
                let tail = tail.min(age*speed).min(distance*if comet { 0.85 } else { 0.60 })
                    *(1.0-((phase-0.65)/0.35).clamp(0.0,1.0)*0.65);
                let (dx,dy)=(direction.0 as f32/10000.0,direction.1 as f32/10000.0);
                // A brief late brightening on some fireballs, never frame noise.
                let flare = if bright && event%3==0 {
                    0.7+0.3*(-((phase-0.68)/0.10).powi(2)).exp()
                } else { 1.0 };
                out.push(Particle {
                    x: (x+dx*speed*age).round() as i32,
                    y: (y+dy*speed*age).round() as i32,
                    radius: ((if comet { 1.4 } else if bright { 1.8 } else { 0.8 })*scale).round().max(1.0) as i32,
                    tail: tail.round() as i32, direction,
                    opacity: (envelope*flare*(0.65+unit(event.wrapping_add(41))*0.35)*255.0).round() as u8,
                    angle: 0, seed: event, effect, comet, stationary: false,
                });
            }
        }
    }
}

fn starfield(out: &mut Vec<Particle>, (w,h): (u32,u32), c: &Config, time: f32) {
    let richness = if c.effect==Effect::Asteroids { 1.0 } else { 1.0+3.0*c.density*c.density };
    let count = ((w as f32*h as f32/16000.0*c.density*richness).ceil() as u32)
        .clamp(1,if c.effect==Effect::Asteroids { 220 } else { 880 });
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
            tail: 0, direction: (0,0), angle: 0, seed, effect: c.effect, comet: false, stationary: true,
        });
    }
}

pub fn generate(out: &mut Vec<Particle>, (w,h): (u32,u32), c: &Config, time: f32) {
    out.clear();
    if c.effect == Effect::Matrix || c.density <= 0.0 || w == 0 || h == 0 { return; }
    starfield(out,(w,h),c,time);
    if c.effect != Effect::Asteroids {
        streaks(out,(w,h),c,time);
        return;
    }
    let size = c.font_size as f32 / 16.0;
    let slots = ((w as f32*h as f32/50000.0*c.density/size).ceil() as u32).clamp(1,220);
    let columns = ((slots as f32*w as f32/h as f32).sqrt().ceil() as u32).max(1);
    let rows = slots.div_ceil(columns);
    let clock = time*c.speed/9.0;
    for slot in 0..slots {
        let base = hash(slot+7919);
        let margin = 40.0*size;
        let interval = ((w as f32).hypot(h as f32)+margin*2.0)/(28.0*size)+5.0;
        let cursor = clock+unit(base.wrapping_add(1))*interval;
        let cycle = (cursor/interval).floor() as u32;
        let age = cursor.rem_euclid(interval);
        let seed = hash(base.wrapping_add(cycle.wrapping_mul(104729)));
        let scale = size*size_variation(seed);
        let direction = sky_direction(seed);
        let (dx,dy) = (direction.0 as f32/10000.0,direction.1 as f32/10000.0);
        let x = (slot%columns) as f32+unit(seed.wrapping_add(3));
        let y = (slot/columns) as f32+unit(seed.wrapping_add(4));
        let anchor = (x*w as f32/columns as f32,y*h as f32/rows as f32);
        let ((x,y),distance) = sky_path(anchor,(dx,dy),(w,h),margin);
        let speed = 47.0*size*speed_variation(seed);
        let duration = distance/speed;
        if age>=duration { continue; }
        let envelope = (age/0.6).min((duration-age)/0.6).clamp(0.0,1.0);
        let envelope = envelope*envelope*(3.0-2.0*envelope);
        let radius = (8.0*scale).round().max(1.0) as i32;
        let tail = 0;
        let spin = (8.0+unit(seed.wrapping_add(7))*18.0)
            *if seed%2 == 0 { 1.0 } else { -1.0 };
        out.push(Particle {
            x: (x+dx*speed*age).round() as i32,
            y: (y+dy*speed*age).round() as i32,
            radius, tail, direction, seed, effect: c.effect, comet: false, stationary: false,
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
        let radius = (p.radius as f32*fade*0.65).max(0.45);
        let x = p.x-(step as f32*p.direction.0 as f32/10000.0).round() as i32;
        let y = p.y-(step as f32*p.direction.1 as f32/10000.0).round() as i32;
        if p.comet {
            disc(x,y,p.radius as f32*(0.7+(1.0-fade)*2.5),
                (fade.powf(2.2)*65.0) as u8,15,&mut plot);
        }
        disc(x,y,radius,(fade.powf(1.8)*210.0) as u8,16,&mut plot);
    }
    disc(p.x,p.y,p.radius as f32+1.5,55,15,&mut plot);
    disc(p.x,p.y,p.radius as f32,255,17,&mut plot);
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
    fn higher_density_adds_visible_moving_particles_in_all_space_modes() {
        for effect in [Effect::ShootingStars,Effect::Meteors,Effect::Asteroids] {
            for dimensions in [(640,520),(1920,1080)] {
                let mut particles=Vec::new();
                let mut totals=[0usize;2];
                for (index,density) in [50000.0/85000.0,1.0].into_iter().enumerate() {
                    let c=Config { effect,density,font_size:14,..Config::default() };
                    for frame in 0..6000 {
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
    fn streaks_use_varied_origins_and_burn_out_inside_the_view() {
        for (w,h) in [(640,520),(1920,1080),(360,4320),(7680,460)] {
            let mut regions=[0;3];
            let mut directions=[0;2];
            let mut middle=0;
            for seed in 0..1000 {
                let ((x,y),distance,dir)=streak_path(seed,seed%3,(w,h));
                let (dx,dy)=(dir.0 as f32/10000.0,dir.1 as f32/10000.0);
                let (end_x,end_y)=(x+dx*distance,y+dy*distance);
                assert!((0.019..=0.551).contains(&(y/h as f32)));
                assert!(distance>0.0 && dy>0.0);
                assert!(x>=0.0 && x<w as f32 && end_x>=0.0 && end_x<w as f32);
                assert!(end_y<h as f32);
                regions[((x/w as f32*3.0) as usize).min(2)]+=1;
                directions[usize::from(dx>0.0)]+=1;
                if y>h as f32*0.3 { middle+=1; }
            }
            assert!(regions.iter().all(|count| *count>200));
            assert!(directions.iter().all(|count| *count>350));
            assert!(middle>200);
        }
    }
    #[test]
    fn shooting_stars_have_quiet_gaps_bursts_and_occasional_bright_meteors() {
        let c=Config { effect:Effect::ShootingStars,density:0.20,..Config::default() };
        let mut particles=Vec::new();
        let mut seen=std::collections::HashMap::new();
        let (mut quiet,mut overlapping,mut longest_gap,mut gap)=(0,0,0,0);
        for frame in 0..12000 {
            let time=frame as f32/20.0;
            generate(&mut particles,(1920,1080),&c,time);
            let mut count=0;
            for p in particles.iter().filter(|p| !p.stationary) {
                count+=1;
                let event=seen.entry(p.seed).or_insert((time,time,p.effect,p.comet));
                event.1=time;
                assert!(event.1-event.0<if p.comet { 3.9 } else { 1.4 });
            }
            if count==0 { quiet+=1; gap+=1; longest_gap=longest_gap.max(gap); }
            else { gap=0; }
            if count>1 { overlapping+=1; }
        }
        assert!(seen.len()>80);
        let bright=seen.values().filter(|event| event.2==Effect::Meteors && !event.3).count();
        assert!(bright>3 && bright<seen.len()/3);
        assert!(quiet>6000 && overlapping>20 && longest_gap>80);
        // Seeking is deterministic and does not depend on previous frames.
        let mut sought=Vec::new();
        generate(&mut particles,(1920,1080),&c,160.05);
        generate(&mut sought,(1920,1080),&c,3.0);
        generate(&mut sought,(1920,1080),&c,160.05);
        assert_eq!(particles,sought);
    }
    #[test]
    fn maximum_density_balances_visible_births_and_includes_vertical_center_and_comets() {
        for dimensions in [(640,520),(1920,1080)] {
            let mut particles=Vec::new();
            let mut totals=[0usize;2];
            for (index,density) in [0.55,1.0].into_iter().enumerate() {
                let c=Config { effect:Effect::ShootingStars,density,..Config::default() };
                let mut births=std::collections::HashMap::new();
                let mut active=0;
                for frame in 0..1800 {
                    generate(&mut particles,dimensions,&c,frame as f32/30.0);
                    for p in particles.iter().filter(|p| !p.stationary && p.opacity>0) {
                        active+=1;
                        births.entry(p.seed).or_insert_with(|| p.clone());
                    }
                }
                totals[index]=births.len();
                if density<1.0 { continue; }
                let mut regions=[0usize;3];
                let mut kinds=[0usize;3];
                let mut vertical=0;
                for p in births.values() {
                    regions[((p.x as f32/dimensions.0 as f32*3.0) as usize).min(2)]+=1;
                    kinds[if p.comet { 2 } else if p.effect==Effect::Meteors { 1 } else { 0 }]+=1;
                    if p.direction.0==0 {
                        assert!(p.x as f32>dimensions.0 as f32/3.0
                            && (p.x as f32)<dimensions.0 as f32*2.0/3.0);
                        assert!((p.y as f32)<dimensions.1 as f32*0.25);
                        vertical+=1;
                    }
                }
                let count=births.len() as f32;
                assert!(regions.iter().all(|n| *n as f32>count*0.25 && (*n as f32)<count*0.42),
                    "{dimensions:?}: {regions:?}");
                assert!(((regions[0] as i32-regions[2] as i32).unsigned_abs() as f32)<count*0.08,
                    "{dimensions:?}: {regions:?}");
                assert!(vertical as f32>count*0.15);
                assert!(kinds[0] as f32>count*0.5 && kinds[1] as f32>count*0.10
                    && kinds[2] as f32>count*0.03,"{kinds:?}");
                assert!(active>if dimensions.0==1920 { 4000 } else { 1000 },
                    "{dimensions:?}: {active}");
            }
            assert!(totals[1]>totals[0]*3,"{dimensions:?}: {totals:?}");
        }
        let mut stars=Vec::new();
        let c=Config { effect:Effect::ShootingStars,density:1.0,..Config::default() };
        starfield(&mut stars,(1920,1080),&c,12.0);
        assert!(stars.len()>500);
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
            if reference.is_empty() { reference=signature; }
            else if effect!=Effect::Asteroids { assert_eq!(reference,signature); }
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
                        let expected_speed = if effect == Effect::Asteroids {
                            47.0*c.font_size as f32/16.0*speed_variation(p.seed)
                        } else {
                            (650.0+unit(p.seed.wrapping_add(31))*650.0)*c.font_size as f32/16.0
                                *if p.comet { 0.38 } else { 1.0 }
                        };
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
                let mut moving=0;
                for frame in 0..600 {
                    generate(&mut particles,(640,520),&c,frame as f32/10.0);
                    moving+=particles.iter().filter(|p| !p.stationary).count();
                    for p in &particles {
                        let (x,y,w,h) = p.bounds();
                        rasterize(p, |px,py,_,level| {
                            assert!(px>=x && py>=y && px<x+w as i32 && py<y+h as i32);
                            assert!(level<=17);
                        });
                    }
                }
                assert!(moving>0,"{effect:?} at size {font_size}");
                c.density=0.0;
                generate(&mut particles,(640,520),&c,0.0);
                assert!(particles.is_empty());
            }
        }
    }
}

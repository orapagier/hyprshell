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
    seed: u32,
    effect: Effect,
    comet: bool,
    twinkle: bool,
    pub stationary: bool,
}
impl Particle {
    pub fn bounds(&self) -> (i32,i32,u32,u32) {
        let margin = if self.comet { self.radius*4+4 } else if self.twinkle { self.radius*3+4 } else { self.radius+4 };
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

/// Evenly spaced rain lanes, with rare diagonal passes and early burn-outs.
fn streak_path(seed: u32, lane: u32, lanes: u32, (w,h): (u32,u32), size: f32)
    -> ((f32,f32),f32,(i16,i16),bool) {
    let x = w as f32*(lane as f32+0.5+(unit(seed.wrapping_add(701))-0.5)*0.2)/lanes as f32;
    let y = -8.0*size;
    let vertical = unit(seed.wrapping_add(711))<0.95;
    let tilt = 12.0+unit(seed.wrapping_add(713))*50.0;
    let degrees = if vertical { 90.0 } else {
        90.0+tilt*if unit(seed.wrapping_add(717))<0.5 { -1.0 } else { 1.0 }
    };
    let (dy,dx) = degrees.to_radians().sin_cos();
    let direction = ((dx*10000.0).round() as i16,(dy*10000.0).round() as i16);
    let (dx,dy)=(direction.0 as f32/10000.0,direction.1 as f32/10000.0);
    let available_x = if dx>0.0 { w as f32-x } else { x }/dx.abs().max(0.0001);
    let burns_out = unit(seed.wrapping_add(719))<0.12;
    let end_y = if burns_out {
        h as f32*(0.18+unit(seed.wrapping_add(727))*0.64)
    } else {
        // Keep the head bright through the bottom, then let the whole tail exit.
        h as f32+(280.0*2.8*size).min(h as f32*0.45)+16.0*size
    };
    let distance = ((end_y-y)/dy).min(available_x+((280.0*2.8+16.0)*size));
    ((x,y),distance,direction,burns_out)
}

fn streak_pace(c: &Config) -> f32 {
    // Matrix moves in (font_size + 5)-pixel rows per Speed unit. Match its
    // typical pixel velocity, scaling the entire event clock so slower motion
    // lengthens each pass without piling up extra simultaneous streaks.
    9.0*(c.font_size+5) as f32/(975.0*(c.font_size as f32/16.0))
}

// Independent choices scatter slow lanes and larger passes throughout the rain.
fn streak_speed_variation(seed: u32) -> f32 {
    if unit(seed.wrapping_add(751))<0.15 {
        0.40+unit(seed.wrapping_add(757))*0.25
    } else { 1.0 }
}

fn streak_size_variation(seed: u32) -> f32 {
    if unit(seed.wrapping_add(761))<0.12 {
        1.8+unit(seed.wrapping_add(769))
    } else { size_variation(seed) }
}

/// Staggered lanes give each screen column a continuous succession of passes.
/// Lane speed fixes its cadence; event size, heading and burn-out vary each pass.
fn streaks(out: &mut Vec<Particle>, (w,h): (u32,u32), c: &Config, time: f32) {
    let clock = time*c.speed/9.0*streak_pace(c);
    let pitch = (((c.font_size*2/3).max(7)+4) as f32/c.density).round().max(1.0);
    let lanes = (w as f32/pitch).floor().max(1.0) as u32;
    let size = c.font_size as f32/16.0;
    let padding = (280.0*2.8*size).min(h as f32*0.45)+16.0*size;
    // Include older tails and shallow diagonals without a fixed lifetime cap.
    let history = ((h as f32+padding+8.0*size)/(h as f32*0.469)).ceil() as i32+1;
    for lane in 0..lanes {
        let base = hash(lane+7919);
        let comet = unit(base.wrapping_add(43))<0.08;
        let speed = (650.0+unit(base.wrapping_add(31))*650.0)*size
            *streak_speed_variation(base)*if comet { 0.38 } else { 1.0 };
        let interval = h as f32/speed;
        let cursor = clock+unit(base.wrapping_add(1))*interval;
        let cycle = (cursor/interval).floor() as i32;
        for period in cycle-history..=cycle {
            let seed = hash(base.wrapping_add((period as u32).wrapping_mul(104729)));
            let birth = period as f32*interval;
            let cluster = if unit(seed.wrapping_add(2))<0.09 { 2+seed%2 } else { 1 };
            for member in 0..cluster {
                let event = if member==0 { seed } else { hash(seed.wrapping_add(member*65537)) };
                let age = cursor-birth-member as f32*interval*(0.12+unit(event)*0.16);
                if age<0.0 { continue; }
                let ((x,y),distance,direction,burns_out) = streak_path(event,lane,lanes,(w,h),size);
                let duration = distance/speed;
                if age>=duration { continue; }
                let phase = age/duration;
                let fade = (age*speed/(20.0*size)).min(if burns_out {
                    (1.0-phase)/0.25
                } else { 1.0 }).clamp(0.0,1.0);
                let envelope = fade*fade*(3.0-2.0*fade);
                let bright = c.effect==Effect::Meteors || unit(event.wrapping_add(37))<0.20;
                let effect = if bright || comet { Effect::Meteors } else { Effect::ShootingStars };
                let scale = size*streak_size_variation(event);
                let tail = ((if comet { 280.0 } else if bright { 125.0 } else { 65.0 })*scale)
                    .min(h as f32*0.45);
                let tail = tail.min(age*speed).min(distance*if comet { 0.85 } else { 0.60 })
                    *if burns_out { 1.0-((phase-0.65)/0.35).clamp(0.0,1.0)*0.65 } else { 1.0 };
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
                    seed: event, effect, comet, twinkle: false, stationary: false,
                });
            }
        }
    }
}

fn starfield(out: &mut Vec<Particle>, (w,h): (u32,u32), c: &Config, time: f32) {
    let richness = 0.92;
    let count = ((w as f32*h as f32/16000.0*c.density*richness).ceil() as u32)
        .clamp(1,1760);
    let sky_height = (h/2).max(1);
    let columns = ((count as f32*w as f32/sky_height as f32).sqrt().ceil() as u32).max(1);
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
            y: (((slot/columns) as f32+unit(seed.wrapping_add(3)))*sky_height as f32/rows as f32)
                .round().clamp(0.0,sky_height.saturating_sub(1) as f32) as i32,
            radius: ((0.55+unit(seed.wrapping_add(4)).powf(1.5)*2.4)*(c.font_size as f32/16.0).max(0.9))
                .round().clamp(1.0,3.0) as i32,
            opacity: (fade*(40.0+unit(seed.wrapping_add(5))*110.0)).round() as u8,
            tail: 0, direction: (0,0), seed, effect: c.effect, comet: false, twinkle: false, stationary: true,
        });
    }
}

/// Sparse, independent glints fade in and out without moving or following Speed.
fn twinkles(out: &mut Vec<Particle>, (w,h): (u32,u32), c: &Config, time: f32) {
    let slots = (w as f32*h as f32/500000.0*c.density).ceil().clamp(1.0,16.0) as u32;
    for slot in 0..slots {
        let base = hash(slot+1789211);
        let interval = 5.0+unit(base)*6.0;
        let cursor = time+unit(base.wrapping_add(1))*interval;
        let cycle = (cursor/interval).floor() as u32;
        let seed = hash(base.wrapping_add(cycle.wrapping_mul(65537)));
        let age = cursor.rem_euclid(interval);
        let duration = 1.2+unit(seed.wrapping_add(2))*1.2;
        if age>=duration { continue; }
        let fade = (std::f32::consts::PI*age/duration).sin().powi(2);
        let size = if unit(seed.wrapping_add(5))<0.65 {
            0.8+unit(seed.wrapping_add(6))*0.6
        } else { 3.2+unit(seed.wrapping_add(6))*1.6 };
        out.push(Particle {
            x: (unit(seed.wrapping_add(3))*w as f32).floor() as i32,
            y: (unit(seed.wrapping_add(4))*h as f32).floor() as i32,
            radius: (size*(c.font_size as f32/16.0)).round().clamp(1.0,6.0) as i32,
            opacity: (fade*255.0).round() as u8,
            tail: 0, direction: (0,0), seed, effect: c.effect, comet: false,
            twinkle: true, stationary: true,
        });
    }
}

pub fn generate(out: &mut Vec<Particle>, (w,h): (u32,u32), c: &Config, time: f32) {
    out.clear();
    if c.effect == Effect::Matrix || c.density <= 0.0 || w == 0 || h == 0 { return; }
    starfield(out,(w,h),c,time);
    if c.effect == Effect::ShootingStars { twinkles(out,(w,h),c,time); }
    streaks(out,(w,h),c,time);
}

/// Emit covered pixels and palette levels; clipping and damage stay in the renderer.
pub fn rasterize(p: &Particle, mut output: impl FnMut(i32,i32,u8,usize)) {
    let mut plot = |x,y,coverage:u8,level| {
        output(x,y,(coverage as u32*p.opacity as u32/255) as u8,level);
    };
    if p.stationary {
        if p.twinkle {
            // Four tapered rays grow with the light, around a soft neutral core.
            let reach = (p.radius*3) as f32*(p.opacity as f32/255.0).sqrt();
            for step in 1..=reach.ceil() as i32 {
                let alpha = ((1.0-step as f32/(reach+1.0)).powi(2)*190.0) as u8;
                for (dx,dy) in [(step,0),(-step,0),(0,step),(0,-step)] {
                    disc(p.x+dx,p.y+dy,0.65,alpha,17,&mut plot);
                }
            }
            disc(p.x,p.y,p.radius as f32+1.5,40,17,&mut plot);
        }
        disc(p.x,p.y,p.radius as f32,255,17,&mut plot);
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
    fn twinkles_are_sparse_smooth_and_scattered_across_the_screen() {
        let c=Config { effect:Effect::ShootingStars,density:0.3,..Config::default() };
        let mut particles=Vec::new();
        let mut previous=std::collections::HashMap::<u32,Particle>::new();
        let mut regions=std::collections::HashSet::new();
        let (mut active,mut dark,mut rising,mut falling)=(0,0,0,0);
        for frame in 0..6000 {
            particles.clear();
            twinkles(&mut particles,(1920,1080),&c,frame as f32/20.0);
            assert!(particles.len()<=2);
            if particles.is_empty() { dark+=1; }
            let mut current=std::collections::HashMap::new();
            for p in &particles {
                active+=1;
                assert!(p.stationary && p.twinkle && p.tail==0 && p.direction==(0,0));
                assert!((0..1920).contains(&p.x) && (0..1080).contains(&p.y));
                regions.insert((p.x/640,p.y/360));
                if let Some(old)=previous.get(&p.seed) {
                    assert_eq!((p.x,p.y,p.radius),(old.x,old.y,old.radius));
                    assert!((p.opacity as i16-old.opacity as i16).abs()<=35);
                    if p.opacity>old.opacity { rising+=1; }
                    if p.opacity<old.opacity { falling+=1; }
                } else if frame>0 { assert!(p.opacity<=5); }
                current.insert(p.seed,p.clone());
            }
            previous=current;
        }
        assert_eq!(regions.len(),9,"Twinkles must reach every third of both axes");
        assert!(dark>2000 && active>1000 && active<6000,"{dark} empty / {active} glints");
        assert!(rising>400 && falling>400);
        let mut a=Vec::new();
        let mut b=Vec::new();
        for time in [0.0,0.1,12.0,25.0,121.0] {
            a.clear(); b.clear();
            twinkles(&mut a,(1920,1080),&c,time);
            twinkles(&mut b,(1920,1080),&Config { speed:30.0,..c.clone() },time);
            assert_eq!(a,b);
        }
    }
    #[test]
    fn only_shooting_stars_add_twinkles_and_zero_density_hides_them() {
        for effect in Effect::ALL {
            for density in [0.0,1.0] {
                let c=Config { effect,density,..Config::default() };
                let mut particles=Vec::new();
                let mut glints=0;
                for frame in 0..300 {
                    generate(&mut particles,(1920,1080),&c,frame as f32/15.0);
                    glints+=particles.iter().filter(|p| p.twinkle && p.opacity>0).count();
                }
                if effect==Effect::ShootingStars && density>0.0 { assert!(glints>30); }
                else { assert_eq!(glints,0); }
            }
        }
    }
    #[test]
    fn twinkles_mix_small_and_large_stars_at_every_particle_size() {
        for font_size in [10,12,16,32] {
            let c=Config { effect:Effect::ShootingStars,density:1.0,font_size,..Config::default() };
            let mut particles=Vec::new();
            let mut seen=std::collections::HashMap::new();
            for frame in 0..6000 {
                particles.clear();
                twinkles(&mut particles,(1920,1080),&c,frame as f32/20.0);
                for p in &particles { seen.insert(p.seed,p.radius); }
            }
            let small_limit=(1.4*font_size as f32/16.0).round() as i32;
            let large_limit=(3.2*font_size as f32/16.0).round().min(6.0) as i32;
            let small=seen.values().filter(|&&radius| radius<=small_limit).count();
            let large=seen.values().filter(|&&radius| radius>=large_limit).count();
            assert!(small>seen.len()/2 && large>seen.len()/5,"size {font_size}: {small} small / {large} large");
            assert!(large_limit>=small_limit+1);
        }
    }
    #[test]
    fn higher_density_adds_visible_moving_particles_in_all_space_modes() {
        for effect in [Effect::ShootingStars,Effect::Meteors] {
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
    fn streak_paths_are_balanced_mostly_vertical_and_usually_cross_the_bottom() {
        for (w,h) in [(640,520),(1920,1080),(360,4320),(7680,460)] {
            let mut directions=[0;3];
            let mut regions=[0;10];
            let mut diagonal_angles=std::collections::HashSet::new();
            let (mut bottom,mut early)=(0,0);
            for seed in 0..10000 {
                let ((x,y),distance,dir,burns_out)=streak_path(seed,seed%30,30,(w,h),1.0);
                let (dx,dy)=(dir.0 as f32/10000.0,dir.1 as f32/10000.0);
                assert!(y<0.0 && x>=0.0 && x<w as f32);
                assert!(distance>0.0 && dy>0.0);
                regions[((x/w as f32*10.0) as usize).min(9)]+=1;
                directions[if dir.0==0 { 1 } else if dir.0<0 { 0 } else { 2 }]+=1;
                if dir.0!=0 {
                    let tilt=(dy.atan2(dx).to_degrees()-90.0).abs();
                    assert!((11.9..=62.1).contains(&tilt));
                    diagonal_angles.insert(tilt.round() as i32);
                }
                if y+dy*distance>=h as f32 { bottom+=1; }
                if burns_out {
                    assert!(y+dy*distance<h as f32*0.821);
                    early+=1;
                }
            }
            assert!(regions.iter().all(|n| (990..=1010).contains(n)),"{regions:?}");
            assert!((9350..=9650).contains(&directions[1]),"{directions:?}");
            assert!(directions[0]>150 && directions[2]>150,"{directions:?}");
            assert!(diagonal_angles.len()>40);
            assert!(bottom>8200,"{w}x{h}: {bottom} bottom exits");
            assert!((1000..=1400).contains(&early),"{early} early fade-outs");
        }
    }
    #[test]
    fn visible_rain_fills_even_lanes_and_stays_bright_near_the_bottom() {
        for effect in [Effect::ShootingStars,Effect::Meteors] {
            for (w,h) in [(640,520),(1920,1080)] {
                for density in [0.30,1.0] {
                    let c=Config { effect,density,speed:6.0,font_size:12,..Config::default() };
                    let pitch=(((c.font_size*2/3).max(7)+4) as f32/density).round();
                    let lanes=(w as f32/pitch).floor().max(1.0) as usize;
                    let mut particles=Vec::new();
                    let mut bands=[0usize;6];
                    let (mut occupied,mut moving,mut diagonal,mut upper,mut lower)=(0,0,0,0,0);
                    for frame in 0..1200 {
                        generate(&mut particles,(w,h),&c,frame as f32/10.0);
                        let mut columns=std::collections::HashSet::new();
                        for p in particles.iter().filter(|p| !p.stationary && p.opacity>0
                            && p.x>=0 && p.x<w as i32 && p.y>=0 && p.y<h as i32) {
                            moving+=1;
                            bands[((p.x as f32/w as f32*6.0) as usize).min(5)]+=1;
                            if p.direction.0==0 {
                                columns.insert((p.x as f32/w as f32*lanes as f32) as usize);
                            } else { diagonal+=1; }
                            if p.y<h as i32/3 { upper+=1; }
                            if p.y>h as i32*2/3 && p.opacity>=100 { lower+=1; }
                        }
                        occupied+=columns.len();
                    }
                    let mean=occupied as f32/1200.0;
                    assert!(mean>lanes as f32*0.75,"{effect:?} {w}x{h} {density}: {mean}/{lanes} lanes");
                    // Account for whole lanes: a sixteenth of the screen cannot
                    // be divided equally into six bands at low density.
                    for (band,count) in bands.iter().enumerate() {
                        let band_lanes=(0..lanes).filter(|lane|
                            ((*lane as f32+0.5)/lanes as f32*6.0) as usize==band).count();
                        let expected=moving as f32*band_lanes as f32/lanes as f32;
                        assert!((*count as f32)>expected*0.75 && (*count as f32)<expected*1.25,
                            "{effect:?} {w}x{h} {density}: {bands:?}, band {band} expected {expected}");
                    }
                    assert!((diagonal as f32)<moving as f32*0.09);
                    assert!(lower as f32>upper as f32*0.70,"{upper} upper / {lower} bright lower heads");
                }
            }
        }
    }
    #[test]
    fn streaks_include_independent_slow_and_large_passes() {
        let (mut slow,mut large,mut both)=(0,0,0);
        for seed in 0..10000 {
            let speed=streak_speed_variation(seed);
            let size=streak_size_variation(seed);
            assert!(speed==1.0 || (0.40..=0.65).contains(&speed));
            assert!((0.8..=1.2).contains(&size) || (1.8..=2.8).contains(&size));
            if speed<1.0 { slow+=1; }
            if size>1.2 { large+=1; }
            if speed<1.0 && size>1.2 { both+=1; }
        }
        assert!((1300..=1700).contains(&slow),"{slow} slow passes");
        assert!((1000..=1400).contains(&large),"{large} large passes");
        assert!((100..=260).contains(&both),"{both} slow large passes");
    }
    #[test]
    fn staggered_streaks_keep_clusters_mixed_meteors_and_deterministic_seeking() {
        let c=Config { effect:Effect::ShootingStars,density:0.3,..Config::default() };
        let mut particles=Vec::new();
        let mut seen=std::collections::HashMap::new();
        for frame in 0..1200 {
            generate(&mut particles,(1920,1080),&c,frame as f32/10.0);
            for p in particles.iter().filter(|p| !p.stationary) {
                seen.entry(p.seed).or_insert((p.effect,p.comet));
            }
        }
        assert!(seen.len()>300);
        let bright=seen.values().filter(|event| event.0==Effect::Meteors && !event.1).count();
        assert!(bright>seen.len()/10 && bright<seen.len()/3);
        assert!(seen.values().any(|event| event.1));
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
                    if p.direction.0==0 && p.x as f32>dimensions.0 as f32/3.0
                        && (p.x as f32)<dimensions.0 as f32*2.0/3.0 {
                        vertical+=1;
                    }
                }
                let count=births.len() as f32;
                assert!(births.len()>if dimensions.0==1920 { 1200 } else { 400 },
                    "{dimensions:?}: {} births",births.len());
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
            assert!(totals[1] as f32>totals[0] as f32*1.6,"{dimensions:?}: {totals:?}");
        }
        let mut stars=Vec::new();
        for effect in [Effect::ShootingStars,Effect::Meteors] {
            stars.clear();
            let c=Config { effect,density:1.0,..Config::default() };
            starfield(&mut stars,(1920,1080),&c,12.0);
            let range=115..=125;
            assert!(range.contains(&stars.len()),"{effect:?}: {} stars",stars.len());
            {
                assert!(stars.iter().all(|p| (0..540).contains(&p.y)));
                assert!(stars.iter().any(|p| p.y>400));
                assert!(stars.iter().filter(|p| p.radius==1).count()>stars.len()/3);
                assert!(stars.iter().filter(|p| p.radius>=2).count()>stars.len()/5);
                assert!(stars.iter().any(|p| p.radius==3));
            }
        }
    }
    #[test]
    fn sky_activity_approaches_matrix_stream_count_at_matching_density() {
        for effect in [Effect::ShootingStars,Effect::Meteors] {
            for (w,h) in [(640,520),(1280,720),(1920,1080)] {
                for font_size in [12,16,32] {
                    for density in [0.25,0.55,1.0] {
                        let c=Config { effect,density,font_size,..Config::default() };
                        let mut particles=Vec::new();
                        let mut active=0;
                        for frame in 0..300 {
                            generate(&mut particles,(w,h),&c,(8.0+frame as f32/20.0)/streak_pace(&c));
                            active+=particles.iter().filter(|p| !p.stationary && p.opacity>0
                                && p.x>=0 && p.x<w as i32 && p.y>=0 && p.y<h as i32).count();
                        }
                        let streams=w as f32/(((c.font_size*2/3).max(7)+4) as f32/density).round();
                        let mean=active as f32/300.0;
                        assert!((streams*0.6..=streams*1.5).contains(&mean),
                            "{effect:?} {w}x{h} size {font_size} density {density}: {mean:.1} events vs {streams:.1} Matrix streams");
                    }
                }
            }
        }
    }
    #[test]
    fn stationary_stars_hold_then_renew_in_every_space_mode_independent_of_speed() {
        let mut reference=Vec::new();
        for effect in [Effect::ShootingStars,Effect::Meteors] {
            let mut c=Config { effect,..Config::default() };
            let mut first=Vec::new();
            let mut next=Vec::new();
            starfield(&mut first,(1280,720),&c,12.0);
            starfield(&mut next,(1280,720),&c,12.1);
            assert!(first.len()>5);
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
            else { assert_eq!(reference,signature); }
            next.clear();
            starfield(&mut next,(1280,720),&c,65.0);
            assert!(first.iter().zip(&next).all(|(a,b)| a.seed!=b.seed));
            assert!(first.iter().zip(&next).filter(|(a,b)| (a.x,a.y)!=(b.x,b.y)).count()>first.len()/2);
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
        for effect in [Effect::ShootingStars,Effect::Meteors] {
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
                        // Vertical streaks identify their evenly spaced lane, whose
                        // cadence keeps slow passes from accumulating in one column.
                        if p.direction.0==0 {
                            let expected_speed = {
                                let pitch=(((c.font_size*2/3).max(7)+4) as f32/c.density).round();
                                let lanes=(1280.0/pitch).floor().max(1.0);
                                let base=hash((p.x as f32/1280.0*lanes) as u32+7919);
                                (650.0+unit(base.wrapping_add(31))*650.0)*c.font_size as f32/16.0
                                    *streak_speed_variation(base)
                                    *(if p.comet { 0.38 } else { 1.0 })*streak_pace(&c)
                            };
                            let distance=((p.x-old.x) as f32).hypot((p.y-old.y) as f32);
                            assert!((distance-expected_speed/10.0).abs()<1.5);
                        }
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
    fn ordinary_streak_motion_matches_matrix_pixel_speed_at_all_size_and_speed_settings() {
        for effect in [Effect::ShootingStars,Effect::Meteors] {
            for font_size in [10,12,16,24,32] {
                for speed in [1.0,6.0,9.0,30.0] {
                    let c=Config { effect,font_size,speed,density:1.0,..Config::default() };
                    let mut before=Vec::new();
                    let mut after=Vec::new();
                    let mut total=0.0;
                    let mut count=0;
                    // One Matrix row of time: enough displacement to avoid
                    // rounding noise at low speeds and small particle sizes.
                    let dt=1.0/speed;
                    for frame in 0..20 {
                        let time=(12.0+frame as f32/2.0)/streak_pace(&c)*9.0/speed;
                        generate(&mut before,(1920,1080),&c,time);
                        generate(&mut after,(1920,1080),&c,time+dt);
                        for p in before.iter().filter(|p| !p.stationary && !p.comet && p.direction.0==0) {
                            let pitch=(((c.font_size*2/3).max(7)+4) as f32/c.density).round();
                            let lanes=(1920.0/pitch).floor().max(1.0);
                            let base=hash((p.x as f32/1920.0*lanes) as u32+7919);
                            if streak_speed_variation(base)<1.0 { continue; }
                            if let Some(next)=after.iter().find(|next| next.seed==p.seed && !next.stationary) {
                                total+=((next.x-p.x) as f32).hypot((next.y-p.y) as f32)/dt;
                                count+=1;
                            }
                        }
                    }
                    assert!(count>100);
                    let mean=total/count as f32;
                    let matrix=speed*(font_size+5) as f32*1.05;
                    assert!((matrix*0.85..=matrix*1.15).contains(&mean),
                        "{effect:?} size {font_size} speed {speed}: {mean:.1} px/s vs Matrix {matrix:.1}");
                }
            }
        }
    }
    #[test]
    fn varied_trajectories_keep_every_drawn_pixel_inside_damage() {
        for effect in [Effect::ShootingStars,Effect::Meteors] {
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

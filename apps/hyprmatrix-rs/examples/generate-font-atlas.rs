//! Regenerate the built-in ASCII bitmap atlas using the installed DejaVu fonts.
//! cargo run --release --example generate-font-atlas --manifest-path apps/hyprmatrix-rs/Cargo.toml
//! The raster output is covered by FONT-LICENSE. No font parser runs for defaults at runtime.
use fontdue::{Font, FontSettings};
use std::{fs, path::Path};
fn main() {
    let root = Path::new(env!("CARGO_MANIFEST_DIR"));
    let mut records = Vec::new();
    let mut pixels = Vec::new();
    for (kind, paths, sizes) in [
        (0u8, ["/usr/share/fonts/dejavu-sans-mono-fonts/DejaVuSansMono.ttf", "/usr/share/fonts/TTF/DejaVuSansMono.ttf", "/usr/share/fonts/truetype/dejavu/DejaVuSansMono.ttf"], (10..=32).collect::<Vec<u8>>()),
        (1u8, ["/usr/share/fonts/dejavu-sans-fonts/DejaVuSans.ttf", "/usr/share/fonts/TTF/DejaVuSans.ttf", "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf"], vec![12,13,20]),
    ] {
        let bytes = paths.iter().find_map(|path| fs::read(path).ok()).expect("DejaVu font missing");
        let font = Font::from_bytes(bytes, FontSettings::default()).unwrap();
        for size in sizes {
            for ch in 32u8..127 {
                let (m, bitmap) = font.rasterize(ch as char, size as f32);
                records.extend_from_slice(&[kind, size, ch, 0]);
                records.extend_from_slice(&(m.width as u16).to_le_bytes());
                records.extend_from_slice(&(m.height as u16).to_le_bytes());
                records.extend_from_slice(&(m.xmin as i16).to_le_bytes());
                records.extend_from_slice(&(m.ymin as i16).to_le_bytes());
                records.extend_from_slice(&m.advance_width.to_le_bytes());
                records.extend_from_slice(&(pixels.len() as u32).to_le_bytes());
                pixels.extend_from_slice(&bitmap);
            }
        }
    }
    let mut output = ((records.len()/20) as u32).to_le_bytes().to_vec();
    output.extend(records);
    output.extend(pixels);
    fs::write(root.join("src/font-atlas.bin"), &output).unwrap();
    println!("Atlas: {} bytes", output.len());
}

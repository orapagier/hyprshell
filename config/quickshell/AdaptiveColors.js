.pragma library

function mix(a, b, amount) {
    return Qt.rgba(a.r + (b.r - a.r) * amount,
                   a.g + (b.g - a.g) * amount,
                   a.b + (b.b - a.b) * amount, 1);
}
function luminance(color) {
    function linear(v) { return v <= 0.04045 ? v / 12.92 : Math.pow((v + 0.055) / 1.055, 2.4); }
    return 0.2126 * linear(color.r) + 0.7152 * linear(color.g) + 0.0722 * linear(color.b);
}
function contrast(a, b) {
    let x = luminance(a), y = luminance(b);
    return (Math.max(x, y) + 0.05) / (Math.min(x, y) + 0.05);
}
function alpha(color, opacity) { return Qt.rgba(color.r, color.g, color.b, opacity); }

// Composite sampled wallpaper with the actual visible panel surfaces, back to front.
function compositeRegion(region, layers) {
    let average = region.average, minimum = region.minimum, maximum = region.maximum;
    for (let layer of layers || []) {
        let amount = layer.color.a * layer.opacity;
        average = mix(average, layer.color, amount);
        minimum = mix(minimum, layer.color, amount);
        maximum = mix(maximum, layer.color, amount);
    }
    return {average:average, minimum:minimum, maximum:maximum};
}

var panelForegroundCache = {entries:Object.create(null), keys:[]};
function panelPalette(region, accent, options) {
    let under = compositeRegion(region, options.layers);
    let dark = mix(Qt.color("#080c14"), accent, 0.06);
    let light = mix(Qt.color("#f7f9ff"), accent, 0.06);
    let originalOpacity = options.style === "emphasized" ? 0.94 : options.style === "muted" ? 0.66 : 0.82;
    let amount = options.shown ? (options.transparency >= 0 ? 1 - options.transparency / 100
        : options.backgroundOpacity >= 0 ? options.backgroundOpacity : originalOpacity) : 0;
    function separation(fill) {
        let composite = mix(under.average, fill, amount);
        return contrast(composite, under.average);
    }
    // Broad glass surfaces should retain the wallpaper hue. Maximizing their
    // contrast selects near-white on dark wallpaper and produces a milky slab.
    let hue = under.average.hsvHue >= 0 ? under.average.hsvHue : accent.hsvHue;
    let glass = Qt.hsva(hue, Math.min(0.85, 0.38 + under.average.hsvSaturation * 0.5),
        0.30 + under.average.hsvValue * 0.24, 1);
    let fill = options.backgroundColor ? Qt.color(options.backgroundColor)
        : options.glassSurface ? glass : separation(dark) >= separation(light) ? dark : light;
    let opacity = options.transparency >= 0 ? 1 : options.backgroundOpacity >= 0 ? options.backgroundOpacity : originalOpacity;
    // Bound all hover/selection shades and the glass shine once, then solve
    // foreground lightness against those composite bounds. This avoids running
    // a separate color search per state on every live slider/hover update.
    let low = mix(under.minimum, mix(fill, Qt.color("#000000"), 0.05), amount);
    let high = mix(under.maximum, mix(fill, Qt.color("#ffffff"), 0.05), amount);
    high = mix(high, Qt.color("#ffffff"), 0.08 * amount);
    let rendered = mix(under.average, fill, amount);
    let key = [rendered, accent, low, high].map(color => [color.r,color.g,color.b].join(",")).join(":");
    let foreground = panelForegroundCache.entries[key];
    if (foreground === undefined) {
        foreground = readableForeground(rendered, accent, low, high, 4.6);
        if (panelForegroundCache.keys.length >= 256)
            delete panelForegroundCache.entries[panelForegroundCache.keys.shift()];
        panelForegroundCache.keys.push(key);
        panelForegroundCache.entries[key] = foreground;
    }
    // Truly bare icons retain the existing bright, varied wallpaper palette.
    if (amount === 0 && !(options.layers || []).some(layer => layer.color.a * layer.opacity > 0))
        foreground = contrastingBrightForeground(under.average, accent, under.minimum, under.maximum, region.distribution);
    return {foreground:foreground, tint:alpha(fill, opacity),
        hover:alpha(mix(fill, foreground, 0.025), opacity),
        selected:alpha(mix(fill, foreground, 0.05), opacity),
        outline:options.glassSurface ? alpha(mix(glass, Qt.color("#ffffff"), 0.78), 0.30) : alpha(glyphEdge(fill), 0.65),
        selectedOutline:alpha(foreground, 0.85)};
}

// Preserve bright hues when a pill can supply the contrasting backing.
function vibrantForeground(sample, accent) {
    let foreground = Qt.hsva(accent.hsvHue, accent.hsvSaturation,
                             Math.max(0.92, accent.hsvValue), 1);
    let backing = Qt.rgba(0.035, 0.04, 0.06, 1);
    for (let i = 0; i < 30 && contrast(foreground, backing) < 5.2; ++i)
        foreground = mix(foreground, Qt.rgba(1, 1, 1, 1), 0.04);
    return foreground;
}

function lightForeground(sample, accent) {
    return Qt.hsla(accent.hslHue, accent.hslSaturation,
                   Math.max(0.70, accent.hslLightness), 1);
}

// Bare glyphs have no backing: adjust their shade instead of drawing an edge.
function readableForeground(sample, accent, minimum, maximum, goal, minimumLightness) {
    goal = goal || 4.6;
    minimumLightness = minimumLightness || 0;
    let preferred = lightForeground(sample, accent);
    let darkest = Qt.hsla(preferred.hslHue, preferred.hslSaturation, minimumLightness, 1);
    let white = Qt.color("#ffffff");
    let useBounds = Math.max(regionContrast(darkest, minimum, maximum), regionContrast(white, minimum, maximum)) >= goal;
    // A mixed light/dark texture may have no single readable shade everywhere.
    // Use its local average in that case, retaining the source hue/saturation.
    let target = useBounds ? goal : Math.min(goal, Math.max(contrast(darkest, sample), contrast(white, sample)) * 0.99);
    function score(color) { return useBounds ? regionContrast(color, minimum, maximum) : contrast(color, sample); }
    if (score(preferred) >= target) return preferred;
    let foreground = preferred, distance = Infinity;
    for (let i = 0; i <= 128; ++i) {
        let candidate = Qt.hsla(preferred.hslHue, preferred.hslSaturation,
                                minimumLightness + (1 - minimumLightness) * i / 128, 1);
        let delta = Math.abs(candidate.hslLightness - preferred.hslLightness);
        if (delta < distance && score(candidate) >= target) {
            foreground = candidate;
            distance = delta;
        }
    }
    return foreground;
}

var brightCandidates = null;
function contrastingBrightForeground(sample, accent, minimum, maximum, distribution) {
    // A bounded, cached gamut: vivid light colors plus white. Never fall back
    // to a dark fill, and never use random choices during wallpaper sampling.
    if (!brightCandidates) {
        brightCandidates = [];
        for (let hue = 0; hue < 24; ++hue)
            for (let lightness of [0.64, 0.74, 0.84]) {
                let color = Qt.hsla(hue / 24, 1, lightness, 1);
                brightCandidates.push({color: color, luminance: luminance(color)});
            }
        brightCandidates.push({color: Qt.color("#ffffff"), luminance: 1});
    }
    function ratio(a, b) { return (Math.max(a, b) + 0.05) / (Math.min(a, b) + 0.05); }
    let tones = distribution && distribution.length ? distribution : [
        {minimum:luminance(minimum), maximum:luminance(minimum), count:1},
        {minimum:luminance(sample), maximum:luminance(sample), count:8},
        {minimum:luminance(maximum), maximum:luminance(maximum), count:1}
    ];
    function readability(value) {
        let score = 0, clear = 0, count = 0;
        for (let tone of tones) {
            let contrast = value >= tone.minimum && value <= tone.maximum ? 1
                : Math.min(ratio(value, tone.minimum), ratio(value, tone.maximum));
            // Extra contrast above the legibility target must not bleach all
            // the accents to white. Weight real pixel coverage, not outliers.
            score += Math.min(4.5, contrast) * tone.count;
            if (contrast >= 4.5) clear += tone.count;
            count += tone.count;
        }
        return {score:score / count, coverage:clear / count};
    }
    let preferred = lightForeground(sample, accent);
    let neutral = accent.hslSaturation < 0.10;
    let allowWhite = neutral && readability(1).coverage >= 0.80;
    let candidates = [], strongest = 0;
    function add(color, value) {
        if (color.hslSaturation < 0.10 && !allowWhite) return;
        let score = readability(value).score;
        candidates.push({color:color, score:score});
        strongest = Math.max(strongest, score);
    }
    add(preferred, luminance(preferred));
    for (let candidate of brightCandidates) add(candidate.color, candidate.luminance);
    let preferredHue = neutral ? (sample.hslHue < 0 ? 0.78 : (sample.hslHue + 0.5) % 1) : preferred.hslHue;
    let best = preferred, distance = Infinity;
    for (let candidate of candidates) {
        // Among similarly legible colors, preserve item identity and variety.
        // The bounded tolerance avoids both unreadable accents and one-color UI.
        if (candidate.score < strongest * 0.92) continue;
        let color = candidate.color;
        let hue = Math.abs(color.hslHue - preferredHue);
        hue = Math.min(hue, 1 - hue);
        let separation = Math.sqrt(Math.pow(color.r - sample.r, 2) + Math.pow(color.g - sample.g, 2) + Math.pow(color.b - sample.b, 2));
        let delta = (color.hslSaturation < 0.10 ? (allowWhite ? -1 : 1) : hue)
            + Math.abs(color.hslLightness - preferred.hslLightness) * 0.3 - separation * 0.08;
        // Prefer at least 45 degrees of hue separation when similarly legible
        // alternatives exist; never sacrifice the readability floor for hue.
        if (sample.hsvSaturation > 0.25 && color.hslSaturation >= 0.10) {
            let gap = Math.abs(color.hslHue - sample.hslHue);
            if (Math.min(gap, 1 - gap) < 0.125) delta += 0.5;
        }
        if (delta < distance) { best = color; distance = delta; }
    }
    return best;
}

function vibrantPalette(sample, accent, minimum, maximum, keepLight, appearanceStyle) {
    let foreground = keepLight ? lightForeground(sample, accent) : vibrantForeground(sample, accent);
    let base = Qt.rgba(0.035, 0.04, 0.06, 1);
    let background = mix(base, accent, 0.04);
    let opacity = keepLight && appearanceStyle === "emphasized" ? 0.38
                : keepLight && appearanceStyle === "muted" ? 0.10 : 0.22;
    // Protect the bright foreground against the lightest sampled pixels,
    // including hover/selection fills and the pill's white glass highlight.
    function minimumContrast() {
        let result = 100;
        for (let state of [0, 1, 2]) {
            let fill = mix(background, foreground, state * 0.03);
            for (let under of [minimum, maximum]) {
                let composite = mix(under, fill, Math.min(0.96, opacity + state * 0.06));
                result = Math.min(result, contrast(foreground, mix(composite, Qt.rgba(1,1,1,1), 0.08)));
            }
        }
        return result;
    }
    while (opacity < 0.96 && minimumContrast() < 4.6)
        opacity = Math.min(0.96, opacity + 0.02);
    // Very dark source accents need a small brightness lift for glass highlights.
    for (let i = 0; i < 30 && minimumContrast() < 4.6; ++i)
        foreground = mix(foreground, Qt.rgba(1,1,1,1), 0.04);
    return {
        foreground: foreground,
        tint: alpha(background, opacity),
        hover: alpha(mix(background, foreground, 0.03), Math.min(0.96, opacity + 0.06)),
        selected: alpha(mix(background, foreground, 0.06), Math.min(0.96, opacity + 0.12)),
        outline: alpha(foreground, keepLight && appearanceStyle === "muted" ? 0.10 : 0.24),
        selectedOutline: alpha(foreground, keepLight && appearanceStyle === "emphasized" ? 0.70 : 0.55),
        glyphOutline: base
    };
}

function regionContrast(foreground, minimum, maximum) {
    let value = luminance(foreground), low = luminance(minimum), high = luminance(maximum);
    // Include intermediate tones: an average or two endpoint comparisons can
    // miss wallpaper pixels with exactly the glyph's brightness.
    if (value >= low && value <= high) return 1;
    return Math.min(contrast(foreground, minimum), contrast(foreground, maximum));
}

function glyphEdge(foreground) {
    let dark = Qt.rgba(0.015, 0.02, 0.03, 1), light = Qt.rgba(1, 1, 1, 1);
    return contrast(foreground, dark) >= contrast(foreground, light) ? dark : light;
}

function barePalette(sample, accent, minimum, maximum, style, distribution) {
    let original = style === "muted" ? Qt.rgba(0.62, 0.62, 0.62, 1)
                 : style === "light" ? lightForeground(sample, accent)
                 : style === "vibrant" ? vibrantForeground(sample, accent) : accent;
    let dark = Qt.rgba(0.015, 0.02, 0.03, 1), light = Qt.rgba(1, 1, 1, 1);
    if (style === "muted") dark = Qt.rgba(0.02, 0.02, 0.02, 1);
    let darkScore = regionContrast(dark, minimum, maximum), lightScore = regionContrast(light, minimum, maximum);
    let target = darkScore > lightScore ? dark : light;
    // On textured regions neither polarity may work everywhere. Choose the
    // most readable fill for the average and protect its silhouette with an edge.
    if (Math.max(darkScore, lightScore) < 4.5)
        target = contrast(dark, sample) > contrast(light, sample) ? dark : light;
    let achievable = regionContrast(target, minimum, maximum);
    let textured = achievable < 4.5;
    // Bare Hyprpane items can change hue when white or their original accent
    // blends into the wallpaper; no background or outline changes are needed.
    let foreground = style === "light" ? contrastingBrightForeground(sample, accent, minimum, maximum, distribution) : original;
    if (!textured && style !== "light") {
        // Change lightness while retaining hue and saturation. Mixing toward
        // white bleached colorful items, even when a richer shade was readable.
        let goal = Math.min(4.6, achievable * 0.99);
        let distance = 2;
        for (let i = 0; i <= 128; ++i) {
            let candidate = Qt.hsla(original.hslHue, original.hslSaturation, i / 128, 1);
            let delta = Math.abs(candidate.hslLightness - original.hslLightness);
            if (delta < distance && regionContrast(candidate, minimum, maximum) >= goal) {
                foreground = candidate;
                distance = delta;
            }
        }
    }
    // A textured region cannot be made readable by washing out the fill.
    // Preserve the accent and use a contrasting silhouette instead.
    // Keep the regular palette fields for consumers, but never solve bare
    // contrast by increasing a background that will not be drawn.
    let result = style === "light" ? vibrantPalette(sample, accent, minimum, maximum, true)
               : style === "vibrant" ? vibrantPalette(sample, accent, minimum, maximum)
                                     : palette(sample, accent, minimum, maximum, style);
    result.foreground = foreground;
    result.glyphHalo = style !== "light" && regionContrast(foreground, minimum, maximum) < 4.5;
    result.glyphOutline = glyphEdge(foreground);
    return result;
}

// Use the dashboard's wallpaper hue, dark surface and light foregrounds.
function wallpaperPalette(sample, highContrast) {
    let background = highContrast ? Qt.color("#000000")
        : Qt.hsva(sample.hsvHue, sample.hsvSaturation * 0.72,
                  0.12 + sample.hsvValue * 0.10, 1);
    let text = highContrast ? Qt.color("#ffffff") : mix(sample, Qt.color("#ffffff"), 0.94);
    let accent = highContrast ? text : mix(lightForeground(sample, sample), text, 0.38);
    return {background: background, text: text, secondary: mix(background, text, 0.82), accent: accent,
            hover: alpha(accent, 0.22), pressed: alpha(accent, 0.33), focus: alpha(accent, 0.53),
            disabled: mix(background, text, 0.60)};
}

// Only popdown descendants inherit this palette; standalone controls keep
// their existing defaults and explicit semantic warning/success colors.
function menuColorsFor(item) {
    for (let parent = item.parent; parent; parent = parent.parent)
        if (parent.menuColors !== undefined) return parent.menuColors;
    return {background: Qt.color("#1e1e2e"), text: Qt.color("#cdd6f4"),
            secondary: Qt.color("#a6adc8"), accent: Qt.color("#b4befe"),
            hover: Qt.color("#38cba6f7"), pressed: Qt.color("#55cba6f7"),
            focus: Qt.color("#88cba6f7"), disabled: Qt.color("#585b70")};
}

function palette(sample, accent, minimum, maximum, style, distribution) {
    minimum = minimum || sample;
    maximum = maximum || sample;
    if (style === "light-bare")
        return barePalette(sample, accent, minimum, maximum, "light", distribution);
    if (style === "light")
        return vibrantPalette(sample, accent, minimum, maximum, true);
    if (style && style.indexOf("light-") === 0)
        return vibrantPalette(sample, accent, minimum, maximum, true, style.slice(6));
    if (style === "vibrant-bare")
        return barePalette(sample, accent, minimum, maximum, "vibrant");
    if (style === "vibrant")
        return vibrantPalette(sample, accent, minimum, maximum);
    if (style && style.indexOf("bare-") === 0) {
        return barePalette(sample, accent, minimum, maximum, style.slice(5));
    }
    let light = luminance(sample) > 0.179;
    if (style === "muted") {
        let gray = 0.2126 * sample.r + 0.7152 * sample.g + 0.0722 * sample.b;
        sample = Qt.rgba(gray, gray, gray, 1);
        accent = Qt.rgba(0.62, 0.62, 0.62, 1);
    }
    let base = light ? Qt.rgba(0.98, 0.98, 1, 1) : Qt.rgba(0.055, 0.06, 0.085, 1);
    if (style === "muted") base = light ? Qt.rgba(0.98, 0.98, 0.98, 1) : Qt.rgba(0.065, 0.065, 0.065, 1);
    let emphasized = style === "emphasized";
    let background = mix(mix(sample, accent, emphasized ? 0.80 : 0.30), base, emphasized ? 0.22 : 0.55);
    let opacity = emphasized ? 0.38 : style === "muted" ? 0.10 : 0.22;
    let foreground = mix(accent, sample, 0.15);
    let target = light ? (style === "muted" ? Qt.rgba(0.035, 0.035, 0.035, 1) : Qt.rgba(0.025, 0.03, 0.045, 1)) : Qt.rgba(1, 1, 1, 1);
    // Start with translucent glass. Increase opacity only when the sampled
    // region's darkest/lightest pixels need more protection for legible text.
    function minimumContrast(fg, opacity) {
        let worst = light ? minimum : maximum;
        let result = 100;
        for (let state of [0, 1, 2]) {
            let fill = mix(background, fg, state * 0.03);
            let composite = mix(worst, fill, Math.min(0.96, opacity + state * 0.06));
            if (!light) composite = mix(composite, Qt.rgba(1, 1, 1, 1), 0.08);
            result = Math.min(result, contrast(fg, composite));
        }
        return result;
    }
    while (opacity < 0.86 && minimumContrast(target, opacity) < 5.2)
        opacity = Math.min(0.86, opacity + 0.04);
    for (let i = 0; i < 20 && minimumContrast(target, opacity) < 5.2; ++i)
        background = mix(background, base, 0.12);
    for (let i = 0; i < 40 && minimumContrast(foreground, opacity) < 5; ++i)
        foreground = mix(foreground, target, 0.12);
    return {
        foreground: foreground,
        tint: alpha(background, opacity),
        hover: alpha(mix(background, foreground, 0.03), Math.min(0.96, opacity + 0.06)),
        selected: alpha(mix(background, foreground, 0.06), Math.min(0.96, opacity + 0.12)),
        outline: alpha(foreground, style === "muted" ? 0.10 : 0.24),
        selectedOutline: alpha(emphasized ? accent : foreground, emphasized ? 0.70 : 0.55)
    };
}

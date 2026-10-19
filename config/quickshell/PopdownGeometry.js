.pragma library

// Follow the drawn silhouette: a slender neck below the pill, a narrow waist,
// then a broad shallow sweep into the card. The cap stays outside the pill.
function outline(x, y, width, height, tip, neck, half, pillRadius, shear) {
    let corner = Math.max(0, Math.min(24, width / 2, height / 2));
    // Wider pills get a slightly broader foot, bounded to keep the neck slender.
    let footHalf = Math.max(0, Math.min(12, 5 + Math.max(0, half - 16) * 0.08, half * 0.4));
    let footY = neck; // the viewport clips the outline at the pill boundary
    let gap = Math.max(1, y - footY);
    let waistHalf = footHalf * 0.4;
    let waistY = footY + gap * 0.35;
    let flare = Math.max(0, Math.min(48, width / 2 - corner));
    let waistX = tip;
    // Bend the stem toward the straight top edge, leaving both corner arcs intact.
    let shoulder = Math.max(x + corner + flare, Math.min(x + width - corner - flare, tip));
    let path = [];
    function n(value) { return Number(value.toFixed(3)); }
    function p(px, py) { return n(px) + ' ' + n(py); }
    function body(px, py) { return p(px + shear * (py - y), py); }
    function line(px, py) { path.push('L ' + body(px, py)); }
    function quad(a,b,c,d) { path.push('Q ' + body(a,b) + ' ' + body(c,d)); }
    path.push('M ' + p(tip - footHalf,footY));
    path.push('L ' + p(tip + footHalf,footY));
    path.push('C ' + p(tip + footHalf,footY + gap * 0.16) + ' '
        + p(waistX + waistHalf,waistY - gap * 0.2) + ' ' + p(waistX + waistHalf,waistY));
    path.push('C ' + p(waistX + waistHalf,waistY + gap * 0.42) + ' '
        + p(shoulder + flare * 0.25,y) + ' ' + p(shoulder + flare,y));
    line(x + width - corner,y);
    quad(x + width,y,x + width,y + corner);
    line(x + width,y + height - corner);
    quad(x + width,y + height,x + width - corner,y + height);
    line(x + corner,y + height);
    quad(x,y + height,x,y + height - corner);
    line(x,y + corner);
    quad(x,y,x + corner,y);
    line(shoulder - flare,y);
    path.push('C ' + p(shoulder - flare * 0.25,y) + ' '
        + p(waistX - waistHalf,waistY + gap * 0.42) + ' ' + p(waistX - waistHalf,waistY));
    path.push('C ' + p(waistX - waistHalf,waistY - gap * 0.2) + ' '
        + p(tip - footHalf,footY + gap * 0.16) + ' ' + p(tip - footHalf,footY));
    path.push('Z');
    return { path: path.join(' '), footLeft: tip - footHalf, footRight: tip + footHalf,
        footY: footY, waistHalf: waistHalf };
}

function toInward(edge, width, height, x, y) {
    if (edge === 'bottom') return {x:x,y:height-y};
    if (edge === 'left') return {x:y,y:x};
    if (edge === 'right') return {x:y,y:width-x};
    return {x:x,y:y};
}
function fromInward(edge, width, height, x, y) {
    if (edge === 'bottom') return {x:x,y:height-y};
    if (edge === 'left') return {x:y,y:x};
    if (edge === 'right') return {x:width-y,y:x};
    return {x:x,y:y};
}

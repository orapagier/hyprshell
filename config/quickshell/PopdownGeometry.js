.pragma library

// Follow the drawn silhouette: a slender neck below the pill, a narrow waist,
// then a broad shallow sweep into the card. The cap stays outside the pill.
function outline(x, y, width, height, tip, neck, half, pillRadius, shear) {
    let corner = Math.max(0, Math.min(24, width / 2, height / 2));
    // Mirror the card shoulder at the pill, scaled down and bounded by the pill.
    let flare = Math.max(0, Math.min(48, width / 2 - corner));
    let footHalf = Math.max(0, Math.min(flare * 0.7, half * 0.7));
    let footY = neck; // the viewport clips the outline at the pill boundary
    let gap = Math.max(1, y - footY);
    let waistHalf = Math.min(4.8, footHalf * 0.25);
    let waistY = footY + gap * 0.35;
    let waistX = tip;
    // Keep the neck under its pill. Trim each shoulder independently instead of
    // pushing the whole stem sideways to fit a full-width flare near a corner.
    let shoulder = Math.max(x + corner, Math.min(x + width - corner, tip));
    let leftFlare = Math.min(flare, shoulder - x - corner);
    let rightFlare = Math.min(flare, x + width - corner - shoulder);
    let path = [];
    function n(value) { return Number(value.toFixed(3)); }
    function p(px, py) { return n(px) + ' ' + n(py); }
    function body(px, py) { return p(px + shear * (py - y), py); }
    function line(px, py) { path.push('L ' + body(px, py)); }
    function quad(a,b,c,d) { path.push('Q ' + body(a,b) + ' ' + body(c,d)); }
    path.push('M ' + p(tip - footHalf,footY));
    path.push('L ' + p(tip + footHalf,footY));
    path.push('C ' + p(tip + footHalf * 0.25,footY) + ' '
        + p(waistX + waistHalf,waistY - (waistY - footY) * (0.42 / 0.65)) + ' ' + p(waistX + waistHalf,waistY));
    path.push('C ' + p(waistX + waistHalf,waistY + gap * 0.42) + ' '
        + p(shoulder + rightFlare * 0.25,y) + ' ' + p(shoulder + rightFlare,y));
    line(x + width - corner,y);
    quad(x + width,y,x + width,y + corner);
    line(x + width,y + height - corner);
    quad(x + width,y + height,x + width - corner,y + height);
    line(x + corner,y + height);
    quad(x,y + height,x,y + height - corner);
    line(x,y + corner);
    quad(x,y,x + corner,y);
    line(shoulder - leftFlare,y);
    path.push('C ' + p(shoulder - leftFlare * 0.25,y) + ' '
        + p(waistX - waistHalf,waistY + gap * 0.42) + ' ' + p(waistX - waistHalf,waistY));
    path.push('C ' + p(waistX - waistHalf,waistY - (waistY - footY) * (0.42 / 0.65)) + ' '
        + p(tip - footHalf * 0.25,footY) + ' ' + p(tip - footHalf,footY));
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

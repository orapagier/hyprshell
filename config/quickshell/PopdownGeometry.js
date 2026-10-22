.pragma library

// Follow the drawn silhouette: a slender neck below the pill, a narrow waist,
// then a broad shallow sweep into the card. The cap stays outside the pill.
function outline(x, y, width, height, tip, neck, half, pillRadius, shear, preserveCornerPosition, pointed) {
    let corner = Math.max(0, Math.min(24, width / 2, height / 2));
    // Mirror the card shoulder at the pill, scaled down and bounded by the pill.
    let flare = Math.max(0, Math.min(48, width / 2 - corner));
    let footHalf = pointed ? 0 : Math.max(0, Math.min(flare * 0.7, half * 0.7));
    let footY = neck; // the viewport clips the outline at the pill boundary
    let gap = Math.max(1, y - footY);
    let waistHalf = pointed ? Math.min(4.8, gap * 0.15) : Math.min(4.8, footHalf * 0.25);
    let waistY = footY + gap * 0.35;
    let waistX = tip;
    // Keep the stem centered on its pill. At a card corner, merge the shoulder
    // at the same card-top baseline on both sides, rounding below the foot.
    let leftFits = tip - flare >= x + corner;
    let rightFits = tip + flare <= x + width - corner;
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
    if (rightFits) {
        path.push('C ' + p(waistX + waistHalf,waistY + gap * 0.42) + ' '
            + p(tip + flare * 0.25,y) + ' ' + p(tip + flare,y));
        line(x + width - corner,y);
        quad(x + width,y,x + width,y + corner);
    } else if (preserveCornerPosition === false) {
        path.push('C ' + p(waistX + waistHalf,waistY + gap * 0.42) + ' '
            + body(x + width,y + corner * 0.4) + ' ' + body(x + width,y + corner));
    } else {
        // Reserve a rounded turn even when the foot reaches the card side.
        let join = Math.min(x + width - corner * 0.5, tip + flare);
        path.push('C ' + p(waistX + waistHalf,waistY + gap * 0.42) + ' '
            + body(Math.min(join, tip + flare * 0.25),y) + ' ' + body(join,y));
        quad(x + width,y,x + width,y + corner);
    }
    line(x + width,y + height - corner);
    quad(x + width,y + height,x + width - corner,y + height);
    line(x + corner,y + height);
    quad(x,y + height,x,y + height - corner);
    line(x,y + corner);
    if (leftFits) {
        quad(x,y,x + corner,y);
        line(tip - flare,y);
        path.push('C ' + p(tip - flare * 0.25,y) + ' '
            + p(waistX - waistHalf,waistY + gap * 0.42) + ' ' + p(waistX - waistHalf,waistY));
    } else if (preserveCornerPosition === false) {
        path.push('C ' + body(x,y + corner * 0.4) + ' '
            + p(waistX - waistHalf,waistY + gap * 0.42) + ' ' + p(waistX - waistHalf,waistY));
    } else {
        let join = Math.max(x + corner * 0.5, tip - flare);
        quad(x,y,join,y);
        path.push('C ' + body(Math.max(join, tip - flare * 0.25),y) + ' '
            + p(waistX - waistHalf,waistY + gap * 0.42) + ' ' + p(waistX - waistHalf,waistY));
    }
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

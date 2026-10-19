.pragma library

// Follow the drawn silhouette: a slender neck below the pill, a narrow waist,
// then a broad shallow sweep into the card. The cap stays outside the pill.
function outline(x, y, width, height, tip, neck, half, pillRadius, shear) {
    let corner = Math.max(0, Math.min(24, width / 2, height / 2));
    let footHalf = Math.max(0, Math.min(5, half * 0.4));
    let footY = neck; // the viewport clips the outline at the pill boundary
    let gap = Math.max(1, y - footY);
    let waistHalf = footHalf * 0.4;
    let waistY = footY + gap * 0.35;
    let flare = Math.max(0, Math.min(48, width / 2 - corner));
    let waistX = tip;
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
    path.push('C ' + p(tip + footHalf,footY + gap * 0.16) + ' '
        + p(waistX + waistHalf,waistY - gap * 0.2) + ' ' + p(waistX + waistHalf,waistY));
    if (rightFits) {
        path.push('C ' + p(waistX + waistHalf,waistY + gap * 0.42) + ' '
            + p(tip + flare * 0.25,y) + ' ' + p(tip + flare,y));
        line(x + width - corner,y);
        quad(x + width,y,x + width,y + corner);
    } else {
        // Beside a screen corner, flow into the side rather than folding a
        // broad shoulder backwards across the top edge.
        path.push('C ' + p(waistX + waistHalf,waistY + gap * 0.42) + ' '
            + body(x + width,y + corner * 0.4) + ' ' + body(x + width,y + corner));
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
    } else {
        path.push('C ' + body(x,y + corner * 0.4) + ' '
            + p(waistX - waistHalf,waistY + gap * 0.42) + ' ' + p(waistX - waistHalf,waistY));
    }
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

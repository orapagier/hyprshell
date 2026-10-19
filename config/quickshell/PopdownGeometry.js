.pragma library

// An independently constructed circular fillet between a capsule and a rounded
// card. Both ends share tangents with their neighbours; there is no added stalk.
function outline(x, y, width, height, tip, neck, half, pillRadius, shear) {
    let r = Math.max(0.01, Math.min(pillRadius, half));
    let corner = Math.max(0, Math.min(24, width / 2, height / 2));
    let gap = Math.max(2, y - neck);
    let fillet = Math.max(6, gap * 0.8);
    let dy = gap + r - fillet;
    let distance = r + fillet;
    let dx = Math.sqrt(Math.max(0.01, distance * distance - dy * dy));
    let capLeft = tip - half + r, capRight = tip + half - r;
    let footY = neck - r + r * dy / distance;
    let footLeft = capLeft - r * dx / distance;
    let footRight = capRight + r * dx / distance;
    let leftShoulder = capLeft - dx, rightShoulder = capRight + dx;
    let leftFits = leftShoulder >= x + corner;
    let rightFits = rightShoulder <= x + width - corner;
    let path = [];
    function n(value) { return Number(value.toFixed(3)); }
    function p(px, py) { return n(px) + ' ' + n(py); }
    function body(px, py) { return p(px + shear * (py - y), py); }
    function line(px, py) { path.push('L ' + body(px, py)); }
    function quad(a,b,c,d) { path.push('Q ' + body(a,b) + ' ' + body(c,d)); }
    path.push('M ' + p(footLeft, footY));
    // This is a cutout along the pill boundary, so translucent fills never stack.
    path.push('A ' + p(r,r) + ' 0 0 0 ' + p(capLeft,neck));
    path.push('L ' + p(capRight,neck));
    path.push('A ' + p(r,r) + ' 0 0 0 ' + p(footRight,footY));
    if (rightFits) {
        path.push('A ' + p(fillet,fillet) + ' 0 0 0 ' + p(rightShoulder,y));
        line(x + width - corner, y);
        quad(x + width,y,x + width,y + corner);
    } else {
        // At a screen corner the join flows into the card's side instead of
        // folding back over a corner whose shoulder no longer fits.
        let handle = Math.max(6, (y + corner - footY) * 0.45);
        path.push('C ' + p(footRight - dy / distance * handle, footY + dx / distance * handle)
            + ' ' + body(x + width,y + corner * 0.35) + ' ' + body(x + width,y + corner));
    }
    line(x + width,y + height - corner);
    quad(x + width,y + height,x + width - corner,y + height);
    line(x + corner,y + height);
    quad(x,y + height,x,y + height - corner);
    line(x,y + corner);
    if (leftFits) {
        quad(x,y,x + corner,y);
        line(leftShoulder,y);
        path.push('A ' + p(fillet,fillet) + ' 0 0 0 ' + p(footLeft,footY));
    } else {
        let handle = Math.max(6, (y + corner - footY) * 0.45);
        path.push('C ' + body(x,y + corner * 0.35) + ' '
            + p(footLeft + dy / distance * handle,footY + dx / distance * handle) + ' ' + p(footLeft,footY));
    }
    path.push('Z');
    return { path: path.join(' '), footLeft: footLeft, footRight: footRight,
        footY: footY, waistHalf: Math.max(0, half - r + dx - fillet) };
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

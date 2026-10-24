pragma ComponentBehavior: Bound
import QtQuick

// Geometry moves with expressive easing. Its measured motion excites damped
// springs, so opening, resizing and changing menus share the same elastic body.
Item {
    id: motion
    property bool animate: true
    property bool opened: false
    property bool active: false
    property real targetX: 0
    property real targetY: 0
    property real targetWidth: 300
    property real targetHeight: 200
    property real minimumX: -Infinity
    property real maximumX: Infinity
    property real minimumY: -Infinity
    property real maximumY: Infinity
    property bool ready: false
    readonly property bool animated: ready && animate
    property real travelProgress: opened ? 1 : 0
    readonly property real progress: animated ? travelProgress : opened ? 1 : 0
    property real center: targetX + targetWidth / 2
    property real leading: targetY
    property real extentT: targetWidth
    property real extentN: targetHeight
    property real impulseT: 1
    property real impulseN: 1
    property real impulseShear: 0
    property real stretchT: 1
    property real stretchN: 1
    property real shear: 0
    property real velocityT: 0
    property real velocityN: 0
    property real velocityShear: 0
    property bool physicsActive: false
    readonly property real reveal: Math.max(0, Math.min(1, progress))
    readonly property real displayY: Math.max(minimumY, Math.min(maximumY, (animated ? leading : targetY) - 6 * (1 - reveal)))
    readonly property real displayHeight: Math.max(0, Math.min(maximumY - displayY, (animated ? extentN : targetHeight) * (0.88 + 0.12 * reveal) * stretchN))
    readonly property real displayWidth: Math.max(0, Math.min(maximumX - minimumX - Math.abs(shear) * displayHeight,
        (animated ? extentT : targetWidth) * (0.94 + 0.06 * reveal) * stretchT))
    readonly property real displayX: Math.max(minimumX - Math.min(0, shear * displayHeight),
        Math.min(maximumX - displayWidth - Math.max(0, shear * displayHeight), (animated ? center : targetX + targetWidth / 2) - displayWidth / 2))
    readonly property bool running: frames.running
    readonly property bool travelling: revealAnim.running || centerAnim.running || leadingAnim.running
        || widthAnim.running || heightAnim.running

    Component.onCompleted: ready = true
    function settle() {
        impulseT = 1; impulseN = 1; impulseShear = 0;
        stretchT = 1; stretchN = 1; shear = 0;
        velocityT = 0; velocityN = 0; velocityShear = 0;
        physicsActive = false;
    }
    onActiveChanged: if (!active) settle()
    onAnimatedChanged: if (!animated) settle()
    Behavior on travelProgress {
        enabled: motion.animated
        NumberAnimation {
            id: revealAnim
            duration: motion.opened ? 480 : 240
            easing.type: Easing.BezierSpline
            easing.bezierCurve: motion.opened ? [0.22, 1, 0.36, 1, 1, 1] : [0.4, 0, 0.2, 1, 1, 1]
        }
    }
    Behavior on center {
        enabled: motion.animated && motion.active
        NumberAnimation { id: centerAnim; duration: 420; easing.type: Easing.BezierSpline; easing.bezierCurve: [0.22, 1, 0.36, 1, 1, 1] }
    }
    Behavior on leading {
        enabled: motion.animated && motion.active
        NumberAnimation { id: leadingAnim; duration: 420; easing.type: Easing.BezierSpline; easing.bezierCurve: [0.22, 1, 0.36, 1, 1, 1] }
    }
    Behavior on extentT {
        enabled: motion.animated && motion.active
        NumberAnimation { id: widthAnim; duration: 420; easing.type: Easing.BezierSpline; easing.bezierCurve: [0.22, 1, 0.36, 1, 1, 1] }
    }
    Behavior on extentN {
        enabled: motion.animated && motion.active
        NumberAnimation { id: heightAnim; duration: 420; easing.type: Easing.BezierSpline; easing.bezierCurve: [0.22, 1, 0.36, 1, 1, 1] }
    }
    // Critical damping keeps fluid deformation continuous without repeated
    // rebounds that look like vertical flicker while the pointer is stationary.
    function spring(value, velocity, goal, dt) {
        let frequency = 20;
        let decay = Math.exp(-frequency * dt);
        let displacement = value - goal;
        let drift = velocity + frequency * displacement;
        return {
            value: goal + (displacement + drift * dt) * decay,
            velocity: (velocity - frequency * drift * dt) * decay
        };
    }

    FrameAnimation {
        id: frames
        running: motion.animated && motion.active && (motion.travelling || motion.physicsActive)
        property bool sampled: false
        property real previousCenter: 0
        property real previousLeading: 0
        property real previousWidth: 0
        property real previousHeight: 0
        property real previousProgress: 0
        onRunningChanged: sampled = false
        onTriggered: {
            let dt = Math.max(0.001, Math.min(0.05, frameTime));
            if (sampled) {
                let vt = (motion.center - previousCenter + (motion.extentT - previousWidth) * 0.3) / dt;
                let vn = (motion.leading - previousLeading + (motion.extentN - previousHeight) * 0.3
                    + (motion.progress - previousProgress) * Math.min(80, motion.extentN * 0.2)) / dt;
                let speed = Math.hypot(vt, vn);
                let bias = (Math.abs(vt) - Math.abs(vn)) / Math.max(1, speed);
                let stretch = 1 + Math.min(0.04, speed * 0.00008) * bias;
                motion.impulseT = speed < 1 ? 1 : stretch;
                motion.impulseN = speed < 1 ? 1 : 1 / stretch;
                motion.impulseShear = speed < 1 ? 0 : Math.max(-0.025, Math.min(0.025, vt * 0.00004));
            }
            let t = motion.spring(motion.stretchT, motion.velocityT, motion.impulseT, dt);
            let n = motion.spring(motion.stretchN, motion.velocityN, motion.impulseN, dt);
            let sh = motion.spring(motion.shear, motion.velocityShear, motion.impulseShear, dt);
            let unsettled = motion.travelling || Math.abs(t.value - 1) + Math.abs(n.value - 1) + Math.abs(sh.value) > 0.0002
                || Math.abs(t.velocity) + Math.abs(n.velocity) + Math.abs(sh.velocity) > 0.002;
            motion.stretchT = unsettled ? t.value : 1;
            motion.stretchN = unsettled ? n.value : 1;
            motion.shear = unsettled ? sh.value : 0;
            motion.velocityT = unsettled ? t.velocity : 0;
            motion.velocityN = unsettled ? n.velocity : 0;
            motion.velocityShear = unsettled ? sh.velocity : 0;
            motion.physicsActive = unsettled;
            previousCenter = motion.center; previousLeading = motion.leading;
            previousWidth = motion.extentT; previousHeight = motion.extentN;
            previousProgress = motion.progress;
            sampled = true;
        }
    }
}

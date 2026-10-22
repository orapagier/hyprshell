import QtQuick
import QtTest
import ".."

Item {
    id: scene
    width: 680; height: 500
    Component {
        id: menu
        MenuPopover { width: scene.width; height: scene.height; pointed: true; requestedBodyHeight: 180 }
    }
    TestCase {
        name: "PopdownStemMotion"
        when: windowShown
        function test_cornerCurveSurvivesAnimation_data() {
            let rows = [];
            for (let edge of ["top", "bottom", "left", "right"])
                for (let side of ["start", "end"])
                    rows.push({tag: edge + "-" + side, edge: edge, side: side});
            return rows;
        }
        function test_cornerCurveSurvivesAnimation(data) {
            let vertical = data.edge === "left" || data.edge === "right";
            let start = data.side === "start";
            let along = start ? 9 : (vertical ? scene.height : scene.width) - 25;
            let trigger = vertical
                ? Qt.rect(data.edge === "left" ? 12 : scene.width - 28, along, 16, 16)
                : Qt.rect(along, data.edge === "top" ? 12 : scene.height - 28, 16, 16);
            let popover = createTemporaryObject(menu, scene, {
                edge: data.edge, alignment: start ? "left" : "right", triggerRect: trigger
            });
            verify(popover !== null);
            verify(popover.fluidMotion.animated);
            function checkCurve() {
                let path = popover.fluidOutline.path;
                let curves = path.match(/C(?: -?[\d.]+){6}/g).map(c => c.slice(2).split(" ").map(Number));
                compare(curves.length, 2);
                if (start) {
                    let foot = Number(path.match(/ L (-?[\d.]+) (-?[\d.]+) C [^C]*Z$/)[1]);
                    verify(curves[1][0] > foot, "Outer left foot must retain its bowed curve during animation");
                } else {
                    verify(curves[0][2] < curves[0][4], "Outer right foot must retain its bowed curve during animation");
                }
            }
            function sample(milliseconds) {
                for (let elapsed = 0; elapsed < milliseconds; elapsed += 16) {
                    checkCurve();
                    wait(16);
                }
            }
            popover.opened = true;
            sample(640);
            popover.opened = false;
            sample(64);
            popover.opened = true;
            sample(640);
            popover.opened = false;
            sample(320);
        }
    }
}

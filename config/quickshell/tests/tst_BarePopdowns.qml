import QtQuick
import QtTest
import ".."

Item {
    id: scene
    width: 1366; height: 900
    Bar {
        id: bar
        width: vertical ? verticalThickness : scene.width
        x: position === "right" ? scene.width - width : 0
        y: position === "bottom" ? scene.height - height : 0
        statusData: ({workspaces:[{id:1,name:"1",active:true}], audio:{icon:"󰕾",text:"64%"}, network:{text:"󰤨"}, bluetooth:{text:"󰂯"}, battery:{present:true,text:"󰁹 86%"}})
        mediaData: ({playing:true,title:"Track",levels:[1,0.5]})
        clockText: "12:34"
        previewWorkspaceId: 1
    }
    MenuPopover {
        id: popover
        anchors.fill: parent
        instant: true
        opened: true
        triggerRect: {
            if (!connected) return Qt.rect(scene.width / 2,0,0,0);
            let rect = bar.menuAnchorRect(scene.menu);
            return Qt.rect(rect.x + bar.x,rect.y + bar.y,rect.width,rect.height);
        }
        edge: connected ? bar.position : "top"
        pointed: bar.menuPointed(scene.menu)
        connected: bar.menuHasTrigger(scene.menu)
        requestedBodyHeight: 200
    }
    property string menu: "wifi"
    TestCase {
        name: "BarePopdowns"
        when: windowShown
        function cleanup() { bar.settings = {}; scene.menu = "wifi"; }
        function test_sizesSurvivePillToggle() {
            for (let edge of ["top","bottom","left","right"]) {
                for (let size of [12,20,48]) {
                    bar.settings = {bar:{position:edge,iconSize:size,background:"on"}};
                    let before = Object.keys(bar.moduleItems).map(id => {
                        let item = bar.moduleItems[id];
                        return [item.width,item.height];
                    });
                    bar.settings = {bar:{position:edge,iconSize:size,background:"off"}};
                    Object.keys(bar.moduleItems).forEach((id,i) => {
                        compare(bar.moduleItems[id].width,before[i][0],id + " width");
                        compare(bar.moduleItems[id].height,before[i][1],id + " height");
                    });
                }
            }
        }
        function test_pointedInkAnchors_data() {
            let rows = [];
            for (let edge of ["top","bottom","left","right"])
                for (let size of [12,48])
                    for (let menu of ["launcher","settings","audio","wifi","bluetooth","notifications","battery","power","calendar","workspacePreview","media"])
                        rows.push({tag:edge + "-" + size + "-" + menu,edge:edge,size:size,menu:menu});
            return rows;
        }
        function test_pointedInkAnchors(data) {
            scene.menu = data.menu;
            bar.settings = {bar:{position:data.edge,iconSize:data.size,background:"off"},
                items:[{id:bar.menuItemId(data.menu),paddingLeft:18,paddingRight:3}]};
            verify(popover.connected);
            verify(popover.pointed);
            let item = bar.menuTargets[data.menu], ink = item.glyphRect;
            let point = item.mapToItem(scene,ink.x,ink.y);
            let anchor = popover.triggerRect;
            fuzzyCompare(anchor.x,point.x,0.001);
            fuzzyCompare(anchor.y,point.y,0.001);
            compare(anchor.width,ink.width);
            compare(anchor.height,ink.height);
            verify(anchor.width > 0 && anchor.height > 0);
            let tip = popover.vertical ? anchor.y + anchor.height / 2 : anchor.x + anchor.width / 2;
            compare(popover.fluidOutline.footLeft,tip);
            compare(popover.fluidOutline.footRight,tip);
            verify(popover.fluidOutline.waistHalf > 0);
            let neck = data.edge === "bottom" ? scene.height - anchor.y
                : data.edge === "right" ? scene.width - anchor.x
                : data.edge === "left" ? anchor.x + anchor.width : anchor.y + anchor.height;
            compare(popover.fluidOutline.footY,neck);
            // Follow both curved sides from the icon toward the card: the
            // width must increase throughout, without a neck or bulge.
            let curves = popover.fluidOutline.path.match(/C(?: -?[\d.]+){6}/g);
            compare(curves.length,2);
            let right = curves[0].slice(2).split(" ").map(Number);
            let left = curves[1].slice(2).split(" ").map(Number);
            let leftBase = popover.fluidOutline.path.match(/ L (-?[\d.]+) (-?[\d.]+) C [^C]*Z$/);
            verify(leftBase !== null);
            function bezier(a,b,c,d,t) {
                let u = 1 - t;
                return u*u*u*a + 3*u*u*t*b + 3*u*t*t*c + t*t*t*d;
            }
            let previous = 0;
            for (let step = 1; step <= 50; ++step) {
                let t = step / 50;
                let width = bezier(tip,right[0],right[2],right[4],t)
                    - bezier(tip,left[2],left[0],Number(leftBase[1]),t);
                verify(width > previous,"Stem must widen continuously toward the card");
                previous = width;
            }
            let bridge = data.edge === "bottom" ? Qt.point(tip,anchor.y - 2)
                : data.edge === "right" ? Qt.point(anchor.x - 2,tip)
                : data.edge === "left" ? Qt.point(anchor.x + anchor.width + 2,tip)
                : Qt.point(tip,anchor.y + anchor.height + 2);
            verify(popover.containsPointer(bridge));
        }
        function test_visiblePillsKeepTheirAnchors() {
            for (let edge of ["top","bottom","left","right"]) {
                for (let style of [
                    {bar:{background:"on"}},
                    {bar:{background:"off"},items:[{id:"wifi",pillGroup:"test",sharedBackground:"on"}]},
                    {bar:{background:"off",fullBackground:"on"}}
                ]) {
                    style.bar.position = edge;
                    bar.settings = style;
                    verify(!popover.pointed);
                    let rect = bar.menuRect("wifi");
                    compare(popover.triggerRect,Qt.rect(rect.x + bar.x,rect.y + bar.y,rect.width,rect.height));
                    verify(popover.fluidOutline.footRight > popover.fluidOutline.footLeft);
                }
                bar.settings = {bar:{position:edge,background:"on"},items:[{id:"wifi",pillGroup:"test",sharedBackground:"off"}]};
                verify(popover.pointed);
            }
        }
        function test_anchorFollowsItemMovementAndScrolling() {
            for (let side of ["left","center","right"]) {
                bar.settings = {bar:{background:"off"},items:[{id:"wifi",side:side,paddingLeft:23,paddingRight:2}]};
                let item = bar.moduleItems.wifi;
                let point = item.mapToItem(scene,item.glyphRect.x,item.glyphRect.y);
                compare(popover.triggerRect.x,point.x);
                compare(popover.triggerRect.y,point.y);
            }
            bar.settings = {bar:{position:"left",background:"off",iconSize:48}};
            let viewport = findChild(bar,"panelViewport");
            viewport.contentY = 30;
            let item = bar.moduleItems.wifi;
            let point = item.mapToItem(scene,item.glyphRect.x,item.glyphRect.y);
            compare(popover.triggerRect.y,point.y);
            viewport.contentY = 0;
        }
        function test_renderSmallAndLargeTips() {
            for (let size of [12,48]) {
                bar.settings = {bar:{background:"off",iconSize:size},items:[{id:"wifi",side:"center"}]};
                waitForRendering(scene);
                grabImage(scene).save("/tmp/hyprshell-bare-tip-" + size + ".png");
            }
        }
        function test_hiddenLauncherHasNoStem() {
            scene.menu = "launcher";
            for (let edge of ["top","bottom","left","right"]) {
                for (let entry of [{enabled:false},{hideIcon:true},{hideText:true,hideIcon:true},{opacity:0}]) {
                    bar.settings = {bar:{position:edge},items:[Object.assign({id:"launcher"},entry)]};
                    verify(!popover.connected);
                    verify(!findChild(popover,"menuFunnel").visible);
                }
                bar.settings = {bar:{position:edge},items:[{id:"launcher",icon:"󰀻"}]};
                verify(popover.connected);
            }
        }
    }
}

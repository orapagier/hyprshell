"""Dashboard geometry must reuse wallpaper pixels; source/output changes invalidate them."""
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]


@unittest.skipUnless(shutil.which('quickshell'), 'Native Quickshell is needed')
class DashboardWallpaperTests(unittest.TestCase):
    def test_resize_reuses_small_sample_and_source_changes_refresh(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / 'shell').symlink_to(ROOT / 'config/quickshell', target_is_directory=True)
            runtime = root / 'runtime'; runtime.mkdir(mode=0o700)
            blue = root / 'blue.svg'
            blue.write_text('<svg xmlns="http://www.w3.org/2000/svg" width="1920" height="1080"><path fill="#0066ee" d="M0 0h1920v1080H0z"/></svg>')
            source = '''import QtQuick
import QtTest
import Quickshell
import "shell"
ShellRoot {
    id: root
    property rect region: Qt.rect(0,400,760,300)
    property int captures: 0
    property url wallpaper: "__WALLPAPER_URL__"
    property real displayHeight: 1080
    FloatingWindow {
        visible: true; implicitWidth: 1920; implicitHeight: 1080
        GlassSurface {
            id: glass; width: 1920; height: 1080
            wallpaperSource: root.wallpaper
            screenWidth:1920; screenHeight:root.displayHeight; region: root.region
        }
        Rectangle { width:100; height:100; color:glass.topColor }
        DashboardContent {
            id: dashboard; x:120; width:724; height:implicitHeight
            wallpaperSource:glass.wallpaperSource
            screenWidth:1920; screenHeight:root.displayHeight; wallpaperRegion:root.region
            services:({statusData:{network:{tooltip:"Test network"}},batteryInfo:{present:false}})
        }
    }
    TestCase { id: test; name:"WallpaperWork"; when:false }
    function samplers(item, list) {
        if (typeof item.sampleRect === "function") list.push(item);
        for (let child of item.children || []) samplers(child, list);
    }
    Timer {
        interval:200; running:true
        onTriggered: {
            try {
                glass.cacheFullWallpaper = true;
                let list=[];root.samplers(glass,list);root.samplers(dashboard,list);
                test.tryVerify(()=>list.every(item=>item.ready),3000);
                for (let sampler of list) {
                    let image = sampler.children.find(child => typeof child.sourceSize !== 'undefined');
                    if (!image || image.sourceSize.width > 1920 || image.implicitWidth > 1920)
                        throw new Error('Wallpaper decode exceeds output width');
                    if (Math.abs(image.implicitWidth / image.implicitHeight - 16 / 9) > 0.01)
                        throw new Error('Wallpaper decode changed aspect ratio');
                }
                test.wait(100);
                for (let sampler of list) sampler.pixelsChanged.connect(()=>root.captures++);
                let start=Date.now();
                for (let i=0;i<12;i++) {
                    root.region=Qt.rect(0,400-i*10,760,300+i*10);
                    test.wait(25);
                }
                test.wait(150);
                if (list.length !== 2 || root.captures !== 0) throw new Error('Resizing rereads wallpaper pixels: ' + root.captures);
                if (list.some(item=>item.sampleWidth !== 96 || item.sampleHeight !== 64)) throw new Error('Unbounded card sample');
                root.wallpaper = "__BLUE_URL__";
                test.tryVerify(()=>root.captures > 0 && list.every(item=>item.ready),2000);
                if (!root.captures || !list.every(item=>item.ready)) throw new Error('Wallpaper change did not invalidate cache');
                test.wait(100);
                let captured=root.captures;
                root.displayHeight = 1200;
                test.tryVerify(()=>root.captures > captured && list.every(item=>item.ready),2000);
                if (root.captures <= captured) throw new Error('Output size did not invalidate cache');
                console.log('DASHBOARD_WALLPAPER_OK elapsed='+(Date.now()-start));
                Qt.quit();
            }catch(error){console.error(error);Qt.exit(1);}
        }
    }
}
'''
            source = source.replace('__WALLPAPER_URL__', (ROOT / 'assets/wallpapers/default.jpg').as_uri()).replace('__BLUE_URL__', blue.as_uri())
            entry = root / 'Check.qml'; entry.write_text(source)
            env = dict(os.environ, XDG_CONFIG_HOME=str(root / 'config'), XDG_STATE_HOME=str(root / 'state'),
                       XDG_RUNTIME_DIR=str(runtime), QT_QPA_PLATFORM='offscreen',
                       QT_QPA_PLATFORMTHEME='', QT_QUICK_BACKEND='software')
            result = subprocess.run(['quickshell', '--log-rules', 'qml=true', '-p', str(entry)],
                                    env=env, capture_output=True, text=True, timeout=20)
            output = result.stdout + result.stderr
            self.assertEqual(result.returncode, 0, output)
            self.assertIn('DASHBOARD_WALLPAPER_OK', output)
            for error in ('ReferenceError', 'Unable to assign', 'TypeError', 'Binding loop'):
                self.assertNotIn(error, output)

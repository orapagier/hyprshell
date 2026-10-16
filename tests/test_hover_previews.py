"""Native preview loading and capture cleanup without touching the desktop."""
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]


@unittest.skipUnless(shutil.which('quickshell'), 'Native Quickshell is needed')
class HoverPreviewTests(unittest.TestCase):
    def test_native_preview_lifecycle(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            payload = root / 'quickshell'
            payload.mkdir()
            for source in (ROOT / 'config/quickshell').iterdir():
                if source.name != 'Dropdown.qml':
                    (payload / source.name).symlink_to(source, target_is_directory=source.is_dir())
            dropdown = (ROOT / 'config/quickshell/Dropdown.qml').read_text()
            dropdown = dropdown.replace('PanelWindow {', 'FloatingWindow {')
            dropdown = '\n'.join(line for line in dropdown.splitlines()
                                 if not any(token in line for token in ('anchors { top:', 'exclusionMode:', 'mask: Region', 'WlrLayershell.')))
            (payload / 'Dropdown.qml').write_text(dropdown)
            (root / 'Check.qml').write_text('''import QtQuick
import QtQuick.Window
import Quickshell
import "''' + (ROOT / 'config/quickshell').as_uri() + '''"
ShellRoot {
    id: test
    Window {
        id: window
        visible: true; width: 650; height: 400
        WorkspacePreview {
            id: workspace
            width: 300
            workspaceId: 2
            output: ({width:1920,height:1080})
            monitor: ({x:1920,y:0})
            windows: [{title:'Editor', workspace:{id:2},lastIpcObject:{at:[2020,100],size:[960,540]}},
                {title:'Other workspace',workspace:{id:1},lastIpcObject:{at:[0,0],size:[800,600]}}]
        }
        MediaPreview {
            id: media
            x:320; width:300
            windows: []
            mediaData: ({trackTitle:'A song',artist:'Artist',appName:'Player',levels:[0.2,0.8,0.4]})
        }
    }
    function check(value, message) { if (!value) throw new Error(message); }
    function find(item, name) {
        if (item.objectName === name) return item;
        for (let child of item.children || []) { let found=find(child,name); if (found) return found; }
        return null;
    }
    Timer {
        interval:200; running:true
        onTriggered: {
            try {
                let shell = Qt.createComponent("''' + (payload / 'Dropdown.qml').as_uri() + '''");
                test.check(shell.status === Component.Ready, shell.errorString());
                test.check(workspace.workspaceWindows.length === 1,'filter windows by workspace');
                test.check(workspace.height > 160 && workspace.height < 170,'monitor aspect ratio');
                let image = test.find(workspace,'previewCapture');
                test.check(image !== null && !image.captureSource && !image.live,'idle capture released');
                let tile=image.parent.parent;
                test.check(Math.abs(tile.x - 15.625) < 0.01,'use monitor-relative window coordinates');
                workspace.active=true;
                media.active=true;
                test.check(!media.sourceWindow,'audio-only media requires no window');
                media.active=false;
                workspace.active=false;
                test.check(!image.captureSource && !image.live,'hidden workspace releases capture');
                let video=test.find(media,'previewCapture');
                test.check(video !== null && !video.captureSource && !video.live,'hidden media releases capture');
                window.contentItem.grabToImage(result => {
                    result.saveToFile('/tmp/hyprpane-hover-previews.png');
                    console.log('HOVER_PREVIEWS_OK'); Qt.quit();
                });
            } catch(error) { console.error('HOVER_PREVIEWS_FAILED '+error); Qt.exit(1); }
        }
    }
    Timer { interval:5000; running:true; onTriggered: Qt.exit(2) }
}''')
            runtime = root / 'runtime'
            runtime.mkdir(mode=0o700)
            env = dict(os.environ, XDG_RUNTIME_DIR=str(runtime), HYPRLAND_INSTANCE_SIGNATURE='',
                       QT_QPA_PLATFORMTHEME='', QT_QPA_PLATFORM='offscreen', QT_QUICK_BACKEND='software')
            result = subprocess.run(['quickshell', '--log-rules', 'qml.debug=true', '-p', str(root / 'Check.qml')],
                                    env=env, capture_output=True, text=True, timeout=12)
            output = result.stdout + result.stderr
            self.assertEqual(result.returncode, 0, output)
            self.assertIn('HOVER_PREVIEWS_OK', output)
            for error in ('ReferenceError', 'TypeError', 'Binding loop', 'Unable to assign', 'HOVER_PREVIEWS_FAILED'):
                self.assertNotIn(error, output)

"""Load the real presenter UI and verify targeting, controls, and teardown."""
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest
ROOT = Path(__file__).resolve().parents[1]


@unittest.skipUnless(shutil.which('quickshell'), 'Native Quickshell is needed')
class PresentationViewTests(unittest.TestCase):
 def test_preview_controls_and_lifecycle(self):
  with tempfile.TemporaryDirectory() as d:
   root=Path(d)
   payload=root/'quickshell'
   shutil.copytree(ROOT/'config/quickshell',payload,ignore=shutil.ignore_patterns('__pycache__','audio-spectrum'))
   p=payload/'PresentationView.qml'
   s=p.read_text().replace('PanelWindow {','FloatingWindow {',1)
   s=s.replace('    screen: laptop\n','').replace('    anchors { top: true; bottom: true; left: true; right: true }','    implicitWidth: 1000; implicitHeight: 760')
   s='\n'.join(l for l in s.splitlines() if 'exclusionMode:' not in l and 'WlrLayershell.' not in l)
   s=s.replace('captureSource: window.visible ? (window.slideshow.wayland || window.output) : null','captureSource: null').replace('live: window.visible','live: false')
   p.write_text(s)
   (payload/'PreviewCheck.qml').write_text('''import QtQuick
  import Quickshell
  ShellRoot {
   id: root
   property var commands: []
   property var laptop: ({name: "eDP-1"})
   property var hdmi: ({name: "HDMI-A-1"})
   property var source: ({address: "0x123abc", title: "Test.pptx — ONLYOFFICE", monitor: hdmi,
       wayland: null, lastIpcObject: {class: "ONLYOFFICE", pid: 42, fullscreen: 2, fullscreenClient: 2}})
   PresentationView { id: view; windows: [root.source]; displays: [root.laptop, root.hdmi]; send: command => root.commands.push(command) }
   Timer {
    interval: 250; running: true
    onTriggered: {
     if (!view.visible || view.slideshow !== root.source) { console.error("PREVIEW_FAILED selection"); Qt.exit(1); return; }
     view.control("Right"); view.control("Left"); view.control("Escape"); view.control("invalid");
     if (root.commands.length !== 3 || root.commands[0].indexOf('address:0x123abc') < 0) { console.error("PREVIEW_FAILED controls"); Qt.exit(1); return; }
     view.windows = [root.source, {title: "Presenter View", monitor: root.laptop,
         lastIpcObject: {class: "ONLYOFFICE", pid: 42, acceptsInput: true, fullscreen: 0}}];
     Qt.callLater(() => {
      if (view.visible) { console.error("PREVIEW_FAILED native presenter"); Qt.exit(1); return; }
      view.windows = [];
      Qt.callLater(() => {
      if (view.visible) { console.error("PREVIEW_FAILED lifecycle"); Qt.exit(1); return; }
      console.log("PRESENTATION_PREVIEW_OK"); Qt.quit();
      });
     });
    }
   }
  }''')
   runtime=root/'runtime';runtime.mkdir(mode=0o700)
   env=dict(os.environ,XDG_RUNTIME_DIR=str(runtime),HYPRLAND_INSTANCE_SIGNATURE='',QT_QPA_PLATFORMTHEME='',QT_QPA_PLATFORM='offscreen',QT_QUICK_BACKEND='software')
   result=subprocess.run(['quickshell','--log-rules','qml.debug=true','-p',str(payload/'PreviewCheck.qml')],env=env,capture_output=True,text=True,timeout=15)
   output = result.stdout + result.stderr
   self.assertEqual(result.returncode, 0, output)
   self.assertIn('PRESENTATION_PREVIEW_OK', output, output)
   for error in ('ReferenceError', 'TypeError', 'Binding loop', 'Unable to assign', 'PREVIEW_FAILED'):
    self.assertNotIn(error, output, output)

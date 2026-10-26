"""Exercise screenshot cancellation and wallpaper recovery with inert tools."""
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]


class DesktopHelperTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix='hyprshell-helpers-')
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.bin = self.root / 'bin'
        self.bin.mkdir()
        self.runtime = self.root / 'runtime'
        self.runtime.mkdir(mode=0o700)
        self.log = self.root / 'calls.jsonl'
        self.env = dict(os.environ, HOME=str(self.root), PATH=str(self.bin),
                        XDG_RUNTIME_DIR=str(self.runtime), XDG_CACHE_HOME=str(self.root / 'cache'),
                        CALLS=str(self.log), LC_ALL='C')
        for name in ('mktemp', 'rm', 'mkdir', 'dirname', 'find', 'sort', 'cat', 'flock', 'sleep'):
            (self.bin / name).symlink_to(shutil.which(name))
        stub = self.bin / 'stub'
        stub.write_text(f'#!{sys.executable}\n' + r'''
import json, os, sys, time
from pathlib import Path
name = Path(sys.argv[0]).name
args = sys.argv[1:]
with Path(os.environ['CALLS']).open('a') as log:
    log.write(json.dumps([name, *args]) + '\n')
code = int(os.environ.get(name.upper() + '_STATUS', '0'))
if name == 'slurp':
    if code == 0: print(os.environ.get('GEOMETRY', '10,20 300x400'))
elif name in ('grim', 'grimblast'):
    if code == 0: Path(args[-1]).write_bytes(b'captured image' if not os.environ.get('EMPTY_IMAGE') else b'')
elif name == 'swappy':
    value = sys.stdin.buffer.read() if args[-1] == '-' else Path(args[-1]).read_bytes()
    Path(os.environ['CALLS']).with_suffix('.image').write_bytes(value)
elif name == 'awww' and args[0] == 'img':
    time.sleep(float(os.environ.get('IMAGE_DELAY', '0')))
    code = int(os.environ.get('IMAGE_STATUS', '0'))
elif name == 'awww' and args[0] == 'query':
    counter = Path(os.environ['CALLS']).with_suffix('.queries')
    count = int(counter.read_text()) + 1 if counter.exists() else 1
    counter.write_text(str(count))
    code = 1 if count <= int(os.environ.get('WAIT_QUERIES', '0')) else 0
raise SystemExit(code)
''')
        stub.chmod(0o755)
        for name in ('slurp', 'grim', 'swappy', 'pgrep', 'awww', 'awww-daemon'):
            (self.bin / name).symlink_to(stub)

    def calls(self, name):
        return [r for r in map(json.loads, self.log.read_text().splitlines()) if r[0] == name] if self.log.exists() else []

    def shot(self, *args):
        result = subprocess.run(['/bin/bash', str(ROOT / 'bin/hyprshell-screenshot'), *args],
                                env=self.env, capture_output=True, timeout=5)
        self.assertEqual(list(self.runtime.glob('hyprshell-shot.*')), [])
        return result

    def test_cancel_or_empty_selection_never_captures_or_opens_editor(self):
        self.env['SLURP_STATUS'] = '1'
        self.assertEqual(self.shot().returncode, 0)
        self.env['SLURP_STATUS'] = '0'
        self.env['GEOMETRY'] = ''
        self.assertEqual(self.shot().returncode, 0)
        self.assertEqual(self.calls('grim'), [])
        self.assertEqual(self.calls('swappy'), [])

    def test_capture_failure_or_empty_image_never_opens_editor(self):
        self.env['GRIM_STATUS'] = '1'
        self.assertNotEqual(self.shot('--screen').returncode, 0)
        self.env['GRIM_STATUS'] = '0'
        self.env['EMPTY_IMAGE'] = '1'
        self.assertNotEqual(self.shot('--screen').returncode, 0)
        self.assertEqual(self.calls('swappy'), [])

    def test_region_and_screen_deliver_finished_capture_and_clean_up(self):
        for args in ([], ['--screen']):
            self.assertEqual(self.shot(*args).returncode, 0)
            self.assertEqual(self.log.with_suffix('.image').read_bytes(), b'captured image')
        self.assertEqual(len(self.calls('slurp')), 1)
        self.assertEqual(self.calls('grim')[0][1:3], ['-g', '10,20 300x400'])
        self.assertEqual(len(self.calls('swappy')), 2)

    def test_frozen_region_success_and_cancellation(self):
        for name in ('grimblast', 'hyprpicker'):
            (self.bin / name).symlink_to(self.bin / 'stub')
        self.assertEqual(self.shot().returncode, 0)
        self.assertEqual(self.calls('grimblast')[0][1:4], ['--freeze', 'save', 'area'])
        self.assertEqual(self.calls('slurp'), [])
        self.env['GRIMBLAST_STATUS'] = '1'
        self.assertNotEqual(self.shot().returncode, 0)
        self.assertEqual(len(self.calls('swappy')), 1)

    def test_file_open_preserves_literal_filename_and_editor_exit(self):
        picture = self.root / 'space $quote " and newline\n.png'
        picture.write_bytes(b'existing image')
        self.env['SWAPPY_STATUS'] = '7'
        self.assertEqual(self.shot('--open', str(picture)).returncode, 7)
        self.assertEqual(self.calls('swappy'), [['swappy', '-f', str(picture)]])
        self.assertEqual(self.calls('grim'), [])

    def wallpapers(self, names=('a.jpg', 'b.png', 'c.webp')):
        self.wall_dir = self.root / 'Pictures/Wallpapers'
        self.wall_dir.mkdir(parents=True)
        for name in names:
            (self.wall_dir / name).write_bytes(b'image')
        self.state = self.root / 'cache/awww-wallpaper-index'
        self.state.parent.mkdir()

    def cycle(self, mode='next'):
        return subprocess.run(['/bin/bash', str(ROOT / 'config/hypr/wallpaper-cycle.sh'), mode],
                              env=self.env, capture_output=True, timeout=8)

    def test_wallpaper_wraparound_and_missing_previous_position(self):
        self.wallpapers()
        for mode, expected in [('prev', 2), ('next', 0), ('prev', 2)]:
            result = self.cycle(mode)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(self.state.read_text().strip(), str(expected))

    def test_wallpaper_cache_handles_leading_zero_overflow_and_stale_values(self):
        self.wallpapers(tuple(f'{i:02}.jpg' for i in range(10)))
        for value, expected in [('08', 9), ('9999999999999999999999999999', 0), ('500', 0), ('broken', 0)]:
            self.state.write_text(value)
            result = self.cycle()
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(self.state.read_text().strip(), str(expected))

    def test_wallpaper_failure_keeps_state_and_newline_filename_is_intact(self):
        self.wallpapers(('a\nwallpaper.jpg', 'b.png'))
        self.assertEqual(self.cycle().returncode, 0)
        self.assertEqual(self.calls('awww')[-1][2], str(self.wall_dir / 'a\nwallpaper.jpg'))
        self.env['IMAGE_STATUS'] = '1'
        self.assertNotEqual(self.cycle().returncode, 0)
        self.assertEqual(self.state.read_text().strip(), '0')

    def test_wallpaper_waits_for_daemon_readiness(self):
        self.wallpapers()
        self.env['WAIT_QUERIES'] = '2'
        self.assertEqual(self.cycle().returncode, 0)
        self.assertEqual([r[1] for r in self.calls('awww')], ['query', 'query', 'query', 'img'])

    def test_concurrent_wallpaper_shortcuts_advance_in_order(self):
        self.wallpapers()
        self.env['IMAGE_DELAY'] = '0.08'
        command = ['/bin/bash', str(ROOT / 'config/hypr/wallpaper-cycle.sh')]
        workers = [subprocess.Popen(command, env=self.env, stdout=subprocess.DEVNULL, stderr=subprocess.PIPE) for _ in range(3)]
        for worker in workers:
            _, error = worker.communicate(timeout=8)
            self.assertEqual(worker.returncode, 0, error)
        self.assertEqual([r[2] for r in self.calls('awww') if r[1] == 'img'],
                         [str(self.wall_dir / n) for n in ('a.jpg', 'b.png', 'c.webp')])


if __name__ == '__main__':
    unittest.main()

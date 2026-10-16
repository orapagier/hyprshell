"""Show Desktop recovery, partial failures, pinned windows and session boundaries."""
import copy
import importlib.util
import json
from pathlib import Path
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('show_desktop', ROOT/'config/quickshell/settings/show_desktop.py')
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


class Compositor:
    def __init__(self):
        self.monitors = [dict(id=0, name='TEST', focused=True, activeWorkspace=dict(id=1), specialWorkspace=dict(id=0),
                              x=0, y=0, width=800, height=600, scale=1)]
        self.windows = [dict(address='0xabc', pid=100, monitor=0, mapped=True, pinned=True,
                             workspace=dict(id=2, name='2'), fullscreen=0, fullscreenClient=0),
                        dict(address='0xdef', pid=101, monitor=0, mapped=True, pinned=False,
                             workspace=dict(id=1, name='1'), fullscreen=2, fullscreenClient=2),
                        dict(address='0xaaa', pid=102, monitor=0, mapped=True, pinned=False,
                             workspace=dict(id=2, name='2'), fullscreen=0, fullscreenClient=0)]
        self.workspaces = [dict(id=1), dict(id=2)]
        self.failure = None
        self.calls = []

    def query(self, name):
        return copy.deepcopy(dict(monitors=self.monitors, clients=self.windows, workspaces=self.workspaces)[name])

    def dispatch(self, name, **fields):
        self.calls.append((name, fields))
        if self.failure and self.failure(name, fields):
            raise RuntimeError('injected dispatcher failure')
        window = next(w for w in self.windows if 'address:'+w['address'] == fields['window'])
        if name == 'window.move' and 'workspace' in fields:
            target = fields['workspace']
            window['workspace'] = dict(id=-99 if target == module.PARK else target, name=str(target))
            window['fullscreen'] = 0  # Exercise restoration even if the compositor clears it.
        elif name == 'window.pin':
            window['pinned'] = fields['action'] == 'set'
        elif name == 'window.fullscreen_state':
            window['fullscreen'] = fields['internal']
        elif name == 'window.resize':
            window['size'] = [fields['x'], fields['y']]
        elif name == 'window.move':
            window['at'] = [fields['x'], fields['y']]


class DesktopTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.path = Path(self.temp.name)/'show-desktop.json'
        self.hypr = Compositor()
        self.desktop = module.Desktop(self.path, self.hypr, 'session')

    def test_hide_and_restore_after_controller_restart_preserves_pins_and_fullscreen(self):
        self.assertTrue(self.desktop.action('toggle', 'TEST')['hidden'])
        self.assertEqual([w['workspace']['name'] for w in self.hypr.windows], [module.PARK, module.PARK, '2'])
        self.assertFalse(self.hypr.windows[0]['pinned'])
        restarted = module.Desktop(self.path, self.hypr, 'session')
        self.assertTrue(restarted.action('status')['hidden'])
        self.assertFalse(restarted.action('toggle')['hidden'])
        self.assertEqual([w['workspace']['id'] for w in self.hypr.windows], [1, 1, 2])
        self.assertTrue(self.hypr.windows[0]['pinned'])
        self.assertEqual(self.hypr.windows[1]['fullscreen'], 2)
        self.assertEqual(self.path.stat().st_mode & 0o777, 0o600)

    def test_closed_and_reused_addresses_are_not_restored(self):
        self.desktop.action('toggle', 'TEST')
        self.hypr.windows.pop(0)
        self.hypr.windows[0]['pid'] = 999
        self.hypr.calls.clear()
        self.desktop.action('restore')
        self.assertEqual(self.hypr.calls, [])

    def test_move_failure_rolls_back_unpin_and_previous_moves(self):
        self.hypr.failure = lambda name, fields: name == 'window.move' and fields['workspace'] == module.PARK and fields['window'] == 'address:0xdef'
        with self.assertRaisesRegex(RuntimeError, 'original windows were restored'):
            self.desktop.action('toggle', 'TEST')
        self.assertTrue(self.hypr.windows[0]['pinned'])
        self.assertEqual(self.hypr.windows[0]['workspace']['id'], 1)
        self.assertFalse(self.desktop.action('status')['hidden'])

    def test_restore_failure_keeps_journal_and_can_retry_after_move(self):
        self.desktop.action('toggle', 'TEST')
        self.hypr.failure = lambda name, fields: name == 'window.fullscreen_state'
        with self.assertRaisesRegex(RuntimeError, 'still need restoration'):
            self.desktop.action('restore')
        self.assertTrue(self.desktop.action('status')['hidden'])
        self.hypr.failure = None
        self.desktop.action('restore')
        self.assertEqual(self.hypr.windows[1]['fullscreen'], 2)

    def test_output_removal_falls_back_to_available_workspace(self):
        self.desktop.action('toggle', 'TEST')
        self.hypr.monitors = [dict(id=1, name='OTHER', focused=True, activeWorkspace=dict(id=7))]
        self.hypr.workspaces = [dict(id=7)]
        self.desktop.action('restore')
        self.assertEqual([w['workspace']['id'] for w in self.hypr.windows[:2]], [7, 7])

    def test_manual_recovery_keeps_chosen_workspace(self):
        self.desktop.action('toggle', 'TEST')
        self.hypr.windows[1]['workspace'] = dict(id=8, name='8')
        self.desktop.action('restore')
        self.assertEqual(self.hypr.windows[1]['workspace']['id'], 8)
        self.assertEqual(self.hypr.windows[1]['fullscreen'], 0)

    def test_new_compositor_session_does_not_replay_old_window_ids(self):
        self.desktop.action('toggle', 'TEST')
        self.hypr.calls.clear()
        self.assertFalse(module.Desktop(self.path, self.hypr, 'new-session').action('restore')['hidden'])
        self.assertEqual(self.hypr.calls, [])

    def test_special_workspace_or_unknown_output_is_rejected_before_mutation(self):
        for output in ('missing', 'TEST'):
            self.hypr.monitors[0]['specialWorkspace']['id'] = -5
            with self.assertRaises(ValueError):
                self.desktop.action('toggle', output)
        self.assertEqual(self.hypr.calls, [])

    def test_corrupt_journal_is_preserved(self):
        self.path.write_text('{"version":99,"windows":[]}')
        before = self.path.read_bytes()
        with self.assertRaises(ValueError):
            self.desktop.action('restore')
        self.assertEqual(self.path.read_bytes(), before)

    def test_pinned_restore_tracks_original_output_active_workspace(self):
        self.desktop.action('toggle', 'TEST')
        self.hypr.monitors[0]['activeWorkspace']['id'] = 9
        self.desktop.action('restore')
        self.assertEqual(self.hypr.windows[0]['workspace']['id'], 9)
        self.assertTrue(self.hypr.windows[0]['pinned'])

    def test_floating_geometry_follows_output_position_change(self):
        self.hypr.windows[0].update(floating=True, at=[50,60], size=[360,240])
        self.desktop.action('toggle', 'TEST')
        self.hypr.monitors[0]['x'] = 1920
        self.hypr.windows[0]['at'] = [-600,-600]
        self.desktop.action('restore')
        self.assertEqual(self.hypr.windows[0]['at'], [1970,60])
        self.assertEqual(self.hypr.windows[0]['size'], [360,240])

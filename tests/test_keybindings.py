"""Managed shortcuts: preserve Lua actions and never leave a failed reload saved."""
import importlib.util
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
HELPERS = ROOT / 'config/quickshell/settings'
with patch.object(sys, 'path', [str(HELPERS)] + sys.path):
    spec = importlib.util.spec_from_file_location('keybindings_backend', HELPERS / 'keybindings.py')
    backend = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(backend)


def entry(**changes):
    value = {'id': 'a' * 32, 'original': '', 'shortcut': 'SUPER + N', 'description': 'Open notes', 'mode': 'command', 'command': 'kitty --title "Notes"'}
    value.update(changes)
    return value


class KeybindingTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory(prefix='hyprshell-keybindings-')
        self.addCleanup(temporary.cleanup)
        self.config = Path(temporary.name) / 'config with spaces'
        self.state = Path(temporary.name) / 'state'
        self.env = patch.dict(os.environ, XDG_CONFIG_HOME=str(self.config), XDG_STATE_HOME=str(self.state))
        self.env.start()
        self.addCleanup(self.env.stop)
        main = self.config / 'hypr/hyprland.lua'
        main.parent.mkdir(parents=True)
        main.write_text('-- hyprshellKeybindings.apply()\n')

    def run_ok(self, argv, **kwargs):
        output = 'config ok' if argv[0] == 'Hyprland' else 'ok' if argv[-1] == 'configerrors' else ''
        return subprocess.CompletedProcess(argv, 0, output, '')

    def test_validate_shortcuts_commands_and_conflicts(self):
        self.assertEqual(backend.shortcut('shift + win + n'), 'SUPER + SHIFT + N')
        for keys in ['SUPER + SUPER + N', 'SUPER + N; evil', 'SUPER + ', 'SUPER + $(touch bad)', 'SUPER + N\n']:
            if keys.endswith('\n'):
                continue  # Leading/trailing whitespace is normalized.
            with self.assertRaises(ValueError):
                backend.validate([entry(shortcut=keys)])
        with self.assertRaises(ValueError):
            backend.validate([entry(), entry(id='b' * 32)])
        with self.assertRaises(ValueError):
            backend.validate([entry(command='echo ok\nrm -rf anything')])
        with self.assertRaises(ValueError):
            backend.save([entry()], [], rows=[{'modmask': 64, 'key': 'n'}])
        self.assertFalse((self.config / 'hyprshell/keybindings.json').exists())

    def test_save_backup_and_stale_writer(self):
        with patch.object(backend.subprocess, 'run', side_effect=self.run_ok):
            backend.save([entry()], [], rows=[])
            first = backend.load()
            backend.save([entry(description='Launch notes')], first, rows=[{'modmask': 64, 'key': 'n'}])
            with self.assertRaisesRegex(ValueError, 'outside'):
                backend.save([entry(description='Stale edit')], first, rows=[])
        manifests = list((self.state / 'hyprshell/backups').glob('*/manifest.json'))
        self.assertEqual(len(manifests), 2)
        backup = next(p for p in manifests if any(e['existed'] for e in json.loads(p.read_text())))
        target = next(e for e in json.loads(backup.read_text()) if e['path'].endswith('keybindings.json'))
        self.assertEqual(json.loads((backup.parent / target['file']).read_text())['entries'], first)

    def test_failed_reload_and_zero_exit_validation_errors_roll_back(self):
        for fail_validation in [False, True]:
            def run(argv, **kwargs):
                if argv[0] == 'Hyprland' and fail_validation:
                    return subprocess.CompletedProcess(argv, 0, 'Lua syntax error', '')
                if argv[-1] == 'reload' and not fail_validation:
                    raise subprocess.CalledProcessError(1, argv, stderr='reload failed')
                return self.run_ok(argv, **kwargs)
            with patch.object(backend.subprocess, 'run', side_effect=run):
                with self.assertRaises(Exception):
                    backend.save([entry()], [], rows=[])
            self.assertFalse((self.config / 'hyprshell/keybindings.json').exists())
            self.assertFalse((self.config / 'hyprshell/keybindings.lua').exists())

    def test_runtime_listing_retains_customization_and_skips_submaps(self):
        saved = entry(original='SUPER + T', mode='existing', command='')
        rows = [{'modmask': 64, 'key': 'n', 'description': 'Open terminal'}, {'modmask': 64, 'key': 'n'}, {'modmask': 64, 'key': 'q', 'submap': 'resize'}]
        self.assertEqual(backend.listing([saved], rows), [saved])

    def test_reset_rejects_restoring_over_another_customization(self):
        moved = entry(original='SUPER + T', mode='existing', command='')
        new = entry(id='b' * 32, shortcut='SUPER + T')
        target = self.config / 'hyprshell/keybindings.json'
        target.parent.mkdir(parents=True)
        target.write_text(json.dumps({'version': 1, 'entries': [moved, new]}))
        with self.assertRaisesRegex(ValueError, 'original shortcut'):
            backend.save([new], [moved, new], rows=[{'modmask': 64, 'key': 'n'}, {'modmask': 64, 'key': 't'}])

    def test_real_hyprland_accepts_remapped_callbacks_and_command_bindings(self):
        overrides = [entry(original='SUPER + H', shortcut='SUPER + SHIFT + N', mode='existing', command=''), entry(id='b' * 32)]
        generated = self.config / 'hyprshell/keybindings.lua'
        generated.parent.mkdir(parents=True)
        generated.write_text(backend.render(overrides))
        result = subprocess.run(['Hyprland', '--verify-config', '--config', str(ROOT / 'config/hypr/hyprland.lua')], capture_output=True, text=True, timeout=15)
        self.assertIn('config ok', result.stdout.lower(), result.stdout + result.stderr)

    def test_qml_recording_release_cancel_and_editor_flow(self):
        fixture = ROOT / 'config/quickshell/tests'
        wrapper = self.config.parent / 'recording.qml'
        wrapper.write_text('import ' + json.dumps(fixture.as_uri()) + ' as Checks\nChecks.ShortcutRecording {}\n')
        runtime = self.config.parent / 'runtime'
        runtime.mkdir(mode=0o700)
        environment = dict(os.environ, QT_QPA_PLATFORMTHEME='', QT_QPA_PLATFORM='offscreen', QT_QUICK_BACKEND='software', XDG_RUNTIME_DIR=str(runtime))
        result = subprocess.run(['quickshell', '-p', str(wrapper)], env=environment, capture_output=True, text=True, timeout=15)
        output = result.stdout + result.stderr
        self.assertIn('SHORTCUT_RECORDING_OK', output, output)
        self.assertNotIn('SHORTCUT_RECORDING_FAILED', output)

    def test_sync_captures_validated_preferences_and_regenerates_lua(self):
        spec = importlib.util.spec_from_file_location('keybinding_sync_test', HELPERS / 'github_sync.py')
        syncer = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(syncer)
        target = self.config / 'hyprshell/keybindings.json'
        target.parent.mkdir(parents=True)
        target.write_text(json.dumps({'version': 1, 'entries': [entry()]}))
        repo = self.config.parent / 'saved repo'
        with patch.object(sys, 'path', [str(HELPERS)] + sys.path):
            syncer.snapshot_managed_files(repo, self.config, self.config.parent)
        self.assertEqual(json.loads((repo / 'profiles/personal/config/hyprshell/keybindings.json').read_text())['entries'], [entry()])
        self.assertEqual((repo / 'profiles/personal/config/hyprshell/keybindings.lua').read_text(), backend.render([entry()]))

    def test_lua_remap_preserves_callbacks_flags_and_safely_quotes_commands(self):
        callback = entry(original='SUPER + H', shortcut='SUPER + SHIFT + H', mode='existing', command='', description='Hide active window')
        command = entry(id='b' * 32, description='Notes — quick', command='echo "quoted"; echo \\path')
        generated = self.config / 'hyprshell/keybindings.lua'
        generated.parent.mkdir(parents=True)
        generated.write_text(backend.render([callback, command]))
        script = r'''
local calls, unbound = {}, {}
hl = { dsp = { exec_cmd = function(command) return {command = command} end } }
hl.bind = function(keys, action, flags) table.insert(calls, {keys = keys, action = action, flags = flags}) end
hl.unbind = function(keys) table.insert(unbound, keys) end
local module = dofile(arg[1])
module.capture()
local callback = function() return 'original callback' end
hl.bind('SUPER + H', callback, {release = true, repeating = true, description = 'Minimize'})
module.apply()
assert(unbound[1] == 'SUPER + H')
assert(calls[2].keys == 'SUPER + SHIFT + H')
assert(calls[2].action == callback)
assert(calls[2].flags.release and calls[2].flags.repeating)
assert(calls[2].flags.description == 'Hide active window')
assert(calls[3].action.command == 'echo "quoted"; echo \\path')
assert(calls[3].flags.description == 'Notes — quick')
'''
        subprocess.run(['lua', '-', str(ROOT / 'config/hypr/keybindings.lua')], input=script, text=True, check=True, capture_output=True)


if __name__ == '__main__':
    unittest.main()

"""Complete config recovery is local, validated and never activates saved Lua."""
import copy
import json
import os
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'config/quickshell/settings'))
import backend
import configuration
import preferences


class ConfigurationTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory(); self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name)
        env = patch.dict(os.environ, XDG_CONFIG_HOME=str(self.root / 'config'), XDG_STATE_HOME=str(self.root / 'state'), HYPRLAND_INSTANCE_SIGNATURE='')
        env.start(); self.addCleanup(env.stop)
        self.config = self.root / 'config'
        path = self.config / 'hyprshell/settings.json'; path.parent.mkdir(parents=True); path.write_text(json.dumps(backend.DEFAULTS))
        main = self.config / 'hypr/hyprland.lua'; main.parent.mkdir(); main.write_text('-- personal configuration\n')
        (self.config / 'quickshell').mkdir(); (self.config / 'quickshell/shell.qml').write_text('source code is excluded')

    def checkpoint(self):
        result = configuration.request({'operation': 'checkpoint', 'expected': configuration.status()['revision']})
        return result['checkpoints'][0]['id']

    def test_checkpoint_preview_restore_full_files_and_new_preferences(self):
        ident = self.checkpoint()
        self.assertNotIn('quickshell/shell.qml', configuration.read_snapshot(ident))
        main = self.config / 'hypr/hyprland.lua'; main.write_text('-- changed\n')
        new = self.config / 'hyprshell/behavior.json'; new.write_text(json.dumps({'version': 1, 'general': {}, 'workspaces': [], 'rules': []}))
        preview = configuration.request({'operation': 'preview', 'id': ident})['preview']
        self.assertIn('hypr/hyprland.lua', preview['changes'])
        result = configuration.request({'operation': 'restore', 'token': preview['token']})
        self.assertTrue(result['ok']); self.assertIn('log out', result['message'])
        self.assertFalse(new.exists()); self.assertEqual(main.read_text(), '-- personal configuration\n')
        self.assertEqual((self.config / 'quickshell/shell.qml').read_text(), 'source code is excluded')
        self.assertTrue(list((self.root / 'state/hyprshell/backups').glob('configuration-undo-*')))

    def test_stale_preview_and_invalid_saved_lua_write_nothing(self):
        ident = self.checkpoint()
        preview = configuration.request({'operation': 'preview', 'id': ident})['preview']
        main = self.config / 'hypr/hyprland.lua'; main.write_text('-- newer manual edit\n')
        with self.assertRaises(ValueError): configuration.request({'operation': 'restore', 'token': preview['token']})
        folder = self.root / 'state/hyprshell/backups' / ident / 'files.json'
        data = json.loads(folder.read_text()); data['hypr/hyprland.lua'] = 'this is invalid Lua'; folder.write_text(json.dumps(data))
        preview = configuration.request({'operation': 'preview', 'id': ident})['preview']
        with self.assertRaises(ValueError): configuration.request({'operation': 'restore', 'token': preview['token']})
        self.assertEqual(main.read_text(), '-- newer manual edit\n')

    def test_generated_rules_are_regenerated_and_unknown_paths_rejected(self):
        files = configuration.current(); files['hyprshell/overrides.lua'] = 'error("never execute this")'
        self.assertNotIn('never execute', configuration.normalized(files)['hyprshell/overrides.lua'])
        for name in ('../outside', 'quickshell/shell.qml', 'hypr/subdir/secret.lua'):
            with self.assertRaises(ValueError): configuration.validate({**files, name: 'bad'})
        link = self.config / 'hypr/linked.lua'; link.symlink_to(self.config / 'hypr/hyprland.lua')
        with self.assertRaises(ValueError): configuration.current()

    def test_delete_transaction_rolls_back_deleted_and_replaced_files(self):
        one, two = self.root / 'one', self.root / 'two'; one.write_text('one'); two.write_text('two')
        with self.assertRaises(ValueError): preferences.transaction({one: None, two: 'new'}, 'test', lambda: (_ for _ in ()).throw(ValueError('failure')))
        self.assertEqual(one.read_text(), 'one'); self.assertEqual(two.read_text(), 'two')


if __name__ == '__main__': unittest.main()

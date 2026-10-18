"""Exercise Settings installation against isolated user directories."""
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
HELPER = ROOT / 'config/quickshell/settings/hyprskill.py'


class HyprskillTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.home = Path(self.temp.name)
        self.env = dict(os.environ, HOME=str(self.home),
                        CODEX_HOME=str(self.home / '.codex'),
                        XDG_CONFIG_HOME=str(self.home / 'config'),
                        XDG_STATE_HOME=str(self.home / 'state'))
        self.pointer = self.home / 'state/hyprshell/repository'
        self.pointer.parent.mkdir(parents=True)
        self.pointer.write_text(str(ROOT))

    def install(self):
        result = subprocess.run([sys.executable, str(HELPER), '--install'],
                                env=self.env, cwd='/tmp', capture_output=True, text=True)
        return result.returncode, json.loads(result.stdout)

    def test_install_and_repeat_from_settings(self):
        for _ in range(2):
            code, data = self.install()
            self.assertEqual(code, 0, data)
            self.assertTrue(data['ok'])
        for directory in ('.agents', '.claude', 'config/opencode'):
            skill = self.home / directory / 'skills/hyprskill'
            self.assertEqual(skill.resolve(), ROOT / 'docs/skills/hyprskill')
            self.assertTrue((skill / 'SKILL.md').is_file())
            rollback = self.home / directory / 'skills/hypr-rollback'
            self.assertEqual(rollback.resolve(), ROOT / 'docs/skills/hypr-rollback')
            self.assertTrue((rollback / 'SKILL.md').is_file())
        for path in ('.codex/prompts/hypr-rollback.md',
                     'config/opencode/commands/hypr-rollback.md'):
            command = self.home / path
            self.assertEqual(command.resolve(),
                             ROOT / 'docs/skills/hypr-rollback/commands/hypr-rollback.md')
            self.assertIn('$ARGUMENTS', command.read_text())

    def test_conflict_is_reported_without_replacing_custom_skill(self):
        custom = self.home / '.claude/skills/hyprskill'
        custom.mkdir(parents=True)
        (custom / 'SKILL.md').write_text('custom')
        code, data = self.install()
        self.assertNotEqual(code, 0)
        self.assertFalse(data['ok'])
        self.assertIn('Refusing to replace', data['message'])
        self.assertEqual((custom / 'SKILL.md').read_text(), 'custom')
        self.assertFalse((self.home / '.agents').exists())

    def test_missing_checkout_is_reported(self):
        self.pointer.write_text(str(self.home / 'missing'))
        code, data = self.install()
        self.assertNotEqual(code, 0)
        self.assertFalse(data['ok'])
        self.assertIn('checkout', data['message'])
        self.assertFalse((self.home / '.agents').exists())

    def test_command_conflict_prevents_all_installation(self):
        custom = self.home / 'config/opencode/commands/hypr-rollback.md'
        custom.parent.mkdir(parents=True)
        custom.write_text('custom command')
        code, data = self.install()
        self.assertNotEqual(code, 0)
        self.assertIn('Refusing to replace', data['message'])
        self.assertEqual(custom.read_text(), 'custom command')
        self.assertFalse((self.home / '.agents').exists())

    def test_agent_selection_and_dry_run_respect_custom_roots(self):
        custom_codex = self.home / 'custom-codex'
        env = dict(self.env, CODEX_HOME=str(custom_codex))
        installer = ROOT / 'tools/install_hyprskill.py'
        for dry_run in (True, False):
            result = subprocess.run(
                [sys.executable, str(installer), '--agent', 'codex'] +
                (['--dry-run'] if dry_run else []), env=env, cwd='/tmp',
                capture_output=True, text=True)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual((custom_codex / 'prompts/hypr-rollback.md').exists(), not dry_run)
        self.assertFalse((self.home / '.claude').exists())
        self.assertFalse((self.home / 'config/opencode').exists())

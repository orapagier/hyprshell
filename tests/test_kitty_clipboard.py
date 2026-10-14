"""Validate paste routing with Kitty's actual custom-kitten loader."""
from pathlib import Path
import shutil
import subprocess
import unittest

ROOT = Path(__file__).resolve().parents[1]


@unittest.skipUnless(shutil.which('kitty'), 'Kitty is not installed')
class ClipboardTests(unittest.TestCase):
    def test_native_loader_and_text_image_routing(self):
        script = '''
from kittens.runner import import_kitten_main_module
from types import SimpleNamespace
from unittest.mock import Mock
module = import_kitten_main_module(CONFIG_DIR, 'clipboard_paste.py')
handler = module['end']
assert handler.no_ui
for formats, image in [(('text/plain',), False), ((), False),
                       (('image/png',), True),
                       (('text/html', 'text/plain', 'image/png'), True)]:
    window = SimpleNamespace(send_key=Mock())
    boss = SimpleNamespace(window_id_map={1: window},
        clipboard=SimpleNamespace(get_available_mime_types_for_paste=Mock(return_value=formats)),
        paste_from_clipboard=Mock())
    handler([], None, 1, boss)
    if image:
        window.send_key.assert_called_once_with('ctrl+v')
        boss.paste_from_clipboard.assert_not_called()
    else:
        window.send_key.assert_not_called()
        boss.paste_from_clipboard.assert_called_once_with()
boss.clipboard.get_available_mime_types_for_paste.side_effect = RuntimeError('unavailable')
window.send_key.reset_mock()
boss.paste_from_clipboard.reset_mock()
handler([], None, 1, boss)
window.send_key.assert_called_once_with('ctrl+v')
boss.paste_from_clipboard.assert_not_called()
window.send_key.reset_mock()
handler([], None, 99, boss)
window.send_key.assert_not_called()
'''
        result = subprocess.run(['kitty', '+runpy',
            'CONFIG_DIR = ' + repr(str(ROOT / 'config/kitty')) + '\n' + script],
            capture_output=True, text=True, timeout=15)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

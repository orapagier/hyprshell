"""Attachment settings persist independently and reject invalid values."""
import copy
import importlib.util
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('attachment_backend', ROOT / 'config/quickshell/settings/backend.py')
backend = importlib.util.module_from_spec(spec)
spec.loader.exec_module(backend)


class PanelAttachmentTests(unittest.TestCase):
    def test_defaults_and_independent_choices_preserve_layout(self):
        baseline = backend.validate({'version': 1})
        self.assertFalse(baseline['bar']['edgeAttached'])
        self.assertFalse(baseline['bar']['autoHide'])
        for edge in ('top', 'bottom', 'left', 'right'):
            for centered in (False, True):
                for attached in (False, True):
                    for hidden in (False, True):
                        data = copy.deepcopy(baseline)
                        data['bar'].update(position=edge, centerItems=centered,
                                           edgeAttached=attached, autoHide=hidden,
                                           screenMarginTop=17, marginSide=23)
                        self.assertEqual(backend.validate(data), data)

    def test_invalid_toggle_values_rejected(self):
        for key in ('edgeAttached', 'autoHide'):
            for value in (None, 0, 1, 'true', [], {}):
                with self.subTest(key=key, value=value), self.assertRaises(ValueError):
                    backend.validate({'version': 1, 'bar': {key: value}})

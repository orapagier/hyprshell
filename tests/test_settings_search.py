"""Static caption indexing never evaluates pages or reads preference values."""
import importlib.util
from pathlib import Path
import re
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('settings_search', ROOT / 'config/quickshell/settings/search.py')
search = importlib.util.module_from_spec(spec)
spec.loader.exec_module(search)


class SettingsSearchTests(unittest.TestCase):
    def test_requested_headings_nested_pages_and_bar_items(self):
        index = search.build_index()
        for caption in ('Effect workspaces', 'Fullscreen windows', 'Advanced glass & blur', 'Glass grain', 'Blur application popups'):
            self.assertIn(caption, index['-2'])
        self.assertIn('System updates', index['-14'])
        self.assertIn('Popdown glass', index['-1'])
        self.assertIn('Popdown glass', index['*'])
        self.assertIn('Hyprshell setup backup & restore', index['-14'])
        self.assertIn('Hyprshell setup backup & restore', index['-23'])
        self.assertIn('Reset & factory reset', index['-4'])
        self.assertIn('Chromium cache', index['-4'])
        self.assertIn('Bar thickness', index['-1'])
        self.assertNotIn('System updates', index['-1'])

    def test_each_navigation_page_has_an_indexed_source(self):
        window = (ROOT / 'config/quickshell/SettingsWindow.qml').read_text()
        sections = {value for value in re.findall(r'\{section: (-\d+), title:', window)}
        self.assertEqual(sections, set(search.PAGES) - {'*'})
        index = search.build_index()
        self.assertTrue(all(index[section] for section in sections))

    def test_comments_escaped_captions_and_conditional_titles(self):
        captions, children = search.source_captions(r'''
// title: "Not a heading"
/* subtitle: "Also not a heading" */
SettingsCard {
    title: enabled ? "First heading" : 'Second heading'
    subtitle: "Use \"quotes\" and https://example.invalid"
    model: [{label: "Nested option"}]
    text: "Literal title: 'not a separate property'"
    SettingsNested {}
}
''')
        self.assertNotIn('Not a heading', captions)
        self.assertNotIn('Also not a heading', captions)
        self.assertNotIn('not a separate property', captions)
        self.assertNotIn('Use "quotes" and https://example.invalid', captions)
        for expected in ('First heading', 'Second heading', 'Nested option'):
            self.assertIn(expected, captions)
        self.assertIn('SettingsNested', children)

    def test_explanations_do_not_match_as_settings(self):
        captions, _ = search.source_captions('''SettingsCard {
            title: "Window behavior"
            subtitle: "Keep your existing desktop behavior"
            description: "Desktop instructions"
            SettingsLabel { text: "Desktop behavior stays as configured. Choose an override only where needed." }
            SettingsLabel { text: "Default tiling layout" }
            SettingsSwitch { text: "Resize windows from borders" }
        }''')
        self.assertEqual(captions, ['Window behavior', 'Default tiling layout', 'Resize windows from borders'])
        self.assertFalse(any('desktop' in caption.lower() for caption in search.build_index()['-19']))

    def test_current_caption_changes_are_found_without_executing_sources(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            page = root / 'SettingsBarEditor.qml'
            page.write_text('ColumnLayout { SettingsNested {} }')
            child = root / 'SettingsNested.qml'
            child.write_text('SettingsCard { title: "Fresh subsection"; Component.onCompleted: throw new Error("never run") }')
            self.assertIn('Fresh subsection', search.build_index(root)['-1'])
            child.write_text('SettingsCard { title: "Renamed subsection"; SettingsBarEditor {} }')
            index = search.build_index(root)
            self.assertIn('Renamed subsection', index['-1'])
            self.assertNotIn('Fresh subsection', index['-1'])

    def test_helper_supplied_section_captions_are_parsed_without_import(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary); (root / 'settings').mkdir()
            (root / 'SettingsCleanup.qml').write_text('Item { property string helper: "settings/example.py" }')
            (root / 'settings/example.py').write_text('''raise RuntimeError("must not import")
rows = [dict(title="Helper header"), {"label": "Helper option"}, row("cache", "Helper category")]
''')
            index = search.build_index(root)
            for value in ('Helper header', 'Helper option', 'Helper category'):
                self.assertIn(value, index['-4'])


if __name__ == '__main__': unittest.main()

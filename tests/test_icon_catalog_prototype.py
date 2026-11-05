import importlib.util
import json
from pathlib import Path
import select
import shutil
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
SPEC = importlib.util.spec_from_file_location('icon_catalog_prototype', ROOT / 'tools/icon_catalog_prototype.py')
icons = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(icons)


class CatalogTests(unittest.TestCase):
    def test_priority_filtering_and_encoded_paths(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            first, second = root / 'first space', root / 'second'
            first.mkdir(); second.mkdir()
            for name in ('same.svg', 'same.png', 'same.xpm', '.hidden.svg', 'upper.PNG', 'café #1.svg'):
                (first / name).write_text('fixture')
            (first / 'directory.svg').mkdir()
            (second / 'same.png').write_text('later folder')
            (second / 'later.png').write_text('later icon')
            (first / 'broken.svg').symlink_to(first / 'missing')
            (first / 'link.svg').symlink_to(first / 'same.svg')
            catalog = icons.scan([first, second])
            self.assertEqual(catalog['same'], f'file://{first}/same.png')
            self.assertEqual(catalog['café #1'], f'file://{first}/café %231.svg')
            self.assertEqual(set(catalog), {'same', 'café #1', 'link', 'later'})

    def test_qt_compatible_urls_and_sort_order(self):
        with tempfile.TemporaryDirectory() as directory:
            folder = Path(directory)
            for name in ('same.png', 'same.svg', 'same.xpm', 'A.svg', 'a.svg',
                         'plus+name.svg', 'space name.svg', 'hash#name.svg',
                         'percent%name.svg', 'unicode-é.svg', 'unicode-É.svg',
                         '.hidden.svg', 'UPPER.SVG'):
                (folder / name).write_text('fixture')
            catalog = icons.scan([folder])
            self.assertEqual(catalog['same'], f'file://{folder}/same.png')
            self.assertEqual(catalog['plus+name'], f'file://{folder}/plus+name.svg')
            self.assertEqual(catalog['space name'], f'file://{folder}/space name.svg')
            self.assertEqual(catalog['hash#name'], f'file://{folder}/hash%23name.svg')
            self.assertEqual(catalog['percent%name'], f'file://{folder}/percent%25name.svg')
            self.assertEqual(catalog['unicode-É'], f'file://{folder}/unicode-É.svg')
            self.assertEqual(catalog['unicode-é'], f'file://{folder}/unicode-é.svg')
            self.assertEqual(set(catalog), {'same', 'A', 'a', 'plus+name', 'space name',
                                            'hash#name', 'percent%name', 'unicode-É', 'unicode-é'})

    def test_missing_folders_and_local_urls(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / 'missing space'
            self.assertEqual(icons.scan([path]), {})
            self.assertEqual(icons.folders_from_json(json.dumps([path.as_uri(), str(path)])), [path])
        for value in ('[]', '["relative"]', '["file://remote/icons"]', '[42]'):
            with self.subTest(value=value), self.assertRaises(ValueError):
                icons.folders_from_json(value)

    def expect_change(self, watcher):
        self.assertTrue(select.select([watcher.fd], [], [], 2)[0], 'No filesystem event')
        self.assertTrue(watcher.changed(), 'Relevant event not recognized')

    def test_create_modify_replace_delete_without_desktop_entries(self):
        with tempfile.TemporaryDirectory() as directory:
            folder = Path(directory)
            watcher = icons.Watcher([folder])
            self.addCleanup(watcher.close)
            icon = folder / 'app.svg'
            icon.write_text('one'); self.expect_change(watcher)
            self.assertIn('app', icons.scan([folder]))
            icon.write_text('two'); self.expect_change(watcher)
            temporary = folder / 'new-file'
            temporary.write_text('three'); temporary.replace(icon)
            self.expect_change(watcher)
            icon.unlink(); self.expect_change(watcher)
            self.assertEqual(icons.scan([folder]), {})

    def test_missing_directory_recovery_and_recreation(self):
        with tempfile.TemporaryDirectory() as directory:
            folder = Path(directory) / 'theme' / 'apps'
            watcher = icons.Watcher([folder]); self.addCleanup(watcher.close)
            folder.mkdir(parents=True); (folder / 'app.png').write_text('one')
            self.expect_change(watcher)
            self.assertIn('app', icons.scan([folder]))
            shutil.rmtree(folder.parent); self.expect_change(watcher)
            self.assertEqual(icons.scan([folder]), {})
            folder.mkdir(parents=True); (folder / 'other.png').write_text('two')
            self.expect_change(watcher)
            self.assertIn('other', icons.scan([folder]))

    def test_symlink_theme_replacement_and_target_updates(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            one, two = root / 'one', root / 'two'
            one.mkdir(); two.mkdir()
            link = root / 'theme'; link.symlink_to(one, target_is_directory=True)
            watcher = icons.Watcher([link]); self.addCleanup(watcher.close)
            (one / 'first.svg').write_text('one'); self.expect_change(watcher)
            self.assertIn('first', icons.scan([link]))
            link.unlink(); link.symlink_to(two, target_is_directory=True)
            (two / 'second.svg').write_text('two'); self.expect_change(watcher)
            self.assertEqual(set(icons.scan([link])), {'second'})
            (two / 'second.svg').write_text('updated'); self.expect_change(watcher)

    def test_unrelated_ancestor_activity_does_not_rescan(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory); folder = root / 'apps'; folder.mkdir()
            watcher = icons.Watcher([folder]); self.addCleanup(watcher.close)
            (root / 'unrelated.txt').write_text('unrelated')
            self.assertTrue(select.select([watcher.fd], [], [], 2)[0])
            self.assertFalse(watcher.changed())
            (folder / 'not-an-icon.txt').write_text('unrelated')
            self.assertTrue(select.select([watcher.fd], [], [], 2)[0])
            self.assertFalse(watcher.changed())

    def test_folder_can_also_be_recreation_ancestor(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory); nested = root / 'theme/apps'
            watcher = icons.Watcher([root, nested]); self.addCleanup(watcher.close)
            nested.mkdir(parents=True); (nested / 'app.svg').write_text('fixture')
            self.expect_change(watcher)
            self.assertIn('app', icons.scan([root, nested]))
